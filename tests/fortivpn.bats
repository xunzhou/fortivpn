#!/usr/bin/env bats

setup() {
  TEST_ROOT="$BATS_TEST_TMPDIR/case-$BATS_TEST_NUMBER"
  FAKE_BIN="$TEST_ROOT/bin"
  export HOME="$TEST_ROOT/home"
  export XDG_CONFIG_HOME="$TEST_ROOT/config-home"
  export TMPDIR="$TEST_ROOT/tmp"
  export FORTIVPN_UNDER_TEST="${FORTIVPN_UNDER_TEST:-$BATS_TEST_DIRNAME/../bin/fortivpn}"
  mkdir -p "$FAKE_BIN" "$HOME" "$TMPDIR"

  for name in bash cat chmod chown cmp dirname install ln mkdir mktemp mv rm stat; do
    ln -s "$(command -v "$name")" "$FAKE_BIN/$name"
  done
  if command -v locale >/dev/null 2>&1; then
    ln -s "$(command -v locale)" "$FAKE_BIN/locale"
  fi
  export PATH="$FAKE_BIN"

  export CALL_LOG="$TEST_ROOT/calls"
  export COOKIE_CAPTURE="$TEST_ROOT/cookie-stdin"
  export ARGV_CAPTURE="$TEST_ROOT/openfortivpn-argv"
  export CONFIG_CAPTURE="$TEST_ROOT/openfortivpn-config"
  export CONFIG_PATH_CAPTURE="$TEST_ROOT/openfortivpn-config-path"
  export PKILL_ARGV_CAPTURE="$TEST_ROOT/pkill-argv"
  export SNAPSHOT_MODE_CAPTURE="$TEST_ROOT/openfortivpn-config-mode"
  export SNAPSHOT_DIR_MODE_CAPTURE="$TEST_ROOT/openfortivpn-config-dir-mode"
  export SUDO_COMMAND_CAPTURE="$TEST_ROOT/sudo-command"

  make_fake sudo 'if [[ ${1-} == -v ]]; then printf "sudo-v\n" >>"$CALL_LOG"; if [[ -n ${REPLACE_CONFIG_DURING_SUDO:-} ]]; then printf "%s" "$REPLACEMENT_CONFIG_BODY" >"$REPLACE_CONFIG_DURING_SUDO"; fi; exit "${SUDO_VALIDATE_EXIT:-0}"; fi; printf "%s" "$1" >"$SUDO_COMMAND_CAPTURE"; exec "$@"'
  make_fake openfortivpn-webview 'printf "webview\n" >>"$CALL_LOG"; if [[ -n ${SYNTHETIC_COOKIE_FILE:-} ]]; then cat "$SYNTHETIC_COOKIE_FILE"; else printf "%s" "${SYNTHETIC_COOKIE:-synthetic-cookie}"; fi; exit "${WEBVIEW_EXIT:-0}"'
  make_fake openfortivpn 'printf "openfortivpn\n" >>"$CALL_LOG"; printf "%s\n" "$@" >"$ARGV_CAPTURE"; config_arg=; previous=; for arg in "$@"; do if [[ $previous == --config ]]; then config_arg=$arg; fi; previous=$arg; done; printf "%s" "$config_arg" >"$CONFIG_PATH_CAPTURE"; stat -c "%a" -- "$config_arg" >"$SNAPSHOT_MODE_CAPTURE"; stat -c "%a" -- "$(dirname -- "$config_arg")" >"$SNAPSHOT_DIR_MODE_CAPTURE"; cat -- "$config_arg" >"$CONFIG_CAPTURE"; cat >"$COOKIE_CAPTURE"; exit "${OPENFORTIVPN_EXIT:-0}"'
  make_fake pkill 'printf "%s\n" "$@" >"$PKILL_ARGV_CAPTURE"'
}

make_fake() {
  local name=$1 body=$2
  printf '#!%s\n%s\n' "$BASH" "$body" >"$FAKE_BIN/$name"
  chmod 0755 "$FAKE_BIN/$name"
}

write_config() {
  local host=${1:-vpn.example.com} port=${2:-443} mode=${3:-600}
  mkdir -p "$(dirname "$(config_path)")"
  printf 'host = %s\nport = %s\n' "$host" "$port" >"$(config_path)"
  chmod "$mode" "$(config_path)"
}

config_path() {
  printf '%s/openfortivpn/config' "$XDG_CONFIG_HOME"
}

assert_no_connection_snapshots() {
  shopt -s nullglob
  local snapshots=("$TMPDIR"/fortivpn.*)
  [ "${#snapshots[@]}" -eq 0 ]
}

@test "config rejects extra arguments" {
  run "$FORTIVPN_UNDER_TEST" config extra
  [ "$status" -eq 2 ]
  [ "$output" = "usage: fortivpn [config|disconnect]" ]
}

@test "config writes a default-port file with private modes" {
  run "$FORTIVPN_UNDER_TEST" config <<<$'vpn.example.com\n'
  [ "$status" -eq 0 ]
  [ "$(<"$(config_path)")" = $'host = vpn.example.com\nport = 443' ]
  [ "$(stat -c '%a' "$XDG_CONFIG_HOME/openfortivpn")" = 700 ]
  [ "$(stat -c '%a' "$(config_path)")" = 600 ]
}

@test "config accepts an explicit valid port" {
  run "$FORTIVPN_UNDER_TEST" config <<<$'vpn.example.com\n10443'
  [ "$status" -eq 0 ]
  [ "$(<"$(config_path)")" = $'host = vpn.example.com\nport = 10443' ]
}

@test "config rejects unsafe hosts" {
  for host in '' 'https://vpn.example.com' '.vpn.example.com' 'vpn example.com' 'vpn.example.com/x'; do
    run "$FORTIVPN_UNDER_TEST" config <<<"$host"
    [ "$status" -eq 1 ]
    [[ "$output" == invalid\ host:* ]]
  done
}

@test "config rejects ports outside 1 through 65535" {
  for port in 0 65536 999999999999 abc '44 3'; do
    run "$FORTIVPN_UNDER_TEST" config <<<$'vpn.example.com\n'"$port"
    [ "$status" -eq 1 ]
    [[ "$output" == invalid\ port:* ]]
  done
}

@test "config refuses replacement unless explicitly confirmed" {
  mkdir -p "$(dirname "$(config_path)")"
  printf 'original\n' >"$(config_path)"

  run "$FORTIVPN_UNDER_TEST" config <<<$'new.example.com\n443\nn'
  [ "$status" -eq 1 ]
  [ "$(<"$(config_path)")" = original ]

  run "$FORTIVPN_UNDER_TEST" config <<<$'new.example.com\n443\ny'
  [ "$status" -eq 0 ]
  [ "$(<"$(config_path)")" = $'host = new.example.com\nport = 443' ]
}

@test "config cannot report success or strand a file when the target is a directory" {
  mkdir -p "$(config_path)"
  printf 'directory-marker\n' >"$(config_path)/marker"

  run "$FORTIVPN_UNDER_TEST" config <<<$'new.example.com\n443\ny'

  [ "$status" -ne 0 ]
  [[ "$output" != *created* ]]
  [ -d "$(config_path)" ]
  [ "$(<"$(config_path)/marker")" = directory-marker ]
  shopt -s nullglob
  local stranded=("$(config_path)"/.config.*)
  [ "${#stranded[@]}" -eq 0 ]
}

@test "config replaces a symlink to a directory without touching that directory" {
  local target_directory="$TEST_ROOT/symlink-target"
  mkdir -p "$(dirname "$(config_path)")" "$target_directory"
  printf 'directory-marker\n' >"$target_directory/marker"
  ln -s "$target_directory" "$(config_path)"

  run "$FORTIVPN_UNDER_TEST" config <<<$'new.example.com\n443\ny'

  [ "$status" -eq 0 ]
  [ -f "$(config_path)" ]
  [ ! -L "$(config_path)" ]
  [ "$(<"$(config_path)")" = $'host = new.example.com\nport = 443' ]
  [ "$(<"$target_directory/marker")" = directory-marker ]
  shopt -s nullglob
  local stranded=("$target_directory"/.config.*)
  [ "${#stranded[@]}" -eq 0 ]
}

@test "host validation stays ASCII-only in an available non-C UTF-8 locale" {
  local candidate utf8_locale=
  if [[ ! -x $FAKE_BIN/locale ]]; then
    skip 'locale utility is unavailable'
  fi
  while IFS= read -r candidate; do
    case $candidate in
      C|C.*|POSIX) ;;
      *[Uu][Tt][Ff]*|*.utf8) utf8_locale=$candidate; break ;;
    esac
  done < <(locale -a)
  if [[ -z $utf8_locale ]]; then
    skip 'no non-C UTF-8 locale is available'
  fi
  export LC_ALL=$utf8_locale

  run "$FORTIVPN_UNDER_TEST" config <<<$'é.example.com\n443'
  [ "$status" -eq 1 ]
  [[ "$output" == invalid\ host:* ]]

  write_config 'é.example.com' 443
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 1 ]
  [[ "$output" == config\ must\ contain* ]]
  [ ! -e "$CALL_LOG" ]
}

@test "connect rejects arguments" {
  run "$FORTIVPN_UNDER_TEST" status
  [ "$status" -eq 2 ]
  [ "$output" = "usage: fortivpn [config|disconnect]" ]
}

@test "connect rejects an explicit empty argument and additional arguments" {
  run "$FORTIVPN_UNDER_TEST" ''
  [ "$status" -eq 2 ]
  [ "$output" = "usage: fortivpn [config|disconnect]" ]

  run "$FORTIVPN_UNDER_TEST" '' extra
  [ "$status" -eq 2 ]
  [ "$output" = "usage: fortivpn [config|disconnect]" ]
}

@test "disconnect rejects extra arguments" {
  run "$FORTIVPN_UNDER_TEST" disconnect extra

  [ "$status" -eq 2 ]
  [ "$output" = "usage: fortivpn [config|disconnect]" ]
  [ ! -e "$CALL_LOG" ]
}

@test "disconnect sends SIGINT to exact openfortivpn processes through sudo" {
  run "$FORTIVPN_UNDER_TEST" disconnect

  [ "$status" -eq 0 ]
  [ "$(<"$SUDO_COMMAND_CAPTURE")" = "$FAKE_BIN/pkill" ]
  [ "$(<"$PKILL_ARGV_CAPTURE")" = $'--signal\nINT\n--exact\nopenfortivpn' ]
}

@test "disconnect reports a missing process-control dependency" {
  mv "$FAKE_BIN/pkill" "$FAKE_BIN/pkill.absent"

  run "$FORTIVPN_UNDER_TEST" disconnect

  [ "$status" -eq 1 ]
  [[ "$output" == *"required command not found on PATH: pkill"* ]]
  [ ! -e "$CALL_LOG" ]
}

@test "connect rejects a missing config and a config symlink" {
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 1 ]
  [[ "$output" == missing\ regular,* ]]

  mkdir -p "$(dirname "$(config_path)")"
  printf 'host = vpn.example.com\nport = 443\n' >"$TEST_ROOT/real-config"
  ln -s "$TEST_ROOT/real-config" "$(config_path)"
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 1 ]
  [[ "$output" == missing\ regular,* ]]
}

@test "connect rejects group or other access" {
  for mode in 640 604 666; do
    write_config vpn.example.com 443 "$mode"
    run "$FORTIVPN_UNDER_TEST"
    [ "$status" -eq 1 ]
    [[ "$output" == config\ must\ not\ be\ accessible* ]]
  done
}

@test "connect rejects the wrong owner when ownership can be changed" {
  if (( EUID != 0 )); then
    skip 'requires root to create a differently owned fixture'
  fi
  write_config
  chown 65534 "$(config_path)"
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 1 ]
  [[ "$output" == config\ must\ be\ owned* ]]
}

@test "connect rejects absent or malformed effective gateway values" {
  mkdir -p "$(dirname "$(config_path)")"
  for body in 'host = vpn.example.com' 'port = 443' 'host = https://vpn.example.com
port = 443' 'host = vpn.example.com
port = 0' 'host = vpn.example.com
port = 65536'; do
    printf '%b\n' "$body" >"$(config_path)"
    chmod 600 "$(config_path)"
    run "$FORTIVPN_UNDER_TEST"
    [ "$status" -eq 1 ]
    [[ "$output" == config\ must\ contain* ]]
  done
}

@test "connect uses the last recognized key and ignores other settings" {
  mkdir -p "$(dirname "$(config_path)")"
  printf '%s\n' 'host = old.example.com' 'trusted-cert = synthetic' \
    'host = vpn.example.com' 'port = 443' >"$(config_path)"
  chmod 600 "$(config_path)"
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *'vpn.example.com:443'* ]]
}

@test "connect does not normalize embedded whitespace in recognized-looking keys" {
  mkdir -p "$(dirname "$(config_path)")"
  for body in 'h ost = vpn.example.com
port = 443' 'host = vpn.example.com
po rt = 443'; do
    printf '%s\n' "$body" >"$(config_path)"
    chmod 600 "$(config_path)"
    run "$FORTIVPN_UNDER_TEST"
    [ "$status" -eq 1 ]
    [[ "$output" == config\ must\ contain* ]]
    [ ! -e "$CALL_LOG" ]
  done
}

@test "connect reports each missing runtime dependency before authentication" {
  write_config
  for name in stat sudo openfortivpn-webview openfortivpn; do
    mv "$FAKE_BIN/$name" "$FAKE_BIN/$name.absent"
    run "$FORTIVPN_UNDER_TEST"
    [ "$status" -eq 1 ]
    [[ "$output" == *"required command not found on PATH: $name"* ]]
    [ ! -e "$CALL_LOG" ]
    mv "$FAKE_BIN/$name.absent" "$FAKE_BIN/$name"
  done
}

@test "connect validates sudo before opening the webview" {
  write_config
  export SUDO_VALIDATE_EXIT=19
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 19 ]
  [ "$(<"$CALL_LOG")" = sudo-v ]
  assert_no_connection_snapshots
}

@test "connect validates sudo before piping the cookie with exact argv" {
  write_config vpn.example.com 10443
  local expected_cookie="$TEST_ROOT/expected-cookie"
  printf '  synthetic cookie line 1  \n\tline 2\t\n\n' >"$expected_cookie"
  export SYNTHETIC_COOKIE_FILE=$expected_cookie

  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 0 ]
  local calls=()
  mapfile -t calls <"$CALL_LOG"
  [ "${calls[0]}" = sudo-v ]
  [ "${#calls[@]}" -eq 3 ]
  [[ " ${calls[*]} " == *' webview '* ]]
  [[ " ${calls[*]} " == *' openfortivpn '* ]]
  [ "$(<"$SUDO_COMMAND_CAPTURE")" = "$FAKE_BIN/openfortivpn" ]
  cmp "$expected_cookie" "$COOKIE_CAPTURE"
  local snapshot_path
  snapshot_path=$(<"$CONFIG_PATH_CAPTURE")
  [ "$snapshot_path" != "$(config_path)" ]
  [ "$(<"$ARGV_CAPTURE")" = $'--config\n'"$snapshot_path"$'\n--cookie-on-stdin' ]
  [ "$(<"$SNAPSHOT_DIR_MODE_CAPTURE")" = 700 ]
  [ "$(<"$SNAPSHOT_MODE_CAPTURE")" = 600 ]
  cmp "$(config_path)" "$CONFIG_CAPTURE"
  [ ! -e "$snapshot_path" ]
  assert_no_connection_snapshots
  [ ! -e "$TEST_ROOT/vpn-cookie" ]
}

@test "connect snapshots config before sudo so authentication and root consume the same gateway" {
  write_config original.example.com 10443
  local expected_config="$TEST_ROOT/expected-config"
  cat "$(config_path)" >"$expected_config"
  export REPLACE_CONFIG_DURING_SUDO
  REPLACE_CONFIG_DURING_SUDO=$(config_path)
  export REPLACEMENT_CONFIG_BODY=$'host = replacement.example.com\nport = 443\n'

  run "$FORTIVPN_UNDER_TEST"

  [ "$status" -eq 0 ]
  [[ "$output" == *'original.example.com:10443'* ]]
  cmp "$expected_config" "$CONFIG_CAPTURE"
  [ "$(<"$(config_path)")" = $'host = replacement.example.com\nport = 443' ]
  local snapshot_path
  snapshot_path=$(<"$CONFIG_PATH_CAPTURE")
  [ "$snapshot_path" != "$(config_path)" ]
  [ ! -e "$snapshot_path" ]
  assert_no_connection_snapshots
}

@test "connect propagates a webview failure through pipefail" {
  write_config
  export WEBVIEW_EXIT=17
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 17 ]
  assert_no_connection_snapshots
}

@test "connect propagates an openfortivpn failure through pipefail" {
  write_config
  export OPENFORTIVPN_EXIT=23
  run "$FORTIVPN_UNDER_TEST"
  [ "$status" -eq 23 ]
  assert_no_connection_snapshots
}

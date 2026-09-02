#!/usr/bin/env bats

setup() {
  TEST_ROOT="$BATS_TEST_TMPDIR/case-$BATS_TEST_NUMBER"
  FAKE_BIN="$TEST_ROOT/bin"
  export CALL_LOG="$TEST_ROOT/calls"
  export I3_TREE_FILE="$TEST_ROOT/i3-tree"
  export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
  export VPN_TOGGLE_UNDER_TEST="${VPN_TOGGLE_UNDER_TEST:-$BATS_TEST_DIRNAME/../contrib/i3-vpn-toggle}"
  mkdir -p "$FAKE_BIN" "$XDG_RUNTIME_DIR"
  printf '{}\n' >"$I3_TREE_FILE"

  make_fake alacritty 'printf "alacritty" >>"$CALL_LOG"; printf " <%s>" "$@" >>"$CALL_LOG"; printf "\n" >>"$CALL_LOG"; if [[ -n ${MAP_FORTI_AFTER:-} ]]; then sleep "$MAP_FORTI_AFTER"; printf "%s\n" '\''{"nodes":[{"window_properties":{"class":"forti"}}]}'\'' >"$I3_TREE_FILE"; fi'
  make_fake i3-msg 'if [[ ${1-} == -t && ${2-} == get_tree ]]; then if [[ -n ${I3_TREE_EXIT:-} ]]; then exit "$I3_TREE_EXIT"; fi; cat "$I3_TREE_FILE"; exit 0; fi; printf "i3-msg" >>"$CALL_LOG"; printf " <%s>" "$@" >>"$CALL_LOG"; printf "\n" >>"$CALL_LOG"'
  make_fake ip 'if [[ ${1-} == -o ]]; then if [[ -n ${IP_QUERY_FAILURE:-} ]]; then exit 1; fi; printf "1: lo: <LOOPBACK>\n"; if [[ ${VPN_CONNECTED:-0} == 1 ]]; then printf "7: ppp0@if9: <POINTOPOINT>\n"; fi; exit 0; fi; if [[ -n ${IP_QUERY_FAILURE:-} ]]; then exit 1; fi; if [[ ${VPN_CONNECTED:-0} == 1 ]]; then exit 0; else exit 1; fi'

  export PATH="$FAKE_BIN:$PATH"
}

make_fake() {
  local name=$1 body=$2
  printf '#!%s\n%s\n' "$BASH" "$body" >"$FAKE_BIN/$name"
  chmod 0755 "$FAKE_BIN/$name"
}

@test "toggle starts fortivpn when no exact forti terminal exists" {
  printf '%s\n' '{"nodes":[{"window_properties":{"class":"openfortivpn-webview"}}]}' >"$I3_TREE_FILE"

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = 'alacritty <--class> <forti> <-e> <fortivpn>' ]
}

@test "toggle closes the forti terminal while authentication is still in progress" {
  printf '%s\n' '{"nodes":[{"window_properties":{"class":"forti"}}]}' >"$I3_TREE_FILE"

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = 'i3-msg <[class="^forti$"] kill>' ]
}

@test "toggle runs disconnect in a terminal when ppp0 is connected" {
  export VPN_CONNECTED=1
  printf '%s\n' '{"nodes":[{"window_properties":{"class":"forti"}}]}' >"$I3_TREE_FILE"

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = 'alacritty <--class> <forti-disconnect> <-e> <fortivpn> <disconnect>' ]
}

@test "toggle honors an explicit fortivpn executable override" {
  export FORTIVPN_EXECUTABLE=/opt/fortivpn/bin/fortivpn

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -eq 0 ]
  [ "$(<"$CALL_LOG")" = 'alacritty <--class> <forti> <-e> </opt/fortivpn/bin/fortivpn>' ]
}

@test "toggle fails closed when network state cannot be read" {
  export IP_QUERY_FAILURE=1

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -eq 2 ]
  [ ! -e "$CALL_LOG" ]
}

@test "toggle fails closed when the i3 tree cannot be read" {
  export I3_TREE_EXIT=7

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -eq 7 ]
  [ ! -e "$CALL_LOG" ]
}

@test "toggle fails closed when i3 returns malformed JSON" {
  printf 'not-json\n' >"$I3_TREE_FILE"

  run "$VPN_TOGGLE_UNDER_TEST"

  [ "$status" -ne 0 ]
  [ ! -e "$CALL_LOG" ]
}

@test "concurrent clicks start only one terminal and the queued click closes it" {
  export MAP_FORTI_AFTER=0.2

  "$VPN_TOGGLE_UNDER_TEST" &
  local first_pid=$!
  sleep 0.05
  "$VPN_TOGGLE_UNDER_TEST" &
  local second_pid=$!
  wait "$first_pid"
  wait "$second_pid"

  [ "$(<"$CALL_LOG")" = $'alacritty <--class> <forti> <-e> <fortivpn>\ni3-msg <[class="^forti$"] kill>' ]
}

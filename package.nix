{
  lib,
  stdenvNoCC,
  makeWrapper,
  bats,
  bash,
  coreutils,
  jq,
  openfortivpn,
  openfortivpn-webview,
  ppp,
  procps,
  util-linux,
}:
stdenvNoCC.mkDerivation {
  pname = "fortivpn";
  version = "0.1.0";
  src = lib.cleanSource ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeInstallCheckInputs = [ bats jq util-linux ];
  dontBuild = true;

  postPatch = ''
    patchShebangs contrib/i3-vpn-toggle
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/fortivpn "$out/bin/fortivpn"
    makeWrapper "${openfortivpn}/bin/openfortivpn" "$out/libexec/openfortivpn" \
      --prefix PATH : ${lib.makeBinPath [ ppp ]}
    wrapProgram "$out/bin/fortivpn" \
      --suffix PATH : ${lib.makeBinPath [
        bash
        coreutils
        openfortivpn-webview
        procps
      ]} \
      --suffix PATH : "$out/libexec"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    if usage_output=$("$out/bin/fortivpn" invalid 2>&1); then
      exit 1
    else
      usage_status=$?
    fi
    test "$usage_status" -eq 2
    test "$usage_output" = 'usage: fortivpn [config|disconnect]'

    disconnect_root=$(mktemp -d)
    trap 'rm -rf "$disconnect_root"' EXIT
    disconnect_fake_bin="$disconnect_root/bin"
    disconnect_argv_capture="$disconnect_root/sudo-argv"
    mkdir -p "$disconnect_fake_bin"
    printf '#!%s\nprintf "%%s\\n" "$@" >"$DISCONNECT_ARGV_CAPTURE"\nexit 75\n' \
      "${bash}/bin/bash" >"$disconnect_fake_bin/sudo"
    chmod 0755 "$disconnect_fake_bin/sudo"
    if DISCONNECT_ARGV_CAPTURE="$disconnect_argv_capture" \
      PATH="$disconnect_fake_bin" "$out/bin/fortivpn" disconnect; then
      exit 1
    else
      disconnect_status=$?
    fi
    test "$disconnect_status" -eq 75
    IFS= read -r selected_pkill <"$disconnect_argv_capture"
    case "$selected_pkill" in
      /nix/store/*-procps-*/bin/pkill) ;;
      *) exit 1 ;;
    esac
    trap - EXIT
    rm -rf "$disconnect_root"
    preflight_root=$(mktemp -d)
    trap 'rm -rf "$preflight_root"' EXIT
    preflight_config_home="$preflight_root/config"
    preflight_fake_bin="$preflight_root/bin"
    mkdir -p "$preflight_config_home/openfortivpn" "$preflight_fake_bin"
    printf 'host = vpn.example.com\nport = 443\n' >"$preflight_config_home/openfortivpn/config"
    chmod 0700 "$preflight_config_home/openfortivpn"
    chmod 0600 "$preflight_config_home/openfortivpn/config"
    printf '#!%s\nif [[ $1 == -v ]]; then exit 73; fi\nexit 99\n' "${bash}/bin/bash" \
      >"$preflight_fake_bin/sudo"
    chmod 0755 "$preflight_fake_bin/sudo"
    if HOME="$preflight_root/home" XDG_CONFIG_HOME="$preflight_config_home" \
      PATH="$preflight_fake_bin" "$out/bin/fortivpn"; then
      exit 1
    else
      preflight_status=$?
    fi
    test "$preflight_status" -eq 73
    trap - EXIT
    rm -rf "$preflight_root"

    # Exercise the public wrapper through the second sudo boundary. The fake
    # sudo stops before exec so neither the real VPN nor webview is launched.
    selection_root=$(mktemp -d)
    trap 'rm -rf "$selection_root"' EXIT
    selection_config_home="$selection_root/config"
    selection_fake_bin="$selection_root/bin"
    selection_argv_capture="$selection_root/sudo-argv"
    mkdir -p "$selection_config_home/openfortivpn" "$selection_fake_bin"
    printf 'host = vpn.example.com\nport = 443\n' >"$selection_config_home/openfortivpn/config"
    chmod 0700 "$selection_config_home/openfortivpn"
    chmod 0600 "$selection_config_home/openfortivpn/config"
    printf '#!%s\nif [[ ''${1-} == -v ]]; then exit 0; fi\nprintf "%%s\\n" "$@" >"$SELECTION_ARGV_CAPTURE"\nexit 74\n' \
      "${bash}/bin/bash" >"$selection_fake_bin/sudo"
    printf '#!%s\nprintf "synthetic-cookie"\n' "${bash}/bin/bash" \
      >"$selection_fake_bin/openfortivpn-webview"
    chmod 0755 "$selection_fake_bin/sudo" "$selection_fake_bin/openfortivpn-webview"
    if SELECTION_ARGV_CAPTURE="$selection_argv_capture" \
      HOME="$selection_root/home" XDG_CONFIG_HOME="$selection_config_home" \
      PATH="$selection_fake_bin" "$out/bin/fortivpn"; then
      exit 1
    else
      selection_status=$?
    fi
    test "$selection_status" -eq 74
    IFS= read -r selected_openfortivpn <"$selection_argv_capture"
    test "$selected_openfortivpn" = "$out/libexec/openfortivpn"
    trap - EXIT
    rm -rf "$selection_root"

    # The public wrapper supplies runtime fallbacks after PATH; run dependency
    # absence assertions against its payload so the Bats fakes stay authoritative.
    FORTIVPN_UNDER_TEST="$out/bin/.fortivpn-wrapped" bats tests/fortivpn.bats
    bats tests/i3-vpn-toggle.bats
    runHook postInstallCheck
  '';

  meta = {
    description = "Secure SAML launcher for OpenFortiVPN";
    license = lib.licenses.mit;
    mainProgram = "fortivpn";
    platforms = lib.platforms.linux;
  };
}

{
  lib,
  stdenvNoCC,
  makeWrapper,
  bats,
  bash,
  alacritty,
  fortivpn,
  i3,
  iproute2,
  jq,
  util-linux,
}:
stdenvNoCC.mkDerivation {
  pname = "i3-vpn-toggle";
  inherit (fortivpn) version;
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ makeWrapper ];
  nativeInstallCheckInputs = [ bats ];
  dontBuild = true;

  postPatch = ''
    patchShebangs contrib/i3-vpn-toggle
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 contrib/i3-vpn-toggle "$out/bin/i3-vpn-toggle"
    wrapProgram "$out/bin/i3-vpn-toggle" \
      --suffix PATH : ${lib.makeBinPath [
        alacritty
        bash
        fortivpn
        i3
        iproute2
        jq
        util-linux
      ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    VPN_TOGGLE_UNDER_TEST="$out/bin/i3-vpn-toggle" bats tests/i3-vpn-toggle.bats
    runHook postInstallCheck
  '';

  meta = {
    description = "i3 click-action helper for FortiVPN";
    license = lib.licenses.mit;
    mainProgram = "i3-vpn-toggle";
    platforms = lib.platforms.linux;
  };
}

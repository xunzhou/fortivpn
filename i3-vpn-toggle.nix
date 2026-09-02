{
  lib,
  stdenvNoCC,
  makeWrapper,
  bats,
  bash,
  alacritty,
  coreutils,
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
      --prefix PATH : ${lib.makeBinPath [
        alacritty
        bash
        coreutils
        fortivpn
        i3
        iproute2
        jq
        util-linux
      ]} \
      --set-default FORTIVPN_EXECUTABLE ${fortivpn}/bin/fortivpn
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PATH=${lib.makeBinPath [
      alacritty
      bash
      coreutils
      fortivpn
      i3
      iproute2
      jq
      util-linux
    ]}:$PATH \
      VPN_TOGGLE_UNDER_TEST="$out/bin/.i3-vpn-toggle-wrapped" \
      VPN_TOGGLE_PUBLIC_UNDER_TEST="$out/bin/i3-vpn-toggle" \
      FORTIVPN_EXPECTED_UNDER_TEST="${fortivpn}/bin/fortivpn" \
      bats tests/i3-vpn-toggle.bats
    runHook postInstallCheck
  '';

  meta = {
    description = "i3 click-action helper for FortiVPN";
    license = lib.licenses.mit;
    mainProgram = "i3-vpn-toggle";
    platforms = lib.platforms.linux;
  };
}

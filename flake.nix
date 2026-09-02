{
  description = "Portable secure FortiVPN launcher";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          fortivpn = pkgs.callPackage ./package.nix { };
          default = fortivpn;
        });

      checks = forAllSystems (system: {
        fortivpn = self.packages.${system}.fortivpn;
      });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.bats ];
          };
        });
    };
}

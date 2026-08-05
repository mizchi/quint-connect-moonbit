{
  description = "MoonBit runtime adapter for Quint model-based testing";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bash
              coreutils
              gnused
              just
              quint
              ripgrep
              zsh
            ];

            shellHook = ''
              export PATH="$HOME/.moon/bin:$PATH"
            '';
          };
        });
    };
}

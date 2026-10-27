{
  description = "Temporary turbostat environment for Speedometer power captures";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nushell
          pkgs.linuxPackages.turbostat
          pkgs.msr-tools
        ];
      };
    };
}

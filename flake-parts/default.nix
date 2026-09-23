{ inputs, ... }:
{
  imports = [
    ./checks.nix
    ./deploy.nix
    ./devshell.nix
    ./hosts.nix
    ./packages.nix
    ./secret-scan.nix
    ./treefmt.nix
  ];

  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-darwin"
    "x86_64-linux"
  ];

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
}

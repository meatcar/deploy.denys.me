{ inputs, ... }:
let
  nixpkgs.config.allowUnfree = true;
  specialArgs = { inherit inputs; };
in
{
  flake.nixosConfigurations = {
    vpn = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ../nixos/systems/vpn/configuration.nix ];
    };
    bao = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ../nixos/systems/bao/configuration.nix ];
    };
    baoVps = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inputs.disko.nixosModules.disko
        ../nixos/systems/bao/vps.nix
      ];
    };
    doImage = inputs.nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      system = "x86_64-linux";
      modules = [
        ../nixos/modules/base.nix
        ../nixos/modules/digitalocean.nix
        {
          system.stateVersion = "25.05";
          mine.username = "meatcar";
        }
      ];
    };
    chunkymonkey = inputs.nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      system = "aarch64-linux";
      modules = [
        {
          inherit nixpkgs;
          system.stateVersion = "23.11";
        }
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        ../nixos/systems/chunkymonkey/configuration.nix
      ];
    };
    vps = inputs.nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      system = "x86_64-linux";
      modules = [
        {
          inherit nixpkgs;
          system.stateVersion = "25.05";
        }
        inputs.agenix.nixosModules.default
        ../nixos/systems/vps/configuration.nix
      ];
    };
    cube = inputs.nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      system = "x86_64-linux";
      modules = [
        {
          inherit nixpkgs;
          system.stateVersion = "25.05";
        }
        inputs.agenix.nixosModules.default
        ../nixos/systems/cube/configuration.nix
      ];
    };
  };
}

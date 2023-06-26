{ config, pkgs, lib, ... }:
let
  sshKeys = lib.pipe
    {
      url = "https://github.com/${config.mine.githubKeyUser}.keys";
      sha256 = "sha256:0km1b077qlp8rjh8mi5fpgmm34hxvzarrm290q01h1sxz6x9a52h";
    } [
    builtins.fetchurl
    builtins.readFile
    (lib.splitString "\n")
  ];
in
{
  options.mine = {
    githubKeyUser = lib.mkOption {
      type = lib.types.str;
      description = "The github user that provides the ssh keys to authorize.";
    };
    username = lib.mkOption {
      type = lib.types.str;
      description = "The default user";
    };
  };

  config = {
    security.sudo.wheelNeedsPassword = false;

    services.sshd.enable = true;
    programs.mosh.enable = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
    users.users = {
      root.openssh.authorizedKeys.keys = sshKeys;
    };

    nix = {
      trustedUsers = [ "root" "@wheel" ];

      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
      };

      optimise.automatic = true;
      gc = {
        automatic = true;
        options = "--delete-older-than 1w";
      };
    };

    system.autoUpgrade = {
      enable = false;
      flake = "github:meatcar/deploy.denys.me#default";
      flags = [ "--update-input" "nixpkgs" ];
    };
  };
}

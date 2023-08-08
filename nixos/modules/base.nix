{ config, pkgs, lib, ... }:
let
  sshKeys = lib.pipe
    {
      url = "https://github.com/${config.mine.githubKeyUser}.keys";
      sha256 = "sha256:04wcfmyzdmd10706j4274f0jh1bghzjh1lxaj9k7acsh6pnh2yyq";
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

      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
        trusted-users = [ "root" "@wheel" ];
      };

      optimise.automatic = true;
      gc = {
        automatic = true;
        dates = "daily";
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

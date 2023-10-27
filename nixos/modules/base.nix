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

    services.openssh.enable = true;
    programs.mosh.enable = true;
    programs.command-not-found.enable = true;
    users.users = {
      root.openssh.authorizedKeys.keys = sshKeys;
    };

    environment.systemPackages =
      with pkgs; [ byobu tmux direnv neovim git htop curl wget ];

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

    services.earlyoom.enable = true;
    services.earlyoom.killHook = pkgs.writeShellScript "earlyoom-kill-hook" ''
      echo "Process $EARLYOOM_NAME ($EARLYOOM_PID) was killed" >> /var/log/earlyoom.log
    '';
  };
}

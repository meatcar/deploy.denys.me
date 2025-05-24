{
  config,
  pkgs,
  lib,
  ...
}: let
  sshKeys =
    lib.pipe
    {
      url = "https://github.com/${config.mine.githubKeyUser}.keys";
      sha256 = "sha256:13sk1s6pzlpzpzjrckaqgnfrsj32qqkdfs9l6labqcbiyg68q8li";
    } [
      builtins.fetchurl
      builtins.readFile
      (lib.splitString "\n")
    ];
in {
  options.mine = {
    githubKeyUser = lib.mkOption {
      type = lib.types.str;
      description = "The github user that provides the ssh keys to authorize.";
    };
    username = lib.mkOption {
      type = lib.types.str;
      description = "The default user";
    };
    notificationEmail = lib.mkOption {
      type = lib.types.str;
      description = "An email address to send system notifications to";
      default = "root";
    };
    persistPath = lib.mkOption {
      type = lib.types.path;
      description = "Mountpoint of main persisted system storeage";
      default = "/persist";
    };
    storagePath = lib.mkOption {
      type = lib.types.path;
      description = "Mountpoint of main storage array";
      default = "/data";
    };
    storageUser = lib.mkOption {
      type = lib.types.str;
      description = "The main user that have R/W access to the storagePath";
      default = "storage";
    };
    storageGroup = lib.mkOption {
      type = lib.types.str;
      description = "The group of users that have R/W access to the storagePath";
      default = "storage";
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

    ids.uids.${config.mine.storageUser} = 997;
    ids.gids.${config.mine.storageUser} = 998;
    users.groups.${config.mine.storageGroup} = {
      gid = config.ids.gids.${config.mine.storageGroup};
    };
    users.users.${config.mine.storageUser} = {
      isSystemUser = true;
      uid = config.ids.uids.${config.mine.storageUser};
      group = config.mine.storageGroup;
      shell = pkgs.shadow;
    };

    environment.systemPackages = with pkgs; [byobu tmux direnv neovim git htop curl wget];

    nix = {
      settings = {
        experimental-features = ["nix-command" "flakes"];
        auto-optimise-store = true;
        trusted-users = ["root" "@wheel"];
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
      flags = ["--update-input" "nixpkgs"];
    };

    services.earlyoom.enable = true;
    services.earlyoom.killHook = pkgs.writeShellScript "earlyoom-kill-hook" ''
      echo "Process $EARLYOOM_NAME ($EARLYOOM_PID) was killed" >> /var/log/earlyoom.log
    '';
  };
}

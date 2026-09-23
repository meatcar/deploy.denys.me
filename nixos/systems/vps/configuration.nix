{
  config,
  lib,
  ...
}:
{
  imports = [
    ./secrets.nix # provided by terraform
    ./agenix.nix
    ../../modules/base.nix
    ../../modules/digitalocean.nix
    ../../modules/docker.nix
    ../../modules/backups.nix
    ../../modules/tailscale.nix
    ../../modules/netbird.nix
    ../../modules/acme.nix
    ../../modules/mumble.nix
    ../../modules/znc.nix
    ./modules/nginx.nix
  ];

  mine = {
    username = "meatcar";
    znc = {
      enable = true;
      users = {
        meatcar = {
          extraConfig = {
            Admin = true;
            RealName = "Denys Pavlov";
          };
          networks = {
            freenode = {
              extraConfig = {
                Server = "chat.freenode.net +7000";
              };
            };
          };
        };
      };
    };
  };

  networking = {
    domain = "denys.me";
    hostName = "to";
    nat.externalInterface = "ens3";
  };

  time.timeZone = "America/Toronto";

  boot.loader.grub.configurationLimit = 3;
  nix.gc.options = lib.mkForce "";
  systemd.services.nix-gc.preStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +3";

  services.journald.extraConfig = ''
    SystemMaxUse=1G
  '';

  users.users."${config.mine.username}" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
      "nginx"
    ];
    hashedPasswordFile = config.age.secrets.hashedPassword.path;
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };
}

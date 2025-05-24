{
  config,
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
    ../../modules/wireguard-server.nix
    ../../modules/tailscale.nix
    ../../modules/acme.nix
    ../../modules/mumble.nix
    ../../modules/znc.nix
    ./modules/nginx.nix
  ];

  mine = {
    username = "meatcar";
    githubKeyUser = "meatcar";
    networking.wireguard.serverPort = 51821;
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

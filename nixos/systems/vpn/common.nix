{
  config,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/virtualisation/openstack-config.nix") ];
  system.stateVersion = "26.05";
  openstack.efi = false;
  networking.domain = "denys.me";
  networking.useDHCP = true;
  time.timeZone = "America/Toronto";
  services.qemuGuest.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "prohibit-password";
  };
  systemd.services.vpn-host-key = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "sshd-keygen.service" ];
    after = [ "sshd-keygen.service" ];
    script = ''
      printf 'VPN-SSH-HOST-KEY '
      cat /etc/ssh/ssh_host_ed25519_key.pub
    '';
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
  };
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  environment.systemPackages = with pkgs; [
    curl
    jq
    python3
    restic
  ];
  boot.kernel.sysctl."vm.swappiness" = 0;
  swapDevices = [ ];
  systemd.tmpfiles.rules = [
    "d /var/lib/vpn 0700 root root -"
    "d /var/lib/vpn/backup 0700 root root -"
    "d /etc/vpn 0700 root root -"
  ];
  environment.etc."vpn/role".text = config.networking.hostName;
  environment.etc."vpn-tools/bootstrap.py".source = ./bootstrap.py;
  services.restic.backups.vpn = {
    initialize = true;
    repositoryFile = "/etc/vpn/restic-repository";
    passwordFile = "/etc/vpn/restic-password";
    environmentFile = "/etc/vpn/backup.env";
    paths = [
      "/var/lib/vpn/backup"
      "/etc/vpn"
    ];
    exclude = [
      "/etc/vpn/openbao-initialization.json"
      "/etc/vpn/bootstrap-pat"
      "/etc/vpn/setup-key"
    ];
    backupPrepareCommand = ''
      ${pkgs.python3}/bin/python3 ${./backup.py}
    '';
    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];
    checkOpts = [ "--read-data-subset=5%" ];
  };
  systemd.services.restic-backups-vpn = {
    unitConfig.ConditionPathExists = "/etc/vpn/backup.env";
    serviceConfig.TimeoutStartSec = "2h";
  };
}

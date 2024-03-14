{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.smartmontools pkgs.hdparm pkgs.hd-idle];
  services.smartd = {
    enable = true;
    defaults.monitored = "-a -n standby,24 -o on -s (S/../.././02|L/../../7/04) -d removable";
    notifications = {
      test = true;
      wall.enable = false;
      mail.enable = true;
      mail.sender = "smartd.${config.networking.hostName}@${config.networking.domain}";
    };
  };
}

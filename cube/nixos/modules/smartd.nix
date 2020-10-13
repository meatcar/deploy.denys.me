{ config, pkgs, lib, ... }:
{
  environment.systemPackages = [ pkgs.smartmontools ];
  services.smartd = {
    enable = true;
    defaults.monitored = "-a -n standby,24 -o on -s (S/../.././02|L/../../7/04)";
    notifications = {
      test = true;
      mail = {
        enable = true;
        recipient = config.notificationEmail;
        wall = false;
      };
    };
  };
}

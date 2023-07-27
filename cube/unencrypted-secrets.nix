{ config, ... }: {
  config = {
    smtp.user = "CHANGEME";
    smtp.host = "CHANGEME";
    notificationEmail = "CHANGEME";
    services.nextcloud.fqdn = "CHANGEME";
    wireguardServer = "CHANGEME";
  };
}

{ config, ... }:
let
  inherit (builtins) getEnv;
in
{
  config.mine = {
    smtp.user = getEnv "SMTP_USER";
    smtp.host = getEnv "SMTP_HOST";
    # services.nextcloud.fqdn = getEnv "NEXTCLOUD_FQDN";
    wireguardServer = getEnv "WIREGUARD_SERVER";
    notificationEmail = getEnv "NOTIFICATION_EMAIL";
  };
}

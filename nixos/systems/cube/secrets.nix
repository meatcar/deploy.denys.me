{ config, ... }:
let
  inherit (builtins) getEnv;
in
{
  config.mine = {
    smtp.user = getEnv "SMTP_USER";
    smtp.host = getEnv "SMTP_HOST";
    # services.nextcloud.fqdn = getEnv "NEXTCLOUD_FQDN";
    networking.wireguard.serverName = getEnv "WIREGUARD_SERVER";
    networking.wireguard.serverPublicKey = getEnv "WIREGUARD_SERVER_KEY";
    notificationEmail = getEnv "NOTIFICATION_EMAIL";
  };
}

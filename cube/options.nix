{ config, lib, ... }:
{
  options =
    let
      inherit (lib) mkOption types;
    in
    {
      domain = mkOption {
        type = types.str;
        description = "the base domain name of server";
      };
      hostname = mkOption {
        type = types.str;
        description = "the hostname of the server";
      };
      sshKeysUrl = mkOption {
        type = types.str;
        description = "the URL of the ssh keys to authorize";
      };
      fqdn = mkOption {
        type = types.str;
        default = "${config.hostname}.${config.domain}";
        description = "the Fully Qualified Domain Name of the server";
      };
      persistPath = mkOption {
        type = types.path;
        description = "Mountpoint of main persisted system storeage";
      };
      notificationEmail = mkOption {
        type = types.str;
        description = "An email address to send system notifications to";
      };
      storagePath = mkOption {
        type = types.path;
        description = "Mountpoint of main storage array";
      };
      storageUser = mkOption {
        type = types.str;
        description = "The main user that have R/W access to the storagePath";
        default = "storage";
      };
      storageGroup = mkOption {
        type = types.str;
        description = "The group of users that have R/W access to the storagePath";
        default = "storage";
      };
      wireguardServer = mkOption {
        type = types.str;
        description = "The WireGuard server URL/IP";
      };
    };
}

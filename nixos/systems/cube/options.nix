{ config, lib, ... }:
{
  options =
    let
      inherit (lib) mkOption types;
    in
    {
      mine = {
        persistPath = mkOption {
          type = types.path;
          description = "Mountpoint of main persisted system storeage";
        };
        notificationEmail = mkOption {
          type = types.str;
          description = "An email address to send system notifications to";
          default = "${config.networking.hostName}-notifications@${config.networking.domain}";
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
    };
}

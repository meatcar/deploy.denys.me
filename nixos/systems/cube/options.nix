{ config, lib, ... }:
{
  options =
    let
      inherit (lib) mkOption types;
    in
    {
      mine = {
        notificationEmail = mkOption {
          type = types.str;
          description = "An email address to send system notifications to";
          default = "root";
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
      };
    };
}

{ config, ... }:
let
  secrets = import ../secrets.nix;
in
{
  config = {
    inherit (secrets) notificationEmail;
    smtp = {
      inherit (secrets.smtp) user host;
    };
  };
}

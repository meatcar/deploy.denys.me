{ ... }:
let
  inherit (builtins) getEnv;
in
{
  smtp = {
    user = getEnv "SMTP_USER";
    host = getEnv "SMTP_HOST";
  };
  notificationEmail = getEnv "NOTIFICATION_EMAIL";
}

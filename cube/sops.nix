{ ... }:
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets = {
      ssmtpPass = { };
      transmissionUser = { };
      transmissionPass = { };
      hashedPassword.neededForUsers = true;
      "cloudflare-email" = { };
      "cloudflare-key" = { };
    };
  };
}

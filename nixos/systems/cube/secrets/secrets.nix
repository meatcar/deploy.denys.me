let
  nixos-wsl = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO meatcar@mormont-wsl";
  users = [ nixos-wsl ];
  cube = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH7aKNMDTXhMoruZYYAqbGY2XBY4Uy81zXHYxs7w6UoR";
  systems = [ cube ];
  publicKeys = users ++ systems;
in
{
  "ssmtp-pass.age" = { inherit publicKeys; };
  "transmission-user.age" = { inherit publicKeys; };
  "transmission-pass.age" = { inherit publicKeys; };
  "hashed-password.age" = { inherit publicKeys; };
  "cloudflare-key.age" = { inherit publicKeys; };
  "wg-private-key.age" = { inherit publicKeys; };
  "postgres-pass.age" = { inherit publicKeys; };
  "redis-conf.age" = { inherit publicKeys; };
  "redis-pass.age" = { inherit publicKeys; };
  "nextcloudPgPass.age" = { inherit publicKeys; };
  "freshrssPgPass.age" = {inherit publicKeys;};
  "transitDashboardEnv.age" = {inherit publicKeys;};
}

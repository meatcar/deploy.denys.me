let
  meatcar = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO";
  users = [ meatcar ];
  machines = {
    to = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIi9aWHbQY0fgmzJsT5JgTikgzwcR+iOB6tVLCSep8rL";
    cube = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH7aKNMDTXhMoruZYYAqbGY2XBY4Uy81zXHYxs7w6UoR";
    chunkymonkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA37SIeI0osaeDoehCQ/SbNowUhygnS5PgdJf+majWkI";
  };
  keys = builtins.mapAttrs (_machine: keys: {
    publicKeys = users ++ (if (builtins.isList keys) then keys else [ keys ]);
  }) (machines // { all = builtins.attrValues machines; });
in
{
  # all
  "hashed-password.age" = { inherit (keys.all) publicKeys; };
  "ssmtp-pass.age" = { inherit (keys.all) publicKeys; };

  # to
  "wg-server-priv-key.age" = { inherit (keys.to) publicKeys; };
  "restic-password.age" = { inherit (keys.to) publicKeys; };
  "restic-env.age" = { inherit (keys.to) publicKeys; };
  "restic-repo.age" = { inherit (keys.to) publicKeys; };

  # cube
  "smtp-user.age" = { inherit (keys.cube) publicKeys; };
  "transmission-user.age" = { inherit (keys.cube) publicKeys; };
  "transmission-pass.age" = { inherit (keys.cube) publicKeys; };
  "cloudflare-key.age" = { inherit (keys.cube) publicKeys; };
  "postgres-pass.age" = { inherit (keys.cube) publicKeys; };
  "redis-conf.age" = { inherit (keys.cube) publicKeys; };
  "redis-pass.age" = { inherit (keys.cube) publicKeys; };
  "nextcloudPgPass.age" = { inherit (keys.cube) publicKeys; };
  "freshrssPgPass.age" = { inherit (keys.cube) publicKeys; };

  # chunkymonkey
  "transitDashboardEnv.age" = { inherit (keys.chunkymonkey) publicKeys; };
}

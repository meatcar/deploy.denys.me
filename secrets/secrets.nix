let
  nixos-wsl = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO meatcar@mormont-wsl";
  users = [ nixos-wsl ];
  to = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIi9aWHbQY0fgmzJsT5JgTikgzwcR+iOB6tVLCSep8rL";
  systems = [ to ];
  publicKeys = users ++ systems;
in
{
  "wg-priv-key.age" = { inherit publicKeys; };
  "restic-password.age" = { inherit publicKeys; };
  "restic-env.age" = { inherit publicKeys; };
  "restic-repo.age" = { inherit publicKeys; };
}

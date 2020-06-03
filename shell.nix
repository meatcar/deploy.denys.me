{ pkgs ? import ./nix { } }:
pkgs.mkShell {
  name = "deploy.denys.me";
  buildInputs = with pkgs; [
    niv
    packer
    nixos-generators
    (terraform.withPlugins (p: [
      p.local
      p.external
      p.null
      p.random
      p.aws
      p.digitalocean
      p.cloudflare
    ]))
    wireguard
    jq
    (pkgs.writeShellScriptBin "push-and-rebuild" ''
      IP=$(${pkgs.terraform}/bin/terraform output ip)
      echo Pushing to $IP
      ${pkgs.rsync}/bin/rsync -avz nixos root@$IP:/etc
      ssh root@$IP nixos-rebuild switch
    ''
    )
    (pkgs.writeShellScriptBin "dev-watch" ''
      #SCRIPT="${pkgs.terraform}/bin/terraform apply -auto-approve -target=null_resource.nixos_rebuild"
      while true; do
        ${pkgs.fd}/bin/fd nixos | \
          ${pkgs.entr}/bin/entr -dc push-and-rebuild
      done
    ''
    )
  ];
}

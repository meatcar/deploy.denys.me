{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { self, ... }@inputs:
    (inputs.flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
        in
        {
          devShell = pkgs.mkShell rec {
            name = "deploy.denys.me";
            NIX_PATH = builtins.concatStringsSep ":" [
              "nixpkgs=${inputs.nixpkgs}"
            ];
            buildInputs = with pkgs; [
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
                REMOTE_USER=
                SUDO=
                if ssh root@$IP >/dev/null 2>&1; then
                  REMOTE_USER=root
                else
                  REMOTE_USER=meatcar
                  SUDO=sudo
                fi
                echo "Pushing to $REMOTE_USER@$IP"
                ${pkgs.rsync}/bin/rsync -avz nixos "$REMOTE_USER@$IP:/etc"
                if [ -n "$SUDO" ]; then
                  echo "** sudo password for $REMOTE_USER@$IP will be required..."
                fi
                ssh -t "$REMOTE_USER@$IP" "$SUDO" nixos-rebuild switch
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
          };
        }));
}

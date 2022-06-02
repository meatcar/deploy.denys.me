{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, ... }@inputs:
    let
      nixpkgsConfig = {
        config = { allowUnfree = true; };
      };
      specialArgs = { inherit inputs; };
    in
    (inputs.flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import inputs.nixpkgs (nixpkgsConfig // { inherit system; });
          nix = pkgs.nixFlakes;
          scripts = [
            (pkgs.writeShellScriptBin "push-and-rebuild" ''
              IP=$(${pkgs.terraform}/bin/terraform output --raw ip)
              REMOTE_USER=meatcar
              HOST=$REMOTE_USER@$IP
              # echo "Pushing to $HOST"
              # ${pkgs.rsync}/bin/rsync -avz nixos "$HOST:/etc"
              if [ -n "$SUDO" ]; then
                echo "** sudo password for $HOST will be required..."
              fi
              nixos-rebuild switch --target-host $HOST --flake .#default --use-remote-sudo --impure --build-host $HOST --use-substitutes
            ''
            )
            (pkgs.writeShellScriptBin "dev-watch" ''
              while true; do
              ${pkgs.fd}/bin/fd nixos | \
              ${pkgs.entr}/bin/entr -dc push-and-rebuild
              done
            ''
            )
          ];
        in
        {
          devShells.default = pkgs.mkShell rec {
            name = "deploy.denys.me";
            NIX_PATH = builtins.concatStringsSep ":" [
              "nixpkgs=${inputs.nixpkgs}"
            ];
            shellHook = ''
              export NIX_SSHOPTS=-t
            '';
            buildInputs = with pkgs; scripts ++ [
              inputs.agenix.defaultPackage.${system}
              packer
              nix
              (pkgs.nixos-rebuild.override { inherit nix; })
              (terraform.withPlugins (p: [
                p.local
                p.external
                p.null
                p.random
                p.aws
                p.digitalocean
                p.cloudflare
              ]))
              awscli
              wireguard-tools
              jq
            ];
          };
        })
    // {
      nixosConfigurations.default =
        inputs.nixpkgs.lib.nixosSystem
          {
            inherit specialArgs;
            system = "x86_64-linux";
            modules = [
              { nixpkgs = nixpkgsConfig; }
              inputs.agenix.nixosModules.age
              {
                age.secrets = {
                  wg-priv-key.file = ./secrets/wg-priv-key.age;
                  restic-password.file = ./secrets/restic-password.age;
                  restic-env.file = ./secrets/restic-env.age;
                };
              }
              ./nixos/configuration.nix
            ];
          };
    });
}

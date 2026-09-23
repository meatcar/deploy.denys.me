{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        name = "deploy.denys.me";
        inputsFrom = [ config.treefmt.build.devShell ];
        # NOTE: Watson's home cache is on a noexec filesystem.
        shellHook = ''
          export TG_PROVIDER_CACHE_DIR="''${TG_PROVIDER_CACHE_DIR:-$PWD/.terragrunt-cache/providers}"
        '';
        CLI_PROXY_API_CONFIG = toString ../nixos/systems/chunkymonkey/cli-proxy-api.json;
        CLI_PROXY_API_TEST_SETTINGS = builtins.toJSON (
          import ../nixos/modules/quadlets/cli-proxy-api/settings.nix {
            publicHost = "api.example.test";
            bridgeVersion =
              (import ../nixos/modules/quadlets/cli-proxy-api/images.nix { inherit pkgs; }).bridge.version;
          }
        );
        buildInputs = [
          (import ../packages/cli-proxy-api/package.nix { inherit pkgs; })
        ]
        ++ (with pkgs; [
          nil
          nixd
          inputs.agenix.packages.${system}.default
          inputs.age-plugin-1p.packages.${system}.age
          inputs.age-plugin-1p.packages.${system}.age-plugin-1p

          awscli2
          openbao
          jq
          railway
          oci-cli
          opentofu
          terragrunt
          tflint
          python3
          python3Packages.pytest
          python3Packages.python-openstackclient

          deploy-rs
        ]);
      };
    };
}

{ config, lib, ... }:
let
  writers = [ "meatcar/dots" ];
in
{
  services.niks3 = {
    enable = true;
    readProxy = {
      enable = true;
      redirectTTL = "5m";
    };
    oidc.providers.github = {
      issuer = lib.mkDefault "https://token.actions.githubusercontent.com";
      audience = config.services.niks3.serverUrl;
      rules = [
        {
          boundClaims.repository_owner = [ "meatcar" ];
          scopes = [ "read" ];
        }
        {
          # NOTE: pull_request_target runs untrusted code with ref = base branch.
          boundClaims = {
            repository = writers;
            ref = [ "refs/heads/main" ];
            event_name = [
              "push"
              "schedule"
              "workflow_dispatch"
            ];
          };
          scopes = [ "write" ];
        }
      ];
    };
  };
}

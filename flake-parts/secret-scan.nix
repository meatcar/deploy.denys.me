{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.secret-scan = pkgs.runCommand "secret-scan" {
        src = self;
        GITLEAKS_CONFIG = ../.gitleaks.toml;
        nativeBuildInputs = [
          pkgs.gitleaks
          pkgs.jq
        ];
      } "${pkgs.bash}/bin/bash ${./secret-scan.sh}";
    };
}

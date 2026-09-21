{ pkgs, src }:
let
  inherit (pkgs) lib;
  roots = builtins.filter (root: builtins.pathExists (./. + "/${root}/.terraform.lock.hcl")) (
    lib.unique (
      map (path: builtins.dirOf (lib.removePrefix "${toString ./.}/" (toString path))) (
        builtins.filter (lib.hasSuffix ".tf") (lib.filesystem.listFilesRecursive ./.)
      )
    )
  );
  lockHash = builtins.hashString "sha256" (
    lib.concatMapStrings (root: builtins.readFile (./. + "/${root}/.terraform.lock.hcl")) roots
  );
  platform = "${pkgs.stdenv.hostPlatform.parsed.kernel.name}_${pkgs.stdenv.hostPlatform.go.GOARCH}";
  providers =
    pkgs.runCommand "terraform-providers-${platform}-${builtins.substring 0 12 lockHash}"
      {
        nativeBuildInputs = [ pkgs.opentofu ];
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash =
          {
            x86_64-linux = "sha256-0AaAh2GqFOY61QQHS9lOV9sI4EUlxoGqq73KO3LVq3I=";
            aarch64-linux = "sha256-M48UnX5lBE7cS64/0GpV0kgpMyjafJpDe2clfHkaOLE=";
          }
          .${pkgs.stdenv.hostPlatform.system};
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        cp -R ${./.} terraform
        chmod -R u+w terraform
        for root in ${lib.escapeShellArgs roots}; do
          tofu -chdir="terraform/$root" get -no-color
          tofu -chdir="terraform/$root" providers mirror -platform=${platform} "$out"
        done
      '';
  cliConfig = pkgs.writeText "terraform-check.tfrc" ''
    provider_installation {
      filesystem_mirror {
        path = "${providers}"
      }
    }
  '';
in
{
  terraform-lint =
    pkgs.runCommand "terraform-lint"
      {
        nativeBuildInputs = [ pkgs.tflint ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        tflint --chdir=${src}/terraform --recursive --config=${src}/.tflint.hcl
        touch "$out"
      '';

  terraform =
    pkgs.runCommand "terraform-check"
      {
        nativeBuildInputs = [
          pkgs.opentofu
          pkgs.terragrunt
        ];
        TF_CLI_CONFIG_FILE = cliConfig;
        TG_NON_INTERACTIVE = "true";
        passthru.providerMirror = providers;
      }
      ''
        export HOME="$TMPDIR/home" TF_IN_AUTOMATION=1 CHECKPOINT_DISABLE=1
        mkdir -p "$HOME"
        cp -R ${src} source
        chmod -R u+w source
        cd source
        terragrunt --working-dir terraform hcl validate
        mkdir -p terraform/bao/output
        touch terraform/bao/cache-probe.{tfvars,tfstate,tfplan} terraform/bao/output/cache-probe
        terragrunt --working-dir terraform run --all -- init -backend=false -input=false -lockfile=readonly
        terragrunt --working-dir terraform run --all --no-auto-init -- validate -no-color
        if find terraform -path '*/.terragrunt-cache/*' -name 'cache-probe*' | grep -q .; then
          echo "Terragrunt copied excluded local files" >&2
          exit 1
        fi
        for root in ${lib.escapeShellArgs roots}; do
          if [ -n "$(find "terraform/$root" -maxdepth 1 -name '*.tftest.hcl' -print -quit)" ]; then
            tofu -chdir="terraform/$root" init -backend=false -input=false -lockfile=readonly
            # NOTE: OpenTofu 1.11 crashes when mock providers process import blocks.
            rm -f "terraform/$root/imports.tf"
            tofu -chdir="terraform/$root" test -no-color
          fi
        done
        touch "$out"
      '';
}

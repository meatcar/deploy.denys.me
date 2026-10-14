{ pkgs, niks3 }:
let
  inherit (pkgs) lib;
  common = import "${niks3}/nix/checks/common.nix" { inherit pkgs; };
  mockOidc = niks3.packages.${pkgs.stdenv.hostPlatform.system}.mock-oidc-server;
  serverUrl = "http://127.0.0.1:5751";
  s3Credentials = pkgs.writeText "minio-credentials" ''
    MINIO_ROOT_USER=${common.s3AccessKey}
    MINIO_ROOT_PASSWORD=${common.s3SecretKey}
  '';
in
pkgs.testers.runNixOSTest {
  name = "niks3-policy";
  nodes.server =
    { config, ... }:
    {
      imports = [
        niks3.nixosModules.niks3
        ./policy.nix
      ];
      virtualisation.memorySize = 2048;
      nix.settings = common.nixSettings;

      services.minio = {
        enable = true;
        # NOTE: Abandoned upstream. Acceptable as a local fixture only.
        package = pkgs.minio.overrideAttrs (old: {
          meta = old.meta // {
            knownVulnerabilities = [ ];
          };
        });
        rootCredentialsFile = s3Credentials;
      };
      systemd.services.minio-bucket = {
        after = [ "minio.service" ];
        requires = [ "minio.service" ];
        before = [ "niks3.service" ];
        requiredBy = [ "niks3.service" ];
        environment = {
          S3_ENDPOINT_URL = "http://127.0.0.1:9000";
          AWS_ACCESS_KEY_ID = common.s3AccessKey;
          AWS_SECRET_ACCESS_KEY = common.s3SecretKey;
        };
        path = [ pkgs.s5cmd ];
        script = ''
          until s5cmd ls >/dev/null 2>&1; do sleep 1; done
          s5cmd mb s3://${common.s3.bucket} || true
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      systemd.services.mock-oidc = {
        before = [ "niks3.service" ];
        requiredBy = [ "niks3.service" ];
        serviceConfig = {
          ExecStart = "${lib.getExe mockOidc} -addr 127.0.0.1:8080";
          DynamicUser = true;
        };
      };

      services.niks3 = {
        s3 = common.s3 // {
          endpoint = "127.0.0.1:9000";
        };
        inherit (common) apiTokenFile;
        signKeyFiles = [ common.signing.secretKeyFile ];
        inherit serverUrl;
        oidc = {
          allowInsecure = true;
          providers.github.issuer = "http://127.0.0.1:8080/oidc";
        };
      };

      environment.systemPackages = [
        config.services.niks3.package
        pkgs.curl
      ];
    };

  testScript = ''
    import json
    import urllib.parse

    server.wait_for_unit("niks3.service")
    server.wait_for_open_port(5751)

    def token(repository, ref="refs/heads/main", event="push"):
        query = urllib.parse.urlencode({
            "sub": f"repo:{repository}:ref:{ref}",
            "aud": "${serverUrl}",
            "repository_owner": repository.split("/")[0],
            "repository": repository,
            "ref": ref,
            "claims": json.dumps({"event_name": event}),
        })
        return server.succeed(f"curl -sf 'http://127.0.0.1:8081/issue?{query}'").strip()

    def status(path, credential=None):
        auth = f"-u x:{credential}" if credential else ""
        return server.succeed(f"curl -so /dev/null -w '%{{http_code}}' {auth} ${serverUrl}/{path}")

    def build(name):
        return server.succeed(
            f"nix-build --no-out-link -E 'derivation {{ name = \"{name}\"; system = builtins.currentSystem; builder = \"/bin/sh\"; args = [ \"-c\" \"echo {name} > $out\" ]; }}'"
        ).strip()

    def push(path, credential):
        return f"NIKS3_SERVER_URL=${serverUrl} niks3 push --auth-token '{credential}' {path}"

    reader = token("meatcar/other")
    stranger = token("someone/dots")

    with subtest("reads need an owner token"):
        assert status("nix-cache-info") == "401"
        assert status("nix-cache-info", stranger) == "401"
        assert status("nix-cache-info", reader) == "200"

    with subtest("only listed repositories push from trusted main events"):
        path = build("denied")
        for credential in [
            reader,
            token("meatcar/dots", ref="refs/pull/1/merge", event="pull_request"),
            token("meatcar/dots", event="pull_request_target"),
            token("meatcar/dots", ref="refs/heads/feature"),
        ]:
            server.fail(push(path, credential))

    with subtest("listed repository pushes and owner tokens substitute"):
        path = build("allowed")
        server.succeed(push(path, token("meatcar/dots")))
        server.succeed(f"echo 'machine 127.0.0.1 login x password {reader}' > /tmp/netrc")
        server.fail(f"nix copy --from ${serverUrl} --to /tmp/anonymous {path}")
        server.succeed(f"nix copy --option netrc-file /tmp/netrc --from ${serverUrl} --to /tmp/store {path}")
        server.succeed(f"grep -q allowed /tmp/store{path}")
  '';
}

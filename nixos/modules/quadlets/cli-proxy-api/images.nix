{ pkgs }:
let
  buildGoModule = pkgs.buildGoModule.override { go = pkgs.go_1_26; };
  api = buildGoModule rec {
    pname = "cli-proxy-api";
    version = "8.0.28";
    src = pkgs.fetchFromGitHub {
      owner = "router-for-me";
      repo = "CLIProxyAPI";
      tag = "v${version}";
      hash = "sha256-6dD1uZuGNrZJhs7iay2c9v+vEtTU7KsqeSaGzY+EVpk=";
    };
    vendorHash = "sha256-r3yWkdMcM40G9jV7MxW/qNv3E9WrHavFilW24quEf+8=";
    env.CGO_ENABLED = 1;
    subPackages = [ "cmd/server" ];
    ldflags = [
      "-s"
      "-w"
      "-X main.Version=${version}"
    ];
    postInstall = "mv $out/bin/server $out/bin/cli-proxy-api";
  };
  bridge = buildGoModule {
    pname = "pi-bridge";
    version = "0.9.1";
    src = pkgs.fetchFromGitHub {
      owner = "abix5";
      repo = "pi-cliproxyapi-bridge";
      rev = "039c28b23abcc2e475252a92cd115a7eb943a251";
      hash = "sha256-CYrZv/zcPJEgpNPMeemZ7kZepPU1IRG76g636DdwnS4=";
    };
    postPatch = ''
      sed -i 's|github.com/router-for-me/CLIProxyAPI/v7/|github.com/router-for-me/CLIProxyAPI/v8/|g' *.go
      go mod edit -droprequire=github.com/router-for-me/CLIProxyAPI/v7 \
        -require=github.com/router-for-me/CLIProxyAPI/v8@v${api.version}
      sed -i '\|^github.com/router-for-me/CLIProxyAPI/v7 |d' go.sum
      printf '%s\n' \
        'github.com/router-for-me/CLIProxyAPI/v8 v8.0.28 h1:02Rxbbf/cjW4Mxoik6I63ZDOx57JvbGxv6be2EiOjWU=' \
        'github.com/router-for-me/CLIProxyAPI/v8 v8.0.28/go.mod h1:j1Mtcj0TrC66O1JwbSBB03lY3uYPx4J7yHNvU6nDBCo=' >> go.sum
    '';
    vendorHash = "sha256-ZnFeB6BMpjBEZvG5ZlpTYyfwic7eWJO73eEHNib5ZTU=";
    env.CGO_ENABLED = 1;
    buildPhase = ''
      runHook preBuild
      go build -buildmode=c-shared -trimpath -o pi-bridge.so .
      runHook postBuild
    '';
    installPhase = ''
      install -Dm755 pi-bridge.so $out/lib/cli-proxy-api/plugins/pi-bridge-v0.9.1.so
    '';
  };
in
{
  inherit api bridge;
  image = pkgs.dockerTools.buildLayeredImage {
    name = "localhost/cli-proxy-api";
    tag = "${api.version}-pi-${bridge.version}";
    contents = [
      api
      bridge
      pkgs.cacert
    ];
    # NOTE: CLIProxyAPI discovers regular files only, not buildEnv symlinks.
    extraCommands = ''
      mkdir -p plugins
      cp ${bridge}/lib/cli-proxy-api/plugins/pi-bridge-v0.9.1.so plugins/
    '';
    config = {
      Entrypoint = [ "/bin/cli-proxy-api" ];
      Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
      WorkingDir = "/CLIProxyAPI";
    };
  };
}

{ pkgs }:
let
  buildGoModule = pkgs.buildGoModule.override { go = pkgs.go_1_26; };
  api = buildGoModule rec {
    pname = "cli-proxy-api";
    # renovate: datasource=github-releases depName=router-for-me/CLIProxyAPI
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
  bridge = buildGoModule rec {
    pname = "pi-bridge";
    # renovate: datasource=github-tags depName=abix5/pi-cliproxyapi-bridge
    version = "0.9.1";
    src = pkgs.fetchFromGitHub {
      owner = "abix5";
      repo = "pi-cliproxyapi-bridge";
      tag = "v${version}";
      hash = "sha256-CYrZv/zcPJEgpNPMeemZ7kZepPU1IRG76g636DdwnS4=";
    };
    postPatch = ''
      sed -i 's|github.com/router-for-me/CLIProxyAPI/v7/|github.com/router-for-me/CLIProxyAPI/v8/|g' *.go
      go mod edit -droprequire=github.com/router-for-me/CLIProxyAPI/v7 \
        -require=github.com/router-for-me/CLIProxyAPI/v8@v${api.version}
      sed -i '\|^github.com/router-for-me/CLIProxyAPI/v7 |d' go.sum
    '';
    # NOTE: The proxy vendor lets the offline build tidy against the fetched modules.
    proxyVendor = true;
    preBuild = "go mod tidy";
    vendorHash = "sha256-K9i5mtye+OZMbzM0oQIlvomtcNkjlOgZ/5u0PRtv0v0=";
    env.CGO_ENABLED = 1;
    buildPhase = ''
      runHook preBuild
      go build -buildmode=c-shared -trimpath -o pi-bridge.so .
      runHook postBuild
    '';
    installPhase = ''
      install -Dm755 pi-bridge.so $out/lib/cli-proxy-api/plugins/pi-bridge-v${version}.so
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
      cp ${bridge}/lib/cli-proxy-api/plugins/pi-bridge-v${bridge.version}.so plugins/
    '';
    config = {
      Entrypoint = [ "/bin/cli-proxy-api" ];
      Env = [ "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt" ];
      WorkingDir = "/CLIProxyAPI";
    };
  };
}

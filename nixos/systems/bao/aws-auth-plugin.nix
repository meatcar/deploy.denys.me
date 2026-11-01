{ pkgs }:
assert pkgs.stdenv.hostPlatform.system == "x86_64-linux";
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "openbao-auth-aws";
  # renovate: datasource=github-releases depName=openbao/openbao-plugins extractVersion=^auth-aws-v(?<version>.+)$
  version = "0.1.1";
  src = pkgs.fetchurl {
    url = "https://github.com/openbao/openbao-plugins/releases/download/auth-aws-v${finalAttrs.version}/openbao-plugin-auth-aws_linux_amd64_v1.tar.gz";
    hash = "sha256-5+u75+zcfRlZS4B7LrbPs/6AEhMrZxqHzsx6ZcZVEqM=";
  };
  sourceRoot = ".";
  installPhase = "install -Dm555 openbao-plugin-auth-aws_linux_amd64_v1 $out/openbao-plugin-auth-aws";
})

# TODO: Drop when nixpkgs ships doctl >= 1.184.0, which adds `doctl auth login`.
{ pkgs }:
pkgs.doctl.overrideAttrs (
  finalAttrs: _: {
    version = "2.0.0";
    src = pkgs.fetchFromGitHub {
      owner = "digitalocean";
      repo = "doctl";
      tag = "v${finalAttrs.version}";
      hash = "sha256-Q8sVKVowZwAx6Y8+/rsuKTHQA774x/Tp3e4+crPqnEc=";
    };
  }
)

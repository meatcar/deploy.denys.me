{ pkgs ? import ./nix {} }:
pkgs.mkShell {
  name = "deploy.denys.me";
  buildInputs = with pkgs; [
    (
      terraform.withPlugins (
        p: [
          p.local
          p.external
          p.null
          p.random
          p.aws
          p.digitalocean
          p.cloudflare
        ]
      )
    )
    packer
    wireguard
    jq
    nixos-generators
    niv
  ];
}

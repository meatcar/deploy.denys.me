{ ... }:
let
  sources = import ./nix/sources.nix;
in
{
  imports = [
    "${sources.sops-nix}/modules/sops"
  ];
  config = {
    sops = {
      defaultSopsFile = ./secrets.yaml;
      secrets.ssmtpPass = { };
      secrets.transmissionUser = { };
      secrets.transmissionPass = { };
    };
  };
}

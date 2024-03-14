{
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    "${toString modulesPath}/virtualisation/oci-image.nix"
  ];
}

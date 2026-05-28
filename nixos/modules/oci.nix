{
  modulesPath,
  ...
}:
{
  imports = [
    "${toString modulesPath}/virtualisation/oci-image.nix"
  ];
}

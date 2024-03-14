{
  modulesPath,
  pkgs,
  ...
}: {
  imports = [
    "${toString modulesPath}/virtualisation/digital-ocean-image.nix"
  ];

  services.do-agent.enable = true;

  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];
}

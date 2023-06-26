{ modulesPath, pkgs, ... }:
{
  imports = [
    "${toString modulesPath}/virtualisation/digital-ocean-image.nix"
  ];

  services.do-agent.enable = true;

  swapDevices = [{
    device = "/swapfile";
    size = 2048;
  }];

  services.earlyoom.enable = true;
  services.earlyoom.killHook = pkgs.writeShellScript "earlyoom-kill-hook" ''
    echo "Process $EARLYOOM_NAME ($EARLYOOM_PID) was killed" >> /var/log/earlyoom.log
  '';
}

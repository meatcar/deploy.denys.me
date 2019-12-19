{ config, lib, ... }:
{
  services.sshd.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}

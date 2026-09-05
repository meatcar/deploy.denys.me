{ lib, ... }:
{
  imports = [ ./configuration.nix ];

  boot.loader.grub.device = lib.mkForce "";
  fileSystems."/".device = lib.mkForce "/dev/disk/by-label/nixos";
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "nixos"
            ];
            mountpoint = "/";
          };
        };
      };
    };
  };
  virtualisation.amazon-init.enable = false;
  systemd.services.openstack-init.enable = false;
  systemd.services.apply-ec2-data.enable = false;

  services.openbao.settings.listener.private.address = lib.mkForce "10.201.219.143:443";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO me@onepassword"
  ];

  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = true;
  systemd.network.networks."10-uplink" = {
    matchConfig.MACAddress = "fa:16:3e:f5:3a:ee";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = false;
    };
    addresses = [ { Address = "2607:5300:205:200::1c0c/128"; } ];
    routes = [
      {
        Gateway = "2607:5300:205:200::1";
        GatewayOnLink = true;
      }
    ];
    linkConfig.RequiredForOnline = "routable";
  };
}

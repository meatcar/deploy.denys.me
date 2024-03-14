{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "net.ifnames=0"

    # From https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-common.nix
    "nvme.shutdown_timeout=10"
    "nvme_core.shutdown_timeout=10"
    "libiscsi.debug_libiscsi_eh=1"
    "crash_kexec_post_notifiers"

    # VNC console
    "console=tty1"

    # x86_64-linux
    "console=ttyS0"

    # aarch64-linux
    "console=ttyAMA0,115200"
  ];

  networking.timeServers = ["169.254.169.254"];
  networking.useNetworkd = true;
}

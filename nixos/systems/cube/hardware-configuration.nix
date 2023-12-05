{ config, lib, inputs, ... }: {
  imports =
    [
      "${inputs.nixpkgs}/nixos/modules/installer/scan/not-detected.nix"
    ];

  hardware.cpu.intel.updateMicrocode = true;

  boot = {
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
    initrd = {
      availableKernelModules = [
        "ehci_pci"
        "ahci"
        "usb_storage"
        "usbhid"
        "sd_mod"
        # speed up luks
        "aesni_intel"
        "cryptd"
      ];
      kernelModules = [ ];
      supportedFilesystems = [ "btrfs" ];
      luks = {
        reusePassphrases = true;
        devices =
          let
            defaults = {
              fallbackToPassword = true;
              keyFile = "/dev/disk/by-id/usb-SanDisk_Ultra_Fit_4C530000070430202130-0:0";
              keyFileSize = 8192;
            };
            devices = {
              "king120ga" = {
                device = "/dev/disk/by-id/ata-KINGSTON_SA400S37120G_50026B7782881240-part2";
                allowDiscards = true;
              };
              "king120gb" = {
                device = "/dev/disk/by-id/ata-KINGSTON_SA400S37120G_50026B778284DC58-part2";
                allowDiscards = true;
              };
              "zdev1" = { device = "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDHBBJW4"; };
              "zdev2" = { device = "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDHBDGH8"; };
              "zdev3" = { device = "/dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M2FCXZSZ"; };
              "zdev4" = { device = "/dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4N2RF5DJT"; };
            };
          in
          lib.mapAttrs (name: opts: defaults // opts) devices;
      };

    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/mapper/king120ga";
      fsType = "btrfs";
      options = [ "subvol=@root" "ssd" "compress=zstd" ];
    };

    "/.snapshots" = {
      device = "/dev/mapper/king120ga";
      fsType = "btrfs";
      options = [ "subvol=@snapshots" "ssd" "compress=zstd" ];
    };

    "/nix" = {
      device = "/dev/mapper/king120ga";
      fsType = "btrfs";
      options = [ "subvol=@nix" "ssd" "compress=zstd" ];
    };

    "/home" = {
      device = "/dev/mapper/king120ga";
      fsType = "btrfs";
      options = [ "subvol=@home" "ssd" "compress=zstd" ];
    };

    "${config.mine.persistPath}" = {
      device = "/dev/mapper/king120ga";
      fsType = "btrfs";
      options = [ "subvol=@persist" "ssd" "compress=zstd" ];
    };

    "/boot" = {
      device = "/dev/disk/by-id/ata-KINGSTON_SA400S37120G_50026B7782881240-part1";
      fsType = "vfat";
    };
    "/boot-backup" = {
      device = "/dev/disk/by-id/ata-KINGSTON_SA400S37120G_50026B778284DC58-part1";
      fsType = "vfat";
    };

    "${config.mine.storagePath}" = {
      device = "zpool/tank";
      fsType = "zfs";
    };
    "${config.mine.storagePath}/Multimedia/Videos" = {
      device = "zpool/video";
      fsType = "zfs";
    };
  };

  swapDevices = [ ];

  services = {
    fstrim.enable = true;
    btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" "${config.mine.storagePath}" ];
    };
    smartd = {
      devices = [
        { device = "/dev/disk/by-id/ata-KINGSTON_SA400S37120G_50026B778284DC58"; }
        { device = "/dev/disk/by-id/ata-KINGSTON_SA400S37120G_50026B7782881240"; }
        { device = "/dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4M2FCXZSZ"; }
        { device = "/dev/disk/by-id/ata-WDC_WD20EZRX-00D8PB0_WD-WCC4N2RF5DJT"; }
        { device = "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDHBDGH8"; }
        { device = "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDHBBJW4"; }
      ];
    };
  };

  nix.settings.max-jobs = lib.mkDefault 4;
}

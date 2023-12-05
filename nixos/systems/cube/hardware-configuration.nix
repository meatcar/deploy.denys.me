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
      availableKernelModules = [ "ehci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
      kernelModules = [ ];
      supportedFilesystems = [ "btrfs" ];
      luks = {
        reusePassphrases = true;
        devices = {
          "king120ga" = {
            device = "/dev/disk/by-uuid/d289c688-38fc-434e-a8ea-899ebf18a413";
            allowDiscards = true;
            fallbackToPassword = true;
            keyFile = "/dev/disk/by-id/usb-SanDisk_Ultra_Fit_4C530000070430202130-0:0";
            keyFileSize = 8192;
          };

          "king120gb" = {
            device = "/dev/disk/by-uuid/550dd120-9025-427f-b8b2-aff5cc9af18b";
            allowDiscards = true;
            fallbackToPassword = true;
            keyFile = "/dev/disk/by-id/usb-SanDisk_Ultra_Fit_4C530000070430202130-0:0";
            keyFileSize = 8192;
          };
        };
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
      device = "/dev/disk/by-uuid/4C2C-8603";
      fsType = "vfat";
    };
    "/boot-backup" = {
      device = "/dev/disk/by-uuid/4C72-6855";
      fsType = "vfat";
    };

    "${config.mine.storagePath}" = {
      device = "/dev/disk/by-uuid/9fbbc081-5aec-4553-95dd-cf33f5727c28";
      fsType = "btrfs";
      options = [ "compress=zstd" ];
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

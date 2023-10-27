# cube.denys.me

NAS config using NixOS

## Drive Layout

* `/dev/sda` - 112G SSD (`KINGSTON_SA400S37120G` - SN: `50026B7782881240`)

  `sda1` - 512M EFI
  - gdisk: `2048+512M ef00 'EFI System'`
  - `mkfs.vfat`

  `sda2` - LUKS `/dev/mapper/king120ga`
  - gdisk: `1050624-234441614 8309 'Linux LUKS'`
  - `cryptsetup luksFormat /dev/sda2`

* `/dev/sdb` - 112G SSD (`KINGSTON_SA400S37120G` - SN: `50026B778284DC58`)
  `sdb1` - 512M EFI
  - gdisk: `2048+512M ef00 'EFI System'`
  - `mkfs.vfat`

  `sda2` - LUKS `/dev/mapper/king120gb`
  - gdisk: `1050624-234441614 8300 'Linux LUKS'`
  - `cryptsetup luksFormat /dev/sda2`

* `/dev/sdc` - 2TB HDD (`ST2000DM001-9YN165` - SN: `S1E0A734`)
  - `sdc1` - BTRFS RAID10 mounted at `/data`
* `/dev/sdd` - 2TB HDD (`ST2000DM001-9YN165` - SN: `S1F0BYQJ`)
  - `sdd1` - BTRFS RAID10 mounted at `/data`
* `/dev/sde` - 2TB HDD (`WDC_WD20EZRX-00D8PB0` - SN: `WD-WCC4M2FCXZSZ`)
  - `sde1` - BTRFS RAID10 mounted at `/data`
* `/dev/sdf` - 2TB HDD (`WDC_WD20EZRX-00D8PB0` - SN: `WD-WCC4N2RF5DJT`)
  - `sdf1` - BTRFS RAID10 mounted at `/data`

## Partition Layout

```
/             -> /dev/mapper/king120a subvol=@root,compress=zstd
  /.snapshots -> /dev/mapper/king120a subvol=@snapshots,compress=zstd
  /nix        -> /dev/mapper/king120a subvol=@nix,compress=zstd
  /home       -> /dev/mapper/king120a subvol=@home,compress=zstd
  /persist    -> /dev/mapper/king120a subvol=@persist,compress=zstd
  /data       -> /dev/sdc1            compress=zstd
```

## Setting up NixOS

```sh
# Using NixOS 20.03 netboot ISO
# make cryptkey
dd bs=512 count=4 if=/dev/urandom of=cryptkey iflag=fullblock
sudo cryptsetup -v luksFormat /dev/sda2
sudo cryptsetup -v luksFormat /dev/sdb2
sudo cryptsetup luksAddKey /dev/sda2 cryptkey
sudo cryptsetup luksAddKey /dev/sdb2 cryptkey
# mount devices
sudo cryptsetup open --key-file=cryptkey /dev/sda2 king120ga
sudo cryptsetup open --key-file=cryptkey /dev/sdb2 king120gb
# make btrfs
sudo mkfs.btrfs -m raid1 -d raid1 /dev/mapper/kingston{a,b}
# mount btrfs
sudo mount -t btrfs -o defaults,compress=zstd,ssd /dev/mapper/kingstona /mnt
# make subvolumes
sudo btrfs subvolume create /mnt/@root
sudo btrfs subvolume create /mnt/@snapshots
sudo btrfs subvolume create /mnt/@nix
sudo btrfs subvolume create /mnt/@home
sudo btrfs subvolume create /mnt/@persist
# mount subvolumes
sudo umount /mnt
sudo mount -t btrfs -o defaults,compress=zstd,ssd,subvol=@root                    /dev/mapper/kingstona /mnt
sudo mount -t btrfs -o defaults,compress=zstd,ssd,x-mount.mkdir,subvol=@snapshots /dev/mapper/kingstonb /mnt/.snapshots
sudo mount -t btrfs -o defaults,compress=zstd,ssd,x-mount.mkdir,subvol=@nix       /dev/mapper/kingstonb /mnt/nix
sudo mount -t btrfs -o defaults,compress=zstd,ssd,x-mount.mkdir,subvol=@home      /dev/mapper/kingstonb /mnt/home
sudo mount -t btrfs -o defaults,compress=zstd,ssd,x-mount.mkdir,subvol=@persist   /dev/mapper/kingstonb /mnt/persist
sudo mount -t btrfs -o defaults,compress=zstd,x-mount.mkdir                       /dev/sdc1             /mnt/data
# mount efi
sudo mount -o defaults,x-mount.mkdir /dev/sda1 /mnt/boot
# generate config
sudo nixos-generate-config --root /mnt
sudo vim /mnt/etc/nixos/configuration.nix
sudo nixos-install
reboot
```


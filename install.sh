#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/vda"
POOL="tank"
HOSTNAME="nixos"
HOSTID="$(head -c4 /dev/urandom | od -A none -t x4 | awk '{print $1}')"

echo "Wiping $DISK..."
dd if=/dev/zero of="$DISK" bs=1M count=100
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"
sgdisk -o "$DISK"
sgdisk -n1:1M:+512M -t1:EF00 "$DISK"
sgdisk -n2:0:0 -t2:BF01 "$DISK"

echo "Creating ZFS pool..."
modprobe zfs
zpool create -f -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O mountpoint=none \
  -O encryption=off \
  "$POOL" "$DISK"2

echo "Creating ZFS datasets..."
zfs create -o mountpoint=legacy "$POOL"/root
zfs create -o mountpoint=legacy "$POOL"/nix
zfs create -o mountpoint=legacy "$POOL"/home

echo "Mounting filesystems..."
mount -t zfs "$POOL"/root /mnt
mkdir -p /mnt/{boot,nix,home}
mount -t zfs "$POOL"/nix /mnt/nix
mount -t zfs "$POOL"/home /mnt/home
mkfs.fat -F32 "$DISK"1
mount "$DISK"1 /mnt/boot

echo "Generating NixOS configuration..."
nixos-generate-config --root /mnt

echo "Injecting ZFS config..."
cat >/mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "$HOSTNAME";
  networking.hostId = "$HOSTID";

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.devices = [ "$DISK" ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = true;
  boot.zfs.devNodes = "/dev";
  boot.zfs.mirroredBoots = false;

  services.openssh.enable = true;
  users.users.root.initialPassword = "nixos";
}
EOF

echo "Ready for nixos-install. Run 'nixos-install' and reboot."

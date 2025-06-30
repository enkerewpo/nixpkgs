# To build, use:
# nix-build nixos -I nixos-config=nixos/modules/installer/sd-card/sd-image-loongarch64.nix -A config.system.build.sdImage
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../profiles/minimal.nix
    ./sd-image.nix
  ];

  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible = {
      enable = true;
    };
  };

  boot.consoleLogLevel = lib.mkDefault 7;
  boot.kernelParams = [ "console=ttyS0" ];

  sdImage = {
    populateFirmwareCommands = "";
    populateRootCommands = let
        nixPathRegistrationFile = config.sdImage.nixPathRegistrationFile;
    in
      ''
        mkdir -p ./files/boot ./files/bin ./files/sbin ./files/etc ./files/var 
        mkdir -p ./files/dev ./files/run ./files/tmp ./files/proc ./files/sys
        # copy busybox to bin
        cp ${pkgs.busybox}/bin/busybox ./files/bin/busybox
        cd ./files/bin
        ln -sf busybox sh
        ln -sf busybox mount
        ln -sf busybox ls
        ln -sf busybox mkdir
        ln -sf busybox ln
        ln -sf busybox rm
        ln -sf busybox chmod
        ln -sf busybox cat
        ln -sf busybox head
        ln -sf busybox echo
        ln -sf busybox mountpoint
        cd ../..
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot

        # create a wrapper init at sbin
        cat > ./files/sbin/init << 'EOF'
        #!/bin/sh
        set -euo pipefail
        set -x
        busybox_path=/bin/busybox
        $busybox_path echo "busybox_path: $busybox_path"
        system_path=$($busybox_path ls -d /nix/store/*-nixos-system-* | $busybox_path head -n1)
        $busybox_path echo -e "\033[1;33mmounting essential filesystems\033[0m"
        $busybox_path mount -t proc proc /proc
        $busybox_path mount -t sysfs sysfs /sys
        
        # only mount devtmpfs only when it's not mounted before
        if ! $busybox_path mountpoint -q /dev; then
          $busybox_path mount -t devtmpfs devtmpfs /dev
        fi
        $busybox_path mount -t tmpfs tmpfs /run
        $busybox_path mount -t tmpfs tmpfs /tmp
        $busybox_path mount -t tmpfs tmpfs /var
        if [ -f ${nixPathRegistrationFile} ]; then
          $busybox_path echo -e "\033[1;33mHello from wheatfox, now we are going to unpack the nix store\033[0m"
          ${config.nix.package.out}/bin/nix-store --load-db < ${nixPathRegistrationFile}
          $busybox_path touch /etc/NIXOS
          $busybox_path rm -f ${nixPathRegistrationFile}
        fi
        $busybox_path echo -e "\033[1;33mBooting NixOS :D\033[0m"
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set $system_path
        $busybox_path ln -sf /nix/var/nix/profiles/system /run/current-system
        exec /run/current-system/init

        EOF
        
        chmod +x ./files/sbin/init
      '';
  };
}

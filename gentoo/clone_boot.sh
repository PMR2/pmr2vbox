#!/bin/sh
set -e
VBOX_SATA_DEVICE=${VBOX_SATA_DEVICE:-0}
UPLOAD_IMG=${UPLOAD_IMG:-"${VBOX_NAME}.vhd"}
UPLOAD_IMG_PORT=${UPLOAD_IMG_PORT:-1}

alias SSH_CMD="ssh -oStrictHostKeyChecking=no -oBatchMode=Yes -i \"${VBOX_PRIVKEY}\" root@${VBOX_IP}"

VBoxManage createmedium disk --size $VBOX_DISK_SIZE --format VHD \
    --filename "${UPLOAD_IMG}"
VBoxManage storageattach "${VBOX_NAME}" --storagectl SATA \
    --port ${UPLOAD_IMG_PORT} --device ${VBOX_SATA_DEVICE} --type hdd \
    --medium "${UPLOAD_IMG}"

sleep 1

SSH_CMD << EOF
while true; do
    check=\$(ls -crt /dev/disk/by-id/ |tail -n1 |grep -v part)
    [ ! -z "\${check}" ] && break
    sleep 1
done
UPLOAD_IMG_DEVICE=\$(realpath "/dev/disk/by-id/\${check}")
parted --script \${UPLOAD_IMG_DEVICE} \\
    mklabel gpt \\
    mkpart primary 0 1MB \\
    mkpart primary 1MB 100% \\
    set 1 bios_grub on
mkfs.ext4 \${UPLOAD_IMG_DEVICE}2
mkdir -p /mnt/gentoo
mount \${UPLOAD_IMG_DEVICE}2 /mnt/gentoo
rsync -raAHXx \\
    --include=var/log/{apache,tomcat}*/ \\
    --include=var/tmp/tomcat*/ \\
    --exclude={root/.cache,proc,sys,dev,mnt,usr/src,usr/portage,usr/local/portage,tmp,var/tmp,var/log,var/log/{apache,tomcat}*,var/lib/portage/distfiles,var/lib/portage/packages,var/cache/{binpkgs,distfiles},var/db/repos,home/*/\\.cache}/* \\
    / /mnt/gentoo/
mount -t proc proc /mnt/gentoo/proc
mount -R /dev /mnt/gentoo/dev
mount -R /sys /mnt/gentoo/sys
echo 'modules="ena"' >> /mnt/gentoo/etc/conf.d/modules
chroot /mnt/gentoo grub-mkconfig -o /boot/grub/grub.cfg
grub-install --root-directory=/mnt/gentoo \${UPLOAD_IMG_DEVICE}
root_uuid=\$(findmnt -n -r -o UUID /)
mnt_gentoo_uuid=\$(findmnt -n -r -o UUID /mnt/gentoo)
sed -i "s/\${root_uuid}/\${mnt_gentoo_uuid}/" /mnt/gentoo/etc/fstab
umount -R /mnt/gentoo
EOF

VBoxManage storageattach "${VBOX_NAME}" --storagectl SATA \
    --port ${UPLOAD_IMG_PORT} --device ${VBOX_SATA_DEVICE} --type hdd \
    --medium none
VBoxManage closemedium disk ${UPLOAD_IMG}

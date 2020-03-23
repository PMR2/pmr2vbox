#!/bin/sh
set -e
VBOX_SATA_DEVICE=${VBOX_SATA_DEVICE:-0}
UPLOAD_IMG=${UPLOAD_IMG:-"${VBOX_NAME}".vhd}
UPLOAD_IMG_PORT=${UPLOAD_IMG_PORT:-1}

alias SSH_CMD="ssh -oStrictHostKeyChecking=no -oBatchMode=Yes -i \"${VBOX_PRIVKEY}\" root@${VBOX_IP}"

VBoxManage createmedium disk --size $VBOX_DISK_SIZE --format VHD \
    --filename "${UPLOAD_IMG}"
VBoxManage storageattach "${VBOX_NAME}" --storagectl SATA \
    --port ${UPLOAD_IMG_PORT} --device ${VBOX_SATA_DEVICE} --type hdd \
    --medium "${UPLOAD_IMG}"

sleep 1

# XXX TODO use $(lsblk -r | grep disk) before and after and use the diff
# to get the device to set ${UPLOAD_IMG_DEVICE}

UPLOAD_IMG_DEVICE=${UPLOAD_IMG_DEVICE:-sdb}

# XXX the above may be _very_ different if there are multiple disk
# images (to be) attached to the target VM.

SSH_CMD << EOF
parted --script /dev/${UPLOAD_IMG_DEVICE} \\
    mklabel gpt \\
    mkpart primary 0 1MB \\
    mkpart primary 1MB 100% \\
    set 1 bios_grub on
mkfs.ext4 /dev/${UPLOAD_IMG_DEVICE}2
mkdir -p /mnt/gentoo
mount /dev/${UPLOAD_IMG_DEVICE}2 /mnt/gentoo
rsync -raAHX \\
    --include=/var/log/{apache,tomcat}*/ \\
    --include=/var/tmp/tomcat*/ \\
    --exclude=/etc/ssh/ssh_host* \\
    --exclude=/{root,proc,sys,dev,mnt,usr/src,usr/portage,usr/local/portage,tmp,var/tmp,var/log,var/log/{apache,tomcat}*,var/lib/portage/distfiles,var/lib/portage/packages,var/cache/{binpkgs,distfiles},var/db/repos}/* \\
    / /mnt/gentoo/
mount -t proc proc /mnt/gentoo/proc
mount -R /dev /mnt/gentoo/dev
mount -R /sys /mnt/gentoo/sys
echo 'modules="ena"' >> /mnt/gentoo/etc/conf.d/modules
chroot /mnt/gentoo grub-install /dev/${UPLOAD_IMG_DEVICE}
chroot /mnt/gentoo grub-mkconfig -o /boot/grub/grub.cfg
sed -i 's/^UUID=\\S*/'\`grep UUID /mnt/gentoo/boot/grub/grub.cfg |head -n1 | sed 's/.*root=\\(\\S*\\).*/\\1/'\`/ /mnt/gentoo/etc/fstab
chroot /mnt/gentoo rc-update add amazon-ec2 boot
umount -R /mnt/gentoo
EOF

VBoxManage storageattach "${VBOX_NAME}" --storagectl SATA \
    --port ${UPLOAD_IMG_PORT} --device ${VBOX_SATA_DEVICE} --type hdd \
    --medium none
VBoxManage closemedium disk ${UPLOAD_IMG}

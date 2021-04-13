#!/bin/bash
# XXX this script assumes vboxtools has been used to "activate" a
# VirtualBox control environment.

set -e
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# XXX these MUST be read from some configuration file

# TODO should also apply optional step to attach a separate disk image

# BACKUP_* flags are origin restoration endpoints
export BACKUP_HOST=${BACKUP_HOST:-"dist.physiomeproject.org"}
export BACKUP_USER=${BACKUP_USER:-"pmrdemo"}

export DIST_SERVER=${DIST_SERVER:-"https://${BACKUP_HOST}"}
export JARS_SERVER=${JARS_SERVER:-"${DIST_SERVER}/jars"}
export NEO4J_VERSION=${NEO4J_VERSION-"neo4j-community-3.0.1"}
export TOMCAT_VERSION=${TOMCAT_VERSION:-"8.5"}

# TODO figure out usage of TOMCAT_SUFFIX and whether it is applicable
# without complicating things.
export TOMCAT_USER=${TOMCAT_USER:-"tomcat"}
export ZOPE_USER=${ZOPE_USER:-"zope"}
export MORRE_USER=${MORRE_USER:-"${ZOPE_USER}"}
export PMR_HOME=${PMR_HOME:-"/home/${ZOPE_USER}"}
export MORRE_HOME=${MORRE_HOME:-"/home/${MORRE_USER}"}
export BUILDOUT_NAME=${BUILDOUT_NAME:-"pmr2.buildout"}

export SITE_ROOT=${SITE_ROOT:-"pmr"}
export HOST_FQDN=${HOST_FQDN:-"pmr.example.com"}

export PMR_DATA_READ_KEY=${PMR_DATA_READ_KEY:-"${DIR}/pmrdemo_key"}
export PMR_DATA_ROOT=${PMR_DATA_ROOT:-"${PMR_HOME}/pmr2"}
export PMR_ZEO_BACKUP=${PMR_ZEO_BACKUP:-"${PMR_HOME}/backup"}

export ZOPE_INSTANCE_PORT=${ZOPE_INSTANCE_PORT:-"8280"}

# for SETUP_AS_PROD usage
export VBOX_SATA_DEVICE=${VBOX_SATA_DEVICE:-0}
export PROD_DISK_SIZE=${PROD_DISK_SIZE:-"30000"}
export PROD_IMG_NAME=${PROD_IMG_NAME:-"${VBOX_NAME}.data.vhd"}
export PROD_IMG_PORT=${PROD_IMG_PORT:-2}
export PROD_ROOT=${PROD_ROOT:-"/opt/${ZOPE_USER}"}


chmod 600 "${DIR}/pmrdemo_key"


# remaining definitions should be static

# alias SSH_CMD="ssh \"${VBOX_SSH_FLAGS[@]}\" root@${VBOX_IP}"
alias SSH_CMD="ssh -oStrictHostKeyChecking=no -oBatchMode=Yes -i \"${VBOX_PRIVKEY}\" root@${VBOX_IP}"

export BUILDOUT_ROOT="${PMR_HOME}/${BUILDOUT_NAME}"

restore_pmr2_backup () {
    if [ ! -z "${SETUP_AS_PROD}" ]; then
        local prod_root_mounted=$(SSH_CMD "mount | grep \"${PROD_ROOT}\"")
        if [ -z "${prod_root_mounted}" ]; then
            local disks_original=$(SSH_CMD "lsblk -n -r -o NAME,TYPE,UUID -p |grep disk |cut -f1 -d\ ")
            VBoxManage createmedium disk --size ${PROD_DISK_SIZE} --format VHD \
                --filename "${PROD_IMG_NAME}"
            VBoxManage storageattach "${VBOX_NAME}" --storagectl SATA \
                --port ${PROD_IMG_PORT} --device ${VBOX_SATA_DEVICE} --type hdd \
                --medium "${PROD_IMG_NAME}"

            while true; do
                local disks_new=$(SSH_CMD "lsblk -n -r -o NAME,TYPE,UUID -p |grep disk |cut -f1 -d\ ")
                export DATA_DEVICE=$(diff --suppress-common-lines <(echo "${disks_original}") <(echo "${disks_new}") | grep '>' | cut -b3-)
                if [ ! -z "${DATA_DEVICE}" ]; then
                    break
                fi
                sleep 1
            done
        fi

        SSH_CMD <<- EOF
        prod_root_mounted=\$(mount | grep /opt/zope)
        if [ -z "\${prod_root_mounted}" ]; then
            parted --script "${DATA_DEVICE}" \\
                mklabel gpt \\
                mkpart primary 0 1MB \\
                mkpart primary 1MB 100% \\
                set 1 bios_grub on
            mkfs.ext4 "${DATA_DEVICE}2"
            while true; do
                uuid=\$(lsblk -n -r -o NAME,TYPE,UUID -p |grep ${DATA_DEVICE}2 | cut -f3 -d\ )
                if [ ! -z "\${uuid}" ]; then
                    break
                fi
                sleep 1
            done
            echo -e "UUID=\"\${uuid}\"\t${PROD_ROOT}\text4\trw,noatime\t0 0" >> /etc/fstab
            mkdir -p "${PROD_ROOT}"
            mount "${PROD_ROOT}"
            chown -R ${ZOPE_USER}:${ZOPE_USER} "${PROD_ROOT}"
        fi

	/etc/init.d/pmr2.instance stop
	/etc/init.d/pmr2.zeoserver stop
	/etc/init.d/virtuoso stop
	/etc/init.d/morre.pmr2 stop

        if [ ! -L "${PMR_HOME}/pmr2.buildout/var/filestorage/" ]; then
            rm -rf "${PMR_HOME}/pmr2.buildout/var/filestorage/"
            ln -s "${PROD_ROOT}/var/filestorage" "${PMR_HOME}/pmr2.buildout/var/filestorage"
            chown ${ZOPE_USER}:${ZOPE_USER} "${PMR_HOME}/pmr2.buildout/var/filestorage"
        fi
        su - ${ZOPE_USER} -c "mkdir -p \"${PROD_ROOT}/var/filestorage\" "

        if [ ! -L "${PMR_HOME}/pmr2.buildout/var/blobstorage/" ]; then
            rm -rf "${PMR_HOME}/pmr2.buildout/var/blobstorage/"
            ln -s "${PROD_ROOT}/var/blobstorage" "${PMR_HOME}/pmr2.buildout/var/blobstorage"
            chown ${ZOPE_USER}:${ZOPE_USER} "${PMR_HOME}/pmr2.buildout/var/blobstorage"
        fi
        su - ${ZOPE_USER} -c "mkdir -p \"${PROD_ROOT}/var/blobstorage\" "

        if [ ! -L "${PMR_HOME}/neo4j-community-3.0.1/data" ]; then
            rm -rf "${PMR_HOME}/neo4j-community-3.0.1/data"
            ln -s "${PROD_ROOT}/var/lib/neo4j/data" "${PMR_HOME}/neo4j-community-3.0.1/data"
        fi
        su - ${ZOPE_USER} -c "mkdir -p \"${PROD_ROOT}/var/lib/neo4j/data\" "


        if [ ! -L "${PROD_ROOT}/pmr2" ]; then
            rm -rf "${PROD_ROOT}/pmr2"
            ln -s "${PROD_ROOT}/pmr2" ${PMR_DATA_ROOT}
        fi

        if [ ! -L "/var/lib/virtuoso/db" ]; then
            mkdir -p "${PROD_ROOT}/var/lib/virtuoso"
            mv /var/lib/virtuoso/db/ "${PROD_ROOT}/var/lib/virtuoso/"
            ln -s "${PROD_ROOT}/var/lib/virtuoso/db" /var/lib/virtuoso/db
        fi
	EOF

        # TODO deal with PMR_DATA_ROOT more correctly?
        # Doing it this way simply due to how production data is typically
        # organized.
        export PMR_DATA_ROOT="${PROD_ROOT}/pmr2"
        export PMR_ZEO_BACKUP="${PROD_ROOT}/backup"
    fi


    # restore from backup
    SSH_CMD <<- EOF
	mkdir -p "${PMR_DATA_ROOT}"
	ssh-keyscan "${BACKUP_HOST}" >> ~/.ssh/known_hosts 2>/dev/null
	EOF

    # using a standalone ssh agent to forward the keypair into the
    # target machine without copying any actual secrets onto its
    # filesystem.
    eval "$(ssh-agent -s)"

    ssh-add "${PMR_DATA_READ_KEY}"
    SSH_CMD -A <<- EOF
	rsync -av ${BACKUP_USER}@${BACKUP_HOST}: "${PMR_DATA_ROOT}"
	EOF
    ssh-add -D

    # terminate the standalone ssh agent.
    ssh-agent -k

    # the zeo backup is kept as a backup subdir in the full data backup;
    # move that back up one level to keep separated from dvcs repos.

    SSH_CMD <<- EOF
	/etc/init.d/pmr2.instance stop
	/etc/init.d/pmr2.zeoserver stop
	chown -R ${ZOPE_USER}:${ZOPE_USER} $PMR_DATA_ROOT
	mv ${PMR_DATA_ROOT}/backup ${PMR_ZEO_BACKUP}
	cd "${BUILDOUT_ROOT}"
	su ${ZOPE_USER} -c \
	    "bin/repozo -R -r \"${PMR_ZEO_BACKUP}\" -o var/filestorage/Data.fs"
	EOF

    POSTINSTALL_REINDEX="${DIR}/server/postinstall_reindex.sh"

    envsubst \$ZOPE_USER,\$PMR_HOME < "${POSTINSTALL_REINDEX}" | SSH_CMD
}


if [ $# = 0 ]; then
    # enable all local commands/shortcuts
    INSTALL_PMR2="${DIR}/server/install_pmr2.sh"
    INSTALL_MORRE="${DIR}/server/install_morre.sh"
    INSTALL_BIVES="${DIR}/server/install_bives.sh"
    INSTALL_PRODSERVICE="${DIR}/server/install_production_services.sh"
    RESTORE_BACKUP=1
fi

while [[ $# > 0 ]]; do
    opt="$1"
    case "${opt}" in
        --install-pmr2)
            INSTALL_PMR2="${DIR}/server/install_pmr2.sh"
            shift
            ;;
        --install-morre)
            INSTALL_MORRE="${DIR}/server/install_morre.sh"
            shift
            ;;
        --install-bives)
            INSTALL_BIVES="${DIR}/server/install_bives.sh"
            shift
            ;;
        --install-production)
            INSTALL_PRODSERVICE="${DIR}/server/install_production_services.sh"
            shift
            ;;
        --setup-as-production)
            export SETUP_AS_PROD=1
            shift
            ;;
        --restore-backup)
            RESTORE_BACKUP=1
            shift
            ;;
        *)
            die "unknown option '${opt}'"
            ;;
    esac
done

# prepare local ssh-agent and outbound connection
SSH_CMD /etc/init.d/net.eth1 start

# install PMR2
if [ ! -z "${INSTALL_PMR2}" ]; then
    envsubst \$DIST_SERVER,\$ZOPE_USER,\$PMR_HOME < "${INSTALL_PMR2}" | SSH_CMD
fi

# install Morre
if [ ! -z "${INSTALL_MORRE}" ]; then
    envsubst \$DIST_SERVER,\$JARS_SERVER,\$MORRE_USER,\$MORRE_HOME,\$NEO4J_VERSION < "${INSTALL_MORRE}" | SSH_CMD
fi

# install Bives
if [ ! -z "${INSTALL_BIVES}" ]; then
    envsubst \$DIST_SERVER,\$TOMCAT_VERSION,\$TOMCAT_USER < "${INSTALL_BIVES}" | SSH_CMD
fi

# install and setup for production
if [ ! -z "${INSTALL_PRODSERVICE}" ]; then
    envsubst \${BUILDOUT_NAME},\$HOST_FQDN,\$BUILDOUT_ROOT,\$ZOPE_INSTANCE_PORT,\$SITE_ROOT < "${INSTALL_PRODSERVICE}" | SSH_CMD
fi

# restore backup
if [ ! -z "${RESTORE_BACKUP}" ]; then
    if [ -z "${PMR_DATA_READ_KEY}" ]; then
        echo "skipping backup restore; PMR_DATA_READ_KEY undefined"
    else
        restore_pmr2_backup
    fi
fi


# XXX make this cleanup run regardless.
SSH_CMD /etc/init.d/net.eth1 stop

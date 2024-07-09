#!/bin/sh
# XXX this script assumes vboxtools has been used to "activate" a
# VirtualBox control environment.

set -e
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

export BACKUP_HOST=${BACKUP_HOST:-"dist.physiomeproject.org"}
export BACKUP_USER=${BACKUP_USER:-"pmrdemo"}
export DIST_SERVER=${DIST_SERVER:-"https://${BACKUP_HOST}"}

export CELLML_USER=${ZOPE_USER:-"zope"}
export CELLML_HOME=${CELLML_HOME:-"/home/${CELLML_USER}"}

# do NOT set this to www.cellml.org - postfix etc
# Note that this impacts on the reverse proxy line, which means the www.
# will need to be added back in.
export HOST_FQDN=${HOST_FQDN:-"cellml.org"}

export CELLML_DATA_READ_KEY=${CELLML_DATA_READ_KEY:-"${DIR}/cellml_key"}
export CELLML_ZEO_BACKUP=${PMR_ZEO_BACKUP:-"${CELLML_HOME}/backup"}

# static definitions

export BUILDOUT_NAME="cellml.site"
export SITE_ROOT="cellml"
export ZOPE_INSTANCE_PORT=13080

# XXX TODO upstream should implement some shell that sets this up
alias SSH_CMD="ssh -oStrictHostKeyChecking=no -oBatchMode=Yes -i \"${VBOX_PRIVKEY}\" root@${VBOX_IP}"

export BUILDOUT_ROOT="${CELLML_HOME}/${BUILDOUT_NAME}"

restore_cellml_backup () {
    # XXX consider `exec ssh-agent $SCRIPT` to ensure ssh-agent dies
    eval "$(ssh-agent -s)"
    # restore from backup
    # XXX figure out how to better add the keyscan results.
    SSH_CMD <<- EOF
	mkdir -p "${CELLML_ZEO_BACKUP}"
	ssh-keyscan "${BACKUP_HOST}" >> ~/.ssh/known_hosts 2>/dev/null
	EOF

    ssh-add "${CELLML_DATA_READ_KEY}"
    SSH_CMD -A <<- EOF
	rsync -av ${BACKUP_USER}@${BACKUP_HOST}: "${CELLML_ZEO_BACKUP}"
	EOF
    ssh-add -d "${CELLML_DATA_READ_KEY}"

    SSH_CMD <<- EOF
        /etc/init.d/cellml.instance stop
        /etc/init.d/cellml.zeoserver stop
	chown -R ${CELLML_USER}:${CELLML_USER} ${CELLML_ZEO_BACKUP}
	cd "${CELLML_HOME}/cellml.site"
	su ${CELLML_USER} -c \
	    "bin/repozo -R -r \"${CELLML_ZEO_BACKUP}\"/backup -o var/filestorage/Data.fs"
	su ${CELLML_USER} -c \
	    "cp -r \"${CELLML_ZEO_BACKUP}\"/blobstorage var/"
	EOF
    ssh-agent -k
}

if [ $# = 0 ]; then
    # enable all local commands/shortcuts
    CELLML_ORG="${DIR}/server/cellml.org.sh"
    INSTALL_PRODSERVICE="${DIR}/server/install_production_services.sh"
    CONFIGURE_SERVICE="${DIR}/server/configure_services.sh"
    RESTORE_BACKUP=1
fi

while [[ $# > 0 ]]; do
    opt="$1"
    case "${opt}" in
        --install-cellml)
            CELLML_ORG="${DIR}/server/cellml.org.sh"
            shift
            ;;
        --install-production)
            INSTALL_PRODSERVICE="${DIR}/server/install_production_services.sh"
            shift
            ;;
        --configure-services)
            CONFIGURE_SERVICE="${DIR}/server/configure_services.sh"
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

# install CELLML
if [ ! -z "${CELLML_ORG}" ]; then
    envsubst \$CELLML_USER,\$CELLML_HOME < "${CELLML_ORG}" | SSH_CMD
fi

# install and setup for production
if [ ! -z "${INSTALL_PRODSERVICE}" ]; then
    envsubst \${BUILDOUT_NAME},\$HOST_FQDN,\$BUILDOUT_ROOT,\$ZOPE_INSTANCE_PORT,\$SITE_ROOT < "${INSTALL_PRODSERVICE}" | SSH_CMD
fi

# configure production services for usage.
if [ ! -z "${CONFIGURE_SERVICE}" ]; then
    envsubst \${BUILDOUT_NAME},\$HOST_FQDN,\$BUILDOUT_ROOT,\$ZOPE_INSTANCE_PORT,\$SITE_ROOT < "${CONFIGURE_SERVICE}" | SSH_CMD
fi

# restore backup
if [ ! -z "${RESTORE_BACKUP}" ]; then
    if [ -z "${CELLML_DATA_READ_KEY}" ]; then
        echo "skipping backup restore; CELLML_DATA_READ_KEY undefined"
    else
        restore_cellml_backup
    fi
fi

# XXX make this cleanup run regardless.
SSH_CMD /etc/init.d/net.eth1 stop

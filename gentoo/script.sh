#!/bin/sh
# XXX this script assumes vboxtools has been used to "activate" a
# VirtualBox control environment.

set -e
# XXX these MUST be read from some configuration file

# BACKUP_* flags are origin restoration endpoints
# export BACKUP_HOST=
# export BACKUP_USER=
# export BACKUP_DATA_PATH=
#
# export DIST_SERVER=https://dist.physiomeproject.org/
# export JARS_SERVER=
# export NEO4J_VERSION=neo4j-community-3.0.1
# export TOMCAT_VERSION=8.5
# TODO figure out usage of TOMCAT_SUFFIX and whether it is applicable
# without complicating things.
# export TOMCAT_USER=tomcat
# XXX PMR_HOME should be configured
# XXX should also apply a step to attach a separate drive
# export PMR_HOME=
# export MORRE_HOME=

# export ZOPE_USER=zope
# export MORRE_USER=zope
# export BUILDOUT_NAME="pmr2.buildout"

# export SITE_ROOT=plone
# export HOST_FQDN="pmr.example.com"

# export PMR_DATA_READ_KEY=
# export PMR_DATA_ROOT=
# export PMR_ZEO_BACKUP=

export ZOPE_INSTANCE_PORT=8280

# XXX TODO upstream should implement some shell that sets this up
alias SSH_CMD="ssh -oStrictHostKeyChecking=no -oBatchMode=Yes -i \"${VBOX_PRIVKEY}\" root@${VBOX_IP}"

export BUILDOUT_ROOT="${PMR_HOME}/${BUILDOUT_NAME}"


restore_pmr2_backup () {
    eval "$(ssh-agent -s)"

    # restore from backup
    SSH_CMD <<- EOF
	mkdir -p "${PMR_DATA_ROOT}"
	ssh-keyscan "${BACKUP_HOST}" >> ~/.ssh/known_hosts 2>/dev/null
	EOF

    ssh-add "${PMR_DATA_READ_KEY}"
    SSH_CMD -A <<- EOF
	rsync -av ${BACKUP_USER}@${BACKUP_HOST}: "${PMR_DATA_ROOT}"
	EOF
    ssh-add -d "${PMR_DATA_READ_KEY}"

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
    ssh-agent -k

    POSTINSTALL_REINDEX="server/postinstall_reindex.sh"

    envsubst \$ZOPE_USER,\$PMR_HOME < "${POSTINSTALL_REINDEX}" | SSH_CMD
}


if [ $# = 0 ]; then
    # enable all local commands/shortcuts
    INSTALL_PMR2=server/install_pmr2.sh
    INSTALL_MORRE=server/install_morre.sh
    INSTALL_BIVES=server/install_bives.sh
    SETUP_PRODUCTION=server/install_production_services.sh
    RESTORE_BACKUP=1
fi

while [[ $# > 0 ]]; do
    opt="$1"
    case "${opt}" in
        --install-pmr2)
            INSTALL_PMR2=server/install_pmr2.sh
            shift
            ;;
        --install-morre)
            INSTALL_MORRE=server/install_morre.sh
            shift
            ;;
        --install-bives)
            INSTALL_BIVES=server/install_bives.sh
            shift
            ;;
        --install-production)
            SETUP_PRODUCTION=server/install_production_services.sh
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
if [ ! -z "${SETUP_PRODUCTION}" ]; then
    envsubst \${BUILDOUT_NAME},\$HOST_FQDN,\$BUILDOUT_ROOT,\$ZOPE_INSTANCE_PORT,\$SITE_ROOT < "${SETUP_PRODUCTION}" | SSH_CMD
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

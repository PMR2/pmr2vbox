#!/bin/sh
# XXX this script assumes vboxtools has been used to "activate" a
# VirtualBox control environment.

set -e

# static definitions

# XXX TODO upstream should implement some shell that sets this up
alias SSH_CMD="ssh -oStrictHostKeyChecking=no -oBatchMode=Yes -i \"${VBOX_PRIVKEY}\" root@${VBOX_IP}"

if [ $# = 0 ]; then
    # enable all local commands/shortcuts
    PHYSIOME_COKO=server/install_physiome-coko.sh
    RESTORE_BACKUP=1
fi

while [[ $# > 0 ]]; do
    opt="$1"
    case "${opt}" in
        --install-cellml)
            PHYSIOME_COKO=server/cellml.org.sh
            shift
            ;;
        *)
            die "unknown option '${opt}'"
            ;;
    esac
done

# prepare local ssh-agent and outbound connection
SSH_CMD /etc/init.d/net.eth1 start

# install physiome-coko
if [ ! -z "${PHYSIOME_COKO}" ]; then
    envsubst "" < "${PHYSIOME_COKO}" | SSH_CMD
fi

# XXX make this cleanup run regardless.
SSH_CMD /etc/init.d/net.eth1 stop

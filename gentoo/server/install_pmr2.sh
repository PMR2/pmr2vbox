#!/bin/bash
set -e

# XXX TODO move all paths hardcoded below to here as variables
ODBC_INI=/etc/unixODBC/odbc.ini

mkdir -p /etc/portage/repos.conf

cat << EOF > /etc/portage/repos.conf/pmr2-overlay.conf
[pmr2-overlay]
location = /var/db/repos/pmr2-overlay
sync-type = git
sync-uri = https://github.com/PMR2/portage.git
priority = 50
auto-sync = Yes
EOF

cat << EOF > /etc/portage/package.use/pmr2
# required by dev-db/virtuoso-server-6.1.6::pmr2-overlay
# required by dev-db/virtuoso-server::pmr2-overlay (argument)
sys-libs/zlib minizip
EOF

mkdir -p /etc/portage/package.accept_keywords

cat << EOF > /etc/portage/package.accept_keywords/pmr2
# omniORB
net-misc/omniORB ~amd64
EOF

cat << EOF > /etc/portage/package.use/mesa
# for the opencmiss dependencies.
media-libs/mesa X
media-libs/libglvnd X
EOF

cat << EOF > /etc/portage/package.mask/virtualenv
>=dev-python/virtualenv-20
EOF

# Installing build and installation dependencies plus Virtuoso

emerge --sync pmr2-overlay
emerge --noreplace dev-lang/python:2.7 dev-lang/python:3.8
emerge --noreplace net-misc/omniORB::pmr2-overlay \
    dev-util/cmake dev-db/unixODBC \
    media-libs/mesa media-libs/glu \
    dev-python/cffi media-libs/openjpeg media-libs/libjpeg-turbo \
    dev-python/virtualenv \
    dev-db/virtuoso-odbc::pmr2-overlay \
    dev-db/virtuoso-server::pmr2-overlay \
    dev-db/virtuoso-vad-conductor::pmr2-overlay

# Add a default virtuoso OpenRC init script.

cat << EOF > /etc/init.d/virtuoso
#!/sbin/openrc-run
# Distributed under the terms of the GNU General Public License v2

DAEMON=/usr/bin/virtuoso-t
NAME=virtuoso
SHORTNAME=virtuoso
DESC="Virtuoso OpenSource Edition"
DBPATH=/var/lib/virtuoso/db
LOGDIR=/var/lib/virtuoso

PIDFILE="\${PIDFILE:-/var/run/\${NAME}.pid}"


depend() {
    need net
}

start() {
    ebegin "Starting \${SVCNAME}"
    if [ -z "\$DAEMONUSER" ] ; then
        start-stop-daemon --start --quiet \\
                    --user \`id -un\` \\
                    --chdir \$DBPATH --exec \$DAEMON \\
                    -- \$DAEMON_OPTS
    else
        # if we are using a daemonuser then change the user id
        start-stop-daemon --start --quiet \\
                    --user \$DAEMONUSER --chuid \$DAEMONUSER \\
                    --chdir \$DBPATH --exec \$DAEMON \\
                    -- \$DAEMON_OPTS
    fi
    # Write the pid file using the process id from virtuoso.lck
    if [ ! -f \$DBPATH/\$SHORTNAME.lck ]; then
        # wait another second for the lock file to be written
        sleep 1
    fi
    sed 's/VIRT_PID=//' \$DBPATH/\$SHORTNAME.lck > \$PIDFILE 2>/dev/null
    retval=\$?
    eend \${retval}
}

stop() {
    ebegin "Stopping \${SVCNAME}"
    # http://docs.openlinksw.com/virtuoso/signalsandexitcodes.html says
    # TERM should be used by rc.d scripts, so we do
    # Stop the process using the wrapper
    if [ -z "\$DAEMONUSER" ] ; then
        start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 \\
                    --pidfile \$PIDFILE \\
                    --user \`id -un\` \\
                    --exec \$DAEMON
    else
    # if we are using a daemonuser then look for process that match
        start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 \\
                    --pidfile \$PIDFILE \\
                    --user \$DAEMONUSER \\
                    --exec \$DAEMON
    fi
    retval=\$?
    rm -f \$PIDFILE
    eend \${retval}
}
EOF

if ! grep -e '^\[VOS\]' "${ODBC_INI}" 2>/dev/null >/dev/null; then
    cat <<- EOF >> "${ODBC_INI}"
	[VOS]
	Driver          = /usr/lib64/virtodbc.so
	Description     = Virtuoso OpenSource Edition
	Address         = localhost:1111
	Locale          = en.UTF-8

	EOF
fi

chmod +x /etc/init.d/virtuoso
rc-update add virtuoso default

# Install PMR2

if ! id -u ${ZOPE_USER} > /dev/null 2>&1; then
    useradd -m -k /etc/skel ${ZOPE_USER}
fi

mkdir -p "${PMR_HOME}"
chown ${ZOPE_USER}:${ZOPE_USER} "${PMR_HOME}"

cd "${PMR_HOME}"
if [ ! -d pmr2.buildout ]; then
    su ${ZOPE_USER} -c "git clone https://github.com/PMR2/pmr2.buildout"
fi

cd pmr2.buildout
# TODO git checkout ${PMR_RELEASE_BRANCH}

# original bootstrap zc.buildout
# su ${ZOPE_USER} -c "bin/python bootstrap.py"

# Force Python 2 be the default for the zope user (eselect lost py2 support)
su ${ZOPE_USER} -c "ln -sf /usr/bin/python2.7 /home/${ZOPE_USER}/bin/python"
echo "export PATH=/home/${ZOPE_USER}/bin:"'${PATH}' > /home/${ZOPE_USER}/.bashrc
chown ${ZOPE_USER}:${ZOPE_USER} /home/${ZOPE_USER}/.bashrc

# virtualenv zc.buildout
su ${ZOPE_USER} -c "virtualenv . -p /usr/bin/python2.7"
# TODO extract setuptools version from the buildout config that has it
su ${ZOPE_USER} -c "bin/pip install -U zc.buildout==1.7.1 setuptools==20.1.1"

# TODO figure out how to specify options/customize a base set of options
# su ${ZOPE_USER} -c "bin/buildout -c buildout-git.cfg"
su ${ZOPE_USER} -c "bin/buildout -c deploy-all.cfg"

# ZincJSGroupExporter

cd "${PMR_HOME}"
if [ ! -d ZincJSGroupExporter ]; then
    su ${ZOPE_USER} -c "git clone https://github.com/metatoaster/ZincJSGroupExporter.git"
fi
cd ZincJSGroupExporter
su ${ZOPE_USER} -c "git checkout rebuild"
su ${ZOPE_USER} -c "virtualenv . -p /usr/bin/python3.8"
su ${ZOPE_USER} -c "bin/pip install --no-index --find-links=https://dist.physiomeproject.org opencmiss.zinc"
su ${ZOPE_USER} -c "bin/pip install -e ."


# Set up OpenRC init scripts for PMR2

S=\\\$

PMR_PROFILE=deploy \
    PMR_USER=${ZOPE_USER} \
    PMR_GROUP=${ZOPE_USER} \
    PMR_HOME="${PMR_HOME}/pmr2.buildout" \
        envsubst ${S}PMR_HOME,\$PMR_USER,\$PMR_GROUP,\$PMR_PROFILE < \
            servicescript/openrc/pmr2.instance > /etc/init.d/pmr2.instance

PMR_PROFILE=deploy \
    PMR_USER=${ZOPE_USER} \
    PMR_GROUP=${ZOPE_USER} \
    PMR_HOME="${PMR_HOME}/pmr2.buildout" \
        envsubst ${S}PMR_HOME,\$PMR_USER,\$PMR_GROUP,\$PMR_PROFILE < \
            servicescript/openrc/pmr2.zeoserver > /etc/init.d/pmr2.zeoserver

chmod +x /etc/init.d/pmr2.instance
chmod +x /etc/init.d/pmr2.zeoserver

rc-update add pmr2.zeoserver default
rc-update add pmr2.instance default

if [ ! -f /var/lib/virtuoso/db/virtuoso.db ]; then
    # Start virtuoso and import schema
    # XXX TODO make optional/detect whether it's been done
    /etc/init.d/virtuoso start
    sleep 3

    # TODO figure out a better location than this?
    SCHEMA_HOME=/var/lib/virtuoso/db

    SCHEMA_FILES="
    celltype.owl
    chebi.owl
    fma.owl
    go.owl
    OPBv1.04.owl
    rdf-schema.rdf
    sbmlrdfschema.rdf
    "

    for file in ${SCHEMA_FILES}; do
        if [ ! -f "${SCHEMA_HOME}/${file}" ]; then
            wget ${DIST_SERVER}/schema/${file} -O "${SCHEMA_HOME}/${file}"
        fi
    done

    isql-v <<- EOF
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/fma.owl'), '', 'http://namespaces.physiomeproject.org/fma.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/go.owl'), '', 'http://namespaces.physiomeproject.org/go.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/celltype.owl'), '', 'http://namespaces.physiomeproject.org/celltype.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/chebi.owl'), '', 'http://namespaces.physiomeproject.org/chebi.owl');
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/OPBv1.04.owl'), '', 'http://namespaces.physiomeproject.org/opb.owl');

	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/rdf-schema.rdf'), '', 'http://namespaces.physiomeproject.org/ricordo-schema.rdf') ;
	DB.DBA.RDF_LOAD_RDFXML_MT (file_to_string_output('${SCHEMA_HOME}/sbmlrdfschema.rdf'), '', 'http://namespaces.physiomeproject.org/ricordo-sbml-schema.rdf');

	rdfs_rule_set('ricordo_rule', 'http://namespaces.physiomeproject.org/ricordo-schema.rdf');
	rdfs_rule_set('ricordo_rule', 'http://namespaces.physiomeproject.org/ricordo-sbml-schema.rdf');
	EOF
fi

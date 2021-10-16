#!/bin/bash
set -e

# various build dependencies

mkdir -p /etc/portage/package.accept_keywords
mkdir -p /etc/portage/package.mask
mkdir -p /etc/portage/package.use

emerge --noreplace \
    dev-lang/python:2.7 \
    dev-python/cffi media-libs/openjpeg media-libs/libjpeg-turbo \
    dev-python/virtualenv

# Install Zope.

if ! id -u $CELLML_USER > /dev/null 2>&1; then
    useradd -m -k /etc/skel $CELLML_USER
fi

mkdir -p "${CELLML_HOME}"
chown ${CELLML_USER}:${CELLML_USER} "${CELLML_HOME}"

# Force Python 2 be the default for the zope user (eselect lost py2 support)
su ${CELLML_USER} -c "
    mkdir -p /home/${CELLML_USER}/bin ;
    ln -sf /usr/bin/python2.7 /home/${CELLML_USER}/bin/python
"
echo "export PATH=/home/${CELLML_USER}/bin:"'${PATH}' > /home/${CELLML_USER}/.bashrc
chown ${CELLML_USER}:${CELLML_USER} /home/${CELLML_USER}/.bashrc

cd "${CELLML_HOME}"
if [ ! -d cellml.site ]; then
    su ${CELLML_USER} -c "git clone https://github.com/PMR2/cellml.site"
fi

cd cellml.site

# original bootstrap zc.buildout
# su ${CELLML_USER} -c "bin/python bootstrap.py"

# virtualenv zc.buildout
# need to bootstrap a sane virtualenv for python 2
su ${ZOPE_USER} -c "virtualenv bootstrap -p /usr/bin/python2.7"
su ${ZOPE_USER} -c "bootstrap/bin/python -m pip install 'virtualenv<20'"
su ${ZOPE_USER} -c "bootstrap/bin/virtualenv . -p /usr/bin/python2.7"
# TODO extract setuptools version from the buildout config that has it
su ${CELLML_USER} -c "bin/pip install -U zc.buildout==1.7.1 setuptools==26.1.1"

# TODO figure out how to specify options/customize a base set of options
# su ${CELLML_USER} -c "bin/buildout -c buildout-git.cfg"
su ${CELLML_USER} -c "bin/buildout -c deploy-all.cfg"

# Set up OpenRC init scripts for CellML zope/plone instances

ZOPE_PROFILE=deploy \
    ZOPE_USER=${CELLML_USER} \
    ZOPE_GROUP=${CELLML_USER} \
    USER_HOME="${CELLML_HOME}/cellml.site" \
        envsubst \$USER_HOME,\$ZOPE_USER,\$ZOPE_GROUP,\$ZOPE_PROFILE < \
            servicescript/openrc/cellml.instance > /etc/init.d/cellml.instance

ZOPE_PROFILE=deploy \
    ZOPE_USER=${CELLML_USER} \
    ZOPE_GROUP=${CELLML_USER} \
    USER_HOME="${CELLML_HOME}/cellml.site" \
        envsubst \$USER_HOME,\$ZOPE_USER,\$ZOPE_GROUP,\$ZOPE_PROFILE < \
            servicescript/openrc/cellml.zeoserver > /etc/init.d/cellml.zeoserver

chmod +x /etc/init.d/cellml.instance
chmod +x /etc/init.d/cellml.zeoserver

rc-update add cellml.zeoserver default
rc-update add cellml.instance default

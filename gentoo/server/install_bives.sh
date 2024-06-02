#!/bin/bash
set -e

cat << EOF > /etc/portage/package.mask/java
EOF

# This assumes the "cups" USE flag is not enabled; otherwise certain
# packages may require other explicit USE flag assignments.
emerge --noreplace \
    www-servers/tomcat:${TOMCAT_VERSION}

# add TOMCAT_SUFFIX when it is required.
TOMCAT_WAR_ROOT="/var/lib/tomcat-${TOMCAT_VERSION}/webapps"
TOMCAT_WARS="
BiVeS-WebApp-1.10.16.war
"

if [ ! -d "${TOMCAT_WAR_ROOT}" ]; then
    /usr/share/tomcat-${TOMCAT_VERSION}/gentoo/tomcat-instance-manager.bash \
        --create
fi

rc-update add tomcat-${TOMCAT_VERSION} default

sed -i 's/^#CATALINA_TMPDIR=/CATALINA_TMPDIR=/' \
    /etc/conf.d/tomcat-${TOMCAT_VERSION}
mkdir -p /var/tmp/tomcat-${TOMCAT_VERSION}
chown tomcat:tomcat /var/tmp/tomcat-${TOMCAT_VERSION}

cat << EOF > /etc/cron.daily/tomcat-${TOMCAT_VERSION}-tmp
#!/bin/sh
/bin/rm -rf /var/tmp/tomcat-${TOMCAT_VERSION}/*
EOF
chmod +x /etc/cron.daily/tomcat-${TOMCAT_VERSION}-tmp

for war in ${TOMCAT_WARS}; do
    if [ ! -f "${TOMCAT_WAR_ROOT}/${war}" ]; then
        wget "${DIST_SERVER}/${war}" -O "${TOMCAT_WAR_ROOT}/${war}"
        chown tomcat:tomcat "${TOMCAT_WAR_ROOT}/${war}"
    fi
done

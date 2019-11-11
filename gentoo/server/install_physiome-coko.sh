POSTGRESQL_VERSION=11
PHYSIOME_USER=physiome

mkdir -p /etc/portage/package.accept_keywords

cat << EOF > /etc/portage/package.accept_keywords/yarn
sys-apps/yarn ~amd64
EOF

cat << EOF > /etc/portage/package.use/physiome_submission
dev-db/postgresql uuid
EOF

emerge --noreplace \
    net-libs/nodejs \
    sys-apps/yarn \
    app-emulation/docker \
    app-crypt/certbot \
    www-servers/apache \
    dev-db/postgresql:${POSTGRESQL_VERSION} \

### Apache

sed -i 's/^APACHE2_OPTS.*/APACHE2_OPTS="-D DEFAULT_VHOST -D INFO -D SSL -D SSL_DEFAULT_VHOST -D LANGUAGE -D PROXY"/' /etc/conf.d/apache2

mkdir -p /var/log/apache2

cat << EOF > /etc/apache2/vhosts.d/ssl_engine.include
## SSL Engine Switch:
# Enable/Disable SSL for this virtual host.
SSLEngine on

## SSLProtocol:
# Don't use SSLv2 anymore as it's considered to be broken security-wise.
# Also disable SSLv3 as most modern browsers are capable of TLS.
SSLProtocol ALL -SSLv2 -SSLv3

## SSL Cipher Suite:
# List the ciphers that the client is permitted to negotiate.
# See the mod_ssl documentation for a complete list.
# This list of ciphers is recommended by mozilla and was stripped off
# its RC4 ciphers. (bug #506924)
SSLCipherSuite ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128:AES256:HIGH:!RC4:!aNULL:!eNULL:!EXPORT:!DES:!3DES:!MD5:!PSK

## SSLHonorCipherOrder:
# Prefer the server's cipher preference order as the client may have a
# weak default order.
SSLHonorCipherOrder On
EOF

### physiome-coko

npm install node-gyp -g

# TODO check each thing individually and not make assumptions for the
# kernel options required for docker
if ! zcat /proc/config.gz | grep -P "CONFIG_IP_NF_NAT=(m|y)" > /dev/null 2>&1; then
    cat >> /usr/src/linux/.config <<- EOF
	CONFIG_IP_NF_TARGET_MASQUERADE=m
	CONFIG_IP_NF_NAT=m
	CONFIG_CGROUP_PIDS=y
	CONFIG_CGROUP_HUGETLB=y
	CONFIG_NET_L3_MASTER_DEV=y
	CONFIG_IPVLAN=m
	CONFIG_CGROUP_NET_PRIO=y
	CONFIG_OVERLAY_FS=m
	CONFIG_NETFILTER_ADVANCED=y
	CONFIG_IP_NF_TARGET_REDIRECT=m
	EOF
    genkernel --oldconfig --no-zfs --no-btrfs all
fi

if ! id -u ${PHYSIOME_USER} > /dev/null 2>&1; then
    useradd -m -k /etc/skel/ ${PHYSIOME_USER}
fi

POSTGRES_DATA_DIR=/var/lib/postgresql/${POSTGRESQL_VERSION}/data
if [ ! -d "${POSTGRES_DATA_DIR}" ]; then
    emerge --config dev-db/postgresql:${POSTGRESQL_VERSION}

    /etc/init.d/postgresql-${POSTGRESQL_VERSION} start
    rc-update add postgresql-${POSTGRESQL_VERSION} default

else
    echo found "${POSTGRES_DATA_DIR}", assume postgres is configured.
fi

# XXX should really check if these exists before doing, but given that
# failure is non-fatal so simply ignore that...
psql -U postgres -d template1 << EOF
    CREATE USER physiome CREATEDB;
    CREATE DATABASE physiome WITH OWNER=physiome;
EOF

psql -U postgres -d physiome << EOF
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

# TODO figure out how to ensure that this instance starts when the
# physiome-coko starts during runtime.
/etc/init.d/docker start
rc-update add docker default
docker run -d --name physiome-camunda -p 8080:8080 camunda/camunda-bpm-platform:latest

# TODO switch to physiome user
su - ${PHYSIOME_USER} -c "/bin/bash" << EOF
if [ ! -d "physiome-coko" ]; then
    git clone https://github.com/digital-science/physiome-coko.git
fi

cd physiome-coko
export NODE_ENV="development"

yarn config set workspaces-experimental true
yarn install --frozen-lockfile
yarn cache clean
yarn dsl-compile
yarn desc
EOF
# don't do this - as this will run in the foreground
# yarn start
echo "Please set up the package/app/.env file manually"
# TODO provide OpenRC init.d script for this daemon

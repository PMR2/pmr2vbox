POSTGRESQL_VERSION=11

mkdir /etc/portage/package.accept_keywords

cat << EOF > /etc/portage/package.accept_keywords/yarn
sys-apps/yarn ~amd64
EOF


cat << EOF > /etc/portage/package.use/physiome_submission
dev-db/postgresql uuid
EOF


emerge --noreplace \
    net-libs/nodejs \
    sys-apps/yarn \
    dev-db/postgresql:${POSTGRESQL_VERSION} \

npm install node-gyp -g


# TODO add the following configuration to kernel to enable docker

# CONFIG_IP_NF_TARGET_MASQUERADE=m
# CONFIG_IP_NF_NAT=m  
# CONFIG_CGROUP_PIDS=y
# CONFIG_CGROUP_HUGETLB=y
# CONFIG_NET_L3_MASTER_DEV=y
# CONFIG_IPVLAN=m
# CONFIG_CGROUP_NET_PRIO=y 
# CONFIG_OVERLAY_FS=m

# CONFIG_NETFILTER_ADVANCED=y
# CONFIG_IP_NF_TARGET_REDIRECT=m


useradd -m -k /etc/skel/ physiome

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


# TODO rules to emerge docker and then run
# docker run -d --name physiome-camunda -p 8080:8080 camunda/camunda-bpm-platform:latest


# TODO switch to physiome user
git clone https://github.com/digital-science/physiome-coko.git
cd physiome-coko
export NODE_ENV="development"
yarn config set workspaces-experimental true
yarn install --frozen-lockfile
yarn cache clean

yarn dsl-compile
yarn desc

yarn start

#!/bin/bash
set -e

# TODO check that both PMR2 and pmrplatform have been fully built and
# data files are available, not just simply check that they exists.

cd "${PMR_HOME}"
for target in pmrplatform pmr2.buildout; do
    if [ ! -d ${target} ]; then
        echo "Installation ${target} is missing; exiting."
        exit 1
    fi
done

cd "${PMR_HOME}/pmr2.buildout"

echo "Generating workspace export file from PMR2..."
su ${ZOPE_USER} -c \
    "bin/instance-deploy debug < \"${PMR_HOME}/pmrplatform/pmr2-migration/pdbg_workspace_export.py\""
if [ ! -f /tmp/workspace_dump.json ]; then
    echo "Workspace dump not found; export failed?"
    exit 1
fi

echo "Generating exposure export file from PMR2..."
su ${ZOPE_USER} -c \
    "bin/instance-deploy debug < \"${PMR_HOME}/pmrplatform/pmr2-migration/pdbg_exposure_export.py\""
if [ ! -f /tmp/exposure_dump.json ]; then
    echo "Exposure dump not found; export failed?"
    exit 1
fi

# TODO Should have some sort of toggle for confirming the removal of
# existing data.

echo "Exporting data from PMR2 into pmrplatform..."
cd "${PMR_HOME}/pmrplatform"

# TODO When the env generation utility becomes available, use it instead.
# TODO make use of `SETUP_AS_PROD` and `PROD_ROOT` when the ability to
# persist becomes a requirement.
cat << EOF > "${PMR_HOME}/pmrplatform/.env"
# Leptos configuration for production version of pmrapp
export LEPTOS_SITE_ADDR="127.0.0.1:9380"
export LEPTOS_SITE_ADDR="0.0.0.0:9380"
export LEPTOS_SITE_ROOT="site"

export BIND_ADDR="0.0.0.0:9380"

# export PMR_ANONYMOUS_READER=true
# export PMR_AUTO_CREATE_DB=true

export PMRAC_DB_URL=sqlite:${PMR_HOME}/pmrplatform/pmrac.db
export PMRAPP_DB_URL=sqlite:${PMR_HOME}/pmrplatform/pmrapp.db
export PMRPC_DB_URL=sqlite:${PMR_HOME}/pmrplatform/pmrpc.db
export PMRTQS_DB_URL=sqlite:${PMR_HOME}/pmrplatform/pmrtqs.db
export PMRPC_IDX_CACHE_KIND="mem-db"

export PMR_REPO_ROOT=${PMR_HOME}/pmrplatform/repo
export PMR_DATA_ROOT=${PMR_HOME}/pmrplatform/data

export SQLX_OFFLINE=true

# This is for zinc as the task runner currently don't have the ability
# to specify required environment variables.
export OC_EXPORTER_RENDERER=osmesa
export PYOPENGL_PLATFORM=osmesa
EOF
chown ${ZOPE_USER}:${ZOPE_USER} "${PMR_HOME}/pmrplatform/.env"

cat << EOF > "${PMR_HOME}/pmrplatform/profiles/env"
export PMR2_BUILDOUT_DIR=${PMR_HOME}/pmr2.buildout
export CMLIBS_VENV_DIR=${PMR_HOME}/opencmiss.zinc
export PMRPLATFORM_BIN_DIR=${PMR_HOME}/pmrplatform/target/release
EOF
chown ${ZOPE_USER}:${ZOPE_USER} "${PMR_HOME}/pmrplatform/profiles/env"

for target in repo data; do
    if [ -d "${PMR_HOME}/pmrplatform/$target" ]; then
        echo "Removing existing $target for pmrplatform..."
        su ${ZOPE_USER} -c "rm -rf \"${PMR_HOME}/pmrplatform/$target\""
    fi
done

echo "Removing existing databases for pmrplatform..."
su ${ZOPE_USER} -c "rm -f \"${PMR_HOME}/pmrplatform/\"pmr*.db*"

echo "Creating initial database for pmrplatform..."
su ${ZOPE_USER} -c "mkdir -p \"${PMR_HOME}/pmrplatform/\"{data,repo}"
su ${ZOPE_USER} -c "sh ./pmrac.sh"
su ${ZOPE_USER} -c "sh ./profiles/import.sh"

echo "Removing ./target/release/deps for disk space..."
su ${ZOPE_USER} -c "rm -rf ./target/release/deps/"

echo "Importing exported workspaces into pmrplatform..."
su ${ZOPE_USER} -c "./target/release/workspace import symlink /opt/zope/pmr2/hg /tmp/workspace_dump.json"

echo "Importing exported exposure into pmrplatform..."
su ${ZOPE_USER} -c "./target/release/exposure import /tmp/exposure_dump.json"

echo "Processing tasks into exposure with the task runner..."
su ${ZOPE_USER} -c "./target/release/pmrctrl-runner -v --poll-until-no-tasks"

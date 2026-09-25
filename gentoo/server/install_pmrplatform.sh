#!/bin/bash
set -e

mkdir -p /etc/portage/package.accept_keywords
mkdir -p /etc/portage/package.mask
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.license

cat << EOF > /etc/portage/package.use/rust
dev-lang/rust clippy miri nightly profiler rustfmt wasm rust_sysroots_wasm  LLVM_TARGETS: WebAssembly
EOF

emerge --noreplace \
    dev-lang/rust\
    net-libs/nodejs

if ! id -u ${ZOPE_USER} > /dev/null 2>&1; then
    useradd -m -k /etc/skel -G cron ${ZOPE_USER}
fi

mkdir -p "${PMR_HOME}"
chown ${ZOPE_USER}:${ZOPE_USER} "${PMR_HOME}"

# Installing pmrplatform.

cd "${PMR_HOME}"
if [ ! -d pmrplatform ]; then
    su ${ZOPE_USER} -c "git clone https://github.com/Physiome/pmrplatform"
fi

# Leptos version of pmrplatform.
# TODO Provide flag to make this optional.
cd pmrplatform
su ${ZOPE_USER} -c "cargo install --locked cargo-leptos"
cd pmrapp
su ${ZOPE_USER} -c "npm install"
su ${ZOPE_USER} -c "npx webpack"
cd ..
su ${ZOPE_USER} -c "cargo build --all-features --release"
su ${ZOPE_USER} -c "cargo leptos build --release"

# PMR2 migration
su ${ZOPE_USER} -c "cargo build -p pmr2-migration --all-features --release"

# The server backend for the vue front end.
su ${ZOPE_USER} -c "cargo build -p pmrapp_vue --release"

# Installing pmrapp-frontend.

# Since gentoo doesn't currently provide `bun` as a ebuild.
# TODO look into if we want to provide this as a ebuild.
su ${ZOPE_USER} -c "npm install -g --prefix ~/.npm bun"

cd "${PMR_HOME}"
if [ ! -d pmrapp-frontend ]; then
    su ${ZOPE_USER} -c "git clone https://github.com/Physiome/pmrapp-frontend"
fi

cd pmrapp-frontend

# FIXME have the _ID be locally defined.
cat << EOF > .env
VITE_BASE_PATH=/
VITE_ENABLE_GH_PAGES_SPA_REDIRECT=false
VITE_API_BASE_URL=http://localhost:9380
VITE_API_BASE_URL_PROXY=http://localhost:8787/cors-proxy
VITE_DOWNLOAD_HOST=
VITE_GITHUB_AUTH_API=https://api.github.com
# FIXME have the following be again sourced locally defined.
VITE_API_BASE_URL=
VITE_DOWNLOAD_API=

VITE_FEATURE_COMPARISON_SHEET_CSV_URL=

VITE_GA_MEASUREMENT_ID=
VITE_GITHUB_CLIENT_ID=
VITE_LOGIN_DISABLED=true
EOF

su ${ZOPE_USER} -c "~/.npm/bin/bun install --frozen-lockfile"
su ${ZOPE_USER} -c "~/.npm/bin/bun run build"

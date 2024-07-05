#!/bin/bash
set -e

emerge --noreplace \
    mail-mta/postfix \
    www-servers/apache

# certbot installation previously was done with emerge, but dependencies
# involved now includes Rust (for the crytpography bindings), resulting
# in extra storage and time usage.  Until we have more things in Rust,
# opting to use a /opt global virtualenv and use wheels for that.

virtualenv /opt
/opt/bin/pip install certbot

# Apache core setup.

sed -i 's/^APACHE2_OPTS.*/APACHE2_OPTS="-D DEFAULT_VHOST -D INFO -D SSL -D SSL_DEFAULT_VHOST -D LANGUAGE -D PROXY"/' /etc/conf.d/apache2

mkdir -p /var/log/apache2

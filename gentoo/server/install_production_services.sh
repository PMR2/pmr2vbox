#!/bin/bash
set -e

emerge --noreplace \
    mail-mta/postfix \
    www-servers/apache \
    app-crypt/certbot

# Postfix setup

# TODO surgically add these configuration settings
cat << EOF >> /etc/postfix/main.cf
myhostname = ${HOST_FQDN}
mydomain = ${HOST_FQDN}
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain,
        mail.\$mydomain, www.\$mydomain, ftp.\$mydomain
mynetworks_style = host
EOF

rc-update add postfix default

# Apache setup.

sed -i 's/^APACHE2_OPTS.*/APACHE2_OPTS="-D DEFAULT_VHOST -D INFO -D SSL -D SSL_DEFAULT_VHOST -D LANGUAGE -D PROXY"/' /etc/conf.d/apache2

mkdir -p /var/log/apache2

cat << EOF > /etc/apache2/modules.d/99_certbot.conf
<Directory "/var/www/.well-known">
        Options -Indexes
        AllowOverride All
        Require all granted
        AddDefaultCharset Off
        Header set Content-Type "text/plain"
</Directory>

ProxyPass /.well-known !
AliasMatch ^/\\.well-known/acme-challenge/(.*)$ /var/www/.well-known/acme-challenge/\$1
EOF


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

cat << EOF > /etc/apache2/vhosts.d/90_${BUILDOUT_NAME}.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName ${HOST_FQDN}

    DocumentRoot ${BUILDOUT_ROOT}/var/www

    <Directory ${BUILDOUT_ROOT}/var/www>
        Options FollowSymLinks MultiViews
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/${HOST_FQDN}.error.log

    # Possible values include: debug, info, notice, warn, error, crit,
    # alert, emerg.
    LogLevel warn

    CustomLog /var/log/apache2/${HOST_FQDN}.access.log combined

    SetOutputFilter DEFLATE
    SetEnvIfNoCase Request_URI "\\.(?:gif|jpe?g|png)$" no-gzip

    # de-chunk the chunked encoding for ZServer (forces Apache to buffer
    # the entire thing by forcing a Content-Length header).
    SetEnv proxy-sendcl 1

    RewriteEngine On
    RewriteCond %{REQUEST_URI} /login
    RewriteCond %{HTTP_REFERER} http://(.*)
    RewriteRule "^/(.*)" "https://${HOST_FQDN}/\$1?came_from=https://%1" [L]

    # RewriteCond %{REQUEST_METHOD} POST
    # RewriteRule "^/.*(?<!git-upload-pack)$" "-" [F,L]

    # RewriteCond %{REQUEST_URI} !^/robots.txt
    RewriteCond %{REQUEST_URI} !^/\\.well\\-known/acme\\-challenge/
    RewriteRule "^/(.*)" "http://127.0.0.1:${ZOPE_INSTANCE_PORT}/VirtualHostBase/http/${HOST_FQDN}:80/${SITE_ROOT}/VirtualHostRoot/\$1" [P]

    # Uncomment when SSL is enabled.
    # Redirect permanent / https://${HOST_FQDN}/
</VirtualHost>

# Uncomment when certbot has been set up to get letsencrypt certificates
#
# <VirtualHost *:443>
#     ServerAdmin webmaster@localhost
#     ServerName ${HOST_FQDN}
#
#     DocumentRoot ${BUILDOUT_ROOT}/var/www
#
#     <Directory ${BUILDOUT_ROOT}/var/www>
#         Options FollowSymLinks MultiViews
#         AllowOverride None
#         Require all granted
#     </Directory>
#
#     ErrorLog /var/log/apache2/${HOST_FQDN}-ssl.error.log
#
#     # Possible values include: debug, info, notice, warn, error, crit,
#     # alert, emerg.
#     LogLevel warn
#
#     CustomLog /var/log/apache2/${HOST_FQDN}-ssl.access.log combined
#
#     Include /etc/apache2/vhosts.d/ssl_engine.include
#
#     SSLCertificateKeyFile /etc/letsencrypt/live/${HOST_FQDN}/privkey.pem
#     SSLCertificateFile /etc/letsencrypt/live/${HOST_FQDN}/fullchain.pem
#
#     Header onsuccess edit Set-Cookie (.*) "\$1;Secure"
#
#     SetOutputFilter DEFLATE
#     SetEnvIfNoCase Request_URI "\\.(?:gif|jpe?g|png)$" no-gzip
#     SetEnv proxy-sendcl 1
#
#     RewriteEngine On
# #     RewriteCond %{REQUEST_URI} !^/robots.txt
#     RewriteCond %{REQUEST_URI} !^/\\.well\\-known/acme\\-challenge/
#     RewriteRule "^/(.*)" "http://127.0.0.1:${ZOPE_INSTANCE_PORT}/VirtualHostBase/https/${HOST_FQDN}:443/${SITE_ROOT}/VirtualHostRoot/\$1" [P]
# </VirtualHost>
EOF

rc-update add apache2 default

# Cronjob for certbot

cat << EOF > /etc/cron.weekly/certbot
#!/bin/sh
set -e

# Certificate must be issued first before it may be renewed
# certbot certonly --webroot -w /var/www -d ${HOST_FQDN}

certbot renew
/etc/init.d/apache2 reload
EOF
chmod +x /etc/cron.weekly/certbot

#!/bin/sh

# Original source : https://github.com/Hostibox/ISPConfig-Let-s-Encrypt-Securing
# Modified version: https://github.com/thctlo/ISPConfig-Let-s-Encrypt-Securing/

# Tested on Debian Buster with supplied certbot of Debian.
# Modified for a change in dns setup.
# 
# Below assumes the following.
# DNS A AAAA and PTR to $(hostname -f) and its ip numbers.
# CNAME MAIL to mail vhost as in (mail.$(hostname -d) 
# 

# The ISP Config pannel runs with the real hostname $(hostname -f )
# The mail services ( incl webmail ) will be pointed to mail.$(hostname -d)
# You need to create these 2 vhost first and enable SSL Lets encrypt. 
# Verify if these are created at/with : ls -al /etc/letsencrypt/live/
# then then all needed certs are there, you can run this script. 
# ISP Panel and PureFTP use "hostname -f" certificate. 
# postfix dovecot use mail.$hostname -d certificates. 

echo "Installing certificate for ISPConfig Panel"
cd /usr/local/ispconfig/interface/ssl/
mv ispserver.crt ispserver.crt-$(date +"%y%m%d%H%M%S").bak
mv ispserver.key ispserver.key-$(date +"%y%m%d%H%M%S").bak

if [ -f ispserver.pem ]; then
    mv ispserver.pem ispserver.pem-$(date +"%y%m%d%H%M%S").bak
fi

# Server hostname.
ln -s /etc/letsencrypt/live/$(hostname -f)/fullchain.pem ispserver.crt
ln -s /etc/letsencrypt/live/$(hostname -f)/privkey.pem ispserver.key
cat ispserver.{key,crt} > ispserver.pem
chmod 600 ispserver.pem

# FTP used hostname cert also.
echo "Installing certificate for Pure-FTPd\n"
cd /etc/ssl/private/
mv pure-ftpd.pem pure-ftpd.pem-$(date +"%y%m%d%H%M%S").bak
ln -s /usr/local/ispconfig/interface/ssl/ispserver.pem pure-ftpd.pem
chmod 600 pure-ftpd.pem
systemctl restart pure-ftpd-mysql


# Mail hostnames
echo "Installing certificate for postfix and dovecot\n"

cd /etc/postfix/
mv smtpd.cert smtpd.cert-$(date +"%y%m%d%H%M%S").bak
mv smtpd.key smtpd.key-$(date +"%y%m%d%H%M%S").bak
ln -s /etc/letsencrypt/live/mail.$(hostname -d)/fullchain.pem smtpd.cert
ln -s /etc/letsencrypt/live/mail.$(hostname -d)/privkey.pem smtpd.key
systemctl restart postfix
systemctl restart dovecot


echo "Installing incrontab"

apt-get install incron -y

echo "Creating post renewal scripts"

echo "#!/bin/sh

### BEGIN INIT INFO
# Provides: LE ISPSERVER.PEM AUTO UPDATER for HOSTNAME
# Required-Start: \$local_fs \$network
# Required-Stop: \$local_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: LE ISPSERVER.PEM AUTO UPDATER HOSTNAME
# Description: Update ispserver.pem automatically after ISPC LE SSL certs are renewed.
### END INIT INFO

# certs that use $(hostname -f) ( FQDN hostname ) of the server. 
cd /usr/local/ispconfig/interface/ssl/ || exit 1
mv ispserver.pem ispserver.pem-\$(date +\"%y%m%d%H%M%S\").bak
cat ispserver.{key,crt} > ispserver.pem
chmod 600 ispserver.pem
chmod 600 /etc/ssl/private/pure-ftpd*.pem

SERVICES=\"apache2 pure-ftpd-mysql monit munin\"
for Service2Restart in \$SERVICES
do
    if [ -d /run/systemd/system ]
    then
        if systemctl --quiet is-active \$Service2Restart
        then
            systemctl --quiet restart \$Service2Restart
        fi
    fi
done
" > /etc/init.d/le_ispc_hostname_pem.sh

echo "#!/bin/sh
### BEGIN INIT INFO
# Provides: LE ISPSERVER.PEM AUTO UPDATER for MAIL
# Required-Start: \$local_fs \$network
# Required-Stop: \$local_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: LE ISPSERVER.PEM AUTO UPDATER
# Description: Update ispserver.pem automatically after ISPC LE SSL certs are renewed.
### END INIT INFO

# certs that use mail.$(hostname -d).
SERVICES=\"postfix dovecot apache2\"
for Service2Restart in \$SERVICES
do
    if [ $Service2Restart = dovecot ]
    	openssl dhparam -out /etc/ssl/private/dovecot-dhparams.pem 2048
	chown root:dovecot /etc/ssl/private/dovecot-dhparams.pem
	chmod 640 /etc/ssl/private/dovecot-dhparams.pem
    fi
    if [ -d /run/systemd/system ]
    then
        if systemctl --quiet is-active \$Service2Restart
        then
            systemctl --quiet restart \$Service2Restart
        fi
    fi
done
" > /etc/init.d/le_ispc_mail_pem.sh

chmod +x /etc/init.d/le_ispc_*_pem.sh

echo "Adding incrontab for post-renewal script execution when certificate changes"

echo "root" >> /etc/incron.allow

incrontab -l > /tmp/incrontab-latest
echo "/etc/letsencrypt/archive/$(hostname -f)/ IN_MODIFY ./etc/init.d/le_ispc_hostname_pem.sh" > /tmp/incrontab-latest
echo "/etc/letsencrypt/archive/mail.$(hostname -d)/ IN_MODIFY ./etc/init.d/le_ispc_hostname_pem.sh" >> /tmp/incrontab-latest
incrontab /tmp/incrontab-latest
rm /tmp/incrontab-latest
incrontab -l

echo "Restarting Apache"
systemctl restart apache2

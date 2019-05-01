#!/bin/sh

echo "Installing certificate for ISPConfig"

cd /usr/local/ispconfig/interface/ssl/
mv ispserver.crt ispserver.crt-$(date +"%y%m%d%H%M%S").bak
mv ispserver.key ispserver.key-$(date +"%y%m%d%H%M%S").bak

if [ -f ispserver.pem ]; then
	mv ispserver.pem ispserver.pem-$(date +"%y%m%d%H%M%S").bak
fi

ln -s /etc/letsencrypt/live/$(hostname -f)/fullchain.pem ispserver.crt
ln -s /etc/letsencrypt/live/$(hostname -f)/privkey.pem ispserver.key
cat ispserver.{key,crt} > ispserver.pem
chmod 600 ispserver.pem

echo "Installing certificate for postfix and dovecot\n"

cd /etc/postfix/
mv smtpd.cert smtpd.cert-$(date +"%y%m%d%H%M%S").bak
mv smtpd.key smtpd.key-$(date +"%y%m%d%H%M%S").bak
ln -s /usr/local/ispconfig/interface/ssl/ispserver.crt smtpd.cert
ln -s /usr/local/ispconfig/interface/ssl/ispserver.key smtpd.key
systemctl restart postfix
systemctl restart dovecot

echo "Installing certificate for Pure-FTPd\n"

cd /etc/ssl/private/
mv pure-ftpd.pem pure-ftpd.pem-$(date +"%y%m%d%H%M%S").bak
ln -s /usr/local/ispconfig/interface/ssl/ispserver.pem pure-ftpd.pem
chmod 600 pure-ftpd.pem
systemctl restart pure-ftpd-mysql

echo "Installing incrontab"

apt-get install incron -y

echo "Creating post renewal script"

cat /etc/init.d/le_ispc_pem.sh <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides: LE ISPSERVER.PEM AUTO UPDATER
# Required-Start: $local_fs $network
# Required-Stop: $local_fs
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: LE ISPSERVER.PEM AUTO UPDATER
# Description: Update ispserver.pem automatically after ISPC LE SSL certs are renewed.
### END INIT INFO
cd /usr/local/ispconfig/interface/ssl/
mv ispserver.pem ispserver.pem-$(date +"%y%m%d%H%M%S").bak
cat ispserver.{key,crt} > ispserver.pem
chmod 600 ispserver.pem
chmod 600 /etc/ssl/private/pure-ftpd.pem
systemctl restart pure-ftpd-mysql
systemctl restart postfix
systemctl restart dovecot
systemctl restart apache2
EOF

chmod +x /etc/init.d/le_ispc_pem.sh

echo "Adding incrontab for post-renewal script execution when certificate changes"

echo "root" >> /etc/incron.allow

incrontab -l > /tmp/incrontab-latest
echo "/etc/letsencrypt/archive/$(hostname -f)/ IN_MODIFY ./etc/init.d/le_ispc_pem.sh" >> /tmp/incrontab-latest
incrontab /tmp/incrontab-latest
rm /tmp/incrontab-latest

echo "Restarting Apache"

systemctl restart apache2

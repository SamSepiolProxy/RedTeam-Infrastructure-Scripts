#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "Script must be run as a root user" 2>&1
  exit 1
fi

echo -n "Enter your DNS (A) record for domain [ENTER]: "
read domain
echo

cd /tmp
apt install dialog -y
wget https://github.com/iredmail/iRedMail/archive/1.6.2.tar.gz
tar -xvf 1.6.2.tar.gz
cd /tmp/iRedMail-1.6.2

function passgen(){
    length=$[ 20 +$[RANDOM % 20]]

    char=(0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z A B C D E F G H I J K L M N O P Q R S T U V W X Y Z)

    max=${#char[*]}
    for ((i = 1; i <= $length ; i++))do

    let rand=${RANDOM}%${max}
    password="${password}${char[$rand]}"
    done
    echo $password
}


cat > /tmp/iRedMail-1.6.2/config << EOF

export STORAGE_BASE_DIR='/var/vmail'
export WEB_SERVER='NGINX'
export BACKEND_ORIG='PGSQL'
export BACKEND='PGSQL'
export VMAIL_DB_BIND_PASSWD='$(passgen)'
export VMAIL_DB_ADMIN_PASSWD='$(passgen)'
export MLMMJADMIN_API_AUTH_TOKEN='$(passgen)'
export NETDATA_DB_PASSWD='$(passgen)'
export PGSQL_ROOT_PASSWD='$(passgen)'
export FIRST_DOMAIN='$domain'
export DOMAIN_ADMIN_PASSWD_PLAIN='$(passgen)'
export USE_IREDADMIN='YES'
export USE_ROUNDCUBE='YES'
export USE_NETDATA='YES'
export USE_FAIL2BAN='YES'
export AMAVISD_DB_PASSWD='$(passgen)'
export IREDADMIN_DB_PASSWD='$(passgen)'
export RCM_DB_PASSWD='$(passgen)'
export SOGO_DB_PASSWD='$(passgen)'
export SOGO_SIEVE_MASTER_PASSWD='$(passgen)'
export IREDAPD_DB_PASSWD='$(passgen)'
export FAIL2BAN_DB_PASSWD='$(passgen)'
#EOF
EOF


export AUTO_USE_EXISTING_CONFIG_FILE=y
export AUTO_INSTALL_WITHOUT_CONFIRM=y
export AUTO_CLEANUP_REMOVE_SENDMAIL=y
export AUTO_CLEANUP_REPLACE_FIREWALL_RULES=y
export AUTO_CLEANUP_RESTART_FIREWALL=y
export AUTO_CLEANUP_REPLACE_MYSQL_CONFIG=y
bash iRedMail.sh

func_mailgun(){
cat << EOF >> /etc/postfix/main.cf
#Mail Gun Config
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous
smtp_sasl_mechanism_filter = AUTH LOGIN
smtp_tls_security_level = may
header_size_limit = 4096000
relayhost = [smtp.eu.mailgun.org]:587
EOF

cat > /etc/postfix/sasl_passwd << EOF
[smtp.eu.mailgun.org]:587 postmaster@yourdomain.com:APIPASSWORD
EOF

postmap /etc/postfix/sasl_passwd
chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
service postfix restart
}

func_sengrid(){
cat <<EOF >> /etc/postfix/main.cf
#SENDGRID CONFIG
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous
smtp_tls_security_level = may
header_size_limit = 4096000
relayhost = [smtp.sendgrid.net]:587
EOF

cat > /etc/postfix/sasl_passwd << EOF
[smtp.sendgrid.net]:587 apikey:APIKEYHERE
EOF

postmap /etc/postfix/sasl_passwd
chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
service postfix restart
}

func_gophish(){
echo -n "Enter your GoPhish IP [ENTER]: "
read gophish_ip
echo

cat <<EOF >> /etc/postfix/main.cf
#GoPhishConfig
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_tls_auth_only = yes
mynetworks = 127.0.0.1 [::1] $gophish_ip #THE LAST IP IS THE GOPHISH IP
EOF

cat <<EOF >> /opt/iredapd/settings.py
mynetworks = ['127.0.0.1', '$gophish_ip']
EOF

systemctl restart postfix
}

func_headerstrip(){
sed -i '/^header_checks/d' /etc/postfix/main.cf
sed -i '/^body_checks/d' /etc/postfix/main.cf

cat <<EOF >> /etc/postfix/main.cf
mime_header_checks = regexp:/etc/postfix/header_checks
header_checks = regexp:/etc/postfix/header_checks
EOF

cat > /etc/postfix/header_checks << EOF
/^Received:.*/ IGNORE
/^X-Originating-IP:/ IGNORE
/^X-Mailer:/ IGNORE
/^Mime-Version:/ IGNORE
EOF

postmap /etc/postfix/header_checks
postfix reload
}


while true; do
read -p "Do you want to add the mailgun config? (y/n) " yn
case $yn in 
	[yY] ) func_mailgun;
		break;;
	[nN] ) echo skipping mailgun;
		break;;
	* ) echo invalid response;;
esac
done

while true; do
read -p "Do you want to add the sendgrid config? (y/n) " yn
case $yn in 
	[yY] ) func_sengrid;
		break;;
	[nN] ) echo skipping sendgrid;
		break;;
	* ) echo invalid response;;
esac
done

func_gophish
func_headerstrip
echo "Reboot the system"
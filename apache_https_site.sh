#!/bin/bash

# Path to the file containing the domains
DOMAIN_FILE="/opt/domains.txt"

# Initialize the domain argument string
DOMAIN_ARGS=""

# Read the domains from the file and append to DOMAIN_ARGS
while IFS= read -r domain
do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $domain"
done < "$DOMAIN_FILE"

# Assuming the first domain is the certificate directory name
FIRST_DOMAIN=$(head -n 1 "$DOMAIN_FILE")

# Environment Checks
func_check_env(){
  # Check Sudo Dependency going to need that!
  if [ $(id -u) -ne '0' ]; then
    echo
    echo ' [ERROR]: This Setup Script Requires root privileges!'
    echo '          Please run this setup script again with sudo or run as login as root.'
    echo
    exit 1
  fi
}

func_check_tools(){
  # Check Sudo Dependency going to need that!
  if [ $(which certbot) ]; then
    echo '[Success] certbot is already installed'
  else
    echo 
    echo '[ERROR]: certbot does not seem to be installed'
    apt update
    apt install certbot -y
    echo
  fi
}

certbot_delete() {
    # List all certs
    echo "Existing SSL Certificates:"
    ls /etc/letsencrypt/live
    
    # Display the prompt message
    read -p "Do you want to delete old certs? (yes/no): " response
    
    # Convert response to lowercase
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    
    # Check if the response is "yes"
    if [[ "$response" == "yes" ]]; then
        # Run the command
        echo "Running command: certbot delete"
        eval "certbot delete"
    else
        echo "Operation canceled."
    fi
}

func_install_apache(){
apt-get install apache2 -y
a2enmod rewrite headers ssl cache
a2dismod -f deflate
service apache2 reload
a2dissite 000-default.conf
a2dissite default-ssl.conf
}

func_install_letsencrypt(){
  echo '[Starting] to build letsencrypt cert!'
  service apache2 stop
  sudo certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email $DOMAIN_ARGS
  if [ -e /etc/letsencrypt/live/$FIRST_DOMAIN/fullchain.pem ]; then
    echo '[Success] letsencrypt certs are built!'
  else
    echo "[ERROR] letsencrypt certs failed to build.  Check that DNS A record is properly configured for this domain"
    exit 1
  fi
}

func_create_virtualhost() {
cd /tmp
cat > site.conf << EOF
<VirtualHost *:80>
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI}
</VirtualHost>
<IfModule mod_ssl.c>
  <VirtualHost *:443>
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile      /etc/letsencrypt/live/$FIRST_DOMAIN/fullchain.pem
    SSLCertificateKeyFile      /etc/letsencrypt/live/$FIRST_DOMAIN/privkey.pem
    SSLCertificateChainFile   /etc/letsencrypt/live/$FIRST_DOMAIN/chain.pem
    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>
    <Directory /usr/lib/cgi-bin>
        SSLOptions +StdEnvVars
    </Directory>
  </VirtualHost>
</IfModule>
EOF

cat > /etc/apache2/mods-enabled/ssl.conf << EOF
<IfModule mod_ssl.c>
        SSLRandomSeed startup builtin
        SSLRandomSeed startup file:/dev/urandom 512
        SSLRandomSeed connect builtin
        SSLRandomSeed connect file:/dev/urandom 512
        AddType application/x-x509-ca-cert .crt
        AddType application/x-pkcs7-crl .crl
        SSLPassPhraseDialog  exec:/usr/share/apache2/ask-for-passphrase
        SSLSessionCache         shmcb:${APACHE_RUN_DIR}/ssl_scache(512000)
        SSLSessionCacheTimeout  300
        SSLCipherSuite HIGH:!aNULL
        SSLProtocol -all +TLSv1 +TLSv1.1 +TLSv1.2
</IfModule>
EOF
sudo cp /tmp/site.conf /etc/apache2/sites-available/site.conf
rm /etc/apache2/sites-available/000-default.conf
rm /etc/apache2/sites-available/default-ssl.conf
}

func_additional_apache_conf() {
## Update Apached Server Header, ServerTokens, and logging
echo "Update Update Apached Server Header, ServerTokens, and logging"
sed -i -e 's/\(ServerTokens\s\+\)OS/\1Prod/g' /etc/apache2/conf-enabled/security.conf
sed -i -e 's/\(ServerSignature\s\+\)On/\1Off/g' /etc/apache2/conf-enabled/security.conf
echo "LogLevel alert rewrite:trace2" >> /etc/apache2/conf-enabled/security.conf
a2dissite 000-default.conf
a2dissite default-ssl.conf
a2ensite site.conf
}

func_crontab() {
(crontab -l 2>/dev/null | grep -v "$RENEW_SCRIPT"; echo "15 3 * * * /usr/bin/certbot renew --quiet") | crontab -
}

func_check_env
func_check_tools
certbot_delete
func_install_apache
func_install_letsencrypt
sudo service apache2 start
func_create_virtualhost
func_additional_apache_conf
func_crontab
sudo service apache2 restart
#!/bin/bash
echo -n "Enter your DNS (A) record for domain [ENTER]: "
read domain
echo

echo -n "Enter your redirection domain [ENTER]: "
read redirectdomain
echo

echo -n "Enter your Teamserver IP address [ENTER]: "
read TEAMSERVER_IP
echo

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
a2enmod rewrite headers proxy proxy_http ssl cache
a2dismod -f deflate
service apache2 reload
}

func_install_letsencrypt(){
  echo '[Starting] to build letsencrypt cert!'
  service apache2 stop
  sudo certbot certonly --standalone -d $domain --non-interactive --agree-tos --register-unsafely-without-email
  if [ -e /etc/letsencrypt/live/$domain/fullchain.pem ]; then
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
  <VirtualHost _default_:443>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ServerAlias $domain
    SSLEngine on
    # Enable Proxy
    SSLProxyEngine On
    # Trust Self-Signed Certificates
    SSLProxyVerify none
    SSLProxyCheckPeerCN off
    SSLProxyCheckPeerName off
    SSLCertificateFile      /etc/letsencrypt/live/$domain/fullchain.pem
    SSLCertificateKeyFile      /etc/letsencrypt/live/$domain/privkey.pem
    SSLCertificateChainFile   /etc/letsencrypt/live/$domain/chain.pem
    # Include redirect.rules
    Include /etc/apache2/redirect.rules
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

func_redirect_rules() {
cd /tmp
cat > /etc/apache2/redirect.rules << EOF
########################################
## .htaccess START
RewriteEngine On

## Allow only GET and POST methods
RewriteCond %{REQUEST_METHOD} ^(GET|POST) [NC]

## Profile URIs
RewriteCond %{REQUEST_URI} ^/jquery-3\.7\.1\.js.*$

## Profile UserAgent
RewriteCond %{HTTP_USER_AGENT} ^Mozilla/5\.0\ \(Windows\ NT\ 10\.0;\ Win64;\ x64\)\ AppleWebKit/537\.36\ \(KHTML,\ like\ Gecko\)\ Chrome/127\.0\.0\.0\ Safari/537\.36\ Edg/127\.0\.2651\.86$

## Profile Host
RewriteCond %{HTTP:Host} ^code\.jquery\.com$

## Profile Accept Header
RewriteCond %{HTTP:Accept} ^text/html,application/xhtml\+xml,application/xml;q=0\.9,image/avif,image/webp,\*/\*;q=0\.8$

## Profile Accept-Language Header
RewriteCond %{HTTP:Accept-Language} ^en-US,en;q=0\.5$

## Profile Accept-Encoding Header
RewriteCond %{HTTP:Accept-Encoding} ^gzip,\ deflate,\ br$

## Profile Upgrade-Insecure-Requests Header
RewriteCond %{HTTP:Upgrade-Insecure-Requests} ^1$

## Proxy the connection to the Teamserver if all conditions match
RewriteRule ^.*$ "https://$TEAMSERVER_IP%{REQUEST_URI}" [P,L]

## Redirect all other traffic here
RewriteRule ^.*$ https://$redirectdomain/? [L,R=302]

## .htaccess END
########################################
EOF
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
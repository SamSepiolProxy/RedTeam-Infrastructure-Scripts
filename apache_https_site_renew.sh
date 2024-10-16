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


func_check_env
func_check_tools
sudo service apache2 stop
certbot_delete
func_install_letsencrypt
sudo service apache2 start
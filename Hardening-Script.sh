#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "Script must be run as a root user" 2>&1
  exit 1
fi

# This script is for the setup of the Server Head End (she)
logger "Hardening: Started"

#update and upgrade packages
apt update && apt upgrade -y
logger "Hardening: Updated packages"

#enable unattended updates
apt install unattended-upgrades -y
logger "Hardening: Installed unattended updates"

# Set logon banner
cat <<EOF > /etc/issue
		PRIVATE SYSTEM
		--------------

************************************************
* Unauthorised access or use of this equipment *
*   is prohibited and constitutes an offence   *
*     under the Computer Misuse Act 1990.      *
*    If you are not authorised to use this     *
*     system, terminate this session now.      *
************************************************
EOF

cat <<EOF > /etc/issue.net
		PRIVATE SYSTEM
		--------------

************************************************
* Unauthorised access or use of this equipment *
*   is prohibited and constitutes an offence   *
*     under the Computer Misuse Act 1990.      *
*    If you are not authorised to use this     *
*     system, terminate this session now.      *
************************************************
EOF
logger "Hardening: Set logon banner"

#config ssh_config
cat <<EOF >> /etc/ssh/sshd_config
Banner /etc/issue.net
AllowTcpForwarding yes
ClientAliveInterval 300
ClientAliveCountMax 0
Compression no
LogLevel VERBOSE
MaxAuthTries 3
MaxSessions 10
TCPKeepAlive no
X11Forwarding no
AllowAgentForwarding no
LoginGraceTime 60
EOF
logger "Hardening: ssh lockdown complete"

#install cracklib
apt-get install libpam-cracklib -y
cat <<EOF > /etc/pam.d/common-password
password        [success=1 default=ignore]      pam_unix.so obscure yescrypt
password        requisite                       pam_cracklib.so retry=3 minlen=12 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1
password        required                        pam_permit.so
password        optional        pam_gnome_keyring.so
EOF
logger "Hardening: Password policy set"

#install fail2ban
apt install fail2ban -y
systemctl start fail2ban
systemctl enable fail2ban
logger "Hardening: fail2ban enabled"

#Install additional auditing
apt install auditd audispd-plugins -y
systemctl start auditd
systemctl enable auditd
logger "Hardening: auditd enabled"

#Enable ufw
apt install ufw -y
ufw allow from (YourIP) to any port 22
ufw allow from (YourIP) to any port 22
ufw logging on
ufw enable
systemctl enable ufw
logger "Hardening: UFW enabled"
logger "Hardening: Finished"
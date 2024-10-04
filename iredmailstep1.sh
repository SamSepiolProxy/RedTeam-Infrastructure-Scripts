#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  echo "Script must be run as a root user" 2>&1
  exit 1
fi

echo -n "Enter your DNS (A) record for domain [ENTER]: "
read domain
echo

cat > /etc/hosts << EOF
127.0.0.1 mail.$domain mail localhost
EOF

cat > /etc/hostname << EOF
echo mail.$domain
EOF

echo "Reboot the system"
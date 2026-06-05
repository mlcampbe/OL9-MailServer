#!/bin/bash
set -e

# ----------------------------
# Variables - UPDATE THESE
# ----------------------------
MAILHOST="mail.x.com"
CALDAV_PORT="5232"

# ----------------------------
# OS Preparation & Repos
# ----------------------------
echo "Installing Packages..."
dnf install radicale3 -y

# ----------------------------
# FIREWALL (Firewalld) and SELINUX PORTS
# ----------------------------
echo "Configuring OS Firewall..."
sudo firewall-cmd --permanent --add-port=$CALDAV_PORT/tcp
sudo firewall-cmd --reload

# ----------------------------
# CONFIGURE TLS CERTIFICATE PERMISSIONS
# ----------------------------
echo "Update Lets Encrypt file permissions..."
sudo chcon -R -t cert_t /etc/letsencrypt/live/$MAILHOST/
sudo chgrp -R radicale /etc/letsencrypt/live/
sudo chgrp -R radicale /etc/letsencrypt/archive/
sudo chmod g+rx /etc/letsencrypt/live/ /etc/letsencrypt/archive/
sudo chmod g+r /etc/letsencrypt/live/$MAILHOST/*
sudo setsebool -P nis_enabled 1

# ----------------------------
# CONFIGURE RADICALE
# ----------------------------
echo "Configuring Radicale..."
cat > /etc/radicale/config <<EOF
[server]
hosts = 0.0.0.0:$CALDAV_PORT
ssl = True
certificate = /etc/letsencrypt/live/$MAILHOST/fullchain.pem
key = /etc/letsencrypt/live/$MAILHOST/privkey.pem
max_content_length = 100000000
max_resource_size = 100000000

[auth]
type = dovecot
dovecot_connection_type = AF_UNIX
dovecot_socket = /var/run/dovecot/auth-radicale

[web]
type = internal

[rights]
type = owner_only

[storage]
filesystem_folder = /var/lib/radicale/collections
EOF

# ----------------------------
# UPDATE DOVECOT 10-master.conf
# ----------------------------
sed -i '/service auth {/,/}/ {
  /e.g. 0777 allows everyone full permissions/a \
  unix_listener auth-radicale {\
    mode = 0660\
    user = radicale\
    group = dovecot\
  }
}' /etc/dovecot/conf.d/10-master.conf

# ----------------------------
# UPDATE FAIL2BAN
# ----------------------------
echo "Configuring fail2ban..."
echo > /etc/fail2ban/filter.d/radicale.conf <<EOF
[Definition]
failregex = ^.*\[.*\] \[INFO\] Login failed for user '.*' from '<HOST>'.*$
journalmatch = _SYSTEMD_UNIT=radicale.service
EOF

cat >> /etc/fail2ban/jail.local <<EOF
[radicale]
enabled = true
port = 5232
filter = radicale
backend = systemd
maxretry = 5
EOF
# ----------------------------
# START SERVICES
# ----------------------------
systemctl daemon-reload
systemctl enable --now radicale
systemctl restart fail2ban radicale

echo ""
echo "INSTALL COMPLETE"
echo "The system has been updated to support caldav on port $CALDAV_PORT
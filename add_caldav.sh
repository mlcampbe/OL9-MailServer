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
type = from_file
file = /etc/radicale/rights

[storage]
filesystem_folder = /var/lib/radicale/collections
EOF

cat >> /etc/radicale/rights <<EOF
# The following 3 rules set authenticated user access to their own principal and their own direct child calendars
[root]
user: .+
collection:
permissions: R

[principal]
user: .+
collection: {user}
permissions: RW

[calendars]
user: .+
collection: {user}/[^/]+
permissions: rw

# For any calendar that should be public, add a separate exact rule such as
[public-mike-calendar]
user: .*
collection: ^mike@mlc1\.net/A73C9E41-2B84-4D7F-9A16-8E5B3C7F2D94(/.*)?$
permissions: r

[public-family-calendar]
user: .*
collection: ^mike@mlc1\.net/D8F14B92-5E6A-4C3D-AB87-1F9E6C24A7B5(/.*)?$
permissions: r

EOF

# ----------------------------
# UPDATE RSYSLOG
# ----------------------------
echo > /etc/rsyslog.d/30-radicale.conf <<EOF
if $programname == 'radicale' then /var/log/radicale.log
& stop
EOF

echo > /etc/logrotate.d/radicale <<EOF
/var/log/radicale.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    create 0640 root root
    sharedscripts
    postrotate
        /bin/systemctl kill -s HUP rsyslog.service >/dev/null 2>&1 || true
    endscript
}
EOF
touch /var/log/radicale.log
chmod 0640 /var/log/radicale.log

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
systemctl restart fail2ban radicale rsyslog

echo ""
echo "INSTALL COMPLETE"
echo "The system has been updated to support caldav on port $CALDAV_PORT

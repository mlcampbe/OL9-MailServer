# Secure Enterprise Mail Server Infrastructure (Oracle Linux 9)

A production-ready, highly secure, and optimized mail server ecosystem designed specifically for **Oracle Linux 9 (aarch64 / x86_64)**. This infrastructure pairs **Postfix** and **Dovecot** with state-of-the-art anti-spam (**Rspamd**), modern authentication mechanisms, Apple Push Notifications (**xapsd**), high-performance caching (**Redis**), localized DNS resolution (**Unbound**), and automated, low-overhead system backups.

The entire architecture is designed with high performance, strict cryptographic controls, and comprehensive SELinux reinforcement in mind.

---

## 🏗️ Architectural Overview & Components

This infrastructure separates operations into clear, modular software layers to achieve maximum resilience, performance, and mail compliance:

```
                      [ Internet / Inbound SMTP ]
                                   │
                                   ▼
                              (Firewalld)
                                   │
                                   ▼
                             [ Postfix ] <───(Milter Protocol)───> [ Rspamd ]
                                   │                                    │
               (Local Mail     (LMTP)                               (Bayes/Reputation/
                Delivery)          │                                 Neural Network)
                                   ▼                                    │
                              [ Dovecot ] <─────────────────────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
 [ Maildir Storage ]       [ IMAP / IMAPS ]            [ xapsd Daemon ]
(/mnt/mailserver/%n)       (Port 993/TCP)        (Apple Push Notifications)
```

### Core Technologies
* **MTA (Mail Transfer Agent):** **Postfix 3.10+** handling high-performance, strictly restricted SMTP transaction pipelines.
* **MDA (Mail Delivery Agent) & IMAP:** **Dovecot** leveraging ultra-fast LMTP (`dovecot-lmtp`) socket transport for internal system delivery.
* **Anti-Spam & Content Filter:** **Rspamd** processing multi-tier filtering engines including statistical Bayes, neural networking classifiers, fuzzy checks, and SPF/DKIM/DMARC evaluation.
* **Outbound Relay:** Integrated with **SMTP2GO** (Port 587) out-of-the-box to ensure high IP reputation and flawless deliverability.
* **Apple Push Notifications:** Native integration via **xapsd** (`dovecot-xaps-daemon`), allowing real-time iOS/macOS push alerts natively within Apple Mail.
* **DNS Resolution:** Dedicated **Unbound** caching resolver to prevent DNS query rate-limiting during real-time blackhole list (RBL) evaluation.
* **Key-Value & Cache Layer:** **Redis** backing Rspamd's statistical Bayes data, runtime greylisting, neural weights, and cross-session reputation.

---

## ✨ Features

* **Dual Node Role Architecture:** The setup easily provisions either a **Primary** mail exchanger node or a dedicated **Backup MX** relay node by setting a single configuration variable (`SERVER_TYPE`).
* **Smart Inbound Protection:** Implements Postfix `postscreen` handling protocol validation, early-stage connection tracking, and pipelining defense before heavy content filters are engaged.
* **Native iOS/macOS Push Notifications:** Full implementation of `xaps_push_notification` and `xaps_imap` plugins to maintain persistent push connections to Apple’s APNs servers.
* **Automated Spam Learning (IMAP-Sieve):** Users can organically train their personalized spam filter simply by dragging emails between folders. Moving a mail into `Junk` automatically pipes it to Rspamd's `learnspam` endpoint via Sieve hooks, while dragging it out executes `learnham`.
* **Outbound Policy Enforcement:** Automatic DKIM cryptographic signing utilizing an optimized 2048-bit (or default system) key matrix managed natively through Rspamd's signing controllers.
* **Auto-Provisioning Storage Engine:** Standardized `Maildir` structure automatically handles standard folder subscriptions (`Junk`, `Drafts`, `Trash`, `Sent Messages`) with automated auto-expunge boundaries (e.g., 90 days for Junk, 365 days for Trash).

---

## 🔒 Security Configuration

Security is baked directly into the configurations rather than treated as an afterthought:

### 1. Cryptographic Controls & Transport Security
* **TLS Protocol Enforcement:** Legacy layers (SSLv2, SSLv3, TLS 1.0, and TLS 1.1) are explicitly disabled across both Postfix and Dovecot. Transport security requires modern **TLS 1.2 or TLS 1.3**.
* **Strict TLS Policies:** Modern cipher suites with forward secrecy are prioritized (`ssl_prefer_server_ciphers = yes`). Plaintext authentication is comprehensively blocked on unencrypted sessions (`disable_plaintext_auth = yes`).
* **Automated Certificate Lifecycle:** Managed natively through an automated Let's Encrypt `certbot` engine with inline systemd hooks (`reload-mail.sh`) that reload mail services instantly upon successful renewal without interrupting active client operations.

### 2. Network Perimeter & Intrusive Hardening
* **Firewalld Restrictions:** Locks down the kernel-level perimeter, exposing only designated service interfaces (`smtp`, `imaps`, `http`, `https`) and strictly defined TCP ports (`587`, `993`, `11334`).
* **Fail2Ban Proactive Banning:** Tailored systemd jails parse log targets for Postfix authentication anomalies, Dovecot validation breaks, and custom Rspamd UI controller unauthorized intrusion vectors. Includes automatic **Bantime Increments** to lock out persistent attackers up to a full week.
* **Rate & Volumetric Constraints:**
    * Maximum connection rate per client: `30/min`
    * Maximum concurrent connection count limit per IP: `10`
    * Maximum messages per minute per client: `20`
    * Maximum recipients per transaction: `50`

### 3. SELinux Policies & Permissions
* **Storage Isolation:** Externalized storage blocks (`/mnt/mailserver`) are strictly managed under standard `vmail` (UID 5000/GID 5000) system space with explicit `700` boundaries.
* **SELinux Context Hardening:** Custom security labeling matches and strictly isolates paths under `mail_spool_t` and `dovecot_etc_t`. Runtime flags explicitly permit specific network/antivirus behavior (`setsebool -P antivirus_can_scan_system 1` and `setsebool -P nis_enabled 1`).

### 4. Advanced Spam Mitigation Architecture
* **Spamhaus DQS Integration:** Implements native real-time query integration with the **Spamhaus Data Query Service (DQS)** using specialized return code evaluations for SBL, CSS, XBL, PBL, DBL, and ZRD (Zero-Day Receiver Domain tracking).
* **Deep Multi-tier Actions:**
    * `Score < 4.0`: No Action (Clean Pass)
    * `Score ≥ 4.0`: Greylist (Temporary deferral to block botnets)
    * `Score ≥ 6.0`: Add spam status headers to mail stream
    * `Score ≥ 7.0`: Rewrite subject line with `***SPAM*** %s`
    * `Score ≥ 25.0`: Outright hard reject at SMTP gateway stage

---

## 📂 File Manifest & Descriptions

The system consists of three distinct, interacting scripts:

### 1. `setup_mailserver_ol9.sh`
The primary deployment automation script. It prepares the operating system repos, modifies firewalls, generates certificates via Let's Encrypt, configures specialized configurations for Postfix, Dovecot, Rspamd, Redis, Fail2Ban, and Unbound, and links system components via LMTP and Milter sockets.

### 2. `add_user.sh`
An administrative user provisioning utility. This script securely provisions flat accounts into the cryptographic file database (`/etc/dovecot/postfix_accounts.cf`). 
* It utilizes Dovecot's native `doveadm` hashing engine to enforce high-grade `SHA512-CRYPT` storage.
* It securely constructs matching localized storage directories under the isolated vmail context.
* It outputs actionable copy-paste instructions for syncing corresponding secondary MX relays (`relay_recipients`).

### 3. `backup_mailserver.sh`
An enterprise backup automation utility designed to run as a scheduled daily cron job.
* Instructs `redis-cli` to securely flush memory segments down to persistent storage blocks prior to snapshotting.
* Compresses configurations, security contexts, shadow verification frames, and actual physical mail directories into timestamps archives (`.tar.gz`).
* Implements automated rolling log maintenance and dynamic retention policies, purging backup records older than 14 days and truncating execution logs to the last 1000 lines.

---

## 🚀 Getting Started

### Prerequisites
* A clean instance of **Oracle Linux 9** (Primary or Backup MX node).
* A valid public IP with correct forward and reverse DNS (PTR) parameters matching your targeted `$MAILHOST`.
* An active account token string mapped to **Spamhaus DQS** and **SMTP2GO**.

### Deployment Procedure

1.  **Clone & Update Variables:**
    Open `setup_mailserver_ol9.sh` and populate the variable frame accurately:
    ```bash
    SERVER_TYPE="primary"  # Change to "backup" on your secondary node
    MAILHOST="mail.yourdomain.com"
    SMTPUSER="smtp2go_username"
    SMTPPASS="smtp2go_password"
    ADMINEMAIL="admin@yourdomain.com"
    RSPAMDPASS="your_secure_rspamd_web_admin_password"
    SPAMHAUSKEY="your_spamhaus_dqs_key_string"
    ```

2.  **Execute Setup:**
    Run the setup script with administrative privileges:
    ```bash
    sudo chmod +x setup_mailserver_ol9.sh add_user.sh backup_mailserver.sh
    sudo ./setup_mailserver_ol9.sh
    ```

3.  **Manage Users:**
    Add interactive production mailboxes safely using the onboarding script:
    ```bash
    sudo ./add_user.sh alice@yourdomain.com 'your_secure_user_password'
    ```

4.  **Automate Backups:**
    Schedule your retention engine natively within root's crontab:
    ```bash
    sudo crontab -e
    ```
    Add the following line to execute backups every night at 3:00 AM:
    ```cron
    0 3 * * * /usr/local/bin/backup_mailserver.sh
    ```

---
*Developed as a secure, modern alternative to legacy bloated mail stacks.*

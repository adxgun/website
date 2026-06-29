#!/usr/bin/env bash
# Run this once on the server to install Caddy and configure it.
# Usage: ssh user@your.server.ip 'bash -s' < scripts/server-setup.sh
set -euo pipefail

WEB_ROOT="/var/www/hammed.live"

# Install Caddy (Debian/Ubuntu)
if ! command -v caddy &>/dev/null; then
  echo "Installing Caddy..."
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

# Create web root owned by the deploy user
mkdir -p "$WEB_ROOT"
# Replace 'ubuntu' below if your deploy user is different
chown -R root:root "$WEB_ROOT"

# Install Caddyfile
cp Caddyfile /etc/caddy/Caddyfile
caddy fmt --overwrite /etc/caddy/Caddyfile

# Enable and (re)start
systemctl enable caddy
systemctl restart caddy

echo "Caddy is running. Point your DNS A record for hammed.live to this server's IP."
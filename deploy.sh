#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these before first run
# ---------------------------------------------------------------------------
REMOTE_USER="root"          # SSH user on the server
REMOTE_HOST="204.168.248.165"  # server IP or hostname
REMOTE_DIR="/var/www/hammed.live"
SSH_KEY="./keys/server"                     # path to SSH key, e.g. ~/.ssh/id_ed25519 (leave empty to use ssh-agent)
# ---------------------------------------------------------------------------

BOLD="\033[1m"
RESET="\033[0m"

log() { echo -e "${BOLD}==> $*${RESET}"; }

# Build
log "Building site..."
hugo --gc --minify

# Sync — trailing slash on source is intentional (syncs contents, not the dir itself)
log "Deploying to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR} ..."
RSYNC_OPTS=(-avz --delete --checksum)
if [[ -n "$SSH_KEY" ]]; then
  RSYNC_OPTS+=(-e "ssh -i ${SSH_KEY}")
fi

rsync "${RSYNC_OPTS[@]}" public/ "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

log "Done. Site is live at https://hammed.live"
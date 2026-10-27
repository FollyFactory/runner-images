#!/usr/bin/env bash
# Stop the PostgreSQL cluster. Re-execs itself under sudo when called as `runner`.
set -euo pipefail

major="${POSTGRES_MAJOR:-16}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -n POSTGRES_MAJOR="${major}" "$0" "$@"
fi

pg_ctlcluster --skip-systemctl-redirect "${major}" main stop --force || true
echo "PostgreSQL ${major} stopped"

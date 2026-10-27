#!/usr/bin/env bash
# Start the PostgreSQL cluster that ships stopped in this image and wait for it
# to accept connections. Re-execs itself under sudo when called as `runner`.
#
#   start-postgres                 # localhost:5432, postgres/postgres
set -euo pipefail

major="${POSTGRES_MAJOR:-16}"
port="${POSTGRES_PORT:-5432}"
timeout="${POSTGRES_START_TIMEOUT:-30}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -n POSTGRES_MAJOR="${major}" POSTGRES_PORT="${port}" \
        POSTGRES_START_TIMEOUT="${timeout}" "$0" "$@"
fi

# Runtime dirs live on tmpfs in most container runtimes, so recreate them.
install -d -o postgres -g postgres -m 2775 /var/run/postgresql

if pg_isready -q -h 127.0.0.1 -p "${port}" -U postgres; then
    echo "PostgreSQL ${major} already accepting connections on port ${port}"
    exit 0
fi

pg_ctlcluster --skip-systemctl-redirect "${major}" main start

for _ in $(seq "${timeout}"); do
    if pg_isready -q -h 127.0.0.1 -p "${port}" -U postgres; then
        echo "PostgreSQL ${major} ready on 127.0.0.1:${port} (user postgres, password postgres)"
        exit 0
    fi
    sleep 1
done

echo "PostgreSQL ${major} did not become ready within ${timeout}s" >&2
tail -n 50 "/var/log/postgresql/postgresql-${major}-main.log" >&2 || true
exit 1

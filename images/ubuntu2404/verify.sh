#!/usr/bin/env bash
# Smoke-test the image's toolchain. Installed as /usr/local/bin/verify-image and
# run by CI against every build; also useful by hand after a local build.
set -uo pipefail

EXPECTED_NODE_VERSIONS="${EXPECTED_NODE_VERSIONS:-22.23.4 24.22.1}"
EXPECTED_DOTNET_SDKS="${EXPECTED_DOTNET_SDKS:-9.0.121 9.0.205 9.0.318 10.0.112 10.0.204 10.0.303 10.0.401}"
EXPECTED_POSTGRES_MAJOR="${EXPECTED_POSTGRES_MAJOR:-${POSTGRES_MAJOR:-18}}"

failures=0

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'ok    %s\n' "${label}"
    else
        printf 'FAIL  %s\n' "${label}"
        failures=$((failures + 1))
    fi
}

echo "== runner agent =="
check "runner binary present" test -x /home/runner/run.sh
check "k8s container hooks present" test -f /home/runner/k8s/index.js
check "docker container hooks present" test -f /home/runner/docker/index.js
check "running as uid 1001" test "$(id -u)" -eq 1001
check "passwordless sudo" sudo -n true

echo
echo "== node =="
for version in ${EXPECTED_NODE_VERSIONS}; do
    arch="$(node -p 'process.arch')"
    check "tool cache has node ${version}" test -x "/opt/hostedtoolcache/node/${version}/${arch}/bin/node"
    check "tool cache marker for node ${version}" test -f "/opt/hostedtoolcache/node/${version}/${arch}.complete"
done
check "node on PATH" node --version
check "npm on PATH" npm --version
check "/opt/node points at the default" test -x /opt/node/bin/node
# actions/setup-node and `npm install --global` both write here.
check "tool cache writable by runner" test -w /opt/hostedtoolcache
check "global npm prefix writable by runner" test -w /opt/node/lib/node_modules
printf 'info  default node %s\n' "$(node --version 2>/dev/null)"

echo
echo "== dotnet =="
installed_sdks="$(dotnet --list-sdks 2>/dev/null | cut -d' ' -f1)"
for version in ${EXPECTED_DOTNET_SDKS}; do
    check "sdk ${version} installed" grep -qx "${version}" <<<"${installed_sdks}"
done
check "dotnet --info" dotnet --info
# actions/setup-dotnet installs into DOTNET_ROOT when a global.json asks for a
# band this image does not carry.
check "dotnet root writable by runner" test -w /usr/share/dotnet

echo
echo "== postgres =="
check "psql client ${EXPECTED_POSTGRES_MAJOR}" test -x "/usr/lib/postgresql/${EXPECTED_POSTGRES_MAJOR}/bin/psql"
check "psql on PATH is ${EXPECTED_POSTGRES_MAJOR}.x" \
    test "$(psql --version 2>/dev/null | sed -E 's/.* ([0-9]+)\..*/\1/')" = "${EXPECTED_POSTGRES_MAJOR}"
check "pg_isready on PATH" command -v pg_isready
check "cluster initialised" test -d "/var/lib/postgresql/${EXPECTED_POSTGRES_MAJOR}/main"
check "start-postgres" start-postgres
check "select 1 over tcp" env PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -tAc 'select 1'
check "stop-postgres" stop-postgres

echo
echo "== tools =="
for tool in git git-lfs gh jq docker railway curl wget unzip zip rsync python3 sqlite3 make gcc; do
    check "${tool}" command -v "${tool}"
done
check "docker buildx plugin" docker buildx version
check "docker compose plugin" docker compose version
check "railway --version" railway --version
printf 'info  %s\n' "$(railway --version 2>/dev/null)"

echo
if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed"
    exit 1
fi
echo "all checks passed"

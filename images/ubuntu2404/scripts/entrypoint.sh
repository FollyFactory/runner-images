#!/usr/bin/env bash
# Entrypoint for the FollyFactory runner image.
#
# Execs whatever it is given (ARC's scale-set controller passes
# /home/runner/run.sh, the image's own default), after optionally bringing up
# PostgreSQL for jobs that want it running from the first step.
set -euo pipefail

case "${START_POSTGRES:-0}" in
    1 | true | TRUE | yes) start-postgres ;;
esac

exec "$@"

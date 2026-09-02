#!/bin/bash
# Wrapper para forçar PULSE_SERVER sem prefixo "unix:"
export PULSE_SERVER=/tmp/host-pulse/native
exec /entrypoint.sh "$@"

#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
export PYTHONPATH=src
exec python3 -m mac_dev_clean

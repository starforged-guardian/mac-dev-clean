#!/bin/sh
set -eu

cd /Users/m4/mac-dev-clean
export PYTHONPATH=src
exec python3 -m mac_dev_clean

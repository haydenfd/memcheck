#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
sh scripts/build-app.sh
mkdir -p "$HOME/Applications"
ditto dist/Memcheck.app "$HOME/Applications/Memcheck.app"
printf 'Installed %s\n' "$HOME/Applications/Memcheck.app"

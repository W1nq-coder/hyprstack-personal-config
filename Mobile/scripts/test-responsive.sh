#!/bin/sh
# Run inside a graphical session. Does not alter system service state.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for size in 360x800 540x1200 393x873 412x915 320x640 800x360; do
    echo "GTK smoke: $size"
    "$ROOT/scripts/run.sh" --smoke-test --size "$size"
done

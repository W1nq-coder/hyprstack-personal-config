#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if test -n "$(git status --porcelain --untracked-files=normal)"; then
    echo 'Сначала зафиксируйте исходники: сборка использует только HEAD' >&2
    exit 1
fi
mkdir -p build/alpine
git -C "$(git rev-parse --show-toplevel)" archive --format=tar --prefix=hyprstack-mobile-0.1.0/ HEAD:Mobile > build/source.tar
gzip -n -c build/source.tar > build/alpine/hyprstack-mobile-0.1.0.tar.gz
rm build/source.tar
cp packaging/alpine/APKBUILD.in build/alpine/APKBUILD
cd build/alpine
printf 'sha512sums="%s"\n' "$(sha512sum hyprstack-mobile-0.1.0.tar.gz)" >> APKBUILD
printf 'Подготовлено: %s\n' "$ROOT/build/alpine"

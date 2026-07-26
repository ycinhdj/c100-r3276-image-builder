#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=config/release.env
source "$ROOT/config/release.env"

patches=("$ROOT"/patches/c100-bootupd/*.patch)
((${#patches[@]} > 0)) || {
    printf 'No upstream patches found.\n' >&2
    exit 1
}

temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary" >/dev/null 2>&1 || true' EXIT

git -C "$temporary" init -q
git -C "$temporary" remote add origin "$C100_BOOTUPD_REPOSITORY"
git -C "$temporary" -c gc.auto=0 fetch -q --depth=1 origin "$C100_BOOTUPD_COMMIT"
git -C "$temporary" checkout -q --detach FETCH_HEAD

for patch in "${patches[@]}"; do
    git -C "$temporary" apply --check "$patch"
    git -C "$temporary" apply "$patch"
done

printf 'Upstream patch series applies to %s.\n' "$C100_BOOTUPD_COMMIT"

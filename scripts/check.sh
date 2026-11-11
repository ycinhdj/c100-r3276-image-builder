#!/usr/bin/env bash
# Static checks, plus a check that the patch series still applies to the
# pinned c100-bootupd commit (needs network; skip with --offline).
set -Eeuo pipefail
shopt -s nullglob

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=config/release.env
source config/release.env

scripts=(build.sh lib/*.sh scripts/*.sh)
patches=("$ROOT"/patches/c100-bootupd/*.patch)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "${scripts[@]}"
else
    printf 'WARNING: shellcheck is not installed; ran syntax checks only.\n' >&2
fi

((${#patches[@]} > 0)) || {
    printf 'No upstream patches found.\n' >&2
    exit 1
}

if [[ "${1:-}" != "--offline" ]]; then
    temporary="$(mktemp -d)"
    trap 'rm -rf -- "$temporary"' EXIT
    git -C "$temporary" init -q
    git -C "$temporary" remote add origin "$C100_BOOTUPD_REPOSITORY"
    git -C "$temporary" -c gc.auto=0 fetch -q --depth=1 origin "$C100_BOOTUPD_COMMIT"
    git -C "$temporary" checkout -q --detach FETCH_HEAD
    for patch in "${patches[@]}"; do
        git -C "$temporary" apply "$patch"
    done
    printf 'Patch series applies to c100-bootupd %s.\n' "$C100_BOOTUPD_COMMIT"
fi

printf 'Repository checks passed.\n'

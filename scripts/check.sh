#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

scripts=(build.sh lib/*.sh scripts/*.sh)
patches=(patches/c100-bootupd/*.patch)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "${scripts[@]}"
else
    printf 'WARNING: shellcheck is not installed; syntax checks completed only.\n' >&2
fi

((${#patches[@]} > 0)) || {
    printf 'No upstream patches found.\n' >&2
    exit 1
}
for patch in "${patches[@]}"; do
    git apply --numstat "$patch" >/dev/null
done

configured_version="$(awk -F= '/^PROJECT_VERSION=/{gsub(/"/, "", $2); print $2}' config/release.env)"
file_version="$(cat VERSION)"
[[ "$configured_version" == "$file_version" ]] || {
    printf 'Version mismatch: VERSION=%s config=%s\n' "$file_version" "$configured_version" >&2
    exit 1
}

printf 'Repository checks passed.\n'

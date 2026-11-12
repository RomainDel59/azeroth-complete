#!/usr/bin/env bash
# Installs the addon into a game installation, as a release package would lay it out.
#
# Usage: tools/install.sh [game directory]
#   The game directory is the "_forever_" folder that holds Interface/AddOns. Without an
#   argument, it is read from WOW_GAME_DIR in the .env file at the root of the repository
#   (see .env.example); the argument takes precedence.
#
# The previous install is replaced: a link (junction or symbolic link) is removed without
# touching its target, a plain directory is deleted. The version placeholder of the TOC is
# replaced by "dev-<commit>" so that the log tells which revision was installed. Lua changes
# are picked up by /reload; a change to the TOC or a new file requires restarting the game.

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$repo_dir/.env"

# Reads KEY=VALUE from .env without executing it, so that a path with spaces needs no quoting.
read_env() {
    [ -f "$env_file" ] || return 0
    local line value
    line="$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$env_file" | tail -n 1 || true)"
    value="${line#*=}"
    value="$(printf '%s' "$value" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    value="${value#\"}"; value="${value%\"}"
    value="${value#\'}"; value="${value%\'}"
    printf '%s' "$value"
}

if [ $# -gt 1 ]; then
    echo "Usage: $0 [game directory]" >&2
    exit 2
fi

game_dir="${1:-${WOW_GAME_DIR:-$(read_env WOW_GAME_DIR)}}"
if [ -z "$game_dir" ]; then
    echo "No game directory: pass it as an argument or set WOW_GAME_DIR in $env_file" >&2
    echo "(copy .env.example to .env and edit it)." >&2
    exit 2
fi

source_dir="$repo_dir/AzerothComplete"
addons_dir="$game_dir/Interface/AddOns"
target="$addons_dir/AzerothComplete"

if [ ! -d "$addons_dir" ]; then
    echo "Not a game directory (no Interface/AddOns): $game_dir" >&2
    exit 1
fi

if [ -L "$target" ]; then
    # rm -r would follow a junction and delete the sources it points to.
    if command -v cygpath >/dev/null; then
        cmd //c rmdir "$(cygpath -w "$target")"
    else
        rm "$target"
    fi
    echo "Removed the previous link: $target"
elif [ -e "$target" ]; then
    rm -rf "$target"
    echo "Removed the previous install: $target"
fi

cp -r "$source_dir" "$target"

version="dev-$(git -C "$source_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git -C "$source_dir" diff --quiet HEAD -- . 2>/dev/null; then version="$version-modified"; fi
sed -i "s/@project-version@/$version/" "$target/AzerothComplete.toc"

echo "Installed Azeroth Complete $version into $target"

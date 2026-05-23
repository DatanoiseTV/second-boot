# Shared helpers for build scripts. Source after versions.env.

set -euo pipefail

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '\033[1;33m[%s WARN]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\033[1;31m[%s ERR ]\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# clone_or_update <repo_url> <ref> <dest_dir>
#   ref may be a tag, branch, or full SHA. Idempotent.
clone_or_update() {
    local repo="$1" ref="$2" dest="$3"
    if [ ! -d "$dest/.git" ]; then
        log "clone $repo -> $dest"
        # Shallow clone with tag depth; we'll deepen if checkout needs it.
        git clone --filter=blob:none "$repo" "$dest"
    fi
    log "checkout $ref in $dest"
    git -C "$dest" fetch --tags --prune origin
    git -C "$dest" checkout --detach "$ref"
}

ensure_dir() { mkdir -p "$1"; }

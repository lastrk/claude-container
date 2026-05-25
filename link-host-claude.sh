#!/bin/bash
# link-host-claude.sh
#
# Selectively symlink entries from the host's ~/.claude (mounted read-only at
# /home/vscode/.claude-host) into the container's writable ~/.claude. This
# exposes host configuration (settings, plugins, commands, agents, skills,
# user-level CLAUDE.md, MCP definitions, etc.) without touching anything
# Claude Code writes to at runtime (history, projects, plans, sessions,
# memory, telemetry, caches).
#
# Idempotent: re-running on container rebuild is safe. Existing real files or
# correct symlinks are left untouched.
#
# To customise the policy, edit DENYLIST below and rebuild the installer.

set -u

HOST_DIR=/home/vscode/.claude-host
LOCAL_DIR="$HOME/.claude"

# Entries Claude Code writes to during normal operation. Linking these to the
# read-only mount would break writes; leaving them out keeps host state pristine
# and lets the container own its own runtime data.
DENYLIST=(
    # Runtime state directories
    projects
    tasks
    plans
    sessions
    session-env
    daemon
    shell-snapshots
    telemetry
    file-history
    paste-cache
    cache
    backups
    ide
    debug
    jobs
    memory
    # Runtime state files
    history.jsonl
    daemon.log
    mcp-needs-auth-cache.json
    stats-cache.json
    .last-cleanup
    # macOS noise
    .DS_Store
)

if [ ! -d "$HOST_DIR" ]; then
    echo "link-host-claude: no host mount at $HOST_DIR — skipping (host ~/.claude not mounted)."
    exit 0
fi

mkdir -p "$LOCAL_DIR"

is_denylisted() {
    local name="$1"
    local d
    for d in "${DENYLIST[@]}"; do
        [ "$d" = "$name" ] && return 0
    done
    return 1
}

linked=0
denied=0
present=0

shopt -s dotglob nullglob
for entry in "$HOST_DIR"/*; do
    name=$(basename "$entry")
    if is_denylisted "$name"; then
        denied=$((denied + 1))
        continue
    fi
    target="$LOCAL_DIR/$name"
    # Skip if anything already exists at the target (real file/dir, valid
    # symlink, or even a broken symlink — don't clobber).
    if [ -e "$target" ] || [ -L "$target" ]; then
        present=$((present + 1))
        continue
    fi
    ln -s "$HOST_DIR/$name" "$target"
    linked=$((linked + 1))
done

echo "link-host-claude: linked=$linked, skipped(denylisted)=$denied, already-present=$present"
echo "  Host mount:    $HOST_DIR (read-only)"
echo "  Container dir: $LOCAL_DIR (writable; runtime state lives here)"

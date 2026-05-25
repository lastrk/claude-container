#!/bin/bash
# Generate Claude Code configuration for container
# Reads ANTHROPIC_* credentials from process env (injected via devcontainer.json
# `containerEnv` from the host shell). No file-based handoff anymore.

DEVCONTAINER_DIR=/workspace/.devcontainer
OUTPUT=~/.claude.json

# Ensure .claude directory exists (a real, writable dir alongside the readonly
# /home/vscode/.claude-host bind mount; symlinks from .claude-host are wired up
# afterwards by link-host-claude.sh).
mkdir -p ~/.claude

if [ -z "$ANTHROPIC_AUTH_TOKEN" ]; then
    echo "Error: ANTHROPIC_AUTH_TOKEN not set"
    echo "Please set ANTHROPIC_AUTH_TOKEN in your host environment before starting the container."
    echo "(It is forwarded into the container via devcontainer.json containerEnv.)"
    exit 1
fi

echo "Using ANTHROPIC_AUTH_TOKEN from container env for authentication"

# Get last 20 chars of token (Claude Code uses this as the key suffix)
TOKEN_SUFFIX="${ANTHROPIC_AUTH_TOKEN: -20}"

# Create minimal ~/.claude.json
# No MCP servers are pre-registered. Install on demand inside the container and add
# a `mcpServers.<name>` entry here (see CLAUDE.md → "Installing MCP Servers on Demand").
jq -n \
  --arg tokenSuffix "$TOKEN_SUFFIX" \
  '{
    numStartups: 1,
    installMethod: "devcontainer",
    hasCompletedOnboarding: true,
    customApiKeyResponses: {
      approved: [$tokenSuffix],
      rejected: []
    },
    projects: {
      "/workspace": {
        allowedTools: [],
        history: [],
        hasTrustDialogAccepted: true
      }
    }
  }' > "$OUTPUT"

chmod 600 "$OUTPUT"
echo "Generated $OUTPUT"

# Auth env vars are injected by containerEnv — no ~/.claude/settings.json write.
# That frees ~/.claude/settings.json to be a symlink to the host's settings.json
# (created by link-host-claude.sh if present on host).
echo "Auth env vars (from containerEnv):"
echo "  - ANTHROPIC_AUTH_TOKEN: set"
[ -n "$ANTHROPIC_BASE_URL" ]      && echo "  - ANTHROPIC_BASE_URL: $ANTHROPIC_BASE_URL"
[ -n "$ANTHROPIC_CUSTOM_HEADERS" ] && echo "  - ANTHROPIC_CUSTOM_HEADERS: set"

# GitHub CLI authentication (optional, captured from host by initializeCommand)
GH_TOKEN_FILE="$DEVCONTAINER_DIR/.gh-auth-token"
GH_TOKEN=$(cat "$GH_TOKEN_FILE" 2>/dev/null || echo "")
if [ -n "$GH_TOKEN" ]; then
    if command -v gh >/dev/null 2>&1; then
        if echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null; then
            echo "  - GitHub CLI: authenticated via host token"
        else
            echo "  - GitHub CLI: authentication failed (token may be invalid or expired)"
        fi
    else
        echo "  - GitHub CLI: host token captured but gh not installed in container"
    fi
else
    echo "  - GitHub CLI: no host token (gh not installed or not logged in on host)"
fi

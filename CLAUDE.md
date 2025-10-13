# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a secure DevContainer configuration for running Claude Code in a hardened, Podman-compatible container environment. The configuration implements defense-in-depth security principles and Microsoft's DevContainer best practices.

## Key Architecture Concepts

### Security Model

The container implements multiple layers of security isolation:

1. **Non-root execution**: Container runs as `vscode` user (UID 1000), never root
2. **Minimal capabilities**: Uses `--cap-drop=ALL` then selectively adds only SETUID, SETGID, and AUDIT_WRITE
3. **Network isolation**: `slirp4netns` provides user-mode networking (allows internet, blocks host services)
4. **Privilege escalation prevention**: `--security-opt=no-new-privileges` prevents setuid exploitation
5. **User namespace mapping**: `--userns=keep-id` (Podman) maps container UID to host UID for proper file ownership

### Authentication Flow

Claude Code authentication happens automatically during container creation:

1. **Host extraction** (`initializeCommand`): Before container starts, extracts API key from macOS keychain and OAuth config from `~/.claude.json` on host
2. **File staging**: Writes `.devcontainer/.claude-token` and `.devcontainer/.claude-oauth.json` (both gitignored)
3. **Container injection** (`postCreateCommand`): After container starts, `generate-claude-config.sh` merges OAuth config and API key into container's `~/.claude.json`
4. **No manual login**: Claude Code works immediately without authentication prompts

### Container Lifecycle Hooks

- **initializeCommand**: Runs on HOST before container creation - extracts secrets from keychain/OAuth
- **postCreateCommand**: Runs in CONTAINER after creation - installs Claude Code, generates config, verifies git
- **shutdownAction**: `stopContainer` preserves container state but stops processes when VSCode disconnects

## Common Commands

### Container Management

```bash
# Open in VSCode DevContainer
code /path/to/claude-container
# Then: F1 -> "Dev Containers: Reopen in Container"

# Rebuild container (after Dockerfile changes)
# In VSCode: F1 -> "Dev Containers: Rebuild Container"

# Check Podman machine status (macOS only)
podman machine list
podman machine start

# View container logs
podman ps -a  # Find container ID
podman logs <container-id>
```

### Development Workflow

```bash
# Verify Claude Code installation
claude --version

# Check authentication
cat ~/.claude.json  # Should contain OAuth config and API key
cat ~/.claude/settings.json  # Should contain ANTHROPIC_API_KEY

# Manual authentication if needed
TOKEN=$(cat /workspace/.devcontainer/.claude-token)
/workspace/.devcontainer/generate-claude-config.sh

# Git operations (pre-configured)
git status
git add .
git commit -m "message"
git push
```

### Installing Additional Tools

```bash
# System packages (requires sudo)
sudo apt-get update
sudo apt-get install <package-name>

# Python packages
pip3 install <package-name>

# NPM packages (global)
npm install -g <package-name>  # Uses ~/.npm-global prefix
```

## File Structure

```
.devcontainer/
├── devcontainer.json          # DevContainer configuration with security settings
├── Dockerfile                 # Multi-stage build with development tools
├── claude.json.template       # Claude Code config template (DEPRECATED - see below)
├── generate-claude-config.sh  # Generates ~/.claude.json from OAuth + token
├── .claude-token             # API key extracted from keychain (gitignored)
└── .claude-oauth.json        # OAuth config extracted from host (gitignored)
```

## Important Implementation Details

### Why No .dockerignore?

The `.dockerignore` file is intentionally absent because:
- Build context is the project root (`context: ".."` in devcontainer.json)
- No files from project root are COPYed into the image during build
- All tools installed via apt/npm, no project files needed at build time
- Runtime mounts handle project file access (not build-time COPY)

### OAuth Account Extraction

The `initializeCommand` extracts OAuth account info from host `~/.claude.json`:
```bash
jq '{oauthAccount, userID, hasAvailableSubscription}' ~/.claude.json > .devcontainer/.claude-oauth.json
```

This preserves organization/team settings when authenticating in the container.

### API Key Handling

Two authentication methods are configured:

1. **settings.json** (primary): `~/.claude/settings.json` with `ANTHROPIC_API_KEY` in `env` field
2. **.claude.json** (OAuth): `~/.claude.json` with full OAuth config and `customApiKeyResponses.approved` array

Both are generated during `postCreateCommand` for maximum compatibility.

### VSCode Server Directory

The `/vscode` directory is created with 777 permissions (not mounted) because:
- VSCode Server needs to install itself on first connection
- With `--userns=keep-id`, ownership mapping makes volume mounts complex
- Trade-off: Server reinstalls on each rebuild (acceptable for dev container)
- Simpler than maintaining persistent volume for VS Code extensions

### Git Safe Directory

`git config --system --add safe.directory /workspace` in Dockerfile prevents "dubious ownership" errors that occur when:
- Mounted volume UID/GID differs from container user
- Git security checks refuse to operate on "untrusted" repositories
- System-wide config ensures it works even after user switches

## Troubleshooting

### Authentication Failures

If Claude Code can't authenticate:

```bash
# Verify files exist
ls -la /workspace/.devcontainer/.claude-*

# Check token content (should be long alphanumeric string)
cat /workspace/.devcontainer/.claude-token

# Regenerate config manually
/workspace/.devcontainer/generate-claude-config.sh

# Check generated config
cat ~/.claude.json
cat ~/.claude/settings.json
```

### Git "Dubious Ownership" Errors

If git refuses to operate:

```bash
# Should already be configured, but verify
git config --system --list | grep safe.directory

# Add manually if missing
git config --global --add safe.directory /workspace
```

### Permission Denied on Workspace Files

If you can't write to `/workspace`:

```bash
# On host (outside container)
ls -la /path/to/claude-container
chown -R $(whoami) /path/to/claude-container

# Check UID mapping (inside container)
id  # Should show UID matching host user
```

### Network Isolation Issues

The container intentionally cannot access host services (e.g., `localhost:3000` on host). This is by design for security.

If you need to access host services:
- Use `--network=host` in `runArgs` (removes network isolation, less secure)
- Or run service in separate container and link via Docker Compose

### Podman Machine Not Running (macOS)

```bash
podman machine list
# If not running:
podman machine start

# If doesn't exist:
podman machine init
podman machine start
```

## Security Considerations

### What the Container Can Do

- Read/write project files in `/workspace`
- Install packages via apt (with sudo)
- Install Python/NPM packages
- Access internet (HTTP/HTTPS)
- Clone/push to Git repositories

### What the Container Cannot Do

- Access host services (e.g., databases on localhost)
- Mount additional host directories
- Access host filesystem outside `/workspace`
- Perform privileged kernel operations
- Escape to host system (capabilities dropped)
- Gain elevated privileges via setuid binaries

### Modifying Security Settings

To add capabilities (only if absolutely necessary):

```jsonc
// In devcontainer.json runArgs:
"--cap-add=CAP_NAME"
```

To allow host network access (reduces isolation):

```jsonc
// In devcontainer.json runArgs (replace slirp4netns):
"--network=host"
```

**Warning**: Only relax security if you understand the implications.

## VSCode Extensions

Pre-installed extensions for C++ development:
- `ms-vscode.cpptools` - C/C++ IntelliSense, debugging
- `ms-vscode.cmake-tools` - CMake integration
- `eamodio.gitlens` - Git visualization
- `editorconfig.editorconfig` - Consistent code style

Add more in `devcontainer.json`:

```jsonc
"customizations": {
  "vscode": {
    "extensions": [
      "existing.extension",
      "your.new.extension"
    ]
  }
}
```

## Customization

### Adding System Packages

Edit `Dockerfile`:

```dockerfile
RUN apt-get update && apt-get install -y \
    existing-package \
    your-new-package \
    && apt-get clean
```

### Changing Base Image

Current: `mcr.microsoft.com/devcontainers/base:ubuntu-22.04`

To change:
- Update `FROM` line in `Dockerfile`
- Ensure new image has `vscode` user or create it
- Update package manager commands if not Ubuntu/Debian

### Adding Port Forwarding

If running web services in container:

```jsonc
// In devcontainer.json:
"forwardPorts": [3000, 8080]
```

## Platform Compatibility

### Podman vs Docker

Configuration works with both:
- **Podman**: `--userns=keep-id` provides rootless UID mapping
- **Docker**: Desktop handles UID mapping automatically (flag ignored)

To use Podman in VSCode:

```json
// .vscode/settings.json or user settings
{
  "dev.containers.dockerPath": "podman"
}
```

### macOS Requirements

- Podman Machine must be running
- Keychain stores Claude Code API key
- `initializeCommand` uses `security` command to extract token

### Linux/Windows

`initializeCommand` assumes macOS keychain. Modify for other platforms:

```jsonc
// For manual token file:
"initializeCommand": "echo 'YOUR_TOKEN' > ${localWorkspaceFolder}/.devcontainer/.claude-token"

// Or skip and authenticate interactively:
"initializeCommand": "echo 'Skipping token extraction'"
```

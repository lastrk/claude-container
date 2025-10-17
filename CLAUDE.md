# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a **self-contained DevContainer installer** for running Claude Code in a secure, Podman-compatible containerized environment. The project implements a unique build system that generates a single-file installer (`install.sh`) with all configuration files embedded as heredocs.

**Key concept**: The installer is built once and can be distributed as a single bash script that contains everything needed to set up the DevContainer configuration in any Git repository.

## Project Architecture

### Build System Architecture

The project uses a **two-stage distribution model**:

1. **Source files** (this repository):
   - `devcontainer.json` - DevContainer configuration with security hardening
   - `Dockerfile` - Container image definition
   - `generate-claude-config.sh` - Runtime authentication configuration script
   - `CLAUDE.md` - Documentation embedded in installer

2. **build.sh** - Build script that:
   - Reads all source files
   - Embeds them as heredocs in a single bash script
   - Adds extraction and installation logic
   - Produces self-contained `install.sh`

3. **install.sh** (generated artifact):
   - Single distributable file (~44KB)
   - Contains all configuration files embedded
   - Can be run in any Git repository
   - Extracts files to `.devcontainer/` directory

### Authentication Flow Architecture

Multi-layered authentication system for Claude Code:

```
Host System (macOS)
  ↓ initializeCommand (runs before container creation)
  ├─→ Extract API key from macOS keychain
  │   └─→ Write to .devcontainer/.claude-token (gitignored)
  └─→ Extract OAuth config from ~/.claude.json
      └─→ Write to .devcontainer/.claude-oauth.json (gitignored)

Container Creation
  ↓ postCreateCommand (runs inside container after creation)
  ├─→ Install Claude Code via npm
  └─→ Run generate-claude-config.sh
      ├─→ Read .claude-token and .claude-oauth.json
      ├─→ Generate ~/.claude.json (OAuth + API key)
      └─→ Generate ~/.claude/settings.json (ANTHROPIC_API_KEY env var)

Result: Claude Code authenticated without manual login
```

**Critical implementation details**:
- `initializeCommand` runs on HOST before container exists
- `postCreateCommand` runs INSIDE container after it's created
- Two authentication methods for compatibility (OAuth + env var)
- Token files are gitignored and never committed
- `tr -d '\n'` strips trailing newline from keychain token (required)

### Security Architecture

Defense-in-depth container hardening via `runArgs` in devcontainer.json:

1. **Capability Model**: Drop ALL, add only essential capabilities:
   - SETUID/SETGID (user switching, sudo)
   - AUDIT_WRITE (authentication logging)
   - CHOWN (package manager file ownership)
   - NET_BIND_SERVICE (bind to ports 80/443)
   - NET_RAW (ping/traceroute for debugging)
2. **Network Isolation**: slirp4netns (user-mode, blocks host services)
3. **Privilege Escalation**: `--security-opt=no-new-privileges`
4. **User Namespace**: `--userns=keep-id` (Podman rootless UID mapping)
5. **Resource Limits**: `--cpus=4` and `--memory=8g` (configurable)

### File Ownership Model

The project root serves dual purposes:

1. **Source repository**: DevContainer configuration files for this project
2. **Installer generator**: Build system that creates distributable installer

When `build.sh` runs, it reads files from project root and embeds them in `install.sh`, which users run in *their* repositories to install the DevContainer configuration.

## Common Commands

### Build the Installer

```bash
# Generate install.sh with all files embedded
./build.sh
```

**What it does**:
- Reads all source files from project root
- Generates git commit hash and build date
- Creates heredocs for each file with EOF delimiters
- Produces self-contained install.sh (~44KB)
- Makes installer executable (chmod +x)

**Files embedded** (defined in build.sh:31-36):
1. devcontainer.json
2. Dockerfile
3. generate-claude-config.sh
4. CLAUDE.md (this file)

### Test the Installer Locally

```bash
# Create test repository
mkdir /tmp/test-repo && cd /tmp/test-repo
git init

# Run installer
bash /path/to/claude-container/install.sh
```

**Expected behavior**:
- Checks if .devcontainer/ already exists (errors if present)
- Shows interactive prompt with ESC to cancel
- Creates .devcontainer/ directory
- Extracts all embedded files
- Makes generate-claude-config.sh executable
- Adds .claude-token and .claude-oauth.json to .gitignore

### Run Claude Code in Unsupervised Mode

After the container is running, start Claude Code in fully autonomous mode:

```bash
# Inside the container
claude --dangerously-skip-permissions
```

**What this does**:
- Bypasses all permission prompts for tool usage
- Enables fully autonomous operation
- Allows Claude Code to execute commands without confirmation

**Security considerations**:
- ⚠️ Only use in sandboxed/isolated environments
- The container already provides isolation (capabilities dropped, network isolated, resource limited)
- This flag grants unrestricted access within the container's security boundaries
- Appropriate for CI/CD, automated workflows, or development in isolated containers

### Modify Configuration Files

When editing configuration files, you must rebuild the installer:

```bash
# 1. Edit source file
vim devcontainer.json

# 2. Rebuild installer
./build.sh

# 3. Commit both source and generated installer
git add devcontainer.json install.sh
git commit -m "Update devcontainer configuration"
```

**Important**: install.sh is a build artifact but is tracked in git because it's the primary distribution method. Both source files and generated installer must stay in sync.

### Adjust Resource Limits

Edit `devcontainer.json` runArgs array:

```jsonc
"runArgs": [
  // ... other flags ...
  "--cpus=2",      // Default: 4
  "--memory=4g"    // Default: 8g
]
```

Then rebuild: `./build.sh`

## Key Implementation Details

### Why Heredoc Embedding?

The build system uses heredocs instead of base64 encoding or downloading files because:
- Human-readable installer (can inspect what will be installed)
- No dependencies (no base64, curl, wget required)
- Preserves exact file content including comments
- Single bash script is easily distributable via curl/wget

### Dynamic Configuration Generation

Authentication configuration is generated dynamically by `generate-claude-config.sh` using `jq -n`:
1. `~/.claude/settings.json` with `env.ANTHROPIC_API_KEY` (primary)
2. `~/.claude.json` generated with OAuth account info and token suffix

No template file is needed - the script creates the JSON structure directly using jq.

### File Naming Convention in build.sh

Heredoc EOF delimiters use file names with special characters replaced:
- `devcontainer.json` → `EOF_devcontainer_json`
- `generate-claude-config.sh` → `EOF_generate_claude_config_sh`

This is done by `${file//[.-]/_}` bash substitution (line 199).

### Why install.sh is Tracked in Git

Though install.sh is a generated artifact, it's tracked in version control because:
- It's the primary distribution method (users curl from GitHub)
- Allows users to download without cloning entire repo
- Build date and commit hash embedded for traceability
- Simplifies distribution via `curl -fsSL https://raw.githubusercontent.com/.../install.sh`

## Modifying the Build System

### Adding a New File to Embed

1. Create the file in project root
2. Add to `FILES` array in build.sh (line 31-36):
   ```bash
   FILES=(
       "devcontainer.json"
       "Dockerfile"
       "your-new-file.txt"  # Add here
   )
   ```
3. Update installer display in build.sh if needed (line 152-157)
4. Rebuild: `./build.sh`

### Changing Installer Behavior

Installer logic is in three sections of build.sh:

1. **Header** (line 78-93): Shebang, version info
2. **Main logic** (line 94-193): Installation flow, error checking
3. **Footer** (line 209-268): Post-install, .gitignore updates, next steps

Edit the heredoc strings in build.sh, then rebuild.

### Testing Changes

```bash
# 1. Make changes to source files or build.sh
# 2. Rebuild
./build.sh

# 3. Test in clean directory
cd /tmp && mkdir test-project && cd test-project
git init
bash /path/to/claude-container/install.sh

# 4. Verify extraction
ls -la .devcontainer/
cat .devcontainer/devcontainer.json

# 5. Test in VSCode (optional)
code .
# F1 → "Dev Containers: Reopen in Container"
```

## Troubleshooting the Build System

### "Missing source file" error

**Cause**: build.sh expects all files in `FILES` array to exist

**Solution**: Ensure all files listed in build.sh:31-36 are present in project root

### Installer creates malformed files

**Cause**: Heredoc EOF delimiter collision (file contains `EOF_filename` string)

**Solution**: Change delimiter name in build.sh:199 to something unique

### Git commit hash shows "unknown"

**Cause**: Not running in a git repository, or git not in PATH

**Solution**: Run build.sh from within the git repository, ensure git is installed

## Platform Compatibility Notes

### macOS-specific Features

The `initializeCommand` in devcontainer.json uses macOS-specific commands:
- `security find-generic-password` - Extracts from keychain
- `tr -d '\n'` - Removes trailing newline from keychain output

**For Linux/Windows**: Users must modify initializeCommand or authenticate interactively inside container.

### Podman vs Docker

Configuration works with both:
- `--userns=keep-id` is Podman-specific (Docker ignores it gracefully)
- `--cpus` and `--memory` work on both Docker and Podman
- Network mode `slirp4netns` is optimal for rootless Podman

Users can set VSCode to use Podman via settings: `"dev.containers.dockerPath": "podman"`

## Documentation Locations

The project has documentation in multiple locations:

1. **README.md** (project root): User-facing documentation, installation instructions
2. **CLAUDE.md** (this file, project root): Architecture and development guidance
3. **.devcontainer/CLAUDE.md** (generated): Copy of this file, embedded in installer, appears in user's projects

When updating documentation, remember that CLAUDE.md gets embedded in the installer and distributed to users.

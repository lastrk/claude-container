#!/usr/bin/env bash
set -e

# Secure DevContainer Configuration Installer
# Self-contained installer with all configuration files embedded
# Generated from commit: 11732d4
# Build date: 2025-10-13 10:37:21


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not a git repository. Please run this script from the root of a git repository."
    exit 1
fi

# Get the repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
DEVCONTAINER_DIR="${REPO_ROOT}/.devcontainer"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Secure DevContainer Configuration Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "Repository root: ${REPO_ROOT}"
print_info "Target directory: ${DEVCONTAINER_DIR}"
echo ""

# Check if .devcontainer already exists
if [ -d "${DEVCONTAINER_DIR}" ]; then
    print_error ".devcontainer directory already exists!"
    print_error "Please remove or rename the existing .devcontainer directory first."
    echo ""
    echo "To remove: rm -rf ${DEVCONTAINER_DIR}"
    echo "To backup: mv ${DEVCONTAINER_DIR} ${DEVCONTAINER_DIR}.backup"
    exit 1
fi

# Display what will be installed
echo "This script will:"
echo ""
echo "  1. Create .devcontainer directory"
echo "  2. Extract embedded configuration files:"
echo ""
echo "     • devcontainer.json"
echo "     • Dockerfile"
echo "     • generate-claude-config.sh"
echo "     • claude.json.template"
echo "     • CLAUDE.md"
echo ""
echo "  3. Set proper permissions (generate-claude-config.sh +x)"
echo ""
echo "Features:"
echo "  • Rootless Podman-compatible container"
echo "  • Minimal Linux capabilities (security hardened)"
echo "  • Network isolation (slirp4netns)"
echo "  • Automatic Claude Code installation"
echo "  • OAuth + API key authentication support"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "Press any key to proceed, or ESC to cancel..."

# Read single character without waiting for Enter
read -n 1 -s -r key

# Check if ESC was pressed (ASCII 27)
if [ "$key" = $'\e' ]; then
    echo ""
    print_warning "Installation cancelled."
    exit 0
fi

echo ""
echo ""
print_info "Starting installation..."
echo ""

# Create .devcontainer directory
mkdir -p "${DEVCONTAINER_DIR}"
print_success "Created ${DEVCONTAINER_DIR}"


# Extracting devcontainer.json
cat > "${DEVCONTAINER_DIR}/devcontainer.json" << 'EOF_devcontainer_json'
{
	// Container Name: Human-readable identifier shown in VSCode
	// Purpose: Helps identify this container in VSCode's Remote Explorer
	// Why necessary: Multiple containers may be running; name distinguishes them
	// Impact: Purely cosmetic, no security or functional impact
	"name": "cudf-metal Development Container",

	// Build Configuration: How to build the container image
	// Purpose: Tells VSCode where to find Dockerfile and what context to use
	// Why object notation: Allows additional build arguments if needed
	"build": {
		// Dockerfile Path: Location of Dockerfile relative to this JSON file
		// Purpose: Specifies which Dockerfile to build from
		// Why "Dockerfile": Standard naming convention, located in same directory
		// Alternative: Could specify different name like "dev.Dockerfile"
		"dockerfile": "Dockerfile",

		// Build Context: Directory containing files needed during build
		// Purpose: Sets root directory for COPY/ADD commands in Dockerfile
		// Why "..": Parent directory (project root) is context, not .devcontainer/
		// Impact: Allows Dockerfile to access project files if needed during build
		// Security: Combined with .dockerignore, prevents leaking sensitive files
		"context": ".."
	},

	// Remote User: User for VSCode operations inside container
	// Purpose: VSCode extensions and terminals will run as this user
	// Why "vscode": Non-root user pre-created by Microsoft's base image
	// Security: Running as non-root prevents accidental system-wide changes
	// Impact: All VSCode operations (terminal, debugging, etc.) use this user
	"remoteUser": "vscode",

	// Container User: Primary user for container processes
	// Purpose: Specifies which user the container runs as
	// Why same as remoteUser: Ensures consistency between container and VSCode
	// Security: Non-root execution is fundamental security best practice
	// Why UID 1000: Matches typical first user on Linux systems
	"containerUser": "vscode",

	// Mounts: Filesystem bindings between host and container
	// Purpose: Controls what host directories are accessible inside container
	// Why explicit: Default mounting can be too permissive; explicit is more secure
	// Format: Docker CLI mount syntax (source,target,type,options)
	"mounts": [
		// Project Workspace Mount (Read-Write)
		// Purpose: Makes project files accessible inside container for development
		// source: ${localWorkspaceFolder} resolves to project root on host
		// target: /workspace is mount point inside container
		// type: bind creates direct link to host filesystem (not a copy)
		// consistency: cached optimizes for read-heavy workloads (macOS/Windows)
		// Why read-write: Need to edit code, run builds, create files
		// Security: Isolated to project directory only, not entire home or root
		// Note: Includes .devcontainer directory - not mounted separately as read-only
		// Rationale: Container config files aren't accessed at runtime; complexity
		//            of read-only mounting outweighs security benefit in dev environment
		"source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
	],

	// Workspace Folder: Initial working directory inside container
	// Purpose: Where VSCode opens when connecting to container
	// Why /workspace: Matches the mount point of project files
	// Impact: Terminal, file explorer, and tasks start from this directory
	// Benefit: Immediate access to project root without navigation
	"workspaceFolder": "/workspace",

	// Run Arguments: Additional flags passed to container runtime (Podman/Docker)
	// Purpose: Implements defense-in-depth security through container hardening
	// Why array: Each element is separate CLI argument to podman/docker run
	// Compatibility: Works with both Docker and Podman (uses standard OCI flags)
	"runArgs": [
		// Capability Drop: Remove ALL Linux capabilities
		// Purpose: Starts with zero capabilities, implements least privilege
		// Why necessary: Default container has many capabilities it doesn't need
		// Security: Reduces attack surface by removing powerful system capabilities
		// Examples of dropped: CAP_NET_ADMIN (network manipulation), CAP_SYS_ADMIN (mount, etc.)
		// Impact: Container cannot perform privileged operations by default
		"--cap-drop=ALL",

		// Capability Add: SETUID (Change user IDs)
		// Purpose: Allows processes to change their user ID
		// Why necessary: Required for 'su', 'sudo', and user switching
		// Use case: Installing packages with sudo, running commands as different user
		// Security risk: Minimal - limited to user namespace, not host system
		// Alternative: Could omit if sudo access not needed (more restrictive)
		"--cap-add=SETUID",

		// Capability Add: SETGID (Change group IDs)
		// Purpose: Allows processes to change their group ID
		// Why necessary: Required for group switching, complements SETUID
		// Use case: File operations requiring specific group ownership
		// Security risk: Minimal - limited to user namespace
		"--cap-add=SETGID",

		// Capability Add: AUDIT_WRITE (Write to kernel audit log)
		// Purpose: Allows writing records to kernel auditing system
		// Why necessary: Some system tools and PAM modules require this
		// Use case: Login operations, sudo may write audit logs
		// Security risk: Low - only writes to logs, doesn't read or modify system
		// Impact: Without this, some authentication operations may fail
		"--cap-add=AUDIT_WRITE",

		// Network Mode: slirp4netns (User-mode networking)
		// Purpose: Isolates container network from host while allowing internet
		// Why slirp4netns: User-mode TCP/IP stack, no root privileges required
		// How it works: NAT-based networking, container gets own IP namespace
		// What's accessible: Internet via HTTP/HTTPS, DNS resolution
		// What's blocked: Host services (127.0.0.1 on host), other containers, host network
		// Security: Prevents lateral movement to host or other services
		// Trade-off: Slightly slower than host networking (5-10% latency overhead)
		// Podman compatibility: Optimal for rootless Podman
		// Alternative: "--network=none" (no network) or "--network=host" (no isolation)
		"--network=slirp4netns",

		// Security Option: no-new-privileges
		// Purpose: Prevents privilege escalation via setuid binaries or file capabilities
		// How it works: Sets Linux kernel PR_SET_NO_NEW_PRIVS bit
		// What it blocks: Setuid/setgid executables cannot gain elevated privileges
		// Attack prevented: Even if attacker finds setuid root binary, can't exploit it
		// Compatibility: Works with sudo (relies on CAP_SETUID, not setuid bit)
		// Security: Defense-in-depth - adds extra layer beyond capability dropping
		// Standard: Recommended by Docker/Podman security best practices
		"--security-opt=no-new-privileges",

		// User Namespace: keep-id (Podman-specific)
		// Purpose: Maps container user UID/GID to host user UID/GID
		// Why necessary: Prevents file ownership issues on mounted volumes
		// How it works: Container UID 1000 maps to host UID (your user)
		// Problem solved: Without this, files created in container may be inaccessible on host
		// Rootless Podman: Essential for proper file permissions
		// Docker equivalent: Handled automatically by Docker Desktop on macOS/Windows
		// Security: Isolates user namespace, prevents container from accessing other users' files
		"--userns=keep-id"
	],

	// Features: Pre-packaged DevContainer functionality modules
	// Purpose: Install additional tools using DevContainer feature system
	// Why features: Modular, versioned, reusable across different containers
	// Format: Map of feature identifier to configuration object
	// Source: Features hosted on GitHub Container Registry (ghcr.io)
	// NOTE: Disabled temporarily due to Podman buildx --load flag incompatibility
	// Git LFS can be installed manually in Dockerfile if needed
	"features": {
		// Git LFS Feature: Large File Storage support for Git
		// Purpose: Enables handling of large binary files in Git repositories
		// Why necessary: Some projects use Git LFS for assets, models, datasets
		// Already installed: Base image has git, this adds LFS extension
		// Version: ":1" means major version 1, gets latest 1.x.x
		// Configuration: {} means use defaults (no custom options needed)
		// Impact: 'git lfs' commands will be available
		// "ghcr.io/devcontainers/features/git-lfs:1": {}
	},

	// Customizations: Tool-specific settings and extensions
	// Purpose: Configure VSCode (or other IDEs) when connecting to container
	// Why customizations: Each IDE has different configuration needs
	// Structure: Organized by tool name (vscode, vim, etc.)
	"customizations": {
		// VSCode-specific customizations
		// Purpose: Configure VSCode behavior and install extensions
		// Applied when: VSCode connects to container for first time
		// Persistence: Extensions installed in container, not on host
		"vscode": {
			// Extensions: VSCode extensions to install automatically
			// Purpose: Provides IDE functionality for C++ development
			// Format: Array of extension IDs from VSCode marketplace
			// Why auto-install: Ensures consistent dev environment for all users
			// Installation: Happens once during container creation (cached in image)
			"extensions": [
				// C/C++ Extension: IntelliSense, debugging, code navigation
				// Purpose: Required for C++ language support in VSCode
				// Why necessary: Project is C++ (compiles to Metal shaders)
				// Provides: Syntax highlighting, autocomplete, error checking, debugging
				"ms-vscode.cpptools",

				// CMake Tools: CMake project support
				// Purpose: Integration with CMake build system
				// Why necessary: Project uses CMakeLists.txt for building
				// Provides: CMake configuration, build/test from VSCode, target selection
				"ms-vscode.cmake-tools",

				// GitLens: Enhanced Git capabilities
				// Purpose: Advanced Git visualization and history exploration
				// Why useful: Blame annotations, commit history, repository insights
				// Not strictly necessary: Base Git works without it, but improves workflow
				"eamodio.gitlens",

				// EditorConfig: Maintain consistent coding styles
				// Purpose: Respects .editorconfig file for formatting rules
				// Why useful: Ensures consistent indentation, line endings across editors
				// Common in projects: Many open-source projects use .editorconfig
				"editorconfig.editorconfig"
			],

			// VSCode Settings: Editor configuration specific to this container
			// Purpose: Override default VSCode settings for better container experience
			// Scope: Applied only in this container, doesn't affect host VSCode
			"settings": {
				// Terminal Default Profile: Which shell to use for integrated terminal
				// Purpose: Specifies bash as the default shell
				// Why bash: Dockerfile uses bash, ensures consistency
				// Platform: "linux" because container runs Linux (even on macOS host)
				// Alternative: Could use zsh, fish, etc. if installed in Dockerfile
				"terminal.integrated.defaultProfile.linux": "bash"
			}
		}
	},

	// Post-Create Command: Script to run after container is created
	// Purpose: Perform initialization tasks on first container startup
	// When executed: Once, after container is built and started for first time
	// Execution context: Runs as remoteUser (vscode) inside container
	// Why useful: Automate setup steps, install tools, verify environment
	// Format: String (shell command) or array (executable + args)
	// This command: Sets up Claude Code with API key in settings.json env field
	// Why mkdir: Ensures directories exist with correct ownership
	// Why npm install: Auto-installs Claude Code globally
	// Why settings.json env field: Proper way to set ANTHROPIC_API_KEY per Claude Code docs
	// Why .claude.json: Creates OAuth account config for organization support
	// Why git --version: Verifies git works (tests safe.directory config)
	// &&: Chain commands - each must succeed for next to run
	"postCreateCommand": "mkdir -p /vscode ~/.claude && npm install -g @anthropic-ai/claude-code && if [ -f /workspace/.devcontainer/.claude-token ]; then TOKEN=$(cat /workspace/.devcontainer/.claude-token) && echo \"{\\\"env\\\": {\\\"ANTHROPIC_API_KEY\\\": \\\"$TOKEN\\\"}}\" > ~/.claude/settings.json && chmod 600 ~/.claude/settings.json; fi && if [ -f /workspace/.devcontainer/generate-claude-config.sh ]; then /workspace/.devcontainer/generate-claude-config.sh; fi && echo 'DevContainer created successfully! Claude Code installed.' && git --version",

	// Forward Ports: Automatically forward ports from container to host
	// Purpose: Makes services running in container accessible from host browser/tools
	// Format: Array of port numbers (e.g., [3000, 8080])
	// Why empty: This project doesn't run web services by default
	// Use case: If running web server, add its port here
	// Security: Only forwarded ports are accessible; others remain isolated
	// Example: If running HTTP server on port 3000, would add: [3000]
	"forwardPorts": [],

	// Port Attributes: Fine-grained control over port forwarding behavior
	// Purpose: Configure how each forwarded port is handled
	// Why object: Maps port number to configuration object
	// When useful: Control visibility, labels, auto-forward behavior per port
	"portsAttributes": {
		// Example configuration (commented out):
		// "3000": Port number to configure
		//   "label": Human-readable name shown in VSCode
		//   "onAutoForward": Action when VSCode auto-detects port
		//     - "notify": Show notification
		//     - "openBrowser": Automatically open in browser
		//     - "ignore": Do nothing
		// Security: Can prevent auto-opening untrusted services in browser
	},

	// Remote Environment Variables: Set environment variables inside container
	// Purpose: Configure environment for development tools and scripts
	// Scope: Available to all processes in container (shells, VSCode tasks, etc.)
	// Format: Object mapping variable names to values
	// Why useful: Provide consistent configuration without modifying shell profiles
	// Initialize Command: Runs on HOST before container is created
	// Purpose: Extract secrets and OAuth config from host system and prepare for container
	// When executed: Before container build/start, runs on your Mac/host OS
	// Why necessary: Container can't access macOS keychain or host home directory directly
	// How it works: Extracts Claude OAuth token from keychain and OAuth account from ~/.claude.json
	// Why tr -d '\n': security command adds trailing newline which makes token invalid
	// Security: Files are gitignored, only exist locally, deleted on container rebuild
	"initializeCommand": "security find-generic-password -s 'Claude Code' -w 2>/dev/null | tr -d '\\n' > ${localWorkspaceFolder}/.devcontainer/.claude-token && jq '{oauthAccount, userID, hasAvailableSubscription}' ~/.claude.json > ${localWorkspaceFolder}/.devcontainer/.claude-oauth.json 2>/dev/null || echo 'Warning: Claude Code config extraction failed'",

	"remoteEnv": {
		// WORKSPACE_DIR: Path to workspace directory
		// Purpose: Provides consistent way to reference workspace in scripts
		// Why useful: Scripts can use $WORKSPACE_DIR instead of hardcoding /workspace
		// Use case: Build scripts, test scripts that need to know project root
		"WORKSPACE_DIR": "/workspace"
	},

	// Privileged Mode: Grant container extended privileges
	// Purpose: Control whether container has access to all host devices and kernel features
	// Why false: Privileged mode bypasses all security restrictions
	// Security: false is critical - privileged containers can escape to host
	// When true needed: Docker-in-Docker, direct hardware access (not needed here)
	// Impact: With false, container cannot access host devices or modify kernel
	// Best practice: Always false unless absolutely required
	"privileged": false,

	// Init Process: Run init system inside container
	// Purpose: Ensures proper process management (reaping zombie processes)
	// Why true: Prevents zombie processes from accumulating
	// What it does: Runs tini (tiny init) as PID 1
	// Problem solved: Orphaned processes get adopted by init and properly cleaned up
	// Use case: Long-running terminals, background processes
	// Impact: Minimal overhead (~1MB RAM), prevents process table pollution
	// Best practice: Recommended for interactive containers
	"init": true,

	// Shutdown Action: What to do when VSCode disconnects
	// Purpose: Controls container lifecycle when closing VSCode window
	// Options:
	//   - "none": Leave container running (can reconnect later)
	//   - "stopContainer": Stop but don't remove (preserves state)
	//   - "stopCompose": Stop docker-compose setup
	// Why stopContainer: Saves resources but preserves container for quick restart
	// State preserved: Installed packages, shell history, file changes in container
	// State lost: Running processes, network connections
	// Trade-off: Start time vs resource usage
	// Alternative: "none" if you want to keep services running between sessions
	"shutdownAction": "stopContainer"
}

EOF_devcontainer_json
print_success "Created devcontainer.json"

# Extracting Dockerfile
cat > "${DEVCONTAINER_DIR}/Dockerfile" << 'EOF_Dockerfile'
# Directive: Specifies Dockerfile syntax parser version
# Purpose: Enables BuildKit features like improved caching and parallel builds
# Why 1.5: Stable version with security improvements and heredoc support
# Security: Ensures consistent build behavior across different Docker/Podman versions
# syntax=docker/dockerfile:1.5

# Base Image Selection (Microsoft's Official DevContainer Image)
# Purpose: Provides Ubuntu 22.04 LTS with DevContainer optimizations
# Why Microsoft's image:
#   - Pre-configured non-root 'vscode' user (UID 1000)
#   - Common dev tools (git, curl, wget, build-essential) already installed
#   - Optimized for VSCode Remote Container extension
#   - Security hardening and regular updates from Microsoft
# Why Ubuntu 22.04: Long-term support (until 2027), wide package availability
# Alternative: Could use 'ubuntu:22.04' but would need manual vscode user setup
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Environment Variable: Disable interactive prompts
# Purpose: Prevents apt-get from waiting for user input during package installation
# Why necessary: Build process is non-interactive; any prompt would hang the build
# Security: Ensures builds are reproducible and don't require human intervention
# Impact: Applied only during image build, not at runtime
ENV DEBIAN_FRONTEND=noninteractive

# Package Installation Layer (Build Tools and Languages)
# Purpose: Install all necessary development tools in a single layer
# Why single RUN: Each RUN creates a new layer; combining reduces image size
# Why '&&': Ensures all commands succeed; failure at any step aborts the build
# Security: Uses official package repositories, validates with apt-get update
RUN apt-get update && apt-get install -y \
    # Build Essential: GCC, G++, make, libc-dev
    # Purpose: Required for compiling C++ code (this project uses C++/Metal)
    # Why necessary: CMake projects need a C++ compiler
    build-essential \
    # CMake: Cross-platform build system generator
    # Purpose: This project uses CMakeLists.txt for building
    # Why necessary: Explicitly required by project's build instructions
    cmake \
    # Ninja: Fast build system (alternative to make)
    # Purpose: Faster parallel builds than traditional make
    # Why included: CMake can use Ninja as backend for improved build speed
    ninja-build \
    # Pkg-config: Helper tool for compiling applications and libraries
    # Purpose: Manages compile/link flags for libraries
    # Why needed: Many CMake scripts use pkg-config to find dependencies
    pkg-config \
    # Python 3: Interpreted language
    # Purpose: Project has Python tools (tools/check_api_coverage.py, etc.)
    # Why necessary: Project documentation references Python scripts
    python3 \
    # Python Pip: Package installer for Python
    # Purpose: Allows installing Python packages needed by project tools
    # Why necessary: May need to install Python dependencies for scripts
    python3-pip \
    # Python Venv: Virtual environment creator
    # Purpose: Isolates Python dependencies from system packages
    # Why useful: Prevents version conflicts between project and system Python packages
    python3-venv \
    # Curl: Command-line tool for transferring data with URLs
    # Purpose: Used below to download Node.js setup script
    # Why necessary: NodeSource setup script must be fetched from web
    curl \
    # Wget: Network downloader
    # Purpose: Alternative to curl for downloading files
    # Why included: Some scripts may prefer wget; provides flexibility
    wget \
    # Node.js Repository Setup (NodeSource)
    # Purpose: Add NodeSource repository for latest LTS version of Node.js
    # Why necessary: Ubuntu 22.04's default Node.js is outdated for Claude Code
    # -f: Fail silently on HTTP errors
    # -s: Silent mode (no progress bar)
    # -S: Show errors even in silent mode
    # -L: Follow redirects
    # Security: HTTPS prevents man-in-the-middle attacks; script is from trusted source
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    # Node.js and NPM Installation
    # Purpose: JavaScript runtime and package manager
    # Why necessary: Claude Code is distributed as npm package (@anthropic-ai/claude-code)
    # Why LTS: Long-term support version is stable and secure
    && apt-get install -y nodejs \
    # Cleanup: Remove package manager caches and temporary files
    # Purpose: Reduce final image size significantly (can save 100+ MB)
    # Why necessary: These files are only needed during installation, not at runtime
    # apt-get clean: Removes downloaded .deb files from /var/cache/apt/archives
    # rm -rf: Removes apt lists, temp files
    # Security: Reduces attack surface by removing unnecessary files
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# NPM Global Directory Configuration (Non-root User)
# Purpose: Configure npm to install global packages in user's home directory
# Why necessary: Default npm global path (/usr/local) requires root privileges
# Why 'su vscode': Runs commands as vscode user (not root)
# Security: Prevents need for sudo when installing npm packages
# mkdir -p ~/.npm-global: Creates directory for global npm packages
# npm config set prefix: Tells npm to install global packages to ~/.npm-global
RUN su vscode -c "mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global"

# PATH Environment Variable: Add NPM global bin directory
# Purpose: Makes globally installed npm packages executable from command line
# Why necessary: Without this, 'claude-code' command wouldn't be found after npm install -g
# ${PATH}: Preserves existing PATH entries (system binaries, etc.)
# Security: Only adds vscode user's directory, not system-wide writable paths
ENV PATH="/home/vscode/.npm-global/bin:${PATH}"

# Git Safe Directory Configuration
# Purpose: Mark /workspace as safe to prevent "dubious ownership" errors
# Why necessary: Mounted volumes may have different UID/GID than container user
# When it occurs: Git sees /workspace owned by different user and refuses operations
# --system: Applies to all users (survives user switching)
# Security: Only marks specific directory, not entire filesystem
# Impact: Allows git commands to work on mounted workspace without warnings
RUN git config --system --add safe.directory /workspace

# VS Code Server Directory
# Purpose: Pre-create directory for VS Code Server installation
# Why necessary: VS Code tries to install server at /vscode/vscode-server
# mkdir -p: Creates /vscode directory (and parents if needed)
# chown: Changes ownership to vscode user and group
# Security: vscode user can write here without sudo, no volume mount needed
# Note: With --userns=keep-id, this directory needs to be created/fixed at runtime
# Trade-off: VS Code Server reinstalled on each container rebuild (acceptable)
RUN mkdir -p /vscode && chmod 777 /vscode

# Working Directory: Set default directory for RUN/CMD/ENTRYPOINT
# Purpose: All commands will execute from /workspace by default
# Why /workspace: Convention for DevContainers; matches mount point in devcontainer.json
# Impact: When opening terminal in container, starts in /workspace
# Benefit: Immediate access to project files without 'cd' command
WORKDIR /workspace

# Default Command: Specify what runs when container starts
# Purpose: Launch interactive bash shell when no other command is provided
# Why bash: Provides full shell environment for development work
# Format: JSON array is exec form (preferred over shell form)
# When used: Only if devcontainer.json doesn't override with different command
# Security: Bash is standard, well-audited shell; no automatic script execution
CMD ["/bin/bash"]

EOF_Dockerfile
print_success "Created Dockerfile"

# Extracting generate-claude-config.sh
cat > "${DEVCONTAINER_DIR}/generate-claude-config.sh" << 'EOF_generate_claude_config_sh'
#!/bin/bash
# Generate .claude.json for container from host OAuth config + keychain token

OAUTH_FILE=/workspace/.devcontainer/.claude-oauth.json
TOKEN_FILE=/workspace/.devcontainer/.claude-token
OUTPUT=~/.claude.json

# Extract OAuth account from exported file
OAUTH_ACCOUNT=$(jq '.oauthAccount' "$OAUTH_FILE" 2>/dev/null)
USER_ID=$(jq -r '.userID // "generated-user-id"' "$OAUTH_FILE" 2>/dev/null)
TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
# Get last 20 chars of token (Claude Code uses this as the key suffix)
TOKEN_SUFFIX="${TOKEN: -20}"

# Create config with OAuth
jq -n \
  --argjson oauth "$OAUTH_ACCOUNT" \
  --arg userId "$USER_ID" \
  --arg tokenSuffix "$TOKEN_SUFFIX" \
  '{
    numStartups: 1,
    installMethod: "devcontainer",
    autoUpdates: true,
    cachedStatsigGates: {
      tengu_disable_bypass_permissions_mode: false,
      tengu_tool_pear: false
    },
    sonnet45MigrationComplete: true,
    shiftEnterKeyBindingInstalled: true,
    hasCompletedOnboarding: true,
    hasOpusPlanDefault: false,
    hasAvailableSubscription: false,
    oauthAccount: $oauth,
    userID: $userId,
    customApiKeyResponses: {
      approved: [$tokenSuffix],
      rejected: []
    },
    projects: {
      "/workspace": {
        allowedTools: [],
        history: [],
        mcpContextUris: [],
        mcpServers: {},
        enabledMcpjsonServers: [],
        disabledMcpjsonServers: [],
        hasTrustDialogAccepted: true,
        ignorePatterns: []
      }
    }
  }' > "$OUTPUT"

chmod 600 "$OUTPUT"
echo "Generated $OUTPUT with OAuth config"

EOF_generate_claude_config_sh
print_success "Created generate-claude-config.sh"

# Extracting claude.json.template
cat > "${DEVCONTAINER_DIR}/claude.json.template" << 'EOF_claude_json_template'
{
  "numStartups": 1,
  "installMethod": "devcontainer",
  "autoUpdates": true,
  "cachedStatsigGates": {
    "tengu_disable_bypass_permissions_mode": false,
    "tengu_tool_pear": false
  },
  "sonnet45MigrationComplete": true,
  "shiftEnterKeyBindingInstalled": true,
  "hasCompletedOnboarding": true,
  "hasOpusPlanDefault": false,
  "projects": {
    "/workspace": {
      "allowedTools": [],
      "history": [],
      "mcpContextUris": [],
      "mcpServers": {},
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": [],
      "hasTrustDialogAccepted": true,
      "ignorePatterns": []
    }
  }
}
EOF_claude_json_template
print_success "Created claude.json.template"

# Extracting CLAUDE.md
cat > "${DEVCONTAINER_DIR}/CLAUDE.md" << 'EOF_CLAUDE_md'
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

EOF_CLAUDE_md
print_success "Created CLAUDE.md"

# Make shell scripts executable
chmod +x "${DEVCONTAINER_DIR}/generate-claude-config.sh"
print_success "Set executable permissions on generate-claude-config.sh"

# Add .devcontainer/.claude-token and .devcontainer/.claude-oauth.json to .gitignore if not already present
GITIGNORE="${REPO_ROOT}/.gitignore"
if ! grep -q ".devcontainer/.claude-token" "${GITIGNORE}" 2>/dev/null; then
    echo "" >> "${GITIGNORE}"
    echo "# Claude Code authentication (auto-generated, keep secret)" >> "${GITIGNORE}"
    echo ".devcontainer/.claude-token" >> "${GITIGNORE}"
    echo ".devcontainer/.claude-oauth.json" >> "${GITIGNORE}"
    print_success "Added authentication files to .gitignore"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Files created:"
echo ""
echo "  ✓ .devcontainer/devcontainer.json"
echo "  ✓ .devcontainer/Dockerfile"
echo "  ✓ .devcontainer/generate-claude-config.sh"
echo "  ✓ .devcontainer/claude.json.template"
echo "  ✓ .devcontainer/CLAUDE.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Review the configuration:"
echo "   ${YELLOW}cat .devcontainer/CLAUDE.md${NC}"
echo ""
echo "2. Configure VSCode to use Podman (if not already done):"
echo "   Add to .vscode/settings.json or user settings:"
echo "   {"
echo '     "dev.containers.dockerPath": "podman"'
echo "   }"
echo ""
echo "3. Open this repository in VSCode:"
echo "   ${YELLOW}code ${REPO_ROOT}${NC}"
echo ""
echo "4. Reopen in DevContainer:"
echo "   Press ${YELLOW}F1${NC} (or ${YELLOW}Cmd+Shift+P${NC} / ${YELLOW}Ctrl+Shift+P${NC})"
echo "   Type: ${YELLOW}Dev Containers: Reopen in Container${NC}"
echo "   Press Enter"
echo ""
echo "5. Wait for container to build (first time takes ~5 minutes)"
echo ""
echo "The container will automatically:"
echo "  • Install Claude Code"
echo "  • Configure authentication (macOS keychain)"
echo "  • Set up development tools"
echo ""
print_info "For troubleshooting, see: .devcontainer/CLAUDE.md"
echo ""

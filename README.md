# Secure DevContainer Configuration for Claude Code

This repository contains a secure, Podman-compatible DevContainer configuration with Claude Code integration. The configuration follows Microsoft's recommended best practices and implements defense-in-depth security principles.

## Quick Install

To add this DevContainer configuration to any Git repository, run:

```bash
curl -fsSL https://raw.githubusercontent.com/lastrk/claude-container/main/install.sh | bash
```

Or for more control (recommended):

```bash
# Download the installer
curl -fsSL https://raw.githubusercontent.com/lastrk/claude-container/main/install.sh -o install.sh

# Review it
cat install.sh

# Run it
bash install.sh
```

The installer is self-contained and includes all configuration files embedded within it.

The installer will:
- Check if you're in a Git repository
- Create `.devcontainer/` directory (errors if it exists)
- Download all configuration files
- Add authentication files to `.gitignore`
- Display next steps for opening in VSCode

## Prerequisites

### Required Software

1. **Podman** (rootless container runtime)
   ```bash
   # macOS
   brew install podman

   # Ubuntu/Debian
   sudo apt-get install podman

   # Fedora/RHEL
   sudo dnf install podman
   ```

2. **VSCode** with DevContainer extension
   ```bash
   # Install VSCode, then add extension:
   code --install-extension ms-vscode-remote.remote-containers
   ```

3. **Podman Machine** (macOS only)
   ```bash
   # Initialize Podman machine with adequate resources
   podman machine init

   # IMPORTANT: Configure VM resources BEFORE first use
   # The container needs at least 8GB RAM and 8 CPUs
   # Allocate more than container needs (VM overhead)
   podman machine stop
   podman machine set --cpus 10 --memory 16384  # 10 CPUs, 16GB RAM
   podman machine start

   # Verify configuration
   podman machine list
   # Should show: CPUS: 10, MEMORY: 16GiB
   ```

   **Why this is required:** On macOS, Podman runs in a VM. The VM must have MORE resources than the container needs. If the container is configured for 8 CPUs/8GB RAM, the VM needs ~10 CPUs/16GB RAM to have headroom.

### Configure VSCode to Use Podman

Add to your VSCode settings (`.vscode/settings.json` or user settings):

```json
{
  "dev.containers.dockerPath": "podman",
  "dev.containers.dockerComposePath": "podman-compose"
}
```

Alternatively, set environment variable:
```bash
export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"
```

## Usage

### Opening the DevContainer

1. **Open project in VSCode**
   ```bash
   code /path/to/your-project
   ```

2. **Reopen in Container**
   - Press `F1` or `Cmd+Shift+P` (macOS) / `Ctrl+Shift+P` (Linux/Windows)
   - Type: "Dev Containers: Reopen in Container"
   - Select it and wait for container to build and start

3. **First-time setup** (inside container)
   ```bash
   # Claude Code is automatically installed via postCreateCommand
   # Authentication token is extracted from macOS keychain and injected automatically
   claude --version

   # Verify git works
   git status
   ```

4. **Run Claude Code in unsupervised mode** (inside container)
   ```bash
   # For fully autonomous operation without permission prompts
   claude --dangerously-skip-permissions
   ```

   **Important**: This flag bypasses all permission prompts and grants unrestricted access. Only use in sandboxed environments like this container. The container security (dropped capabilities, network isolation, resource limits) provides the safety boundary.

### Authentication

Claude Code authentication is handled automatically:

1. **On container start**: `initializeCommand` extracts your API/OAuth token from macOS keychain
2. **Token file**: Token is written to `.devcontainer/.claude-token` (gitignored)
3. **OAuth extraction**: `initializeCommand` also extracts OAuth account info from `~/.claude.json`
4. **Configuration generation**: `postCreateCommand` runs `generate-claude-config.sh` which:
   - Creates `~/.claude/settings.json` with `ANTHROPIC_API_KEY` environment variable
   - Generates `~/.claude.json` dynamically with OAuth account info and API key
5. **No manual login needed**: Claude Code works immediately without authentication prompts

**How it works**:
1. The `generate-claude-config.sh` script uses `jq` to build the configuration JSON dynamically
2. It merges OAuth account data with the API key token
3. The resulting `~/.claude.json` and `~/.claude/settings.json` files contain your credentials securely

**Security notes**:
- Token is extracted from keychain on-demand, not stored in git
- `.claude-token` file is gitignored and dockerignored
- Token only exists locally on your machine
- Fresh token extracted on each container rebuild
- Claude Code refreshes credentials automatically (default: every 5 minutes)

**If authentication fails**: You can manually authenticate inside the container:
```bash
# Verify token files exist
ls -la /workspace/.devcontainer/.claude-*

# Verify .claude.json was created and contains API key
cat ~/.claude.json
cat ~/.claude/settings.json

# Manually regenerate configuration if needed
/workspace/.devcontainer/generate-claude-config.sh

# Or authenticate interactively
claude /login
```

## Container Architecture

### Base Image

Uses Microsoft's official DevContainer base image:
```
mcr.microsoft.com/devcontainers/base:ubuntu-22.04
```

**Why this image?**
- Officially maintained by Microsoft
- Optimized for DevContainer workflows
- Includes common development tools (git, curl, wget, build-essential)
- Ubuntu 22.04 LTS provides long-term support
- Non-root `vscode` user pre-configured

### Installed Tools

| Tool | Purpose | Installed Via |
|------|---------|---------------|
| git | Version control | Base image |
| build-essential | Compilation tools | apt |
| cmake, ninja | Build system | apt |
| python3, pip | Python tooling | apt |
| node.js, npm | Claude Code, npx | NodeSource |
| pkgx | User-space package manager | pkgx.sh installer |

### Mount Points

| Host Path | Container Path | Access |
|-----------|----------------|--------|
| `${workspaceFolder}` | `/workspace` | Read-Write |

## Network Configuration

### What's Accessible

✅ **Allowed:**
- Package repositories (apt, npm, pip)
- Git remote repositories (GitHub, GitLab, etc.)
- Public internet via HTTP/HTTPS
- DNS resolution

❌ **Blocked:**
- Host machine services (e.g., `localhost:3000` on host)
- Host filesystem outside mounted workspace
- Other containers on host (unless explicitly linked)
- Privileged operations without sudo

### Network Mode: slirp4netns

The container uses `slirp4netns` for user-mode networking:
- No elevated privileges required
- Provides NAT-based internet access
- Isolates container from host network stack
- Compatible with rootless Podman

## Troubleshooting

### Container Won't Start

**Problem**: "Error: container failed to start"

**Solution**:
```bash
# Check Podman is running (macOS)
podman machine list
podman machine start

# Rebuild container
# In VSCode: F1 -> "Dev Containers: Rebuild Container"
```

### Permission Denied Errors

**Problem**: Cannot write to workspace

**Solution**:
```bash
# On host, check ownership
ls -la /path/to/your-project

# Fix if needed (macOS/Linux)
chown -R $(whoami) /path/to/your-project
```

### Git "Dubious Ownership" Error

**Problem**: `fatal: detected dubious ownership in repository`

**Solution**: Already handled by `git config --system --add safe.directory /workspace` in Dockerfile. If still occurs:
```bash
# Inside container
git config --global --add safe.directory /workspace
```

### NPM Global Install Fails

**Problem**: Permission denied when installing global npm packages

**Solution**: Already configured to use `~/.npm-global`. If issues persist:
```bash
# Inside container
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
export PATH=~/.npm-global/bin:$PATH
```

### Container Has Limited Resources (macOS)

**Problem**: Container shows only 4 CPUs, 2GB RAM despite devcontainer.json configuration

**Cause**: On macOS, Podman runs in a VM. The VM itself has resource limits that override container limits.

**Solution**:
```bash
# 1. Stop the Podman machine
podman machine stop

# 2. Check current VM resources
podman machine list

# 3. Set adequate resources (more than container needs)
podman machine set --cpus 10 --memory 16384

# 4. Start machine
podman machine start

# 5. Verify
podman machine list
# Should show: CPUS: 10, MEMORY: 16GiB

# 6. Rebuild DevContainer in VSCode
# F1 → "Dev Containers: Rebuild Container"
```

**Rule of thumb**: Podman VM needs ~20-25% more resources than container configuration
- Container wants 8 CPUs → VM needs 10 CPUs
- Container wants 8GB RAM → VM needs 16GB RAM

### Cannot Access Host Services

**Problem**: Cannot connect to database/service running on host

**This is by design for security.** If you need to access host services:

**Option 1** (Recommended): Run service in separate container and link
```bash
# Use docker-compose or podman-compose
# Add service to docker-compose.yml
```

**Option 2** (Less secure): Modify network mode
```jsonc
// In devcontainer.json, change runArgs:
"--network=host"  // ⚠️ This removes network isolation!
```

### Slow File Operations

**Problem**: File operations feel sluggish

**Solution**: Already using `consistency=cached` for mounts. For better performance:
- Ensure Podman machine has adequate resources (macOS):
  ```bash
  podman machine stop
  podman machine set --cpus 4 --memory 8192
  podman machine start
  ```

### Container Performance Issues

**Problem**: Container is slow or unresponsive

**Possible causes and solutions:**

1. **Insufficient resources allocated**
   - Check container resource limits in `devcontainer.json` (`--cpus` and `--memory`)
   - Increase limits if your host has available resources
   - See "Adjusting Resource Limits" section below

2. **Host resource exhaustion**
   - Check host CPU/memory usage with `top` or Activity Monitor
   - Close unnecessary applications
   - Reduce container resource limits if host is constrained

3. **Memory limit too low**
   - Claude Code needs minimum 2GB RAM
   - If seeing OOM (Out of Memory) errors, increase `--memory` value
   - Check container logs: `podman logs <container-id>`

## Customization

### Adding VSCode Extensions

Edit `devcontainer.json`:
```jsonc
"customizations": {
  "vscode": {
    "extensions": [
      "ms-vscode.cpptools",
      "your.extension.id"
    ]
  }
}
```

### Adding System Packages

Edit `Dockerfile`:
```dockerfile
RUN apt-get update && apt-get install -y \
    your-package-here \
    && apt-get clean
```

**Pre-configured Development Environments:**

The Dockerfile includes commented-out blocks for common development environments. To enable any of them, uncomment the relevant block in `.devcontainer/Dockerfile` and rebuild the container:

- **Java**: OpenJDK 11, 17, 21 (with Maven and Gradle)
  - Multi-architecture support: Works on both Intel (AMD64) and Apple Silicon (ARM64)
  - Automatic architecture detection using `$(dpkg --print-architecture)`
  - Three options provided for setting default Java version
  - Includes ca-certificates-java fix for reliable certificate store initialization
- **Rust**: rustup with cargo and multi-version support (stable/beta/nightly)
- **C++**: LLVM 18 with Clang, LLDB, LLD, and analysis tools
- **Python**: Enhanced setup with conda, virtualenv, and development tools
- **Clojure**: Official Clojure CLI tools (clj and clojure commands with rlwrap)

See the Dockerfile comments for detailed instructions and configuration options.

### Installing Additional Tools

#### Option 1: User-Space Packages (No sudo required)

The container includes **pkgx**, a user-space package manager that allows you to install tools without sudo:

```bash
# Inside the container

# Install packages persistently
pkgx install ripgrep fd-find jq

# Use packages temporarily (ephemeral, doesn't persist)
pkgx +ripgrep rg "TODO" .
pkgx +python@3.11 python --version

# Search for available packages
pkgx search postgres

# List installed packages
pkgx list

# Uninstall packages
pkgx uninstall ripgrep
```

**Common use cases:**

```bash
# Java development environment
pkgx install openjdk.org@17 maven.apache.org gradle.org

# Multiple Java versions for testing
pkgx +openjdk.org@11 java -version
pkgx +openjdk.org@17 java -version
pkgx +openjdk.org@21 java -version

# Python environments
pkgx install python@3.11 python@3.12

# CLI tools
pkgx install ripgrep fd-find bat exa jq yq
```

**Advantages of pkgx:**
- ✅ No sudo required (pure user-space)
- ✅ Fast installation (~2-5 seconds)
- ✅ 10,000+ packages available
- ✅ Multiple versions of same tool
- ✅ Ephemeral mode for testing tools without installing
- ✅ No container rebuild needed

**Package catalog:** Browse available packages at [pkgx.dev/pkgs](https://pkgx.dev/pkgs/)

#### Option 2: System Packages (Requires sudo)

For packages not available in pkgx or when you need system-wide installation:

```bash
# Inside the container
sudo apt-get update
sudo apt-get install <package-name>

# Or using pip
pip3 install <package-name>

# Or using npm
npm install -g <package-name>
```

### Running Web Services

The container can bind to privileged ports (80, 443) for development:

```bash
# Run HTTP server on port 80 (standard HTTP port)
python3 -m http.server 80

# Or install and run nginx on port 80
sudo apt-get install nginx
sudo nginx

# Node.js server on port 443
node server.js  # Can bind to 443 without root
```

### Network Debugging

Network diagnostic tools are available:

```bash
# Test connectivity
ping google.com

# Trace route to destination
traceroute example.com

# Install additional tools
sudo apt-get install curl wget netcat-openbsd
```

### Committing from Inside Container

Git is pre-configured and has access to the workspace:

```bash
# Inside the container
git add .
git commit -m "Your commit message"
git push
```

**Note**: Git credentials may need to be configured. Use SSH keys or GitHub CLI for authentication.

### Adjusting Resource Limits

The container has default resource limits configured for generous development workloads:
- **CPU**: 8 CPUs (~80% of 10-core system)
- **Memory**: 8GB RAM minimum
- **Swap**: 48GB maximum (not preallocated, uses disk only when RAM full)
- **Total Virtual Memory**: 56GB (8GB RAM + 48GB swap)

**These defaults assume:**
- Host with 10+ CPU cores (adjust proportionally for your system)
- Host with 16GB+ RAM
- Available disk space for swap (only used when needed)

To adjust these limits, edit `devcontainer.json`:

```jsonc
"runArgs": [
  // ... other args ...
  "--cpus=12",         // For 16-core system (80% = 12-13 cores)
  "--memory=16g",      // Double RAM for large projects
  "--memory-swap=64g"  // 16GB RAM + 48GB swap
]
```

**Quick calculation guide:**
```bash
# Find your host CPU cores
sysctl -n hw.ncpu  # macOS
nproc              # Linux
# Multiply by 0.8 for container allocation

# Find your host RAM
sysctl hw.memsize | awk '{print $2/1024/1024/1024 " GB"}'  # macOS
free -h            # Linux
# Allocate at least 8GB, more for heavy builds
```

**Swap configuration options:**
- `--memory-swap=8g` (same as memory): Disables swap entirely, RAM only
- `--memory-swap=16g` (2x memory): Moderate 8GB swap buffer
- `--memory-swap=56g` (default): Large 48GB swap for intensive builds
- `--memory-swap=-1`: Unlimited swap (not recommended, can hang system)

**Common configurations:**

| Use Case | CPUs | Memory | Swap Total | Swap Space | Notes |
|----------|------|--------|------------|------------|-------|
| Constrained host (4 cores, 8GB RAM) | 3 | 4g | 4g | 0GB | No swap, minimal but functional |
| Small host (8 cores, 16GB RAM) | 6 | 8g | 16g | 8GB | Moderate swap buffer |
| Standard (10 cores, 32GB RAM) | 8 | 8g | 56g | 48GB | Default, large swap for builds |
| Performance (12 cores, 32GB RAM) | 10 | 16g | 16g | 0GB | No swap, all RAM, fastest |
| Heavy builds (16 cores, 64GB RAM) | 12 | 32g | 80g | 48GB | Large RAM + large swap |
| Extreme (32 cores, 128GB RAM) | 25 | 64g | 112g | 48GB | Maximum resources |

**Finding your host's resources:**
```bash
# CPU cores
nproc  # Linux
sysctl -n hw.ncpu  # macOS

# Total memory
free -h  # Linux
sysctl hw.memsize  # macOS
```

**Recommendations:**
- Allocate no more than 75% of host CPU cores
- Allocate no more than 75% of host RAM
- Leave resources for host OS and other applications
- Claude Code alone needs ~2GB RAM minimum
- Increase limits for memory-intensive builds or large codebases

### Relaxing Security (Not Recommended)

**Current configuration** provides 6 explicit capabilities (SETUID, SETGID, AUDIT_WRITE, CHOWN, NET_BIND_SERVICE, NET_RAW), plus implicit capabilities granted by the user namespace. This is sufficient for most development workflows.

If you need to add additional capabilities:
```jsonc
// devcontainer.json
"runArgs": [
  "--cap-add=CAP_SYS_PTRACE"  // Example: for debugging with ptrace
]
```

**Common capability requests**:
- `CAP_SYS_PTRACE`: Debugging other processes (gdb, strace)
- `CAP_SYS_ADMIN`: Mount filesystems (usually not needed in dev containers)
- `CAP_NET_ADMIN`: Modify network configuration (iptables, routing)

**Warning**:
- Only add capabilities you fully understand and have verified you need
- Each capability increases attack surface—even within namespace isolation
- `CAP_SYS_ADMIN` is particularly dangerous and should be avoided if possible
- Document why each additional capability is required
- Consider using pkgx or other userspace alternatives instead of escalating privileges

## Security Model

### Overview: Defense in Depth for Development Containers

This configuration implements a **multi-layered security model** that balances developer productivity with strong isolation:

- **Primary boundary**: User namespace isolation ensures container processes cannot escalate to host root
- **Network isolation**: slirp4netns prevents access to host services while allowing internet access
- **Capability minimization**: Drops all capabilities, only adds 6 essential ones for development workflows
- **Resource limits**: Prevents resource exhaustion attacks (CPU, memory, swap constrained)

**Key security property**: Even if an attacker gains root inside the container, they remain confined to the container namespace and cannot:
- Access or modify host files outside `/workspace`
- Become root on the host system
- Access host network services (databases, APIs, etc.)
- Affect other containers or system processes

**Developer experience**: Within these security boundaries, you have full control:
- Install packages with `sudo apt-get install`
- Bind to privileged ports (80, 443) for web development
- Use standard package managers (apt, npm, pip, cargo, etc.)
- Debug network issues with `ping` and `traceroute`

### Access Controls

| Resource | Access Level | Explanation |
|----------|--------------|-------------|
| Project workspace (`/workspace`) | **Read-Write** | Full access to project files for development (includes `.devcontainer/`) |
| Host network | **Blocked** | Container cannot access host services |
| Internet (HTTP/HTTPS) | **Allowed** | Required for package installation |
| Root privileges (inside container) | **Namespace-root only** | Sudo available for package installation, but isolated to container namespace—cannot affect host system |
| Root privileges (host system) | **Blocked** | User namespace isolation prevents any escalation to host root |

### Security Features

1. **User Namespace Isolation**
   - Container runs in isolated user namespace with rootless Podman (`--userns=keep-id`)
   - Inside container: `vscode` user can use `sudo` to become namespace-root for package installation
   - On host: Container processes map to your regular user UID—cannot become real root or access other users' files
   - **Security boundary**: Sudo gives "root" inside the namespace ONLY; cannot affect host system, modify host files, or escalate to host root
   - **Developer benefit**: Can run `sudo apt-get install`, bind to privileged ports (80, 443), use standard package managers
   - **Attack mitigation**: Even if attacker gains root inside container, they remain confined to the namespace and cannot escape to host

2. **Minimal Capabilities**
   - Drops all Linux capabilities by default (`--cap-drop=ALL`)
   - Only grants 6 essential capabilities for development:
     - **SETUID**: Required for sudo to change UID within namespace—enables `sudo apt-get install`
     - **SETGID**: Required for sudo to change GID within namespace—complements SETUID
     - **AUDIT_WRITE**: Allows authentication systems (PAM, sudo) to write audit logs
     - **CHOWN**: Allows package managers (apt, npm, pip) to change file ownership during installation
     - **NET_BIND_SERVICE**: Allows binding to privileged ports (80, 443) for web servers without root
     - **NET_RAW**: Enables ICMP for network debugging tools (`ping`, `traceroute`)
   - **Security model**: All capabilities scoped to container namespace—cannot affect host system
   - **Trade-off**: Balances developer convenience (package installation, port binding) with security (no host access)
   - Reduces attack surface by ~95% compared to default container capabilities

3. **Network Isolation**
   - Uses `slirp4netns` for user-mode networking
   - Container cannot access host services (no `127.0.0.1` access to host)
   - Internet access via HTTP/HTTPS for package downloads
   - Ideal for development while maintaining security boundaries

4. **Filesystem Isolation**
   - Project workspace has full read-write access
   - Git repository accessible for commits
   - Container isolated from host filesystem outside workspace

5. **Additional Hardening**
   - **`no-new-privileges`** (`--security-opt=no-new-privileges`): Prevents privilege escalation beyond current namespace via setuid binaries or file capabilities—blocks exploiting setuid-root binaries even if found
   - **Capability-based sudo**: Sudo relies on CAP_SETUID capability (allowed), not setuid binary bit (blocked by no-new-privileges)
   - **Init process (tini)**: Proper zombie process reaping prevents resource exhaustion
   - **Rootless Podman**: No privileged daemon running as host root—entire container runtime runs as your user
   - **Resource limits**: CPU (8 cores), memory (8GB RAM + 48GB swap) prevent denial-of-service within container

## Architecture Decisions

### Why Podman Instead of Docker?

1. **Rootless by default**: More secure architecture
2. **No daemon**: Reduces attack surface
3. **OCI-compatible**: Works with standard container images
4. **Drop-in replacement**: Compatible with Docker CLI

### Why slirp4netns Network Mode?

1. **User-mode networking**: No root privileges required
2. **Security**: Isolates container from host network
3. **Compatibility**: Works with rootless Podman
4. **Internet access**: Allows HTTP/HTTPS while blocking host

### Why Not Read-Only DevContainer Config?

The `.devcontainer/` directory is accessible at `/workspace/.devcontainer` with read-write permissions. While making it read-only would provide defense-in-depth, the practical benefits are minimal:
- Config files (Dockerfile, devcontainer.json) are only used at build/startup time
- Malicious code with write access already has access to all source code
- Container already has strong security boundaries (capabilities, network isolation)
- Simplicity and ease of maintenance outweigh marginal security benefit in dev environments

## Performance Considerations

### Build Performance

- Image layers are cached between builds
- `.dockerignore` excludes build artifacts and dependencies
- Using Microsoft's base image reduces build time

### Runtime Performance

- Rootless Podman has minimal overhead vs root mode
- slirp4netns adds ~5-10% latency to network calls
- File I/O performance is near-native with volume mounts

## Security Checklist

Before using this configuration in production or with sensitive data:

- [ ] **Review and understand the security model**: User namespace isolation, capability restrictions, network isolation
- [ ] **Verify rootless Podman**: Confirm Podman runs as your user, not root (`podman info | grep rootless`)
- [ ] **Understand sudo limitations**: Sudo gives namespace-root only—cannot affect host system
- [ ] **Confirm capability set**: Only 6 explicit capabilities granted (SETUID, SETGID, AUDIT_WRITE, CHOWN, NET_BIND_SERVICE, NET_RAW), plus user namespace implicit capabilities
- [ ] **Test network isolation**: Verify container cannot reach host services (`curl http://host.docker.internal:3000` should fail)
- [ ] **Workspace security**: DevContainer config (`.devcontainer/`) is part of workspace with read-write access—treat as untrusted if repo is untrusted
- [ ] **Audit extensions and packages**: Review all VSCode extensions and additional packages for security implications
- [ ] **Keep base image updated**: Regularly rebuild with latest Microsoft DevContainer base image for security patches
- [ ] **Resource limits**: Verify CPU and memory limits are appropriate for your host system
- [ ] **Authentication secrets**: Ensure `.claude-token` and `.claude-oauth.json` are gitignored and never committed

## References

- [DevContainer Specification](https://containers.dev/)
- [Microsoft DevContainer Images](https://github.com/devcontainers/images)
- [Podman Documentation](https://docs.podman.io/)
- [VSCode DevContainers](https://code.visualstudio.com/docs/devcontainers/containers)
- [slirp4netns Documentation](https://github.com/rootless-containers/slirp4netns)

## License

MIT License - Free to use and modify for your own projects.

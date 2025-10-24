#!/usr/bin/env bash
set -e

# Build Script for Claude Container DevContainer Configuration
# This script generates a self-contained install.sh with all configuration files embedded

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

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Get script directory (where this build.sh is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/install.sh"

# Source files to embed
FILES=(
    "devcontainer.json"
    "Dockerfile"
    "generate-claude-config.sh"
    "CLAUDE.md"
)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building Self-Contained install.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get git commit hash and date
if git rev-parse --git-dir > /dev/null 2>&1; then
    COMMIT_HASH=$(git rev-parse --short HEAD)
    COMMIT_DATE=$(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M:%S')
    print_info "Git commit: ${COMMIT_HASH} (${COMMIT_DATE})"
else
    COMMIT_HASH="unknown"
    COMMIT_DATE="unknown"
    print_error "Not a git repository - version info will be generic"
fi

# Verify all source files exist
print_info "Checking source files..."
missing_files=0
for file in "${FILES[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${file}" ]; then
        print_error "Missing: ${file}"
        missing_files=1
    else
        print_success "Found: ${file}"
    fi
done

if [ $missing_files -eq 1 ]; then
    print_error "Some source files are missing. Cannot build installer."
    exit 1
fi

echo ""
print_info "Generating ${OUTPUT_FILE}..."
echo ""

# Start writing the installer script
cat > "${OUTPUT_FILE}" << 'INSTALLER_HEADER'
#!/usr/bin/env bash
set -e

# Secure DevContainer Configuration Installer
# Self-contained installer with all configuration files embedded
INSTALLER_HEADER

# Add version info
cat >> "${OUTPUT_FILE}" << VERSION_INFO
# Generated from commit: ${COMMIT_HASH}
# Build date: ${COMMIT_DATE}

VERSION_INFO

# Add the main installer logic
cat >> "${OUTPUT_FILE}" << 'INSTALLER_MAIN'

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

# Parse command line arguments
FORCE_UPGRADE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-upgrade)
            FORCE_UPGRADE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force-upgrade]"
            echo ""
            echo "Options:"
            echo "  --force-upgrade    Overwrite existing .devcontainer (only if under git version control)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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
if [ "$FORCE_UPGRADE" = true ]; then
    print_warning "Force upgrade mode enabled"
fi
echo ""

# Check if .devcontainer already exists
if [ -d "${DEVCONTAINER_DIR}" ]; then
    if [ "$FORCE_UPGRADE" = false ]; then
        print_error ".devcontainer directory already exists!"
        print_error "Please remove or rename the existing .devcontainer directory first."
        echo ""
        echo "To remove: rm -rf ${DEVCONTAINER_DIR}"
        echo "To backup: mv ${DEVCONTAINER_DIR} ${DEVCONTAINER_DIR}.backup"
        echo ""
        echo "Or use --force-upgrade to overwrite (requires .devcontainer to be under git version control)"
        exit 1
    fi

    # Force upgrade mode - check if .devcontainer is under version control
    print_warning ".devcontainer directory exists, checking git status..."

    # Check if any files in .devcontainer are tracked by git
    cd "${REPO_ROOT}"
    TRACKED_FILES=$(git ls-files .devcontainer/ 2>/dev/null | wc -l)

    if [ "$TRACKED_FILES" -eq 0 ]; then
        print_error ".devcontainer directory is NOT under git version control!"
        echo ""
        print_error "Cannot use --force-upgrade on unversioned .devcontainer directory."
        echo ""
        echo "This is a safety measure to prevent accidental data loss."
        echo ""
        echo "Please choose one of these options:"
        echo ""
        echo "  1. Put .devcontainer under version control:"
        echo "     ${YELLOW}git add .devcontainer/${NC}"
        echo "     ${YELLOW}git commit -m \"Add current devcontainer configuration\"${NC}"
        echo "     Then re-run: ${YELLOW}$0 --force-upgrade${NC}"
        echo ""
        echo "  2. Manually backup the directory:"
        echo "     ${YELLOW}cp -r ${DEVCONTAINER_DIR} ${DEVCONTAINER_DIR}.backup${NC}"
        echo "     ${YELLOW}rm -rf ${DEVCONTAINER_DIR}${NC}"
        echo "     Then re-run: ${YELLOW}$0${NC}"
        echo ""
        echo "  3. Delete the directory (if you're sure):"
        echo "     ${YELLOW}rm -rf ${DEVCONTAINER_DIR}${NC}"
        echo "     Then re-run: ${YELLOW}$0${NC}"
        echo ""
        exit 1
    fi

    print_success ".devcontainer is under version control (${TRACKED_FILES} tracked files)"
    print_warning "Proceeding with upgrade - existing files will be overwritten"
    echo ""
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

INSTALLER_MAIN

# Now embed each file as a heredoc
for file in "${FILES[@]}"; do
    echo "" >> "${OUTPUT_FILE}"
    echo "# Extracting ${file}" >> "${OUTPUT_FILE}"
    echo "cat > \"\${DEVCONTAINER_DIR}/${file}\" << 'EOF_${file//[.-]/_}'" >> "${OUTPUT_FILE}"
    cat "${SCRIPT_DIR}/${file}" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"
    echo "EOF_${file//[.-]/_}" >> "${OUTPUT_FILE}"
    echo "print_success \"Created ${file}\"" >> "${OUTPUT_FILE}"

    print_success "Embedded ${file}"
done

# Add the footer with post-installation steps
cat >> "${OUTPUT_FILE}" << 'INSTALLER_FOOTER'

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
echo "  ✓ .devcontainer/CLAUDE.md"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Review the configuration:"
echo -e "   ${YELLOW}cat .devcontainer/CLAUDE.md${NC}"
echo ""
echo "2. Configure VSCode to use Podman (if not already done):"
echo "   Add to .vscode/settings.json or user settings:"
echo "   {"
echo '     "dev.containers.dockerPath": "podman"'
echo "   }"
echo ""
echo "3. Open this repository in VSCode:"
echo -e "   ${YELLOW}code ${REPO_ROOT}${NC}"
echo ""
echo "4. Reopen in DevContainer:"
echo -e "   Press ${YELLOW}F1${NC} (or ${YELLOW}Cmd+Shift+P${NC} / ${YELLOW}Ctrl+Shift+P${NC})"
echo -e "   Type: ${YELLOW}Dev Containers: Reopen in Container${NC}"
echo "   Press Enter"
echo ""
echo "5. Wait for container to build (first time takes ~5 minutes)"
echo ""
echo "The container will automatically:"
echo "  • Install Claude Code"
echo "  • Configure authentication (macOS keychain)"
echo "  • Set up development tools"
echo ""
echo "6. Run Claude Code in unsupervised mode (inside container):"
echo -e "   ${YELLOW}claude --dangerously-skip-permissions${NC}"
echo ""
echo "   This enables fully autonomous operation without permission prompts."
echo "   ⚠️  Use only in sandboxed environments - grants unrestricted access."
echo ""
print_info "For troubleshooting, see: .devcontainer/CLAUDE.md"
echo ""
INSTALLER_FOOTER

# Make the generated installer executable
chmod +x "${OUTPUT_FILE}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "Build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "Generated: ${OUTPUT_FILE}"

# Get file size
FILE_SIZE=$(wc -c < "${OUTPUT_FILE}" | xargs)
FILE_SIZE_KB=$((FILE_SIZE / 1024))

print_info "Size: ${FILE_SIZE_KB} KB (${FILE_SIZE} bytes)"
echo ""
print_success "The installer is self-contained and ready to distribute!"
echo ""
echo "To test locally:"
echo -e "  ${YELLOW}cd /path/to/test-repo && bash ${OUTPUT_FILE}${NC}"
echo ""
echo "To publish to GitHub:"
echo -e "  ${YELLOW}git add install.sh${NC}"
echo -e "  ${YELLOW}git commit -m \"Update installer (${COMMIT_HASH})\"${NC}"
echo -e "  ${YELLOW}git push${NC}"
echo ""

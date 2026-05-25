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
    "link-host-claude.sh"
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

# EOF-collision guard: a bare "EOF_<munged>" line inside any source file would
# prematurely close its heredoc in the generated install.sh and corrupt the
# emitted file. Catch this at build time rather than at install time.
for file in "${FILES[@]}"; do
    munged="${file//[.-]/_}"
    if grep -qE "^EOF_${munged}\$" "${SCRIPT_DIR}/${file}"; then
        print_error "Source ${file} contains a line literally equal to 'EOF_${munged}'"
        print_error "This would close its heredoc marker prematurely in install.sh"
        print_error "Rename the marker or escape the line in ${file}"
        exit 1
    fi
done

echo ""
print_info "Generating ${OUTPUT_FILE}..."
echo ""

# Start writing the installer script
cat > "${OUTPUT_FILE}" << 'INSTALLER_HEADER'
#!/usr/bin/env bash
set -e

# Secure DevContainer Configuration Installer
# Self-contained installer with all configuration files embedded

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
INSTALLER_HEADER

# Add version info
cat >> "${OUTPUT_FILE}" << VERSION_INFO
# Generated from commit: ${COMMIT_HASH}
# Build date: ${COMMIT_DATE}

VERSION_INFO

# Emit write_current_templates function (one heredoc per source file)
cat >> "${OUTPUT_FILE}" << 'CURRENT_FN_HEADER'

# write_current_templates <target_dir>
# Writes the embedded current-release templates into the given directory.
write_current_templates() {
    local target_dir="$1"
    mkdir -p "${target_dir}"
CURRENT_FN_HEADER

for file in "${FILES[@]}"; do
    munged="${file//[.-]/_}"
    echo "    cat > \"\${target_dir}/${file}\" << 'EOF_${munged}'" >> "${OUTPUT_FILE}"
    cat "${SCRIPT_DIR}/${file}" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"
    echo "EOF_${munged}" >> "${OUTPUT_FILE}"
    print_success "Embedded current ${file}"
done

echo "}" >> "${OUTPUT_FILE}"
echo "" >> "${OUTPUT_FILE}"

# Emit write_previous_templates function — used as the 3-way-merge base in --merge mode.
# If a prior install.sh exists in git HEAD, extract its embedded templates and emit them
# as a parallel set of heredocs. Otherwise emit a body that errors out cleanly.
if git cat-file -e HEAD:install.sh 2>/dev/null; then
    PREV_INSTALLER=$(mktemp)
    git show HEAD:install.sh > "${PREV_INSTALLER}"
    print_info "Found prior install.sh in HEAD — embedding previous templates for --merge baseline"

    cat >> "${OUTPUT_FILE}" << 'PREV_FN_HEADER'
# write_previous_templates <target_dir>
# Writes the templates from the previous installer release (extracted from
# install.sh at git HEAD when this installer was built). Used as the common
# ancestor for --merge mode's 3-way merge.
write_previous_templates() {
    local target_dir="$1"
    mkdir -p "${target_dir}"
PREV_FN_HEADER

    for file in "${FILES[@]}"; do
        munged="${file//[.-]/_}"
        # Previous installers may have emitted heredocs either inline (older
        # build.sh, target was ${DEVCONTAINER_DIR}/...) or inside the new
        # write_current_templates function (target is ${target_dir}/...). Try
        # both start markers.
        echo "    cat > \"\${target_dir}/${file}\" << 'EOF_PREV_${munged}'" >> "${OUTPUT_FILE}"
        awk -v marker="EOF_${munged}" -v file="${file}" '
            $0 == "cat > \"${DEVCONTAINER_DIR}/" file "\" << '\''" marker "'\''" { p=1; next }
            $0 == "    cat > \"${target_dir}/" file "\" << '\''" marker "'\''" { p=1; next }
            p && $0 == marker { p=0; exit }
            p { print }
        ' "${PREV_INSTALLER}" >> "${OUTPUT_FILE}"
        echo "EOF_PREV_${munged}" >> "${OUTPUT_FILE}"
        print_success "Embedded previous ${file}"
    done

    echo "}" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"
    rm "${PREV_INSTALLER}"
else
    print_warning "No prior install.sh in git HEAD — --merge mode will refuse cleanly"
    cat >> "${OUTPUT_FILE}" << 'PREV_FN_EMPTY'
# write_previous_templates <target_dir>
# No previous installer was committed when this installer was built, so there
# are no embedded base templates. --merge mode will refuse cleanly.
write_previous_templates() {
    print_error "No base templates embedded — --merge mode is unavailable in this installer."
    echo "  Reason: this install.sh was built without a prior install.sh in git HEAD."
    echo "  Workaround: use --force-upgrade for a clean overwrite, or back up + reinstall."
    exit 1
}

PREV_FN_EMPTY
fi

# Main installer logic (arg parsing, mode dispatch, install/force/merge flows)
cat >> "${OUTPUT_FILE}" << 'INSTALLER_LOGIC'
# Parse command line arguments
MODE=install
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-upgrade)
            [ "$MODE" != "install" ] && { print_error "Cannot combine $1 with another mode"; exit 1; }
            MODE=force
            shift
            ;;
        --merge)
            [ "$MODE" != "install" ] && { print_error "Cannot combine $1 with another mode"; exit 1; }
            MODE=merge
            shift
            ;;
        -h|--help)
            cat <<USAGE
Usage: $0 [--force-upgrade | --merge]

Modes:
  (default)         Fresh install. Errors if .devcontainer/ already exists.
  --force-upgrade   Overwrite existing .devcontainer/ (must be git-tracked).
  --merge           Three-way merge embedded templates into existing
                    .devcontainer/. Conflicts are emitted as standard git
                    conflict markers (<<<<<<<, =======, >>>>>>>) for the
                    user to resolve manually. Requires .devcontainer/ files
                    to be git-tracked and clean.

Options:
  -h, --help        Show this help message.
USAGE
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

# Files this installer manages — kept in sync with build.sh FILES array
FILES=(devcontainer.json Dockerfile generate-claude-config.sh link-host-claude.sh CLAUDE.md)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Secure DevContainer Configuration Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_info "Repository root: ${REPO_ROOT}"
print_info "Target directory: ${DEVCONTAINER_DIR}"
print_info "Mode: ${MODE}"
echo ""

# ─── Mode: merge ──────────────────────────────────────────────────────────────
# Three-way merge using git merge-file with the embedded previous-release
# templates as the common ancestor. Conflicts land in the user's files as
# standard <<<<<<< / ======= / >>>>>>> markers for manual resolution.
if [ "$MODE" = "merge" ]; then
    if [ ! -d "${DEVCONTAINER_DIR}" ]; then
        print_error ".devcontainer/ does not exist — nothing to merge."
        echo "Run without --merge for a fresh install."
        exit 1
    fi

    cd "${REPO_ROOT}"

    # Refuse if any target file is untracked or has uncommitted changes.
    # Git is the user's recovery path — a clean baseline is required.
    for f in "${FILES[@]}"; do
        [ -f ".devcontainer/$f" ] || continue
        if ! git ls-files --error-unmatch ".devcontainer/$f" >/dev/null 2>&1; then
            print_error ".devcontainer/$f exists but is not tracked by git."
            echo "  Commit it first (so 'git checkout' can recover if the merge goes wrong)."
            exit 1
        fi
        if ! git diff --quiet -- ".devcontainer/$f" || ! git diff --cached --quiet -- ".devcontainer/$f"; then
            print_error ".devcontainer/$f has uncommitted changes."
            echo "  Commit, stash, or 'git checkout -- .devcontainer/$f' first."
            exit 1
        fi
    done

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    # write_previous_templates exits with an error if no base was embedded
    # (first-ever build, before install.sh existed in git history).
    write_previous_templates "$TMP/base"
    write_current_templates  "$TMP/new"

    total_conflicts=0
    conflicted_files=()
    for f in "${FILES[@]}"; do
        if [ ! -f ".devcontainer/$f" ]; then
            cp "$TMP/new/$f" ".devcontainer/$f"
            print_success "Added $f (new file in this installer release)"
            continue
        fi
        if git merge-file --diff3 \
            -L "ours (your .devcontainer/$f)" \
            -L "base (previous installer)" \
            -L "theirs (new installer)" \
            ".devcontainer/$f" "$TMP/base/$f" "$TMP/new/$f"; then
            print_success "Merged $f cleanly"
        else
            rc=$?
            total_conflicts=$((total_conflicts + rc))
            conflicted_files+=("$f")
            print_warning "Conflicts in $f ($rc hunk(s))"
        fi
    done

    echo ""
    if [ "$total_conflicts" -eq 0 ]; then
        print_success "Merge complete — review with: git diff .devcontainer/"
    else
        print_warning "$total_conflicts conflict hunk(s) across: ${conflicted_files[*]}"
        echo ""
        echo "Next steps:"
        echo "  1. Open the conflicted files and resolve the <<<<<<< / ======= / >>>>>>> markers."
        echo -e "  2. Stage and commit: ${YELLOW}git add .devcontainer/ && git commit${NC}"
        echo ""
        echo -e "Or abort the merge: ${YELLOW}git checkout -- .devcontainer/${NC}"
    fi
    exit 0
fi

# ─── Modes: install (default) and force-upgrade ───────────────────────────────
if [ -d "${DEVCONTAINER_DIR}" ]; then
    if [ "$MODE" != "force" ]; then
        print_error ".devcontainer directory already exists!"
        echo ""
        echo "Choose one of:"
        echo -e "  ${YELLOW}--merge${NC}            Three-way merge (preserves customizations)"
        echo -e "  ${YELLOW}--force-upgrade${NC}    Overwrite existing files (requires git tracking)"
        echo ""
        echo "Or manually clear first:"
        echo "  rm -rf ${DEVCONTAINER_DIR}"
        echo "  mv ${DEVCONTAINER_DIR} ${DEVCONTAINER_DIR}.backup"
        exit 1
    fi

    print_warning ".devcontainer directory exists, checking git status..."

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
        echo -e "     ${YELLOW}git add .devcontainer/${NC}"
        echo -e "     ${YELLOW}git commit -m \"Add current devcontainer configuration\"${NC}"
        echo -e "     Then re-run: ${YELLOW}$0 --force-upgrade${NC}"
        echo ""
        echo "  2. Manually backup the directory:"
        echo -e "     ${YELLOW}cp -r ${DEVCONTAINER_DIR} ${DEVCONTAINER_DIR}.backup${NC}"
        echo -e "     ${YELLOW}rm -rf ${DEVCONTAINER_DIR}${NC}"
        echo -e "     Then re-run: ${YELLOW}$0${NC}"
        echo ""
        echo "  3. Delete the directory (if you're sure):"
        echo -e "     ${YELLOW}rm -rf ${DEVCONTAINER_DIR}${NC}"
        echo -e "     Then re-run: ${YELLOW}$0${NC}"
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
for f in "${FILES[@]}"; do
    echo "     • $f"
done
echo ""
echo "  3. Set proper permissions (generate-claude-config.sh +x)"
echo ""
echo "Features:"
echo "  • Rootless Podman-compatible container"
echo "  • Minimal Linux capabilities (security hardened)"
echo "  • Network isolation (slirp4netns)"
echo "  • Automatic Claude Code installation"
echo "  • Environment variable authentication (ANTHROPIC_AUTH_TOKEN)"
echo "  • Optional GitHub CLI auth bridge (if gh is logged in on host)"
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

write_current_templates "${DEVCONTAINER_DIR}"
for f in "${FILES[@]}"; do
    print_success "Created $f"
done

# Make shell scripts executable
chmod +x "${DEVCONTAINER_DIR}/generate-claude-config.sh"
print_success "Set executable permissions on generate-claude-config.sh"
chmod +x "${DEVCONTAINER_DIR}/link-host-claude.sh"
print_success "Set executable permissions on link-host-claude.sh"

# Add credential files to .gitignore if not already present.
# As of the containerEnv migration, only the GitHub token is still file-based
# (ANTHROPIC_* now flow through containerEnv from the host shell). The three
# .claude-* entries are kept here as a safety net for older installs that may
# have leftover files on disk from the previous installer release.
GITIGNORE="${REPO_ROOT}/.gitignore"
if ! grep -q ".devcontainer/.gh-auth-token" "${GITIGNORE}" 2>/dev/null; then
    echo "" >> "${GITIGNORE}"
    echo "# Claude Code / GitHub authentication (auto-generated, keep secret)" >> "${GITIGNORE}"
    echo ".devcontainer/.gh-auth-token" >> "${GITIGNORE}"
    # Legacy entries from pre-containerEnv installers; harmless if never created.
    echo ".devcontainer/.claude-auth-token" >> "${GITIGNORE}"
    echo ".devcontainer/.claude-base-url" >> "${GITIGNORE}"
    echo ".devcontainer/.claude-custom-headers" >> "${GITIGNORE}"
    print_success "Added authentication files to .gitignore"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Files created:"
echo ""
for f in "${FILES[@]}"; do
    echo "  ✓ .devcontainer/$f"
done
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
echo "  • Configure authentication from ANTHROPIC_AUTH_TOKEN"
echo "  • Bridge GitHub CLI auth from host (if gh is installed and logged in)"
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
INSTALLER_LOGIC

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

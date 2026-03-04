#!/usr/bin/env bash
# sync.sh — Synchronize Claude Code configuration between this repo and live locations
#
# Usage:
#   bash sync.sh deploy    — Push config from repo → live locations
#   bash sync.sh collect   — Pull config from live locations → repo
#   bash sync.sh status    — Show what's different between repo and live
#   bash sync.sh setup     — Initial setup: replace live files with symlinks to repo
#
# Cross-platform: detects WSL vs native Linux vs Git Bash on Windows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_DIR="$SCRIPT_DIR/global"
PROJECTS_DIR="$SCRIPT_DIR/setup/projects"

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macos"
elif grep -qi microsoft /proc/version 2>/dev/null; then
    PLATFORM="wsl"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    PLATFORM="windows"
else
    PLATFORM="linux"
fi

# Target locations (adjust per platform if needed)
CLAUDE_HOME="$HOME/.claude"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Portable hostname (SteamOS has no hostname binary)
get_hostname() { hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo "unknown"; }

# Source user-local overrides (hostname map, post-setup hook) if present
if [[ -f "$SCRIPT_DIR/sync.local.sh" ]]; then
    source "$SCRIPT_DIR/sync.local.sh"
fi

# ---- SETUP: Replace live files with symlinks to repo ----
cmd_setup() {
    log_info "Setting up symlinks from live locations → repo"
    log_info "Platform: $PLATFORM"

    # Backup existing files
    if [ -f "$CLAUDE_HOME/CLAUDE.md" ] && [ ! -L "$CLAUDE_HOME/CLAUDE.md" ]; then
        log_info "Backing up existing $CLAUDE_HOME/CLAUDE.md"
        cp "$CLAUDE_HOME/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md.bak"
    fi

    # Global CLAUDE.md
    ln -sf "$GLOBAL_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
    log_info "Linked: $CLAUDE_HOME/CLAUDE.md → $GLOBAL_DIR/CLAUDE.md"

    # Ensure ~/.claude exists as a real directory (not a symlink)
    if [ -L "$CLAUDE_HOME" ]; then
        log_warn "$CLAUDE_HOME is a symlink — removing and creating directory"
        rm "$CLAUDE_HOME"
    fi
    mkdir -p "$CLAUDE_HOME"

    # Knowledge architecture directories (directory symlinks)
    for dir in foundation reference domains knowledge machines; do
        if [ -d "$GLOBAL_DIR/$dir" ]; then
            # Remove whatever exists at the target — symlink, directory, or file
            if [ -L "$CLAUDE_HOME/$dir" ]; then
                rm -f "$CLAUDE_HOME/$dir"
            elif [ -d "$CLAUDE_HOME/$dir" ]; then
                log_warn "$CLAUDE_HOME/$dir exists as directory — backing up"
                mv "$CLAUDE_HOME/$dir" "$CLAUDE_HOME/${dir}.bak.$(date +%s)"
            fi
            # Use ln -sfn: -n prevents following existing symlink-to-dir
            ln -sfn "$GLOBAL_DIR/$dir" "$CLAUDE_HOME/$dir"
            log_info "Linked: $CLAUDE_HOME/$dir → $GLOBAL_DIR/$dir"
        fi
    done

    # Hooks
    deploy_hooks

    # Project-specific rules
    deploy_project_rules

    # Create CLAUDE.local.md if missing (machine-specific @import)
    if [[ ! -f "$HOME/CLAUDE.local.md" ]]; then
        # Auto-detect machine file from hostname
        local machine_file=""
        local hn
        hn=$(get_hostname)

        # Try user-defined hostname map first (from sync.local.sh)
        if type local_hostname_map &>/dev/null; then
            machine_file=$(local_hostname_map "$hn")
        fi

        # Fall back to framework defaults (commented examples for new users)
        if [[ -z "$machine_file" ]]; then
            case "$hn" in
                # Example: map your hostnames to machine definition files
                # my-vps-*)       machine_file="vps.md" ;;
                # DESKTOP-*)      machine_file="wsl.md" ;;
                # steamdeck*)     machine_file="steamdeck.md" ;;
                # my-workstation*)
                #     if [[ "$(whoami)" == "work-user" ]]; then
                #         machine_file="office.md"
                #     else
                #         machine_file="home.md"
                #     fi
                #     ;;
                *) ;;  # No match
            esac
        fi

        if [[ -n "$machine_file" && -f "$CLAUDE_HOME/machines/$machine_file" ]]; then
            echo "@~/.claude/machines/$machine_file" > "$HOME/CLAUDE.local.md"
            log_info "Created CLAUDE.local.md → machines/$machine_file"
        else
            log_warn "Could not auto-detect machine — create ~/CLAUDE.local.md manually"
            log_warn "  echo '@~/.claude/machines/<machine>.md' > ~/CLAUDE.local.md"
        fi
    else
        log_info "CLAUDE.local.md already exists"
    fi

    # Run user-defined post-setup hook (from sync.local.sh)
    if type local_post_setup &>/dev/null; then
        local_post_setup
    fi

    # Clean unwanted marketplace plugins
    clean_marketplace_plugins

    log_info "Setup complete. Live locations now symlinked to repo."
    log_warn "Restart Claude Code for changes to take effect."
}

# ---- DEPLOY: Copy from repo → live (for non-symlink setups or project rules) ----
cmd_deploy() {
    log_info "Deploying config from repo → live locations"

    # Global CLAUDE.md
    if [ -L "$CLAUDE_HOME/CLAUDE.md" ]; then
        log_info "CLAUDE.md is symlinked — no copy needed"
    else
        cp "$GLOBAL_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
        log_info "Copied: CLAUDE.md → $CLAUDE_HOME/"
    fi

    # Knowledge architecture directories
    for dir in foundation reference domains knowledge machines; do
        if [ -d "$GLOBAL_DIR/$dir" ]; then
            if [ -L "$CLAUDE_HOME/$dir" ]; then
                log_info "$dir/ is symlinked — no copy needed"
            else
                mkdir -p "$CLAUDE_HOME/$dir"
                cp -r "$GLOBAL_DIR/$dir/." "$CLAUDE_HOME/$dir/"
                log_info "Copied: $dir/ → $CLAUDE_HOME/$dir/"
            fi
        fi
    done

    # Hooks
    deploy_hooks

    # Project-specific rules
    deploy_project_rules

    # Statusline script
    if [ -f "$SCRIPT_DIR/setup/config/statusline.sh" ]; then
        cp "$SCRIPT_DIR/setup/config/statusline.sh" "$CLAUDE_HOME/statusline.sh"
        chmod +x "$CLAUDE_HOME/statusline.sh"
        log_info "Deployed: statusline.sh → $CLAUDE_HOME/"
    fi

    # Apply project folder icons (platform-appropriate)
    apply_project_icons

    # Clean unwanted marketplace plugins (auto-installed by Claude Code)
    clean_marketplace_plugins

    # Deploy settings (merge base + override if present)
    deploy_settings

    # Check live settings.json for missing critical blocks
    check_settings_health

    # Template drift check
    check_template_drift

    # Personal-data leak check on template
    check_personal_data_leaks

    log_info "Deploy complete."
}

clean_marketplace_plugins() {
    local script="$SCRIPT_DIR/setup/scripts/clean-marketplace-plugins.sh"
    if [ -f "$script" ]; then
        bash "$script" 2>/dev/null || log_warn "Marketplace plugin cleanup returned non-zero"
    fi
}

deploy_settings() {
    local base="$SCRIPT_DIR/setup/config/settings.json"
    local override="$SCRIPT_DIR/setup/config/settings.override.json"

    if [[ ! -f "$base" ]]; then
        log_warn "No settings.json found — skipping settings deploy"
        return
    fi

    if [[ -f "$override" ]]; then
        log_info "Merging settings.json + settings.override.json"
        # Deep merge: override wins for scalars, arrays are concatenated (deduped)
        python3 -c "
import json, sys
base = json.load(open(sys.argv[1]))
over = json.load(open(sys.argv[2]))
def merge(b, o):
    for k, v in o.items():
        if k in b and isinstance(b[k], dict) and isinstance(v, dict):
            merge(b[k], v)
        elif k in b and isinstance(b[k], list) and isinstance(v, list):
            combined = b[k] + [x for x in v if x not in b[k]]
            b[k] = combined
        else:
            b[k] = v
merge(base, over)
print(json.dumps(base, indent=2))
" "$base" "$override"
    else
        # No override — use base as-is (substitute __HOME__)
        sed "s|__HOME__|$HOME|g" "$base"
    fi > /dev/null  # Settings are deployed by check_settings_health, not here
    # Note: actual settings deployment is handled by check_settings_health
    # This function just validates the merge works. Full deploy TBD.
}

deploy_hooks() {
    mkdir -p "$CLAUDE_HOME/hooks"
    for hook in "$GLOBAL_DIR/hooks/"*.sh; do
        [ -f "$hook" ] || continue
        base=$(basename "$hook")
        cp "$hook" "$CLAUDE_HOME/hooks/$base"
        chmod +x "$CLAUDE_HOME/hooks/$base"
        log_info "Deployed hook: $base"
    done
}

deploy_project_rules() {
    # Deploy project-specific rules to projects that exist on this machine
    for project_dir in "$PROJECTS_DIR"/*/; do
        [ -d "$project_dir" ] || continue
        project_name=$(basename "$project_dir")

        # Find the project path from registry
        project_path=$(find_project_path "$project_name")
        if [ -z "$project_path" ]; then
            log_warn "Project '$project_name' not found on this machine — skipping"
            continue
        fi

        if [ ! -d "$project_path" ]; then
            log_warn "Project path '$project_path' doesn't exist — skipping"
            continue
        fi

        # Deploy rules
        if [ -d "$project_dir/rules" ]; then
            mkdir -p "$project_path/.claude"
            for rule in "$project_dir/rules/"*.md; do
                [ -f "$rule" ] || continue
                base=$(basename "$rule")
                cp "$rule" "$project_path/.claude/$base"
                log_info "Deployed: $project_name/rules/$base → $project_path/.claude/"
            done
        fi
    done
}

# ---- SETTINGS HEALTH CHECK ----
# Warns if live settings.json is missing critical blocks (permissions, hooks).
# A partial settings.json causes permission prompt storms and missing hooks.
check_settings_health() {
    local live_settings="$HOME/.cc-mirror/mclaude/config/settings.json"
    [ -f "$live_settings" ] || return 0

    local issues=0

    if ! grep -q '"permissions"' "$live_settings" 2>/dev/null; then
        log_warn "settings.json is missing 'permissions' block — all tool calls will require manual approval"
        log_warn "  Fix: redeploy from template: sed 's|__HOME__|$HOME|g' setup/config/settings.json > $live_settings"
        issues=$((issues + 1))
    fi

    if ! grep -q '"hooks"' "$live_settings" 2>/dev/null; then
        log_warn "settings.json is missing 'hooks' block — SessionStart/End hooks won't fire"
        issues=$((issues + 1))
    fi

    if ! grep -q '"enabledPlugins"' "$live_settings" 2>/dev/null; then
        log_warn "settings.json is missing 'enabledPlugins' block — skill plugins won't load"
        issues=$((issues + 1))
    fi

    if [ "$issues" -gt 0 ]; then
        log_warn "$issues critical block(s) missing from settings.json. Redeploy from template."
    fi
}

# ---- PROJECT FOLDER ICONS ----
# Applies priority-colored badge icons to project folders.
# Platform-detected: Windows (shortcut hub on NTFS) and/or KDE (.directory files).
apply_project_icons() {
    local icon_script="$SCRIPT_DIR/setup/scripts/project-icons.sh"
    [ -f "$icon_script" ] || return 0

    # Generate icons if they don't exist yet
    if [ ! -f "$SCRIPT_DIR/setup/icons/p1.ico" ]; then
        if python3 -c "from PIL import Image" 2>/dev/null; then
            log_info "Generating project badge icons..."
            bash "$icon_script" generate 2>/dev/null || log_warn "Icon generation failed (Pillow missing?)"
        else
            log_warn "Pillow not installed — skipping icon generation (pip install Pillow, or pipx run pip install Pillow on SteamOS)"
            return 0
        fi
    fi

    # Apply based on platform
    if [ -d /mnt/c/ ]; then
        # WSL — apply Windows shortcut hub
        log_info "Applying project folder icons (Windows shortcut hub)..."
        bash "$icon_script" apply-windows 2>/dev/null || log_warn "Windows icon application failed"
    fi

    if command -v kwriteconfig6 >/dev/null 2>&1 || command -v kwriteconfig5 >/dev/null 2>&1; then
        # KDE — apply .directory files
        log_info "Applying project folder icons (KDE Dolphin)..."
        bash "$icon_script" apply-kde 2>/dev/null || log_warn "KDE icon application failed"
    fi
}

# ---- PERSONAL DATA LEAK CHECK ----
# Scans the template repo for patterns that suggest personal data leaked into public files.
# Warns but does not block — manual review required.
#
# Customize: set PERSONAL_DATA_PATTERNS in sync.local.sh as a grep -E regex.
# Example: PERSONAL_DATA_PATTERNS='(your-email@example\.com|your-username|your-ip-address)'
check_personal_data_leaks() {
    local template_dir="$HOME/agent-fleet"
    [ -d "$template_dir" ] || return 0  # Template not on this machine

    # Patterns must be configured by the user — skip if empty
    local pattern="${PERSONAL_DATA_PATTERNS:-}"
    if [[ -z "$pattern" ]]; then
        return 0
    fi

    local leak_count=0
    local hits
    hits=$(grep -rn --include='*.md' --include='*.sh' --include='*.json' --include='*.yml' --include='*.yaml' \
        -E "$pattern" \
        "$template_dir" 2>/dev/null \
        | grep -v '\.git/' \
        | grep -v "PERSONAL_DATA_PATTERNS" \
        | grep -v 'tests/.*\.sh:.*echo.*Contact' \
        || true)

    if [ -n "$hits" ]; then
        leak_count=$(echo "$hits" | wc -l)
        log_warn "Personal data patterns found in template ($leak_count occurrence(s)):"
        echo "$hits" | head -10 | while IFS= read -r line; do
            log_warn "  $line"
        done
        if [ "$leak_count" -gt 10 ]; then
            log_warn "  ... and $((leak_count - 10)) more"
        fi
        log_warn "Review these before pushing the template to a public repo."
    fi
}

# ---- TEMPLATE DRIFT CHECK ----
# Checks tracked files for changes since last template sync.
# The manifest stores personal file hashes — if changed, template may need updating.
check_template_drift() {
    local template_dir="$HOME/agent-fleet"
    [ -d "$template_dir" ] || return 0  # Template not on this machine

    # CRC32 computation requires python3
    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "python3 not found — skipping template drift check"
        return 0
    fi

    local manifest="$SCRIPT_DIR/template-sync-manifest.md"
    [ -f "$manifest" ] || { log_warn "template-sync-manifest.md missing — cannot check template drift"; return 0; }

    local drift_count=0

    # Extract tracked file rows from manifest: lines matching "| `path` | `hash` |"
    # Use process substitution to avoid consuming stdin
    local tracked_files
    tracked_files=$(grep -oP '^\| `[^`]+` \| `[0-9a-f]{8}`' "$manifest" | sed 's/^| `//;s/` | `/|/;s/`$//' || true)

    local line file_path hash
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        file_path="${line%%|*}"
        hash="${line##*|}"
        [ -n "$file_path" ] && [ -n "$hash" ] || continue

        local full_path="$SCRIPT_DIR/$file_path"
        [ -f "$full_path" ] || continue

        local current_hash
        current_hash=$(python3 -c "import binascii,sys;print(format(binascii.crc32(open(sys.argv[1],'rb').read())&0xFFFFFFFF,'08x'))" "$full_path")

        if [ "$current_hash" != "$hash" ]; then
            log_warn "$file_path changed since last template sync (was: $hash, now: $current_hash)"
            drift_count=$((drift_count + 1))
        fi
    done <<< "$tracked_files"

    if [ "$drift_count" -gt 0 ]; then
        log_warn "$drift_count file(s) drifted. Review template-sync-manifest.md and propagate to template."
    fi
}

# ---- COLLECT: Copy from live locations → repo ----
cmd_collect() {
    log_info "Collecting config from live locations → repo"

    # Global CLAUDE.md (only if not symlinked — symlinks are already in sync)
    if [ -L "$CLAUDE_HOME/CLAUDE.md" ]; then
        log_info "CLAUDE.md is symlinked — already in sync"
    elif [ -f "$CLAUDE_HOME/CLAUDE.md" ]; then
        cp "$CLAUDE_HOME/CLAUDE.md" "$GLOBAL_DIR/CLAUDE.md"
        log_info "Collected: CLAUDE.md"
    fi

    # Knowledge architecture directories
    for dir in foundation reference domains knowledge machines; do
        if [ -L "$CLAUDE_HOME/$dir" ]; then
            log_info "$dir/ is symlinked — already in sync"
        elif [ -d "$CLAUDE_HOME/$dir" ] && [ -d "$GLOBAL_DIR/$dir" ]; then
            cp -r "$CLAUDE_HOME/$dir/." "$GLOBAL_DIR/$dir/"
            log_info "Collected: $dir/"
        fi
    done

    # Collect hooks (if not symlinked)
    if [ -d "$CLAUDE_HOME/hooks" ] && [ ! -L "$CLAUDE_HOME/hooks" ]; then
        for hook in "$CLAUDE_HOME/hooks/"*.sh; do
            [ -f "$hook" ] || continue
            base=$(basename "$hook")
            if [ -f "$GLOBAL_DIR/hooks/$base" ]; then
                # Safety: skip if the source has uncommitted changes (editing hazard)
                if git -C "$SCRIPT_DIR" diff --name-only 2>/dev/null | grep -q "global/hooks/$base"; then
                    log_warn "Skipping hook collect: $base has uncommitted edits in repo"
                    continue
                fi
                if ! diff -q "$hook" "$GLOBAL_DIR/hooks/$base" >/dev/null 2>&1; then
                    cp "$hook" "$GLOBAL_DIR/hooks/$base"
                    log_info "Collected hook: $base"
                fi
            fi
        done
    fi

    # Collect project-specific rules
    for project_dir in "$PROJECTS_DIR"/*/; do
        [ -d "$project_dir" ] || continue
        project_name=$(basename "$project_dir")
        project_path=$(find_project_path "$project_name")
        [ -n "$project_path" ] && [ -d "$project_path/.claude" ] || continue

        mkdir -p "$project_dir/rules"
        for rule in "$project_path/.claude/"*.md; do
            [ -f "$rule" ] || continue
            base=$(basename "$rule")
            cp "$rule" "$project_dir/rules/$base"
            log_info "Collected: $project_name/$base"
        done
    done

    log_info "Collect complete. Review changes with 'git diff'."
}

# ---- STATUS: Compare repo vs live ----
cmd_status() {
    log_info "Comparing repo vs live locations"
    log_info "Platform: $PLATFORM"
    echo ""

    local diffs=0

    # Global CLAUDE.md
    if [ -L "$CLAUDE_HOME/CLAUDE.md" ]; then
        echo "  CLAUDE.md: symlinked ✓"
    elif diff -q "$GLOBAL_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" >/dev/null 2>&1; then
        echo "  CLAUDE.md: in sync ✓"
    else
        echo -e "  CLAUDE.md: ${RED}DIFFERS${NC}"
        diffs=$((diffs + 1))
    fi

    # Knowledge architecture directories
    for dir in foundation reference domains knowledge machines; do
        if [ -L "$CLAUDE_HOME/$dir" ]; then
            echo "  $dir/: symlinked ✓"
        elif [ -d "$CLAUDE_HOME/$dir" ]; then
            echo -e "  $dir/: ${YELLOW}EXISTS BUT NOT SYMLINKED${NC}"
            diffs=$((diffs + 1))
        elif [ -d "$GLOBAL_DIR/$dir" ]; then
            echo -e "  $dir/: ${YELLOW}NOT DEPLOYED${NC}"
            diffs=$((diffs + 1))
        fi
    done

    # Project-specific
    echo ""
    log_info "Project-specific rules:"
    for project_dir in "$PROJECTS_DIR"/*/; do
        [ -d "$project_dir" ] || continue
        project_name=$(basename "$project_dir")
        project_path=$(find_project_path "$project_name")

        if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
            echo "  $project_name: not on this machine"
            continue
        fi

        for rule in "$project_dir/rules/"*.md; do
            [ -f "$rule" ] || continue
            base=$(basename "$rule")
            target="$project_path/.claude/$base"
            if [ ! -f "$target" ]; then
                echo -e "  $project_name/$base: ${YELLOW}NOT DEPLOYED${NC}"
                diffs=$((diffs + 1))
            elif diff -q "$rule" "$target" >/dev/null 2>&1; then
                echo "  $project_name/$base: in sync ✓"
            else
                echo -e "  $project_name/$base: ${RED}DIFFERS${NC}"
                diffs=$((diffs + 1))
            fi
        done
    done

    # Agent roster summary
    echo ""
    log_info "Agent rosters:"
    for d in "$HOME"/*/; do
        [ -d "$d/.claude/agents" ] || continue
        count=$(find "$d/.claude/agents/" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
        [ "$count" -gt 0 ] && echo "  $(basename "$d"): $count agents"
    done

    # Cross-project status
    local cross_dir="$SCRIPT_DIR/cross-project"
    if [ -d "$cross_dir" ]; then
        echo ""
        log_info "Cross-project state:"
        # Inbox pending count
        local inbox="$cross_dir/inbox.md"
        if [ -f "$inbox" ]; then
            local pending
            pending=$(grep -c '^\- \[ \]' "$inbox" 2>/dev/null || true)
            if [ "$pending" -gt 0 ] 2>/dev/null; then
                echo -e "  inbox.md: ${YELLOW}$pending pending task(s)${NC}"
            else
                echo "  inbox.md: empty ✓"
            fi
        fi
        # Strategy file freshness
        for f in "$cross_dir"/*-strategy.md "$cross_dir"/contacts.md "$cross_dir"/engagement-log.md; do
            [ -f "$f" ] || continue
            local base last_mod days_ago
            base=$(basename "$f")
            last_mod=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)
            if [ -n "$last_mod" ]; then
                days_ago=$(( ($(date +%s) - last_mod) / 86400 ))
                if [ "$days_ago" -gt 14 ]; then
                    echo -e "  $base: ${YELLOW}last modified ${days_ago}d ago${NC}"
                else
                    echo "  $base: updated ${days_ago}d ago ✓"
                fi
            fi
        done
    fi

    echo ""
    if [ $diffs -eq 0 ]; then
        log_info "Everything in sync ✓"
    else
        log_warn "$diffs difference(s) found. Run 'deploy' or 'collect' to sync."
    fi
}

# ---- CHECK: Aggregated drift/staleness check ----
# Usage: bash sync.sh check [--repo-root PATH] [--template-dir PATH]
# Checks all propagation chains for drift or staleness.
# Output: summary per chain. Exit 0 always (warning-only, never blocks).
cmd_check() {
    local check_repo_root="$SCRIPT_DIR"
    local check_template_dir="$HOME/agent-fleet"
    local check_mobile_dir="$HOME/agent-fleet-mobile"

    # Parse override arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo-root)     check_repo_root="$2"; shift 2 ;;
            --template-dir)  check_template_dir="$2"; shift 2 ;;
            --mobile-dir)    check_mobile_dir="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local total_issues=0

    # ── 1. Template drift (CRC32 manifest) ───────────────────────────────
    log_info "Checking template drift..."
    local manifest="$check_repo_root/template-sync-manifest.md"
    if [ ! -f "$manifest" ]; then
        log_warn "template-sync-manifest.md missing — cannot check template drift"
        total_issues=$((total_issues + 1))
    elif ! command -v python3 >/dev/null 2>&1; then
        log_warn "python3 not found — skipping template drift check"
    else
        local drift_count=0
        local tracked_files
        tracked_files=$(grep -oP '^\| `[^`]+` \| `[0-9a-f]{8}`' "$manifest" | sed 's/^| `//;s/` | `/|/;s/`$//' || true)

        local line file_path hash
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            file_path="${line%%|*}"
            hash="${line##*|}"
            [ -n "$file_path" ] && [ -n "$hash" ] || continue

            local full_path="$check_repo_root/$file_path"
            if [ ! -f "$full_path" ]; then
                continue  # Missing file — skip gracefully
            fi

            local current_hash
            current_hash=$(python3 -c "import binascii,sys;print(format(binascii.crc32(open(sys.argv[1],'rb').read())&0xFFFFFFFF,'08x'))" "$full_path")

            if [ "$current_hash" != "$hash" ]; then
                log_warn "$file_path drifted (was: $hash, now: $current_hash)"
                drift_count=$((drift_count + 1))
            fi
        done <<< "$tracked_files"

        if [ "$drift_count" -gt 0 ]; then
            log_warn "Template: $drift_count file(s) drifted"
            total_issues=$((total_issues + drift_count))
        else
            log_info "Template: clean"
        fi
    fi

    # ── 2. Personal data leak check ──────────────────────────────────────
    # Patterns must be configured by user in sync.local.sh (PERSONAL_DATA_PATTERNS)
    local pattern="${PERSONAL_DATA_PATTERNS:-}"
    if [ -d "$check_template_dir" ] && [ -n "$pattern" ]; then
        log_info "Checking template for sensitive patterns..."
        local hits
        hits=$(grep -rn --include='*.md' --include='*.sh' --include='*.json' --include='*.yml' --include='*.yaml' \
            -E "$pattern" \
            "$check_template_dir" 2>/dev/null \
            | grep -v '\.git/' \
            | grep -v "PERSONAL_DATA_PATTERNS" \
            | grep -v 'tests/.*\.sh:.*echo.*Contact' \
            || true)

        if [ -n "$hits" ]; then
            local leak_count
            leak_count=$(echo "$hits" | wc -l)
            log_warn "personal data patterns found in template ($leak_count occurrence(s)):"
            echo "$hits" | head -5 | while IFS= read -r line; do
                log_warn "  $line"
            done
            total_issues=$((total_issues + leak_count))
        else
            log_info "Template: clean (no sensitive patterns found)"
        fi
    fi

    # ── 3. Mobile staleness ──────────────────────────────────────────────
    if [ -d "$check_mobile_dir" ]; then
        log_info "Checking mobile repo staleness..."
        local mobile_script="$check_repo_root/setup/scripts/mobile-deploy.sh"
        if [ -f "$mobile_script" ]; then
            local mobile_out
            mobile_out=$(bash "$mobile_script" --check-staleness --config-repo "$check_repo_root" --target "$check_mobile_dir" 2>&1)
            echo "$mobile_out" | grep -v '^\[' || true  # Pass through non-log lines
            if echo "$mobile_out" | grep -q "is stale"; then
                total_issues=$((total_issues + 1))
            else
                log_info "Mobile: up to date"
            fi
        fi
    else
        log_info "Mobile repo not present — skipping"
    fi

    # ── 4. Hook drift (repo vs deployed) ─────────────────────────────────
    log_info "Checking hook drift..."
    local hook_drift=0
    if [ -d "$check_repo_root/global/hooks" ] && [ -d "$CLAUDE_HOME/hooks" ]; then
        for hook in "$check_repo_root/global/hooks/"*.sh; do
            [ -f "$hook" ] || continue
            local base
            base=$(basename "$hook")
            local deployed="$CLAUDE_HOME/hooks/$base"
            if [ ! -f "$deployed" ]; then
                log_warn "Hook $base: not deployed"
                hook_drift=$((hook_drift + 1))
            elif ! diff -q "$hook" "$deployed" >/dev/null 2>&1; then
                log_warn "Hook $base: drifted (repo ≠ deployed)"
                hook_drift=$((hook_drift + 1))
            fi
        done
    fi
    if [ "$hook_drift" -eq 0 ]; then
        log_info "Hooks: clean"
    else
        total_issues=$((total_issues + hook_drift))
    fi

    # ── 5. Project rule drift (repo vs deployed) ─────────────────────────
    log_info "Checking project rule drift..."
    local rule_drift=0
    if [ -d "$check_repo_root/setup/projects" ]; then
        for project_dir in "$check_repo_root/setup/projects"/*/; do
            [ -d "$project_dir" ] || continue
            local project_name
            project_name=$(basename "$project_dir")
            local project_path
            project_path=$(find_project_path "$project_name")
            [ -n "$project_path" ] && [ -d "$project_path" ] || continue

            for rule in "$project_dir/rules/"*.md; do
                [ -f "$rule" ] || continue
                local base
                base=$(basename "$rule")
                local target="$project_path/.claude/$base"
                if [ ! -f "$target" ]; then
                    log_warn "Rule $project_name/$base: not deployed"
                    rule_drift=$((rule_drift + 1))
                elif ! diff -q "$rule" "$target" >/dev/null 2>&1; then
                    log_warn "Rule $project_name/$base: drifted (repo ≠ deployed)"
                    rule_drift=$((rule_drift + 1))
                fi
            done
        done
    fi
    if [ "$rule_drift" -eq 0 ]; then
        log_info "Project rules: clean"
    else
        total_issues=$((total_issues + rule_drift))
    fi

    # ── Summary ──────────────────────────────────────────────────────────
    echo ""
    if [ "$total_issues" -eq 0 ]; then
        log_info "All propagation chains clean ✓"
    else
        log_warn "$total_issues issue(s) found across propagation chains"
    fi
}

# ---- Helper: find project path by name ----
find_project_path() {
    local name="$1"
    # Check common locations
    for candidate in "$HOME/$name" "$HOME/projects/$name"; do
        if [ -d "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
    # Check registry for custom paths
    if [ -f "$SCRIPT_DIR/registry.md" ]; then
        # Extract path from registry table (format: | Project | Priority | Path | GitHub Remote | Machines | Type | Phase | Notes |)
        local path
        path=$(grep -F "| $name |" "$SCRIPT_DIR/registry.md" 2>/dev/null | head -1 | awk -F'|' '{print $4}' | xargs | tr -d '`')
        if [ -n "$path" ]; then
            # Expand ~
            path="${path/#\~/$HOME}"
            if [ -d "$path" ]; then
                echo "$path"
            fi
        fi
    fi
}

# ---- Stamp: refresh all manifest hashes to current values ----
cmd_stamp() {
    local manifest="$SCRIPT_DIR/template-sync-manifest.md"
    if [ ! -f "$manifest" ]; then
        log_warn "template-sync-manifest.md not found — nothing to stamp"
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "python3 not found — cannot compute hashes"
        return 1
    fi

    local refreshed=0 skipped=0
    local tracked_files
    tracked_files=$(grep -oP '^\| `[^`]+` \| `[0-9a-f]{8}`' "$manifest" | sed 's/^| `//;s/` | `/|/;s/`$//' || true)

    local line file_path old_hash
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        file_path="${line%%|*}"
        old_hash="${line##*|}"
        [ -n "$file_path" ] && [ -n "$old_hash" ] || continue

        local full_path="$SCRIPT_DIR/$file_path"
        if [ ! -f "$full_path" ]; then
            log_warn "Skipping $file_path — file not found"
            skipped=$((skipped + 1))
            continue
        fi

        local new_hash
        new_hash=$(python3 -c "import binascii,sys;print(format(binascii.crc32(open(sys.argv[1],'rb').read())&0xFFFFFFFF,'08x'))" "$full_path")

        if [ "$new_hash" != "$old_hash" ]; then
            # Replace the old hash with new hash in the manifest (exact match on backtick-wrapped hash)
            sed -i "s/\`$old_hash\`/\`$new_hash\`/" "$manifest"
            log_info "Refreshed $file_path: $old_hash → $new_hash"
            refreshed=$((refreshed + 1))
        fi
    done <<< "$tracked_files"

    if [ "$refreshed" -gt 0 ]; then
        log_info "Refreshed $refreshed hash(es) in template-sync-manifest.md"
    else
        log_info "All manifest hashes are current — nothing to refresh"
    fi
    [ "$skipped" -eq 0 ] || log_warn "Skipped $skipped missing file(s)"
}

# ---- Main ----
case "${1:-help}" in
    setup)          cmd_setup ;;
    deploy)         cmd_deploy ;;
    collect)        cmd_collect ;;
    check)          shift; cmd_check "$@" ;;
    stamp)          cmd_stamp ;;
    status)         cmd_status ;;
    mobile-deploy)  bash "$SCRIPT_DIR/setup/scripts/mobile-deploy.sh" ;;
    mobile-collect) bash "$SCRIPT_DIR/setup/scripts/mobile-deploy.sh" --collect ;;
    *)
        echo "Usage: bash sync.sh {setup|deploy|collect|check|stamp|status|mobile-deploy|mobile-collect}"
        echo ""
        echo "  setup          — Replace live files with symlinks to repo (recommended, one-time)"
        echo "  deploy         — Copy from repo → live locations (for non-symlink setups)"
        echo "  collect        — Copy from live locations → repo (capture session edits)"
        echo "  check          — Check all propagation chains for drift/staleness"
        echo "  stamp          — Refresh all manifest hashes to current values (after template sync)"
        echo "  status         — Show differences between repo and live"
        echo "  mobile-deploy  — Generate/refresh the mobile agent-fleet repo"
        echo "  mobile-collect — Merge mobile outbox tasks into cross-project inbox"
        ;;
esac

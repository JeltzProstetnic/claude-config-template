#!/usr/bin/env bash
# mobile-deploy.sh — Generate or refresh the mobile agent-fleet repo
#
# Usage:
#   bash mobile-deploy.sh [--config-repo PATH] [--target PATH] [--home PATH]
#   bash mobile-deploy.sh --collect [--config-repo PATH] [--target PATH]
#
# Modes:
#   (default)   Generate/refresh the mobile repo with read-only context snapshots
#   --collect   Merge outbox tasks from mobile repo into the main cross-project inbox
#
# Options:
#   --config-repo PATH   Config repo root (default: auto-detect or ~/cfg-agent-fleet)
#   --target PATH        Mobile repo location (default: ~/agent-fleet-mobile)
#   --home PATH          Home directory for finding projects (default: $HOME)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────

MODE="deploy"
CONFIG_REPO=""
TARGET=""
USER_HOME=""

# ── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --collect)    MODE="collect"; shift ;;
        --config-repo) CONFIG_REPO="$2"; shift 2 ;;
        --target)     TARGET="$2"; shift 2 ;;
        --home)       USER_HOME="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Auto-detect config repo ─────────────────────────────────────────────────

if [[ -z "$CONFIG_REPO" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/../../sync.sh" ]]; then
        CONFIG_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
    else
        CONFIG_REPO="$HOME/cfg-agent-fleet"
    fi
fi

[[ -z "$TARGET" ]] && TARGET="${USER_HOME:-$HOME}/agent-fleet-mobile"
[[ -z "$USER_HOME" ]] && USER_HOME="$HOME"

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Freshness stamp ─────────────────────────────────────────────────────────

stamp_file() {
    local file="$1"
    local timestamp
    timestamp="$(date -u +'%Y-%m-%d %H:%M UTC')"
    local tmp="${file}.tmp.$$"
    echo "<!-- Snapshot: $timestamp -->" > "$tmp"
    cat "$file" >> "$tmp"
    mv "$tmp" "$file"
}

# ── COLLECT MODE ─────────────────────────────────────────────────────────────

cmd_collect() {
    local outbox="$TARGET/inbox/outbox.md"
    local inbox="$CONFIG_REPO/cross-project/inbox.md"

    if [[ ! -f "$outbox" ]]; then
        log_warn "No outbox found at $outbox"
        return 0
    fi

    # Extract task lines (- [ ] entries)
    local tasks
    tasks=$(grep '^\- \[ \]' "$outbox" 2>/dev/null || true)

    if [[ -z "$tasks" ]]; then
        log_info "Outbox is empty — nothing to collect"
        return 0
    fi

    # Append tasks to inbox
    echo "" >> "$inbox"
    echo "$tasks" >> "$inbox"
    local count
    count=$(echo "$tasks" | wc -l)
    log_info "Merged $count task(s) from outbox into inbox"

    # Reset outbox (keep header)
    cat > "$outbox" <<'OUTBOX'
# Mobile Outbox

Tasks posted here will be merged into the main cross-project inbox
when `sync.sh mobile-collect` runs on any full machine.

## Pending

OUTBOX
    log_info "Outbox cleared"
}

# ── DEPLOY MODE ──────────────────────────────────────────────────────────────

cmd_deploy() {
    log_info "Deploying mobile repo to $TARGET"

    # Create directory structure
    mkdir -p "$TARGET/context/project-summaries"
    mkdir -p "$TARGET/inbox"

    # Marker file
    echo "mobile-repo" > "$TARGET/.mobile-repo"

    # ── Copy context files ───────────────────────────────────────────────

    # Foundation files
    for f in user-profile.md personas.md; do
        local src="$CONFIG_REPO/global/foundation/$f"
        if [[ -f "$src" ]]; then
            cp "$src" "$TARGET/context/$f"
            stamp_file "$TARGET/context/$f"
            log_info "Copied: $f"
        fi
    done

    # Registry
    if [[ -f "$CONFIG_REPO/registry.md" ]]; then
        cp "$CONFIG_REPO/registry.md" "$TARGET/context/registry.md"
        stamp_file "$TARGET/context/registry.md"
        log_info "Copied: registry.md"
    fi

    # Dashboard cache
    if [[ -f "$CONFIG_REPO/cross-project/dashboard-cache.md" ]]; then
        cp "$CONFIG_REPO/cross-project/dashboard-cache.md" "$TARGET/context/dashboard-cache.md"
        stamp_file "$TARGET/context/dashboard-cache.md"
        log_info "Copied: dashboard-cache.md"
    fi

    # ── Generate machine index ───────────────────────────────────────────

    local machine_index="$TARGET/context/machine-index.md"
    echo "# Machine Index" > "$machine_index"
    echo "" >> "$machine_index"
    local machines_dir="$CONFIG_REPO/global/machines"
    if [[ -d "$machines_dir" ]]; then
        for mf in "$machines_dir"/*.md; do
            [[ -f "$mf" ]] || continue
            local base
            base=$(basename "$mf")
            [[ "$base" == _template.md ]] && continue
            local title
            title=$(head -3 "$mf" | grep -oP '(?<=# Machine: ).*' || echo "$base")
            echo "- **$title**: \`$base\`" >> "$machine_index"
        done
    fi
    stamp_file "$machine_index"
    log_info "Generated: machine-index.md"

    # ── Generate project summaries ───────────────────────────────────────

    # Parse registry for project paths
    if [[ -f "$CONFIG_REPO/registry.md" ]]; then
        while IFS='|' read -r _ name _ _ path _; do
            name=$(echo "$name" | xargs)
            path=$(echo "$path" | xargs | tr -d '`')
            [[ -z "$name" || "$name" == "Project" || "$name" == "---"* ]] && continue
            [[ -z "$path" ]] && continue

            # Expand ~ to user home
            path="${path/#\~/$USER_HOME}"
            [[ -d "$path" ]] || continue

            local summary="$TARGET/context/project-summaries/$name.md"
            echo "# $name" > "$summary"
            echo "" >> "$summary"

            # Session context (head 30 lines)
            if [[ -f "$path/session-context.md" ]]; then
                echo "## Session Context" >> "$summary"
                head -30 "$path/session-context.md" >> "$summary"
                echo "" >> "$summary"
            fi

            # Backlog (head 40 lines)
            if [[ -f "$path/backlog.md" ]]; then
                echo "## Backlog (top)" >> "$summary"
                head -40 "$path/backlog.md" >> "$summary"
                echo "" >> "$summary"
            fi

            log_info "Summary: $name"
        done < <(grep -E '^\|[^-]' "$CONFIG_REPO/registry.md" | grep -v 'Project.*Priority')
    fi

    # ── Outbox (create only if missing) ──────────────────────────────────

    if [[ ! -f "$TARGET/inbox/outbox.md" ]]; then
        cat > "$TARGET/inbox/outbox.md" <<'OUTBOX'
# Mobile Outbox

Tasks posted here will be merged into the main cross-project inbox
when `sync.sh mobile-collect` runs on any full machine.

## Pending

OUTBOX
        log_info "Created: outbox.md"
    else
        log_info "Preserved existing outbox.md"
    fi

    # ── CLAUDE.md ────────────────────────────────────────────────────────

    local claude_template="$CONFIG_REPO/setup/config/mobile-CLAUDE.md"
    if [[ -f "$claude_template" ]]; then
        cp "$claude_template" "$TARGET/CLAUDE.md"
        log_info "Deployed: CLAUDE.md"
    else
        log_warn "No mobile-CLAUDE.md template found — creating minimal"
        echo "# MOBILE MODE" > "$TARGET/CLAUDE.md"
        echo "You are in MOBILE MODE. Read context/ for project info. Write to inbox/outbox.md only." >> "$TARGET/CLAUDE.md"
    fi

    # ── Session context (minimal template) ───────────────────────────────

    cat > "$TARGET/session-context.md" <<'SC'
# Session Context

## Session Info
- **Last Updated**:
- **Machine**: mobile
- **Working Directory**: ~/agent-fleet-mobile
- **Session Goal**:

## Current State
- **Active Task**:
- **Progress** (use `- [x]` checkbox for each completed item):
- **Pending**:

## Key Decisions

## Recovery Instructions
SC

    log_info "Mobile repo deployed to $TARGET"
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "$MODE" in
    deploy)  cmd_deploy ;;
    collect) cmd_collect ;;
esac

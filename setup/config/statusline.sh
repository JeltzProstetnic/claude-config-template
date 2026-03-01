#!/bin/bash
# Context usage statusline for Claude Code
# Shows: [Model] ▓▓▓▓░░░░░░ 108k/200k (54%)
# Color: green <70%, yellow 70-89%, red 90%+
input=$(cat)
python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    model = d.get('model', {}).get('display_name', '?')
    cw = d.get('context_window') or {}
    pct = cw.get('used_percentage') or 0
    win_size = cw.get('context_window_size') or 200000
    cu = cw.get('current_usage') or {}
    # Real context = input_tokens + cache_creation + cache_read (not just input_tokens)
    input_tokens = (cu.get('input_tokens') or 0) + (cu.get('cache_creation_input_tokens') or 0) + (cu.get('cache_read_input_tokens') or 0)
    pct_int = int(pct)
    # Primary: derive from percentage (always correct). Token sum as cross-check only.
    used_k = int(win_size * pct / 100000)
    if used_k == 0 and input_tokens > 0:
        used_k = input_tokens // 1000
    total_k = win_size // 1000
    bar_w = 10
    filled = pct_int * bar_w // 100
    empty = bar_w - filled
    if pct_int >= 90:
        c = '\033[31m'
    elif pct_int >= 70:
        c = '\033[33m'
    else:
        c = '\033[32m'
    r = '\033[0m'
    bar = '\u2593' * filled + '\u2591' * empty
    sys.stdout.write(f'[{model}] {c}{bar} {used_k}k/{total_k}k ({pct_int}%){r}\n')
except Exception:
    sys.stdout.write('[?] ...\n')
" <<< "$input"

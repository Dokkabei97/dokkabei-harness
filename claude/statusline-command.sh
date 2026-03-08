#!/bin/bash

# Session start time tracking file
SESSION_FILE="/Users/jmk/.claude/statusline-session.txt"

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
session_id=$(echo "$input" | jq -r '.session_id // ""')
model_display=$(echo "$input" | jq -r '.model.display_name // "Claude"')
model_id=$(echo "$input" | jq -r '.model.id // ""')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // ""')
# Extract model name, version
# model_id examples: claude-opus-4-5, claude-sonnet-4-6, claude-haiku-3-5
model_name="Claude"
model_version=""
if echo "$model_display" | grep -qi "opus"; then
    model_name="Opus"
    model_color=$'\033[91m'  # Bright Red
elif echo "$model_display" | grep -qi "sonnet"; then
    model_name="Sonnet"
    model_color=$'\033[94m'  # Bright Blue
elif echo "$model_display" | grep -qi "haiku"; then
    model_name="Haiku"
    model_color=$'\033[32m'  # Green
else
    model_color=$'\033[37m'  # White
fi

# Extract version from model_id (e.g., claude-sonnet-4-6 -> 4.6, claude-opus-4-5 -> 4.5)
if [ -n "$model_id" ]; then
    # Match trailing digits pattern like -4-6 or -3-5 at end of model id
    raw_version=$(echo "$model_id" | grep -oE '[0-9]+-[0-9]+$')
    if [ -n "$raw_version" ]; then
        model_version=$(echo "$raw_version" | sed 's/-/./')
    fi
fi

# Build model label: "Sonnet 4.6 high" or "Opus 4.5 medium"
model_label="${model_name}"
[ -n "$model_version" ] && model_label="${model_label} ${model_version}"

# Append effort level only for non-Haiku models
if [ "$model_name" != "Haiku" ]; then
    effort=$(jq -r '.effortLevel // empty' /Users/jmk/.claude/settings.json 2>/dev/null)
    # Normalize effort: if empty, "default", or anything other than "high"/"low" -> "medium"
    if [ "$effort" = "high" ]; then
        effort_label="high"
    elif [ "$effort" = "low" ]; then
        effort_label="low"
    else
        effort_label="medium"
    fi
    model_label="${model_label} ${effort_label}"
fi

reset=$'\033[0m'
dim_gray=$'\033[90m'

# Get current folder name
folder_name=$(basename "$cwd")

# Get git branch and detect worktree
cd "$cwd" 2>/dev/null || cd "$HOME"
git_branch=""
is_worktree=0
main_repo_name=""
worktree_dir_name=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -c core.useBuiltinFSMonitor=false -c core.fsmonitor=false branch --show-current 2>/dev/null || echo "")

    # Detect if current directory is a linked worktree
    # Main worktree path is the first entry of `git worktree list`
    main_wt_path=$(git worktree list 2>/dev/null | head -1 | awk '{print $1}')
    current_toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$main_wt_path" ] && [ -n "$current_toplevel" ] && [ "$current_toplevel" != "$main_wt_path" ]; then
        is_worktree=1
        main_repo_name=$(basename "$main_wt_path")
        worktree_dir_name=$(basename "$current_toplevel")
    fi
fi

# Extract context window size and current input tokens
ctx_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
current_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')

# Format context window size (e.g., 200000 -> 200k, 1000000 -> 1m)
format_ctx_size() {
    local size=$1
    if [ "$size" -ge 1000000 ] 2>/dev/null; then
        echo "$(echo "scale=0; $size / 1000000" | bc)m"
    elif [ "$size" -ge 1000 ] 2>/dev/null; then
        echo "$(echo "scale=0; $size / 1000" | bc)k"
    else
        echo "${size}"
    fi
}

# Format token count in k (e.g., 40000 -> 40k, 15500 -> 15k)
format_tokens_k() {
    local tokens=$1
    if [ "$tokens" -ge 1000 ] 2>/dev/null; then
        echo "$(echo "scale=0; $tokens / 1000" | bc)k"
    else
        echo "${tokens}"
    fi
}

ctx_size_label=$(format_ctx_size "$ctx_window_size")

# Build context usage label: "40k/200k" or "200k"
if [ -n "$current_input" ] && [ "$current_input" -gt 0 ] 2>/dev/null; then
    used_label=$(format_tokens_k "$current_input")
    ctx_usage_label="${used_label}/${ctx_size_label}"
else
    ctx_usage_label="${ctx_size_label}"
fi

# Create progress bar: filled blocks + empty blocks
# Always show percentage; default to 0% when used_pct is absent (session start)
bar_width=10
used_int=$(printf "%.0f" "${used_pct:-0}" 2>/dev/null || echo "0")
filled=$(( used_int * bar_width / 100 ))
[ "$filled" -lt 0 ] && filled=0
[ "$filled" -gt "$bar_width" ] && filled=$bar_width
empty_chars=$(( bar_width - filled ))

# Color based on usage (green when 0% too)
if [ "$used_int" -lt 50 ]; then
    ctx_color=$'\033[32m'  # Green
elif [ "$used_int" -lt 75 ]; then
    ctx_color=$'\033[33m'  # Yellow
else
    ctx_color=$'\033[31m'  # Red
fi

bar_filled=""
bar_empty=""
for ((i=0; i<filled; i++)); do bar_filled="${bar_filled}█"; done
for ((i=0; i<empty_chars; i++)); do bar_empty="${bar_empty}░"; done

progress_bar=$(printf "${ctx_color}%s${dim_gray}%s${reset} ${used_int}%% | ${dim_gray}%s${reset}" "$bar_filled" "$bar_empty" "$ctx_usage_label")

# Line 1: Robot icon + Model | Progress bar | context usage
# U+1F916 ROBOT FACE in UTF-8: F0 9F A4 96
robot=$(printf '\xF0\x9F\xA4\x96')
line1=$(printf "%s ${model_color}%s${reset} | %s" "$robot" "$model_label" "$progress_bar")

# Icons for line 2
# U+1F4C1 OPEN FILE FOLDER in UTF-8: F0 9F 93 81
icon_dir=$(printf '\xF0\x9F\x93\x81')
# U+E0A0 POWERLINE BRANCH SYMBOL in UTF-8: EE 82 A0
icon_branch=$(printf '\xEE\x82\xA0')
# U+1F33F HERB (worktree) in UTF-8: F0 9F 8C BF
icon_worktree=$(printf '\xF0\x9F\x8C\xBF')

# Line 2: Directory | Git branch
# If in a linked worktree: show "📁 main-repo | 🌿 worktree-dir"
# Otherwise: show "📁 current-dir"
if [ "$is_worktree" -eq 1 ]; then
    line2=$(printf "%s %s | %s %s" "$icon_dir" "$main_repo_name" "$icon_worktree" "$worktree_dir_name")
else
    line2=$(printf "%s %s" "$icon_dir" "$folder_name")
fi
if [ -n "$git_branch" ]; then
    line2=$(printf "%s | %s %s" "$line2" "$icon_branch" "$git_branch")
fi

# Output both lines
printf "%s\n%s" "$line1" "$line2"

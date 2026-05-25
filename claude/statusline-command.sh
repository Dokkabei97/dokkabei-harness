#!/bin/bash

# Session start time tracking file
SESSION_FILE="${HOME}/.claude/statusline-session.txt"
USAGE_CACHE_FILE="${HOME}/.claude/statusline-usage-cache.json"
USAGE_CACHE_TTL=120  # seconds

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

# Extract version from model_id (e.g., claude-sonnet-4-6 -> 4.6, claude-haiku-4-5-20251001 -> 4.5)
if [ -n "$model_id" ]; then
    # Strip "claude-{name}-" prefix, then take first two number segments (major-minor)
    # This correctly handles date suffixes like claude-haiku-4-5-20251001 -> 4.5
    raw_version=$(echo "$model_id" | sed -E 's/^claude-[a-z]+-//' | grep -oE '^[0-9]+-[0-9]+')
    if [ -n "$raw_version" ]; then
        model_version=$(echo "$raw_version" | sed 's/-/./')
    fi
fi

# Build model label: "Sonnet 4.6 high" or "Opus 4.5 medium"
model_label="${model_name}"
[ -n "$model_version" ] && model_label="${model_label} ${model_version}"

# Append effort level only for non-Haiku models
# Source: settings.local.json → settings.json (persisted enum: low|medium|high|xhigh)
# Note: `/effort max` is session-only and Claude Code doesn't expose it to statusline.
if [ "$model_name" != "Haiku" ]; then
    effort=$(jq -r '.effortLevel // empty' ${HOME}/.claude/settings.local.json 2>/dev/null)
    [ -z "$effort" ] && effort=$(jq -r '.effortLevel // empty' ${HOME}/.claude/settings.json 2>/dev/null)
    [ -z "$effort" ] && effort=$([ "$model_name" = "Opus" ] && echo "xhigh" || echo "medium")

    case "$effort" in
        low|medium|high|xhigh) effort_label="$effort" ;;
        *)                     effort_label="medium" ;;
    esac
    model_label="${model_label} ${effort_label}"
fi

reset=$'\033[0m'
dim_gray=$'\033[90m'
bright_white=$'\033[97m'
bright_yellow=$'\033[93m'
bright_green=$'\033[92m'
bright_red=$'\033[91m'
bright_blue=$'\033[94m'
bright_cyan=$'\033[96m'
bold_red=$'\033[1;31m'

# === Usage API (5h/7d rate limits) with file-based caching ===
refresh_usage_cache() {
    local now=$(date +%s)
    local creds
    creds=$(/usr/bin/security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    [ -z "$creds" ] && return 1

    local token
    token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [ -z "$token" ] && return 1

    local response
    response=$(curl -s --max-time 3 \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    [ -z "$response" ] && return 1

    local five_hour seven_day
    five_hour=$(echo "$response" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    seven_day=$(echo "$response" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    [ -z "$five_hour" ] && return 1

    local five_hour_reset seven_day_reset
    five_hour_reset=$(echo "$response" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    seven_day_reset=$(echo "$response" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)

    printf '{"timestamp":%d,"five_hour":%s,"seven_day":%s,"five_hour_reset":"%s","seven_day_reset":"%s"}\n' \
        "$now" "$five_hour" "$seven_day" "$five_hour_reset" "$seven_day_reset" > "$USAGE_CACHE_FILE"
}

get_usage() {
    local now=$(date +%s)
    local need_refresh=1

    if [ -f "$USAGE_CACHE_FILE" ]; then
        local cache_time
        cache_time=$(jq -r '.timestamp // 0' "$USAGE_CACHE_FILE" 2>/dev/null)
        local age=$(( now - cache_time ))
        [ "$age" -lt "$USAGE_CACHE_TTL" ] && need_refresh=0
    fi

    [ "$need_refresh" -eq 1 ] && refresh_usage_cache

    if [ -f "$USAGE_CACHE_FILE" ]; then
        cat "$USAGE_CACHE_FILE"
    else
        echo '{}'
    fi
}

usage_json=$(get_usage)
five_hour=$(echo "$usage_json" | jq -r '.five_hour // "-"' 2>/dev/null)
seven_day=$(echo "$usage_json" | jq -r '.seven_day // "-"' 2>/dev/null)
five_hour_reset=$(echo "$usage_json" | jq -r '.five_hour_reset // ""' 2>/dev/null)
seven_day_reset=$(echo "$usage_json" | jq -r '.seven_day_reset // ""' 2>/dev/null)

# Format ISO 8601 reset time as absolute local time (e.g., "14:30", "3/9 14:30")
format_reset_time() {
    local reset_at=$1
    [ -z "$reset_at" ] || [ "$reset_at" = "null" ] || [ "$reset_at" = "" ] && return

    # Strip fractional seconds and timezone suffix, parse as UTC
    local clean=$(echo "$reset_at" | sed -E 's/\.[0-9]+(Z|\+[0-9:]+)$//' | sed 's/Z$//' | sed 's/+00:00$//')
    local reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null)
    [ -z "$reset_epoch" ] && return

    local now=$(date +%s)
    [ "$reset_epoch" -le "$now" ] && printf "now" && return

    # Compare dates: if same day, show only HH:MM; otherwise show M/D HH:MM
    local today=$(date +%Y%m%d)
    local reset_day=$(date -r "$reset_epoch" +%Y%m%d)

    if [ "$today" = "$reset_day" ]; then
        date -r "$reset_epoch" "+%H:%M"
    else
        date -r "$reset_epoch" "+%-m/%-d %H:%M"
    fi
}

# Build a colored progress bar for usage (same style as context bar)
make_usage_bar() {
    local label=$1
    local val=$2
    local reset_at=$3
    local bw=10

    local int_val=0
    if [ "$val" != "-" ] && [ "$val" != "null" ]; then
        int_val=$(printf "%.0f" "$val" 2>/dev/null || echo "0")
    fi

    # Color based on usage
    local bar_color
    if [ "$int_val" -lt 50 ]; then
        bar_color=$'\033[32m'  # Green
    elif [ "$int_val" -lt 80 ]; then
        bar_color=$'\033[33m'  # Yellow
    else
        bar_color=$'\033[31m'  # Red
    fi

    local f=$(( int_val * bw / 100 ))
    [ "$f" -lt 0 ] && f=0
    [ "$f" -gt "$bw" ] && f=$bw
    local e=$(( bw - f ))

    local bar_f="" bar_e=""
    for ((i=0; i<f; i++)); do bar_f="${bar_f}█"; done
    for ((i=0; i<e; i++)); do bar_e="${bar_e}░"; done

    local reset_label=""
    if [ -n "$reset_at" ] && [ "$reset_at" != "null" ]; then
        local rt=$(format_reset_time "$reset_at")
        [ -n "$rt" ] && reset_label=$(printf " ${bright_white}(%s)${reset}" "$rt")
    fi

    printf "${bright_white}%s${reset} ${bar_color}%s${dim_gray}%s${reset} ${bright_white}%d%%${reset}%s" \
        "$label" "$bar_f" "$bar_e" "$int_val" "$reset_label"
}

five_hour_bar=$(make_usage_bar "5h" "$five_hour" "$five_hour_reset")
seven_day_bar=$(make_usage_bar "7d" "$seven_day" "$seven_day_reset")

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

progress_bar=$(printf "${bright_white}Context${reset} ${ctx_color}%s${dim_gray}%s${reset} ${bright_white}${used_int}%%${reset} | ${bright_white}%s${reset}" "$bar_filled" "$bar_empty" "$ctx_usage_label")

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
    line2=$(printf "%s ${bright_yellow}%s${reset} | %s ${bright_green}%s${reset}" "$icon_dir" "$main_repo_name" "$icon_worktree" "$worktree_dir_name")
else
    line2=$(printf "%s ${bright_yellow}%s${reset}" "$icon_dir" "$folder_name")
fi
if [ -n "$git_branch" ]; then
    # Color branch by type
    branch_color="$bright_white"
    if [ "$git_branch" = "master" ] || [ "$git_branch" = "main" ]; then
        branch_color="$bright_red"
    elif echo "$git_branch" | grep -q "^develop"; then
        branch_color="$bright_blue"
    elif echo "$git_branch" | grep -q "^feat" || echo "$git_branch" | grep -q "^feature"; then
        branch_color="$bright_cyan"
    elif echo "$git_branch" | grep -q "^release"; then
        branch_color="$bright_yellow"
    elif echo "$git_branch" | grep -q "^hotfix"; then
        branch_color="$bold_red"
    elif [ "$is_worktree" -eq 1 ]; then
        branch_color="$bright_green"
    fi
    line2=$(printf "%s | %s ${branch_color}%s${reset}" "$line2" "$icon_branch" "$git_branch")

    # Git file change stats (added/modified/deleted)
    git_status=$(git -c core.useBuiltinFSMonitor=false -c core.fsmonitor=false status --porcelain 2>/dev/null)
    if [ -n "$git_status" ]; then
        added=$(echo "$git_status" | grep -c '^??\|^A \|^A[MD]')
        modified=$(echo "$git_status" | grep -c '^ M\|^M \|^MM\|^AM\|^R ')
        deleted=$(echo "$git_status" | grep -c '^ D\|^D \|^MD')

        git_changes=""
        [ "$added" -gt 0 ] && git_changes="${git_changes} ${bright_green}+${added}${reset}"
        [ "$modified" -gt 0 ] && git_changes="${git_changes} ${bright_yellow}~${modified}${reset}"
        [ "$deleted" -gt 0 ] && git_changes="${git_changes} ${bright_red}-${deleted}${reset}"
        [ -n "$git_changes" ] && line2=$(printf "%s |%s" "$line2" "$git_changes")
    fi
fi

# Append session id at the end of line 2
if [ -n "$session_id" ]; then
    sid_short="${session_id:0:8}"
    line2=$(printf "%s | ${bright_white}Session: %s${reset}" "$line2" "$sid_short")
fi

# Append usage bars to line 1
line1=$(printf "%s | ${bright_white}Usage${reset} %s | %s" "$line1" "$five_hour_bar" "$seven_day_bar")

# Output both lines
printf "%s\n%s" "$line1" "$line2"

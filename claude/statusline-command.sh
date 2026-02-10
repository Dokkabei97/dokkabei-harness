#!/bin/bash

# Session start time tracking file
SESSION_FILE="/Users/admin/.claude/statusline-session.txt"

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

# Extract model name without version (e.g., "Claude 3.5 Sonnet" -> "Sonnet")
model_name="Claude"
if echo "$model_display" | grep -qi "opus"; then
    model_name="Opus"
    model_color="\033[31m"  # Red
elif echo "$model_display" | grep -qi "sonnet"; then
    model_name="Sonnet"
    model_color="\033[34m"  # Blue
elif echo "$model_display" | grep -qi "haiku"; then
    model_name="Haiku"
    model_color="\033[32m"  # Green
else
    model_color="\033[37m"  # White
fi
reset="\033[0m"

# Icons
brain_icon="🧠"
folder_icon="📁"
git_icon="🌿"
context_icon="📊"
cost_icon="💰"
clock_icon="⏰"

# Get current folder name
folder_name=$(basename "$cwd")

# Get git branch
cd "$cwd" 2>/dev/null || cd "$HOME"
git_branch=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -c core.useBuiltinFSMonitor=false -c core.fsmonitor=false branch --show-current 2>/dev/null || echo "")
fi

# First line: 🧠 Model | 📁 Folder | 🌿 Git branch
line1=$(printf "%s ${model_color}%s${reset} | %s %s" "$brain_icon" "$model_name" "$folder_icon" "$folder_name")
if [ -n "$git_branch" ]; then
    line1=$(printf "%s | %s %s" "$line1" "$git_icon" "$git_branch")
fi

# Create progress bar for context usage
progress_bar=""
if [ -n "$used_pct" ]; then
    # Calculate filled portion (out of 20 characters)
    filled=$(echo "scale=0; $used_pct / 5" | bc 2>/dev/null || echo "0")
    empty=$((20 - filled))

    bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done

    # Color based on usage (reverse of remaining)
    if (( $(echo "$used_pct < 50" | bc -l 2>/dev/null || echo "0") )); then
        ctx_color="\033[32m"  # Green
    elif (( $(echo "$used_pct < 75" | bc -l 2>/dev/null || echo "0") )); then
        ctx_color="\033[33m"  # Yellow
    else
        ctx_color="\033[31m"  # Red
    fi

    progress_bar=$(printf "%s ${ctx_color}[%s] %.1f%%${reset}" "$context_icon" "$bar" "$used_pct")
fi

# Calculate cost (approximate pricing for Claude models)
input_cost=$(echo "scale=4; $total_input * 3 / 1000000" | bc 2>/dev/null || echo "0")
output_cost=$(echo "scale=4; $total_output * 15 / 1000000" | bc 2>/dev/null || echo "0")
total_cost=$(echo "scale=2; $input_cost + $output_cost" | bc 2>/dev/null || echo "0")
cost_display=$(printf "%s \$%.2f" "$cost_icon" "$total_cost")

# Session elapsed time tracking
session_time="0s"
current_time=$(date +%s)

if [ -n "$session_id" ]; then
    # Check if session file exists and matches current session
    if [ -f "$SESSION_FILE" ]; then
        stored_session=$(head -n 1 "$SESSION_FILE" 2>/dev/null)
        stored_start_time=$(tail -n 1 "$SESSION_FILE" 2>/dev/null)

        if [ "$stored_session" = "$session_id" ] && [ -n "$stored_start_time" ]; then
            # Same session, calculate elapsed time
            start_time="$stored_start_time"
        else
            # New session, reset start time
            start_time="$current_time"
            echo "$session_id" > "$SESSION_FILE"
            echo "$start_time" >> "$SESSION_FILE"
        fi
    else
        # First run, create session file
        start_time="$current_time"
        echo "$session_id" > "$SESSION_FILE"
        echo "$start_time" >> "$SESSION_FILE"
    fi

    # Calculate elapsed time
    elapsed=$((current_time - start_time))

    hours=$((elapsed / 3600))
    minutes=$(((elapsed % 3600) / 60))
    seconds=$((elapsed % 60))

    if [ $hours -gt 0 ]; then
        session_time=$(printf "%dh %dm %ds" $hours $minutes $seconds)
    elif [ $minutes -gt 0 ]; then
        session_time=$(printf "%dm %ds" $minutes $seconds)
    else
        session_time=$(printf "%ds" $seconds)
    fi
fi

# Second line: 📊 Context bar | 💰 Cost | ⏰ Elapsed time
line2=""
if [ -n "$progress_bar" ]; then
    line2="$progress_bar"
fi
if [ -n "$total_cost" ] && [ "$total_cost" != "0" ] && [ "$total_cost" != "0.00" ]; then
    if [ -n "$line2" ]; then
        line2="$line2 | $cost_display"
    else
        line2="$cost_display"
    fi
fi
line2="$line2 | $clock_icon $session_time"

# Output both lines
printf "%s\n%s" "$line1" "$line2"

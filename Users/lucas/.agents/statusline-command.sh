#!/usr/bin/env bash
status_input=$(cat)

# ANSI color helpers (use $'...' so the ESC byte is stored, not literal \033)
color_reset=$'\033[0m'
color_dim=$'\033[2m'
color_bold=$'\033[1m'
color_cyan=$'\033[36m'
color_magenta=$'\033[35m'
color_yellow=$'\033[33m'
color_red=$'\033[31m'
color_green=$'\033[32m'
color_dim_cyan=$'\033[2;36m'
color_dim_white=$'\033[2;37m'

model_name=$(echo "$status_input" | jq -r '.model.display_name // empty')
effort_level=$(jq -r '.effortLevel // empty' ~/.agents/settings.json 2>/dev/null)
current_directory=$(echo "$status_input" | jq -r '.workspace.current_dir // .cwd // empty')
git_branch=$(git -C "$current_directory" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
  || git -C "$current_directory" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
context_used_percentage=$(echo "$status_input" | jq -r '.context_window.used_percentage // empty')
context_window_size=$(echo "$status_input" | jq -r '.context_window.context_window_size // empty')
five_hour_used_percentage=$(echo "$status_input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets_at=$(echo "$status_input" | jq -r '.rate_limits.five_hour.resets_at // empty')
weekly_used_percentage=$(echo "$status_input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Choose a color for a percentage value: green < 60, yellow < 80, red >= 80
percentage_color() {
  local percentage
  percentage=$(printf '%.0f' "$1")
  if [ "$percentage" -ge 80 ]; then
    printf '%s' "$color_red"
  elif [ "$percentage" -ge 60 ]; then
    printf '%s' "$color_yellow"
  else
    printf '%s' "$color_green"
  fi
}

# Choose a color for the effort level
effort_level_color() {
  case "$1" in
    xhigh|max) printf '%s' "$color_red" ;;
    high)      printf '%s' "$color_yellow" ;;
    *)         printf '%s' "$color_green" ;;
  esac
}

# Separator used between segments on the same line
segment_separator="${color_dim_white} · ${color_reset}"

line1_segments=()

if [ -n "$model_name" ]; then
  line1_segments+=("$(printf "${color_cyan}%s${color_reset}" "$model_name")")
fi

if [ -n "$effort_level" ]; then
  effort_color=$(effort_level_color "$effort_level")
  line1_segments+=("$(printf "${effort_color}%s${color_reset}" "$effort_level")")
fi

if [ -n "$context_used_percentage" ]; then
  context_color=$(percentage_color "$context_used_percentage")
  context_segment="$(printf "${color_dim}context:${color_reset} ${context_color}$(printf '%.0f' "$context_used_percentage")%%${color_reset}")"
  if [ -n "$context_window_size" ]; then
    context_window_kilo=$((context_window_size / 1000))
    context_segment="${context_segment}$(printf "${color_dim} / ${context_window_kilo}K${color_reset}")"
  fi
  line1_segments+=("$context_segment")
fi

if [ -n "$five_hour_used_percentage" ]; then
  five_hour_color=$(percentage_color "$five_hour_used_percentage")
  five_hour_segment="$(printf "${color_dim}5h limit:${color_reset} ${five_hour_color}$(printf '%.0f' "$five_hour_used_percentage")%%${color_reset}")"
  if [ -n "$five_hour_resets_at" ]; then
    five_hour_reset_time=$(date -r "$five_hour_resets_at" +"%I%p" 2>/dev/null | sed 's/^0//')
    if [ -n "$five_hour_reset_time" ]; then
      now_epoch=$(date +%s)
      secs_remaining=$(( five_hour_resets_at - now_epoch ))
      if [ "$secs_remaining" -gt 0 ]; then
        remaining_hh=$(( secs_remaining / 3600 ))
        remaining_mm=$(( (secs_remaining % 3600) / 60 ))
        if [ "$remaining_hh" -gt 0 ]; then
          remaining_fmt=$(printf '%dh %dmin' "$remaining_hh" "$remaining_mm")
        else
          remaining_fmt=$(printf '%dmin' "$remaining_mm")
        fi
        five_hour_segment="${five_hour_segment}$(printf "${color_dim} (resets in ${color_reset}${color_green}%s at %s${color_reset}${color_dim})${color_reset}" "$remaining_fmt" "$five_hour_reset_time")"
      else
        five_hour_segment="${five_hour_segment}$(printf "${color_dim} (resets at ${color_reset}${color_green}%s${color_reset}${color_dim})${color_reset}" "$five_hour_reset_time")"
      fi
    fi
  fi
  line1_segments+=("$five_hour_segment")
fi

if [ -n "$weekly_used_percentage" ]; then
  weekly_color=$(percentage_color "$weekly_used_percentage")
  weekly_segment="$(printf "${color_dim}weekly limit:${color_reset} ${weekly_color}$(printf '%.0f' "$weekly_used_percentage")%%${color_reset}")"
  weekly_resets_at=$(echo "$status_input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  if [ -n "$weekly_resets_at" ]; then
    weekly_reset_fmt=$(date -r "$weekly_resets_at" +"%a %I%p" 2>/dev/null | sed 's/ 0/ /')
    if [ -n "$weekly_reset_fmt" ]; then
      now_epoch=$(date +%s)
      weekly_secs_remaining=$(( weekly_resets_at - now_epoch ))
      if [ "$weekly_secs_remaining" -gt 0 ]; then
        weekly_remaining_dd=$(( weekly_secs_remaining / 86400 ))
        weekly_remaining_hh=$(( (weekly_secs_remaining % 86400) / 3600 ))
        weekly_remaining_mm=$(( (weekly_secs_remaining % 3600) / 60 ))
        if [ "$weekly_remaining_dd" -eq 1 ]; then
          weekly_remaining_fmt="1 day"
        elif [ "$weekly_remaining_dd" -gt 1 ]; then
          weekly_remaining_fmt=$(printf '%d days' "$weekly_remaining_dd")
        elif [ "$weekly_remaining_hh" -gt 0 ]; then
          weekly_remaining_fmt=$(printf '%dh %dmin' "$weekly_remaining_hh" "$weekly_remaining_mm")
        else
          weekly_remaining_fmt=$(printf '%dmin' "$weekly_remaining_mm")
        fi
        weekly_segment="${weekly_segment}$(printf "${color_dim} (resets in ${color_reset}${color_green}%s on %s${color_reset}${color_dim})${color_reset}" "$weekly_remaining_fmt" "$weekly_reset_fmt")"
      else
        weekly_segment="${weekly_segment}$(printf "${color_dim} (resets on ${color_reset}${color_green}%s${color_reset}${color_dim})${color_reset}" "$weekly_reset_fmt")"
      fi
    fi
  fi
  line1_segments+=("$weekly_segment")
fi

line2_segments=()
project_directory=$(echo "$status_input" | jq -r '.workspace.project_dir // empty')

if [ -n "$project_directory" ] && [ -n "$git_branch" ]; then
  project_directory_display="${project_directory/#$HOME/\~}"
  line2_segments+=("$(printf "${color_dim}root:${color_reset} ${color_cyan}%s${color_reset}" "$project_directory_display")")
  line2_segments+=("$(printf "${color_dim}branch:${color_reset} ${color_magenta}%s${color_reset}" "$git_branch")")
  if [ -n "$current_directory" ] && [ "$current_directory" != "$project_directory" ]; then
    relative_directory="${current_directory#$project_directory/}"
    line2_segments+=("$(printf "${color_dim}current:${color_reset} ${color_cyan}%s${color_reset}" "$relative_directory")")
  fi
elif [ -n "$current_directory" ]; then
  current_directory_display="${current_directory/#$HOME/\~}"
  line2_segments+=("$(printf "${color_dim}root:${color_reset} ${color_cyan}%s${color_reset}" "$current_directory_display")")
  [ -n "$git_branch" ] && line2_segments+=("$(printf "${color_dim}branch:${color_reset} ${color_magenta}%s${color_reset}" "$git_branch")")
fi

join_segments() {
  local joined=""
  for segment in "$@"; do
    if [ -n "$joined" ]; then
      joined="${joined}${segment_separator}${segment}"
    else
      joined="$segment"
    fi
  done
  printf '%s' "$joined"
}

line1_output=$(join_segments "${line1_segments[@]}")
line2_output=$(join_segments "${line2_segments[@]}")
printf '%s\n%s\n' "$line1_output" "$line2_output"

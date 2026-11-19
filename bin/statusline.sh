#!/bin/bash
# claude-statusline (https://github.com/rushi-me/claude-statusline)
set -f

# Read stdin with a builtin (no `cat` fork).
IFS= read -r -d '' input

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
# These set a variable instead of printing, so callers avoid $(...) subshells.

# Sets pct_color for a percentage.
set_pct_color() {
    if [ "$1" -ge 90 ]; then pct_color="$red"
    elif [ "$1" -ge 70 ]; then pct_color="$yellow"
    elif [ "$1" -ge 50 ]; then pct_color="$orange"
    else pct_color="$green"
    fi
}

# Sets bar to a coloured ●○ bar for a percentage and width.
set_bar() {
    local pct=$1 width=$2 i filled_str="" empty_str=""
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( pct * width / 100 ))
    set_pct_color "$pct"
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=filled; i<width; i++)); do empty_str+="○"; done
    bar="${pct_color}${filled_str}${dim}${empty_str}${reset}"
}

# ── Shared jq helpers (formatting happens in jq, not date/awk/sed) ──
jq_defs='
def num: if type == "number" then . elif type == "string" then (tonumber? // null) else null end;
def round0: num | if . == null then "" else (round | tostring) end;
def money: num // 0 | (. * 100 | round) as $c
    | "\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)";
def tokens: num // 0 |
    if . >= 1000000 then ((. / 100000 | round) / 10 | tostring) + "M"
    elif . >= 1000 then "\(. / 1000 + 0.5 | floor)k"
    else tostring end;
def clock: strflocaltime("%l:%M%p") | ltrimstr(" ") | ascii_downcase;
def dayclock: strflocaltime("%b %e, %l:%M%p") | gsub(" +"; " ") | ltrimstr(" ") | ascii_downcase;
def left($now): (. - $now | floor) as $l |
    if $l <= 0 then "now"
    elif $l >= 86400 then "\($l / 86400 | floor)d \($l % 86400 / 3600 | floor)h"
    elif $l >= 3600 then "\($l / 3600 | floor)h \($l % 3600 / 60 | floor)m"
    elif $l >= 60 then "\($l / 60 | floor)m"
    else "<1m" end;
def reset_fields($p; $style; $now): num as $e |
    if $e == null or $e == 0 then {("\($p)_reset_epoch"): "", ("\($p)_reset"): "", ("\($p)_left"): ""}
    else {("\($p)_reset_epoch"): ($e | floor | tostring),
          ("\($p)_reset"): ($e | if $style == "time" then clock else dayclock end),
          ("\($p)_left"): ($e | left($now))} end;
def emit: to_entries[] | "\(.key)=\(.value // "" | tostring | @sh)";
'

# ── Extract everything from stdin in one jq call ────────
eval "$(printf '%s' "$input" | jq -r "$jq_defs"'
    (now | floor) as $now
    | (.context_window.context_window_size | num // 200000 | if . == 0 then 200000 else . end) as $size
    | (.context_window.total_input_tokens | num // 0) as $current
    | (.cost.total_duration_ms | num) as $ms
    | (.rate_limits // {}) as $rl
    | {
        now: $now,
        model_name: (.model.display_name // "Claude"),
        current_fmt: ($current | tokens),
        size_fmt: ($size | tokens),
        pct_used: (.context_window.used_percentage | round0
                   | if . == "" then ($current * 100 / $size | floor | tostring) else . end),
        cost_usd: (.cost.total_cost_usd | money),
        effort: (.effort.level // ""),
        session_id: (.session_id // ""),
        cwd: (.workspace.current_dir // .cwd // ""),
        project_dir: (.workspace.project_dir // ""),
        worktree_name: (.workspace.git_worktree // .worktree.name // ""),
        added_dirs: (.workspace.added_dirs // [] | length),
        session_duration: (if $ms == null then "" else ($ms / 1000 | floor) as $s |
            if $s >= 3600 then "\($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
            elif $s >= 60 then "\($s / 60 | floor)m"
            else "\($s)s" end end),
        cc_version: (.version // "2.1.34"),
        has_stdin_rates: (if ($rl.five_hour.used_percentage | num) != null then "true" else "false" end),
        five_hour_pct: ($rl.five_hour.used_percentage | round0),
        seven_day_pct: ($rl.seven_day.used_percentage | round0),
        spend_pct: ($rl.spend_limit.used_percentage | round0),
        spend_used: (if ($rl.spend_limit.used_usd | num) == null then "" else ($rl.spend_limit.used_usd | money) end),
        spend_limit: (if ($rl.spend_limit.limit_usd | num) == null then "" else ($rl.spend_limit.limit_usd | money) end)
      }
      + ($rl.five_hour.resets_at | reset_fields("five_hour"; "time"; $now))
      + ($rl.seven_day.resets_at | reset_fields("seven_day"; "datetime"; $now))
    | emit
' 2>/dev/null)"

if [ -z "$effort" ]; then
    settings_path="$HOME/.claude/settings.json"
    [ -f "$settings_path" ] && effort=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
fi

# ── LINE 1: Model │ Context (cost) │ Directory (branch) │ Session │ Effort ──
set_pct_color "${pct_used:-0}"
context_color="$pct_color"
[ -z "$cwd" ] && cwd=$PWD

# Physical paths (builtin cd -P, no subshell), so they compare cleanly with git's
# paths (e.g. /tmp vs /private/tmp).
real_cwd="$cwd"
cd -P "$cwd" 2>/dev/null && real_cwd=$PWD
real_project="$project_dir"
[ -n "$project_dir" ] && cd -P "$project_dir" 2>/dev/null && real_project=$PWD

# ── Git: two calls, cached for 5s per session ───────────
# Cache file lines: timestamp, cwd, toplevel, common dir, branch, short sha, dirty.
git_top="" git_common="" git_head="" git_sha="" git_dirty=""
cache_dir="${TMPDIR:-/tmp}"
cache_dir="${cache_dir%/}/claude-statusline-${UID}"
git_cache=""
[ -n "$session_id" ] && git_cache="$cache_dir/git-${session_id//[^A-Za-z0-9_-]/}"
git_fresh=false
if [ -n "$git_cache" ] && [ -f "$git_cache" ]; then
    {
        IFS= read -r c_ts; IFS= read -r c_cwd; IFS= read -r git_top; IFS= read -r git_common
        IFS= read -r git_head; IFS= read -r git_sha; IFS= read -r git_dirty
    } < "$git_cache"
    if [ "$c_cwd" = "$cwd" ] && [ "$c_ts" -ge $(( now - 5 )) ] 2>/dev/null; then
        git_fresh=true
    fi
fi
if ! $git_fresh; then
    git_top="" git_common="" git_head="" git_sha="" git_dirty=""
    git_info=$(git -C "$cwd" rev-parse --show-toplevel --git-common-dir 2>/dev/null)
    if [ -n "$git_info" ]; then
        git_top="${git_info%%$'\n'*}"
        git_common="${git_info#*$'\n'}"
        while IFS= read -r l; do
            case "$l" in
                "# branch.oid "*)  git_sha="${l#\# branch.oid }"; git_sha="${git_sha:0:7}" ;;
                "# branch.head "*) git_head="${l#\# branch.head }" ;;
                "#"*) ;;
                ?*) git_dirty="*" ;;
            esac
        done <<< "$(git -C "$cwd" --no-optional-locks status --porcelain=v2 -b 2>/dev/null)"
    fi
    if [ -n "$git_cache" ]; then
        [ -d "$cache_dir" ] || mkdir -p -m 700 "$cache_dir" 2>/dev/null
        printf '%s\n' "$now" "$cwd" "$git_top" "$git_common" "$git_head" "$git_sha" "$git_dirty" \
            > "$git_cache" 2>/dev/null
    fi
fi

# Directory label: repo root plus path inside it, e.g. repo, repo/bin, repo/…/tasks/graph
dir_label="${cwd%/}"
dir_label="${dir_label##*/}"
git_branch=""
if [ -n "$git_top" ]; then
    case "$git_common" in /*) ;; *) git_common="$git_top/$git_common" ;; esac
    if [ -n "$worktree_name" ]; then
        # Linked worktree: name the main repo, not the worktree folder.
        repo_name="${git_common%/*}"
        repo_name="${repo_name##*/}"
    else
        repo_name="${git_top##*/}"
    fi

    rel="${real_cwd#"$git_top"}"
    rel="${rel#/}"
    [ "$rel" = "$real_cwd" ] && rel=""
    dir_label="$repo_name"
    [ -n "$worktree_name" ] && dir_label+=" ⎇ ${worktree_name}"
    if [ -n "$rel" ]; then
        IFS='/' read -r -a parts <<< "$rel"
        if [ "${#parts[@]}" -gt 2 ]; then
            dir_label+="/…/${parts[${#parts[@]}-2]}/${parts[${#parts[@]}-1]}"
        else
            dir_label+="/$rel"
        fi
    fi

    if [ -z "$git_head" ] || [ "$git_head" = "(detached)" ]; then
        # Detached HEAD (rebase, bisect, tag checkout): show the commit instead.
        [ -n "$git_sha" ] && [ "$git_sha" != "(initial" ] && git_branch="@${git_sha}"
    elif [[ "$git_head" == */* ]]; then
        # Drop prefixes like user/ or feature/: keep the last part.
        git_branch="…/${git_head##*/}"
    else
        git_branch="$git_head"
    fi
    if [ ${#git_branch} -gt 30 ]; then
        git_branch="${git_branch:0:29}…"
    fi
fi

# Launched elsewhere: show where, unless we're still inside the launch directory.
drift=""
if [ -n "$project_dir" ]; then
    case "$real_cwd/" in
        "$real_project"/*) ;;
        *) drift="${project_dir%/}"; drift="${drift##*/}" ;;
    esac
fi

line1="${blue}${model_name}${reset}"
line1+="${sep}"
# Token icon blinks: one frame per second, driven by statusLine.refreshInterval.
# Empty and filled circle alternate, both single-width glyphs.
spinner_frames=('○' '●')
token_icon="${spinner_frames[${now:-0} % ${#spinner_frames[@]}]}"
line1+="${context_color}${token_icon} ${current_fmt}${dim}/${reset}${white}${size_fmt}${reset} ${dim}(${reset}${yellow}~\$${cost_usd}${reset}${dim})${reset}"
line1+="${sep}"
line1+="${cyan}${dir_label}${reset}"
if [ -n "$git_branch" ]; then
    line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
fi
[ -n "$drift" ] && line1+=" ${dim}‹ ${drift}${reset}"
[ "$added_dirs" -gt 0 ] 2>/dev/null && line1+=" ${dim}+${added_dirs}${reset}"
if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
fi

# Effort as a 4-cell meter: low=1, medium=2, high=3, xhigh/max=4. Hidden when unknown.
# xhigh and max fill every cell and differ by colour: a cool violet→pink gradient
# for xhigh, a hot pink→amber gradient for max.
effort_cells=0
case "$effort" in
    low) effort_cells=1 ;; medium) effort_cells=2 ;; high) effort_cells=3 ;;
    xhigh|max) effort_cells=4 ;;
esac
if [ "$effort_cells" -gt 0 ]; then
    effort_meter=""
    case "$effort" in
        xhigh)
            effort_gradient=('140;110;255' '170;110;245' '200;105;230' '230;100;210') ;;
        max)
            effort_gradient=('235;90;200' '250;95;140' '255;125;80' '255;175;50') ;;
        *)
            effort_gradient=() ;;
    esac
    if [ "${#effort_gradient[@]}" -gt 0 ]; then
        for c in "${effort_gradient[@]}"; do effort_meter+="\033[38;2;${c}m▮"; done
        effort_label="\033[1;38;2;${effort_gradient[3]}m${effort}${reset}"
        effort_meter+="${reset}"
    else
        case "$effort" in
            high)   effort_color="$magenta" ;;
            medium) effort_color='\033[38;2;120;190;255m' ;;  # sky blue
            *)      effort_color="$dim" ;;
        esac
        effort_meter="${effort_color}"
        for ((i=0; i<effort_cells; i++)); do effort_meter+="▮"; done
        effort_meter+="${reset}${dim}"
        for ((i=effort_cells; i<4; i++)); do effort_meter+="▯"; done
        effort_meter+="${reset}"
        effort_label="${effort_color}${effort}${reset}"
    fi
    line1+="${sep}"
    line1+="${effort_meter} ${effort_label}"
fi

# ── Fallback: API call (cached) ────────────────────────
cache_file="/tmp/claude/statusline-usage-cache.json"
# Touched on every refresh attempt, successful or not. Throttling on the attempt
# (not the cache) stops a failing API from being retried on every 1s render.
attempt_file="/tmp/claude/statusline-usage-attempt"
cache_max_age=60
[ -d /tmp/claude ] || mkdir -p /tmp/claude

needs_refresh=true
if [ -f "$attempt_file" ]; then
    attempt_mtime=$(stat -c %Y "$attempt_file" 2>/dev/null || stat -f %m "$attempt_file" 2>/dev/null)
    [ $(( now - ${attempt_mtime:-0} )) -lt "$cache_max_age" ] && needs_refresh=false
fi

if $needs_refresh; then
    : > "$attempt_file" 2>/dev/null
    token=""
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        token="$CLAUDE_CODE_OAUTH_TOKEN"
    elif command -v security >/dev/null 2>&1; then
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        [ -n "$blob" ] && token=$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        creds_file="${HOME}/.claude/.credentials.json"
        [ -f "$creds_file" ] && token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
    fi
    if { [ -z "$token" ] || [ "$token" = "null" ]; } && command -v secret-tool >/dev/null 2>&1; then
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        [ -n "$blob" ] && token=$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi

    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/${cc_version}" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && printf '%s' "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            printf '%s\n' "$response" > "$cache_file"
        fi
    fi
fi

# Read the cached usage response in one jq call. Its rate limits are used only when
# stdin had none; extra usage always comes from here.
extra_enabled="false"
use_api_rates=yes
[ "$has_stdin_rates" = true ] && use_api_rates=no
if [ -f "$cache_file" ]; then
    eval "$(jq -r --argjson now "$now" --arg use_rates "$use_api_rates" "$jq_defs"'
        def iso_epoch: if . == null or . == "" then null
            else sub("\\.[0-9]+"; "") | sub("(\\+00:00|-00:00)$"; "Z") | (fromdateiso8601? // null) end;
        (if $use_rates == "yes" then
            {five_hour_pct: (.five_hour.utilization // 0 | round0),
             seven_day_pct: (.seven_day.utilization // 0 | round0)}
            + (.five_hour.resets_at | iso_epoch | reset_fields("five_hour"; "time"; $now))
            + (.seven_day.resets_at | iso_epoch | reset_fields("seven_day"; "datetime"; $now))
         else {} end)
        + (if .extra_usage.is_enabled == true then
            {extra_enabled: "true",
             extra_pct: (.extra_usage.utilization // 0 | round0),
             extra_used: ((.extra_usage.used_credits | num // 0) / 100 | money),
             extra_limit: ((.extra_usage.monthly_limit | num // 0) / 100 | money),
             # Extra usage resets on the 1st of next month.
             extra_reset: (["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
                           [($now | localtime | .[1] + 1) % 12] + " 1")}
           else {} end)
        | emit
    ' "$cache_file" 2>/dev/null)"
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_hour_pct" ]; then
    set_bar "$five_hour_pct" "$bar_width"
    set_pct_color "$five_hour_pct"
    printf -v five_hour_pct_fmt "%3d" "$five_hour_pct"

    rate_lines+="${white}current${reset} ${bar} ${pct_color}${five_hour_pct_fmt}%${reset}"
    [ -n "$five_hour_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"
    [ -n "$five_hour_left" ] && rate_lines+=" ${dim}· ${five_hour_left}${reset}"
fi

if [ -n "$seven_day_pct" ]; then
    set_bar "$seven_day_pct" "$bar_width"
    set_pct_color "$seven_day_pct"
    printf -v seven_day_pct_fmt "%3d" "$seven_day_pct"

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}weekly${reset}  ${bar} ${pct_color}${seven_day_pct_fmt}%${reset}"
    [ -n "$seven_day_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"
    [ -n "$seven_day_left" ] && rate_lines+=" ${dim}· ${seven_day_left}${reset}"
fi

if [ "$extra_enabled" = "true" ]; then
    set_bar "$extra_pct" "$bar_width"
    set_pct_color "$extra_pct"
    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}extra${reset}   ${bar} ${pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

if [ -n "$spend_pct" ]; then
    set_bar "$spend_pct" "$bar_width"
    set_pct_color "$spend_pct"
    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}spend${reset}   ${bar} ${pct_color}"
    if [ -n "$spend_used" ] && [ -n "$spend_limit" ]; then
        rate_lines+="\$${spend_used}${dim}/${reset}${white}\$${spend_limit}${reset}"
    else
        rate_lines+="${spend_pct}%${reset}"
    fi
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0

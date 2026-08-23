#!/usr/bin/env bash
# Usage statistics for the dispatch logs glm-dispatch writes to
# ~/.claude/glm-runs/<worktree>-<timestamp>.json - one file per dispatch.
#
# Prints one line per dispatch (turns / tokens / duration), then totals.
# Turns are the billing unit on per-prompt plans, so the totals answer
# "how much did GLM execution cost this week".
#
#   INPUT column = usage.input_tokens + usage.cache_read_input_tokens
#
# The camelCase modelUsage fields are deliberately NOT used: they are a
# per-model breakdown, and summing them double-counts tokens.
#
# JSON parsing is delegated to node (the same runtime the claude CLI
# already requires); it strips the UTF-8 BOM that older logs carry
# (PS 5.1 Tee-Object legacy) before parsing, so both old and new log
# formats read. Unparseable files are skipped and reported, never fatal.
#
# Output matches glm-stats.ps1: files are listed in byte order and numbers
# use locale-independent thousands separators.
#
# Targets bash 3.2 (macOS system bash): no associative arrays.

set -euo pipefail

LOG_DIR="$HOME/.claude/glm-runs"

# Emit one tab-separated record per log file:
# turns, failed(0/1), input_tokens(+cache_read), output_tokens, duration_ms
PARSE_JS='
const fs = require("fs");
let text = fs.readFileSync(process.argv[1], "utf8");
if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);  // legacy Tee-Object BOM
const r = JSON.parse(text);
const n = v => (typeof v === "number" && isFinite(v)) ? v : 0;
const u = r.usage || {};
process.stdout.write([n(r.num_turns), r.is_error ? 1 : 0,
                      n(u.input_tokens) + n(u.cache_read_input_tokens),
                      n(u.output_tokens), n(r.duration_ms)].join("\t") + "\n");
'

group() {  # thousands separators, locale-independent: 1234567 -> 1,234,567
  local s=$1 r=""
  while [ ${#s} -gt 3 ]; do
    r=",${s: -3}$r"
    s="${s%???}"
  done
  printf '%s%s' "$s" "$r"
}

if [ ! -d "$LOG_DIR" ]; then
  echo "[glm-stats] log directory ~/.claude/glm-runs does not exist yet - nothing to stat."
  exit 0
fi

command -v node >/dev/null 2>&1 || { echo "[glm-stats] node is required to parse the logs" >&2; exit 1; }

export LC_ALL=C  # byte-order glob expansion below; matches the .ps1 ordinal sort
shopt -s nullglob
files=("$LOG_DIR"/*.json)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "[glm-stats] no *.json logs in ~/.claude/glm-runs - nothing to stat yet."
  exit 0
fi

rows=()      # raw fields per dispatch, tab-separated
skipped=()   # filenames that failed to parse
tot_turns=0; tot_fail=0; tot_in=0; tot_out=0; tot_ms=0
name_re='^(.*)-([0-9]{8})-([0-9]{6})$'

for f in "${files[@]}"; do
  base="$(basename "$f" .json)"
  task="$base"; stamp="-"
  if [[ "$base" =~ $name_re ]]; then
    d="${BASH_REMATCH[2]}"; t="${BASH_REMATCH[3]}"
    task="${BASH_REMATCH[1]}"
    stamp="${d:0:4}-${d:4:2}-${d:6:2} ${t:0:2}:${t:2:2}"
  fi
  if ! vals="$(node -e "$PARSE_JS" "$f" 2>/dev/null)"; then
    skipped+=("$(basename "$f")")
    continue
  fi
  IFS=$'\t' read -r turns failed in_tok out_tok ms <<< "$vals"
  rows+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$task" "$stamp" "$turns" "$failed" "$in_tok" "$out_tok" "$ms")")
  tot_turns=$((tot_turns + turns)); tot_fail=$((tot_fail + failed))
  tot_in=$((tot_in + in_tok)); tot_out=$((tot_out + out_tok)); tot_ms=$((tot_ms + ms))
done

echo ""
echo "[glm-stats] reading ~/.claude/glm-runs: ${#files[@]} json files"

# pass 1: column widths from the formatted values
w_task=4; w_stamp=5; w_turns=5; w_in=5; w_out=6; w_ms=11
if [ ${#rows[@]} -gt 0 ]; then
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r task stamp turns failed in_tok out_tok ms <<< "$row"
    f_t="$(group "$turns")"; f_i="$(group "$in_tok")"; f_o="$(group "$out_tok")"; f_m="$(group "$ms")"
    w_task=$((  ${#task} > w_task  ? ${#task}  : w_task  ))
    w_stamp=$(( ${#stamp} > w_stamp ? ${#stamp} : w_stamp ))
    w_turns=$(( ${#f_t} > w_turns  ? ${#f_t}   : w_turns ))
    w_in=$((    ${#f_i} > w_in     ? ${#f_i}    : w_in    ))
    w_out=$((   ${#f_o} > w_out    ? ${#f_o}    : w_out   ))
    w_ms=$((    ${#f_m} > w_ms     ? ${#f_m}    : w_ms    ))
  done
fi

if [ ${#rows[@]} -gt 0 ]; then
  echo ""
  printf '%-*s  %-*s  %*s  %*s  %*s  %*s  %s\n' \
    "$w_task" TASK "$w_stamp" STAMP "$w_turns" TURNS "$w_in" INPUT "$w_out" OUTPUT "$w_ms" DURATION_MS STATUS
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r task stamp turns failed in_tok out_tok ms <<< "$row"
    status="ok"
    if [ "$failed" = "1" ]; then status="FAIL"; fi
    printf '%-*s  %-*s  %*s  %*s  %*s  %*s  %s\n' \
      "$w_task" "$task" "$w_stamp" "$stamp" \
      "$w_turns" "$(group "$turns")" "$w_in" "$(group "$in_tok")" "$w_out" "$(group "$out_tok")" \
      "$w_ms" "$(group "$ms")" "$status"
  done
else
  echo ""
  echo "[glm-stats] no parseable logs found."
fi

if [ ${#skipped[@]} -gt 0 ]; then
  echo ""
  for s in "${skipped[@]}"; do
    echo "[glm-stats] skipped unparseable log: $s"
  done
fi

# totals
c_disp="$(group "${#rows[@]}")"; c_fail="$(group "$tot_fail")"; c_turns="$(group "$tot_turns")"
c_in="$(group "$tot_in")"; c_out="$(group "$tot_out")"; c_ms="$(group "$tot_ms")"
tenth=$(( tot_ms / 6000 ))
c_min="$(printf '%d.%d' $(( tenth / 10 )) $(( tenth % 10 )))"
w_tot=0
for s in "$c_disp" "$c_fail" "$c_turns" "$c_in" "$c_out" "$c_ms"; do
  w_tot=$(( ${#s} > w_tot ? ${#s} : w_tot ))
done
total_w=$(( w_task + 2 + w_stamp + 2 + w_turns + 2 + w_in + 2 + w_out + 2 + w_ms + 2 + 6 ))
echo ""
printf '%*s\n' "$total_w" '' | tr ' ' '-'
printf '%-13s  %*s\n' "dispatches"    "$w_tot" "$c_disp"
printf '%-13s  %*s\n' "failures"      "$w_tot" "$c_fail"
printf '%-13s  %*s\n' "turns"         "$w_tot" "$c_turns"
printf '%-13s  %*s\n' "input tokens"  "$w_tot" "$c_in"
printf '%-13s  %*s\n' "output tokens" "$w_tot" "$c_out"
printf '%-13s  %*s ms (%s min)\n' "duration" "$w_tot" "$c_ms" "$c_min"

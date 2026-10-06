#!/bin/zsh
# Coherence ratchet (docs/coherence.md): counts known drift patterns in app code
# and fails if any count goes UP versus ci_scripts/coherence_baseline.txt.
# Lower a baseline number whenever you remove instances; never raise it.
#   ci_scripts/coherence_ratchet.sh            check
#   ci_scripts/coherence_ratchet.sh --update   rewrite the baseline (only after a decrease)
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=LanguageLearning
BASELINE=ci_scripts/coherence_baseline.txt

count() { { grep -rEo --include="*.swift" "$1" "$SRC" || true; } | wc -l | tr -d " " }

typeset -A now
# Visual language: tokens, not literals; one primary button style.
now[raw_corner_radius]=$(count 'cornerRadius: [0-9]+')
now[raw_rgb_colors]=$(count 'Color\(red:')
now[private_button_styles]=$(count 'struct [A-Za-z]+: ButtonStyle')
now[bordered_prominent]=$(count '\.borderedProminent')
# Glossary: banned user-facing terms inside string literals.
now[glossary_mission]=$(count '"[^"]*Mission[^"]*"')
now[glossary_jargon]=$(count '"[^"]*\b(FSRS|SRS|Tier|Habit)\b[^"]*"')
now[glossary_item_synonyms]=$(count '"[^"]*\b(Phrasen|Einheit|Einheiten)\b[^"]*"')
# Language-agnostic: no hardcoded Russian fallbacks.
now[language_hardcodes]=$(count '\?\? "(ru-RU|Russisch)"')

if [[ "${1:-}" == "--update" ]]; then
  : > "$BASELINE"
  for key in ${(ko)now}; do echo "$key ${now[$key]}" >> "$BASELINE"; done
  echo "Baseline written."; cat "$BASELINE"; exit 0
fi

failed=0
while read -r key limit; do
  [[ -z "$key" ]] && continue
  value=${now[$key]:-0}
  if (( value > limit )); then
    echo "✘ $key: $value (baseline $limit) — see docs/coherence.md"; failed=1
  elif (( value < limit )); then
    echo "↓ $key: $value (baseline $limit) — lower the baseline with --update"
  fi
done < "$BASELINE"
(( failed == 0 )) && echo "Coherence ratchet: OK"
exit $failed

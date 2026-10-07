#!/bin/zsh
# Region audit of every shipped collection film (or candidates passed as overrides).
# Rects are fractions of the VISIBLE 1:1.30 hero card (x0,y0,x1,y1), measured from the
# current final frames. Re-check them on the heatmap whenever a composition changes.
#
#   ./audit_collections.sh                         # shipped reveal + loop for all four
#   NINFEA_LOOP=ninfea-loop-v3.mp4 ./audit_collections.sh ninfea
set -u
here=${0:A:h}
res=${here:h:h}/ios/Salini/Resources
out=$here/audit
mkdir -p $out
typeset -A intro loop regions
intro=(ninfea $res/ninfea-film-v3.mp4 aria $res/aria-film-v1.mp4
       opera $res/opera-film-v1.mp4 greca $res/greca-film-v1.mp4)
loop=(ninfea ${NINFEA_LOOP:-$res/ninfea-loop-v1.mp4} aria ${ARIA_LOOP:-$res/aria-loop-v1.mp4}
      opera ${OPERA_LOOP:-$res/opera-loop-v1.mp4} greca ${GRECA_LOOP:-$res/greca-loop-v1.mp4})
# rigid = the Salini product body must not move; alive = must move in every 0.5 s.
regions=(
  ninfea "--region tub=0.28,0.56,0.62,0.72:rigid --region water=0.22,0.45,0.82,0.52:alive --region foreground=0.62,0.62,1.0,1.0:alive --region garden=0.0,0.0,0.55,0.40:alive"
  aria   "--region tub=0.25,0.55,0.75,0.72:rigid --region fabric=0.0,0.0,1.0,0.45:alive"
  opera  "--region tub=0.25,0.58,0.75,0.72:rigid --region water=0.25,0.55,0.75,0.60:alive --region floor=0.0,0.80,1.0,1.0:alive"
  greca  "--region tub=0.25,0.48,0.70,0.66:rigid --region meander=0.0,0.62,1.0,0.80:alive --region sea=0.10,0.28,0.95,0.40:alive"
)
overall=0
if (( $# )); then names=($@); else names=(ninfea aria opera greca); fi
for name in $names; do
  python3 $here/motion_regions.py --loop ${loop[$name]} --intro ${intro[$name]} \
    ${=regions[$name]} --heatmap $out/$name-heat.png > $out/$name.json
  code=$?
  python3 - $out/$name.json $name <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); l = d["loop"]; i = d.get("intro", {})
print(f"{sys.argv[2]:7} {d['result']:4}  loop live median {l['median_window_alive']:.0%} "
      f"min {l['min_window_alive']:.0%}  seam×{l['seam_ratio']:.1f}  "
      f"reveal tail {i.get('tail_alive', 0):.0%}  handoff×{i.get('handoff_step_ratio', 0):.2f}")
for f in d["failures"]:
    print("        -", f)
EOF
  (( code )) && overall=1
done
exit $overall

#!/bin/zsh
# One bounded Greca I2V feasibility take (internal research). ltx-2-mlx v0.16.1, q4, --low-ram.
# Never starts on its own: requires LTX_RUN_APPROVED=1 (given by Codex when the resource window
# is open), complete weights and healthy memory. supervise.py runs the renderer in its own
# process group, logs memory every 5 s, and stops that group only, on 30 s of critical pressure
# or at the wall-time cap.
L=/Users/daviddoronin/.codex/worktrees/salini-native-materials/Salini/tmp/local-video
R=$L/runs/greca-01
IMG=/Users/daviddoronin/.codex/worktrees/salini-native-materials/Salini/research/collection-worlds-2026-10-07/greca-tidal-keyframe-v2.png
WALL_CAP=${WALL_CAP:-3600}
mkdir -p $R
[[ "$LTX_RUN_APPROVED" == 1 ]] || { print "not approved: set LTX_RUN_APPROVED=1"; exit 2; }
for f in transformer-distilled-1.1 connector vae_encoder vae_decoder spatial_upscaler_x2_v1_1; do
  [[ -s $L/weights/ltx-2.3-mlx-q4/$f.safetensors ]] || { print "SKIPPED: missing $f" | tee -a $R/timing.txt; exit 3; }
done
[[ -s $L/weights/gemma-3-12b-it-4bit/model-00002-of-00002.safetensors ]] || { print "SKIPPED: missing gemma" | tee -a $R/timing.txt; exit 3; }
level=$(sysctl -n kern.memorystatus_vm_pressure_level)
print "$(date '+%H:%M:%S') precheck level=$level swap=[$(sysctl -n vm.swapusage)] $(memory_pressure -Q | tail -1)" >> $R/memory.log
if [[ $level -ne 1 ]]; then print "SKIPPED: memory pressure level $level (needs 1)" | tee -a $R/timing.txt; exit 4; fi
cd $L/ltx-2-mlx
export HF_HOME=$L/hf HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
PROMPT="A locked-off static camera shot. A pale turquoise freestanding bathtub with an ivory rim stands perfectly still on a flat sandstone island in the open sea at golden hour. All around it the clear turquoise sea water moves continuously: small waves roll toward the island, ripples cross the shallow water, bright sun glints sparkle and drift on the surface, and water gently washes over the edges of the stone. The bathtub, the stone island and the distant cliffs stay rigid and unchanged. No camera movement, no zoom, no cuts."
print -r -- "$PROMPT" > $R/prompt.txt
CMD=(.venv/bin/ltx-2-mlx generate --distilled --model $L/weights/ltx-2.3-mlx-q4 --gemma $L/weights/gemma-3-12b-it-4bit
  --prompt "$PROMPT" --image $IMG 0 1.0 -H 512 -W 384 -f 97 --frame-rate 24 --seed 42 --low-ram --no-audio
  -o $R/greca-01-384x512-97f.mp4)
print -r -- "${(q)CMD[@]}" > $R/command.txt
date '+start %Y-%m-%d %H:%M:%S' >> $R/timing.txt
/usr/bin/python3 $L/supervise.py --log $R --wall $WALL_CAP --critical-seconds 30 --interval 5 --grace 15 -- "${CMD[@]}"
rc=$?
date '+end %Y-%m-%d %H:%M:%S' >> $R/timing.txt
print "supervisor exit $rc" >> $R/timing.txt
exit $rc

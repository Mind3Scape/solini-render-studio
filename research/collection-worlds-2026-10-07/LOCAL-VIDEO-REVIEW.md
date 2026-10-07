# Codex review of the local feasibility setup

7 October 2026. No generated local video exists yet. Prepared commands and installed dependencies are not evidence of working inference or quality.

- Actual resource check after archive: memory pressure level 2, swap used 35,779 MB / 36,864 MB. Do not start inference automatically while memory is constrained. Downloads may continue; no unrelated apps may be closed.
- Review correction for the launch script: `GEN=$!` after `/usr/bin/time -l command &` identifies the time wrapper, so sending TERM/KILL only to that PID can leave the memory-heavy child alive; RSS also measures the wrapper. Before any execution, supervise the actual child/process group created for this one run. Verify termination with a harmless child-process fixture, not a full model load. Keep a hard wall-time limit as well as the pressure watchdog.
- Do not treat the existing free swap count as the Mac's total possible swap capacity, or describe 24 GB hardware as categorically incapable of local video. The blocker is the observed current memory pressure plus incomplete weights.
- Keep scripts and large dependencies isolated; the committed research note must include pinned revisions, prompt, command and exact state. No claim of production quality, seamless loop, timing or peak generation memory before a successful run and inspection.
- No implicit research exemption should be inferred from a model license. Record terms and unresolved applicability without promising a legal conclusion.

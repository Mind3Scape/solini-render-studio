# Local trial scripts

Snapshots of the Opus-authored preparation under `tmp/local-video/`, reviewed by Codex. The runner intentionally targets this Mac's isolated working directory; dependencies, caches, weights and outputs remain outside Git. See `../LOCAL-VIDEO.md` for pinned revisions, command, prompt, resource checks and unverified limits.

The launch guard requires `LTX_RUN_APPROVED=1` from the coordinating agent after rechecking the resource window. This is a technical guard, not a request for an additional user approval. Automatic inference is disabled. No local video has been produced or accepted.

`supervise.py` was exercised against harmless child-process fixtures for wall timeout, critical pressure, SIGTERM resistance, normal exit and orphaned children. No full-model benchmark is claimed. The resource `ru_maxrss` field is a child-process maximum, not a simultaneous aggregate peak; the memory log samples total group RSS separately.

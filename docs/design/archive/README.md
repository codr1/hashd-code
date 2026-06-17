# Archived Design Records

Design documents in this directory describe features that have been
implemented. They are kept for historical reference -- to answer "why did
we build it this way" questions -- but the implementation in code is the
authoritative source of truth.

Do not update archived design records. If the design evolves, update the
implementation and code-level documentation; if the design rationale
itself shifts, write a new document and supersede the archived entry.

## Archived

- `build-system-detection.md` -- auto-detect build/test commands at
  project add time. Shipped 2026-04 through 2026-05 across PRs #312, #314,
  #316, #328, #336, #337, #339.
- `multi-repo-v2.md` -- multi-repo project model with four-value repo
  status, lazy AI investigation, DB-first repo state, mode: multi marker.
  Shipped across multiple PRs through mid-2026-05.

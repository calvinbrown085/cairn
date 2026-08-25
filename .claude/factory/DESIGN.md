# The Stacks Factory — design

*Agreed 2026-08-24. An orchestrated, worktree-parallel implementation harness for
this repo. Read `CONSTITUTION.md` for the rules agents may not break.*

---

## Shape

```
ROADMAP.md ──(planner, you approve)──> ledger ──> orchestrator
                                                     │
                                 ┌───────────────────┼───────────────────┐
                                 ▼                   ▼                   ▼
                            worktree A          worktree B          worktree C
                            implementer         implementer         implementer
                            (Sonnet)            (Sonnet)            (Sonnet)
                                 │                   │                   │
                                 └────────► reviewer (Opus) ◄────────────┘
                                                     │
                                            merge queue (serial)
                                          rebase → verify → squash → push
```

**Roles**

| Role | Model | Runs in | Job |
|---|---|---|---|
| Overseer | Opus | main checkout | The standing leader. Holds the roadmap, runs the fleet, converses with in-flight agents and with the human. Entry point for interactive work. |
| Planner | Opus | main checkout | ROADMAP.md → draft ledger tasks. You approve. |
| Orchestrator | Opus | main checkout | The mechanical cycle the overseer runs: health, selection, dispatch, merge queue, ledger writes. The only writer of `.claude/factory/`. |
| Implementer | Sonnet | git worktree | Implement one task until `verify.sh` exits 0. Commits. Never touches the factory dir. |
| Review | — | overseer + `/code-review low` | Two questions: is the code sound (`/code-review low`), and is it the work that was asked for (the overseer, against the acceptance criteria and the constitution). |

## Settled decisions

| Question | Decision |
|---|---|
| Queue | In-repo JSON ledger, one file per task, dependency edges. ROADMAP.md stays the human narrative. |
| Landing authority | The overseer decides; the implementing agent executes `merge.sh` on instruction. No PRs, no `gh`. `land_requires_human` gates whether the overseer needs your sign-off first — it ships **true**. |
| Parallelism | 2 implementers to start, 3 ceiling. Merges serialized. Simulator serialized. |
| Verify bar | `xcodegen → build → test → invariants`, one script, one exit code. |
| Run mode | Supervised `/loop` session. Promote to overnight cron only after calibration. |
| Failure | 3 attempts, then park the task, preserve the worktree, escalate, move on. |
| Decomposition | Planner drafts, you approve. Nothing is factory-eligible until you have signed off on its acceptance criteria. |
| Models | Opus orchestrates and reviews; Sonnet implements; Opus rescue-attempt before parking. |
| Home | `.claude/` in this repo. Goes public with the repo in Q2, deliberately. |
| Attribution | Your authorship, `Co-Authored-By` trailer naming the agent. `git log` stays honest. |

## Layout

```
.claude/
  skills/overseer/SKILL.md         the standing leader; talks to agents and to you
  skills/factory/SKILL.md          orchestrator loop
  skills/factory-plan/SKILL.md     planner pass
  agents/factory-implementer.md    Sonnet, worktree isolation
  factory/
    DESIGN.md                      this file
    CONSTITUTION.md                hard rules, derived from ROADMAP decisions
    config.json                    land_requires_human, max_parallel, attempts, models
    tasks/T-0001-*.json            the ledger
    state/                         gitignored
      locks/{merge,sim}.lock       mkdir-atomic, pid + stale timeout
      runs/<task>/                 build logs, verify output, review verdicts
      blocked/<task>.md            escalations awaiting your triage
    bin/
      ledger.sh                    queries + mutations; deps and touches-conflicts  [phase 0]
      worktree.sh                  create/destroy, per-worktree DerivedData         [phase 0]
      verify.sh                    the gate. one exit code.                         [phase 1]
      invariants.sh                deterministic constitution checks                [phase 1]
      main-health.sh               is main still green?                             [phase 1]
      merge.sh                     rebase -> re-verify -> squash -> push            [phase 1]
```

## Ledger entry

```json
{
  "id": "T-0007",
  "title": "Dynamic Type as the base, reader slider as a relative offset",
  "type": "implement",           // implement | chore | debt | decide | spike
  "status": "ready",             // draft todo ready in_progress in_review verifying merged blocked
  //                                draft = planner wrote it, human has not approved it
  "quarter": "Q2",
  "roadmap_anchor": "Q2 > Accessibility > Dynamic Type as the base",
  "depends_on": ["T-0003"],
  "acceptance": [
    "No `.system(size:)` remains in Stacks/Views or Stacks/Design",
    "Reader slider is a relative offset via Font.custom(size:relativeTo:)",
    "adjustsFontForContentSizeCategory is true in SelectableTextView"
  ],
  "touches": ["Stacks/Views/**", "Stacks/Design/**"],
  "risk": "high",
  "factory_eligible": true,
  "attempts": 0,
  "branch": "factory/T-0007-dynamic-type",
  "agent": {"name": "...", "id": "...", "role": "implementer", "spawned": "..."},
  "$agent": "Recorded at spawn so the overseer can address the agent later; SendMessage resumes it from its own transcript.",
  "history": []
}
```

`type` is load-bearing: **only `implement`, `chore` and `debt` are ever dispatched.**
`decide` and `spike` tasks are queued *to you* — the roadmap's text-architecture
call and the embeddings gate are judgement, not tickets, and an agent must never
resolve them.

## The cycle

0. **Health.** `main-health.sh`. If `main` is red, halt the entire factory and escalate. Nothing is dispatched onto a broken base.
1. **Reap.** Collect finished agents, advance their tasks.
2. **Select.** `status: ready` (all `depends_on` merged) ∧ `factory_eligible` ∧ `touches` disjoint from every in-flight task. Cap at `max_parallel`. File-overlap exclusion is what keeps `ReaderView.swift` from being edited by two agents at once.
3. **Dispatch.** Branch + worktree + per-worktree DerivedData. Implementer gets the task JSON, the constitution, and one instruction that matters: *`verify.sh` must exit 0.*
4. **Review.** `/code-review low` on the branch for code soundness; the overseer reads `git diff main...HEAD` against the acceptance criteria and the constitution. `land` | `revise` (notes) | `reject` (wrong work).
5. **Iterate.** `revise` → attempt++ → back to the implementer with notes. At attempt 3, one Opus rescue attempt, then park.
6. **Park.** Worktree preserved, log + diff + reason written to `state/blocked/`, task marked `blocked`, orchestrator moves on. The factory never stalls on one bad task.
7. **Merge.** Acquire `merge.lock` → rebase onto `main` → **re-run `verify.sh`** (the rebase is new code; the pre-rebase green does not count) → squash-merge → push → tick the ROADMAP box → update ledger → destroy worktree and its DerivedData → release.
8. **Report** the cycle, then schedule the next.

Squash merges are not cosmetic: one merge = one revert. With auto-merge on and
nobody watching, the ability to undo exactly one feature is the safety net.

## Concurrency hazards, and what handles each

| Hazard | Handling |
|---|---|
| Two agents editing `ReaderView.swift` | `touches` disjointness at selection time |
| Simulator contention (`simctl`, test runs) | `sim.lock`, serialized |
| Racing merges | `merge.lock` + rebase + re-verify |
| DerivedData disk blowup (70 GB free) | per-worktree `-derivedDataPath`, destroyed on merge or park |
| Code-sign contention on parallel builds | simulator builds run `CODE_SIGNING_ALLOWED=NO` |
| Agents rewriting factory state | constitution: a worktree diff touching `.claude/factory/**` is an automatic reject |
| `main` silently rotting | health check at the head of every cycle |

## The gate

`verify.sh`, in order, fail fast:

1. `xcodegen generate` — the `.xcodeproj` is gitignored, so every worktree builds its own. This is why worktrees work cleanly here.
2. `xcodebuild build` — app + share extension, simulator destination, signing off.
3. `xcodebuild test` — unit suite.
4. `invariants.sh` — deterministic greps, no model judgement:
   - `system(size:` count measured against the merge-base with `main`, monotonically non-increasing (never a number frozen in config — it moves with active development)
   - every `import` in the Apple-framework allowlist; no `Package.resolved`
   - no `badge` / `streak` / `unreadCount` identifiers (the guilt-engine ban)
   - no analytics or tracker SDK references
   - `build/`, `build-device/`, `xcuserdata/` not committed
   - diff does not touch `.claude/factory/**`

**This does not exist yet, and building it is the factory's own first job.**

## Bootstrap phases

- **Phase 0 — scaffolding.** Directories, config, constitution, ledger seeded from ROADMAP, the four skill/agent definitions, `worktree.sh`. No app behaviour changes.
- **Phase 1 — the gate.** `StacksTests` unit target in `project.yml`, first extractor fixtures, `verify.sh`, `invariants.sh`, `main-health.sh`, `merge.sh`. Auto-merge OFF; these land as PRs you read.
- **Phase 2 — calibration.** Two or three genuinely low-risk real tasks, supervised, one at a time: `PrivacyInfo.xcprivacy`, accessibility labels on icon-only controls, more fixtures. Watch the gate catch something real.
- **Phase 3 — production.** Flip `land_requires_human` to false, raise `max_parallel` to 3, consider the nightly cron with a per-night task cap.

## Open

- **Escaping the simulator** — tracked as ledger task `D-0001`, which every Phase 1 task depends on, so the factory is structurally blocked until it is answered. An iOS unit-test target needs a booted sim, so the sim lock serializes the gate and largely defeats parallelism. Pulling the Q2 item *"extract SwiftReadability as an SPM package"* forward would let the extractor, HTML parser, block builder and metadata tests — the most testable and most fixture-driven code in the repo — run as `swift test` on macOS: seconds, no simulator, fully parallel. It reorders the roadmap, and it is the single highest-leverage change to factory throughput.

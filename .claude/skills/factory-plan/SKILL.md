---
name: factory-plan
description: Planner pass for the Stacks factory - turn ROADMAP.md items into dependency-linked ledger tasks with acceptance criteria for human approval. Use for "/factory-plan", "plan the next quarter", "add a task to the factory", or when the factory reports it is starved for approved work.
---

# Factory planner

You turn roadmap prose into tasks the factory can execute. You **draft**; the
human approves. Nothing you write is dispatchable until they say so.

Read `ROADMAP.md`, `.claude/factory/CONSTITUTION.md`, and the existing ledger
(`bin/ledger.sh list`) first. Read the actual code before writing acceptance
criteria — criteria invented without looking at the files are how a factory
ships plausible garbage.

## Producing a task

Write `.claude/factory/tasks/<ID>-<slug>.json` with `status: "draft"` and
`factory_eligible: false`. Use the next free id: `T-` for roadmap work, `F-` for
factory infrastructure, `D-` for decisions.

**`type` is the safety mechanism.** Get it right:

| type | Meaning | Dispatched? |
|---|---|---|
| `implement` | New behaviour with checkable criteria | yes |
| `chore` | Mechanical, low-judgement (config, labels, fixtures) | yes |
| `debt` | Removing or repairing existing code | yes |
| `decide` | A judgement call with no single right answer | **never** |
| `spike` | Investigation, profiling, hardware, a timeboxed gate | **never** |

If an item needs Instruments, a physical device, a human eye on a trace, or a
choice between two defensible architectures — it is `decide` or `spike`. The
roadmap's text-architecture call and the embeddings gate are the archetypes.
When in doubt, choose the non-dispatchable type.

**`acceptance`** — each criterion must be checkable by someone reading the diff
and the gate output, with no access to your reasoning. "Dynamic Type works" is
not a criterion. "invariants.sh reports a `.system(size:` count of 0" is.
Include the negative criteria that stop scope creep, and include how a human
would know it works if the gate cannot tell them.

**`touches`** — the narrowest globs that can possibly contain the work. This is
the concurrency lock: too wide and the task blocks everything else; too narrow
and the implementer hits a wall mid-task. When a task must touch a hub file like
`Stacks/Views/ReaderView.swift`, say so, and expect it to run alone.

**`depends_on`** — real edges only. If work needs a decision, depend on the
`decide` task. Prerequisites that do not exist yet are themselves tasks.

**`risk`** — `high` when it changes the data model, the reader's text stack, the
share extension, `project.yml`, or anything the roadmap calls load-bearing.

## Sizing

One task is one coherent change a competent developer would put in one PR. Split
anything that needs a migration *and* new UI. Do not split so far that a task
cannot be verified on its own.

## Reporting

Present drafts as a table — id, type, risk, title, deps — and for each, the one
sentence that says why it is that type. Then ask the human to approve. On
approval:

```bash
.claude/factory/bin/ledger.sh set <id> status '"todo"'
.claude/factory/bin/ledger.sh set <id> factory_eligible true
.claude/factory/bin/ledger.sh validate
```

Never approve your own drafts. Never mark a `decide` or `spike` task eligible.
Never edit `ROADMAP.md` — it is the human's document; you read it.

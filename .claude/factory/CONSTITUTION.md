# Constitution

*Rules no agent working in this repo may break. Derived from the Decisions table
and the load-bearing arguments in `ROADMAP.md`. The reviewer checks every rule;
`bin/invariants.sh` checks the mechanical subset without asking a model's
opinion.*

A violation of any **PRODUCT** or **PROCESS** rule is an automatic `reject` —
not a `revise`. The work is discarded, not patched.

---

## PRODUCT — what Stacks is

**P1. No backend. Ever.**
CloudKit private database only. No server, no API you control, no account
system, no remote config. The private database bills against each user's own
iCloud quota, which is the only reason "free forever" and "no size limit" are
promises that can be kept. A feature that needs a server is not a feature that
ships; it is a roadmap change, and roadmap changes are the human's.

**P2. No third-party dependencies.**
Apple frameworks only, from the allowlist in `config.json`. No SPM package, no
CocoaPod, no vendored source, no `Package.resolved`. The App Privacy label says
*Data Not Collected* honestly because there is no third-party SDK to disclose
and no vendor privacy manifest to inherit. One dependency ends that.

**P3. No trackers, analytics, ads, or telemetry.**
Crash visibility is Xcode Organizer and on-device MetricKit. Nothing else. The
roadmap accepts seeing less than a normal app does; that trade is already made
and is not yours to revisit.

**P4. AI never writes.**
Models rank, relate, and find. A model may never mutate a `Post` — not tags, not
title, not body, not a summary field. *A wrong search result costs a second; a
wrong tag silently corrupts an archive intended to last a decade.* Retrieval is
reversible, mutation is not. No auto-tagging, no auto-summaries, no auto-filing.

**P5. A library, not a queue.**
No unread badge counts, no streaks, no daily digests, no "you have 47 unread",
no nagging. Before adding anything, ask the roadmap's question: *does this help
me find something, or does it pressure me to consume something?* Only the first
ships. See `banned_identifiers` in `config.json`.

**P6. Dynamic Type is the base.**
The reader's size slider is a *relative offset*, never an absolute size. Do not
add a `.system(size:)` call site. The baseline count only goes down.

**P7. The archive is durable and escapable.**
Never write a migration or a feature that destroys or lossily rewrites stored
posts, highlights, or original HTML without a reversible path. Export is a trust
feature. An archive you cannot leave is a trap.

**P8. Do not relitigate settled decisions.**
The Decisions table in `ROADMAP.md` is closed. Distribution, launch dates,
identity, the AI autonomy rule, the backend rule, text sizing, money, platforms.
If the task appears to require breaking one, stop and escalate — do not
negotiate with yourself in a commit message.

---

## PROCESS — how agents work here

**X1. Stay inside `touches`.**
Edit only paths matching the task's `touches` globs. No drive-by refactors, no
opportunistic cleanups, no reformatting files the task does not name. If the
task cannot be done inside its declared paths, that is an escalation, not a
licence to widen.

**X2. Implement the acceptance criteria — all of them, and only them.**
Not a subset, not a superset. If a criterion is impossible or wrong, say so in
the report and stop; do not silently substitute your own.

**X3. The factory's own state is off limits.**
No worktree agent may modify `.claude/factory/**`, `.claude/skills/**`, or
`.claude/agents/**`. A diff touching them is an automatic reject. The
orchestrator is the only writer of factory state.

**X4. `ROADMAP.md` is the human's document.**
Only the orchestrator ticks a box, and only on merge. Never edit its prose.

**X5. Never touch `main` directly.**
Work happens on `factory/<task-id>-<slug>` in a worktree. No commits to `main`,
no `git push --force` anywhere, no rewriting published history, no
`git checkout main` inside a worktree.

**X6. Never commit build output or user state.**
`build/`, `build-device/`, `DerivedData/`, `.dd/`, `xcuserdata/`, `*.xcresult`,
`.DS_Store`, and the generated `Stacks.xcodeproj/` stay out of every commit.

**X7. Never change signing or identity.**
`DEVELOPMENT_TEAM`, bundle identifiers, the app group, and the CloudKit
container are fixed. Changing one to make a build pass is forgery, not a fix.

**X8. Green means the gate said so.**
`bin/verify.sh` exiting 0 is the only definition of done. Never report success
on a build you did not run, never disable, skip, weaken, or `XCTSkip` a test to
get there, and never relax an invariant threshold. If the gate is wrong, that is
an escalation.

**X9. Commits are honest.**
Squash to one commit per task. Message: `<type>: <title>` then the task id. Keep
the `Co-Authored-By` trailer naming the agent — `git log` must stay truthful
about what was machine-written, especially in a repo going public.

**X10. Secrets stay out.**
No credentials, tokens, API keys, or personal data in code, tests, fixtures, or
commit messages — this repo becomes public in Q2.

---

## Reviewer verdicts

| Verdict | Meaning | Consequence |
|---|---|---|
| `approve` | Every acceptance criterion is met and no rule is broken. | Merge queue. |
| `revise` | Right direction, specific fixable defects. Notes are mandatory and must be concrete. | Back to the implementer, `attempts++`. |
| `reject` | Wrong work, or any PRODUCT/PROCESS violation. | Discard the branch, park the task, escalate. |

A reviewer that cannot verify a criterion from the diff must say so explicitly
and return `revise` — never `approve` on the assumption that it probably works.

# Stacks — Roadmap

*Written 2026-08-24. Covers the twelve months to August 2027.*

---

## The thesis

**A read-later app's value should compound with age. Almost none of them do.**

Every product in this category optimises the save and neglects the archive, so
the archive becomes a landfill and people delete the app. Pocket, Omnivore,
Readability and Matter are all dead or gone. The survivors — GoodLinks, Readwise
Reader — survive by being good at *reading*, not at *remembering*.

Stacks bets the other way: that the thing worth building is a **personal library
whose retrieval is good enough that a five-year-old archive is genuinely
searchable**, and that on-device intelligence now makes that possible without a
server, a subscription, or handing your reading history to anyone.

> **Everything you've read, still findable in ten years. On your devices, and
> nowhere else.**

---

## Decisions (settled — stop relitigating these)

| Question | Decision |
|---|---|
| Distribution | **App Store, free.** Public source. **Never any trackers or ads.** |
| Launch | **TestFlight ~Feb 2027. App Store 1.0 ~Aug 2027.** |
| Identity | **A library, not a queue.** Optimise retrieval, not throughput. |
| The one bet | **On-device intelligence**, starting with semantic search. |
| AI autonomy | **Never writes, only finds.** No auto-tags, no rewrites, no auto-filing. |
| Backend | **Never.** CloudKit private database only. |
| Text sizing | **Dynamic Type is the base; the reader's slider is a relative offset.** |
| Money | **In-app tip jar.** Nothing gated, no subscription, no ads. |
| Platforms | iPhone, iPad, and a native SwiftUI Mac app (Q4, stretch). |

### Two things the App Store decision resolved

**The open-source provisioning objection is now moot.** I argued against
"cloners self-provision" because it meant nobody could build a working copy. But
*users* now get a signed build from the App Store with the real CloudKit
container. Self-provisioning is only a **contributor** problem, and contributors
can reasonably be expected to edit four identifiers. `Tools/configure.sh` (Q2)
reduces that to one command. The concern stands down.

**Free forever is genuinely sustainable.** CloudKit's *private* database bills
against each user's own iCloud quota, not the developer's. There is no per-user
cost, at any scale. Running cost is the $99/yr developer program and nothing
else. This is the whole reason the no-backend rule and the free price can
coexist indefinitely — and why an archive with no size limit is a promise that
can actually be kept.

### Why "library, not queue" is load-bearing

It kills features that would otherwise look obviously good: unread badges,
streaks, daily digests, "you have 47 unread". Every one of those is a guilt
engine, and guilt is what makes people delete read-later apps. When a feature is
proposed, the first question is *does this help me find something, or does it
pressure me to consume something?* Only the first ships.

### Why "AI never writes" is load-bearing

On-device models are small and will be wrong. The risk is asymmetric: **a wrong
search result costs a second; a wrong tag silently corrupts an archive you
intend to keep for a decade.** Retrieval and ranking are reversible. Mutation
is not. The model ranks, relates, and finds — it never edits the record.

---

## What actually differentiates this

**GoodLinks** (£10 once, local-first, excellent) already does everything Stacks
does *today*: share sheet, full-text search, tags, offline reading, good
typography. Shipping what exists now differentiates on nothing.

**Readwise Reader** ($8/mo) has the AI and the breadth, but it's cloud-hosted,
subscription-priced, and your reading history lives on their servers.

Four gaps neither fills:

1. **Semantic retrieval over your own corpus, fully on-device.** Nobody has
   shipped this well. Strongest wedge, and it preserves the whole architecture.
2. **Re-extractable preservation.** Keeping the *original HTML* means a better
   extractor in year two can repair every post saved in year one. Without it,
   an archive is frozen at the quality of the parser that first saw it.
3. **Intent capture.** One line at save time — *why am I keeping this?* — is the
   highest-signal text in the record, and no competitor asks for it. It is also
   the best thing to embed for later retrieval.
4. **A privacy label that says "Data Not Collected", honestly.** No third-party
   SDKs at all, so there is nothing to disclose and no vendor manifest to
   inherit. Rare enough to be a genuine differentiator, and free — it's a
   consequence of decisions already made.

And one existing asset: **the extractor.** A fast, dependency-free pure-Swift
Readability is rare — most iOS clients run a server-side extractor or JS
Readability in a hidden `WKWebView`. As an SPM package it's the most reusable
thing in the repo.

---

## Verified technical ground

Checked against the installed iOS 26.2 SDK and this codebase on 2026-08-24, not
from memory:

- `FoundationModels.framework` **is present**, but its public surface is
  **generation-only** — `LanguageModelSession`, `SystemLanguageModel`,
  `Generable`, `GenerationSchema`, tool calling. **There is no embedding API.**
- On-device embeddings come from **`NLContextualEmbedding`** (NaturalLanguage,
  iOS 17+).

**This de-risks the bet.** Semantic search does not depend on Foundation Models,
and therefore does not depend on Apple Intelligence being available or enabled.
It rests on older, broader, more stable ground than "the new AI framework".

Still unvalidated, gated by the Q3 spike: retrieval quality of
`NLContextualEmbedding` on document-length text (it produces contextual *token*
embeddings; pooling them into a good document vector is the open question),
model asset download size and offline behaviour, and whether Foundation Models
is worth using at all given "AI never writes" (probably not this year).

### Audited gaps, App Store blocking

- **`PrivacyInfo.xcprivacy` is missing.** Required. `UserDefaults` in
  `Stacks/Services/AppGroup.swift` is a "required reason" API and must declare
  one (app-group shared defaults).
- **Zero Dynamic Type support.** **77** hardcoded `.system(size:)` call sites
  across **16** files, plus `adjustsFontForContentSizeCategory = false` in
  `SelectableTextView.swift`. For a reading app this is close to disqualifying
  for low-vision users. *(Recounted 2026-08-25: the original figure of 29 across
  10 files was measured before the markup and card work landed. T-0012 is 2.6x
  the job this line originally described.)*
- ~~**Zero accessibility labels.**~~ **Closed 2026-08-25** by T-0011 (`0feb6c2`);
  every icon-only control now carries one. Two corrections to the original
  audit, for the record: 13 labels already existed when it was written, and
  there is no icon-only *filter menu* — filtering is `SidebarView` rows, which
  pair each icon with visible text and were never unlabelled. VoiceOver reading
  order inside the reader is still open; it is Q2 work and depends on the text
  architecture decision.

---

## Q1 (Sep–Nov 2026) — Pay the debt, make the archive durable

Nothing new ships until the foundation is honest. Most of this is known
outstanding work, not speculation.

**Debt**
- [ ] **Finish the scroll investigation.** CPU for 8 swipes went 10.2s → 3.8s via
      `LazyVStack` + caching the decode, but the remaining 3.8s is *unprofiled* —
      one hypothesis (attributed-string/height caching) was tested and disproved.
      Use Instruments' Time Profiler. Prime suspect: `.scrollPosition(id:)`
      forcing a full body re-evaluation per block crossing.
- [x] **Resolve the reader's text architecture.** **Decided 2026-08-25: keep one
      `UITextView` per block.** Highlights persist as `(blockIndex, start,
      length)` and sync through CloudKit, so per-block views make that anchoring
      native; blocks are heterogeneous (images, dividers, code, bulleted lists
      are views, not text); `LazyVStack` virtualises long documents for free;
      and position restore keys off block id, which survives font-size changes
      where pixel offsets do not. Mac does not force the change — either
      architecture needs a platform text view.
      **Accepted cost:** no selection across block boundaries (T-0023).
      **This decision is wrong if** the VoiceOver pass finds reading order or
      rotor navigation is bad across many small text views — that is the one
      piece of evidence that overturns it, and it must be checked before the
      Mac app. Decided on structure, not on profiling: T-0001 was never run, so
      the CPU question stays open and is orthogonal.
- [ ] Revert `ReaderRenderCache` unless profiling vindicates it — it bought
      nothing measurable and is currently unearned complexity.
- [ ] **Verify CloudKit sync on two real devices.** Entitlements and provisioning
      are confirmed correct, but sync has never been *observed working*. This is
      a load-bearing unverified assumption underneath the entire product.
- [ ] Re-run and extend the functional UI suite — `ReaderView` was rewritten and
      position restore, highlighting, and typography are unverified against it.

**Extractor hardening** *(prerequisite for public source)*
- [ ] Freeze ~30 real pages as HTML fixtures — Wikipedia, Paul Graham's
      table-era markup, lazy-loaded galleries, `<br><br>` paragraphs,
      meta-refresh redirects, paywalls, 404s.
- [ ] Assert titles, word counts, and block mixes against them. Extraction is
      currently validated only against *live* sites, so the checks aren't
      repeatable and can't gate a pull request.

**Durability**
- [ ] **Store the original HTML** alongside extracted blocks, compressed, in
      external storage. This was declined during the initial build; the library
      thesis reverses that call. Without it nothing can ever be re-extracted.
- [ ] **Export**: whole-library Markdown bundle and per-post EPUB. An archive you
      can't leave is a trap; export is a trust feature before a convenience one.
- [ ] Re-extraction command — rebuild blocks from stored HTML when the parser
      improves.

---

## Q2 (Dec 2026–Feb 2027) — Become a library, get accessible, ship a beta

**Shed the queue**
- [x] Rethink "unread" as a library concept, not an inbox. No badge counts.
      Recency and "never opened" become *filters*, not accusations.
- [ ] Make the backlog honest rather than hidden — if the pile is four months
      deep, say so plainly and offer to bulk-archive, rather than nagging.

**Reading experience**
- [ ] **Opening an article goes straight to full screen.** Reading is the point;
      having to ask for it every time is friction the app imposes on its own
      primary action. The chrome comes back on request — the exit affordances
      already exist and are labelled. Immersive is the state you *enter* a
      post in, not a mode you *switch to* once you are there.

**Retrieval, before intelligence**
- [x] Search result snippets with the matched phrase in context, highlighted.
- [ ] Saved searches and combined filters (site + tag + date + has-highlights).
- [ ] **Intent capture** — an optional one-line "why" at save time, searchable,
      shown in results. Cheap, unique, and the highest-signal field for Q3.

**Preservation**
- [ ] Periodic source liveness checks; badge dead sources
      *"this blog is gone — you still have it."*

**Accessibility** *(now a shipping requirement, not a nicety)*
- [ ] **Dynamic Type as the base, reader slider as a relative offset** — via
      `UIFontMetrics` / `Font.custom(size:relativeTo:)`. Someone on Accessibility
      XL must open the reader at a size that already works, before touching any
      control. Covers all 29 fixed-size call sites.
- [ ] `accessibilityLabel` on every icon-only control.
- [ ] VoiceOver pass over the reader — the per-block text views need sensible
      rotor navigation and reading order. Depends on the Q1 architecture call.
- [x] Contrast audit of the warm palette in all three reader themes.

**Ship a beta**
- [x] `PrivacyInfo.xcprivacy` with the `UserDefaults` reason declared.
- [ ] Privacy policy page — GitHub Pages off the public repo, zero cost. Apple
      requires a URL even when the answer is "nothing is collected".
- [ ] App Privacy nutrition label: **Data Not Collected.**
- [ ] First-run onboarding. The share extension is the primary capture path and
      is currently *invisible* to a new user — that's the single biggest
      first-session failure mode.
- [ ] Crash visibility without trackers: Xcode Organizer (Apple-collected,
      user opt-in) plus on-device MetricKit. No third-party SDK, ever. Accept
      that you will see less than a normal app does; that is the trade.
- [ ] Support channel: GitHub Issues on the public repo, plus an email.
- [ ] **Public TestFlight opens.**

**Open source**
- [ ] Extract `SwiftReadability` as an SPM package, with the Q1 fixtures as its
      test suite.
- [ ] `Tools/configure.sh` — rewrite team ID, bundle prefix, app group, and
      CloudKit container in one command, so contributors aren't blocked.
- [ ] Promote the existing local-store fallback to a documented first-class mode
      so a contributor with a free Apple account gets a working app.
- [ ] LICENSE, CONTRIBUTING, CI running the fixture suite, honest README.
- [ ] **Repo goes public.**

---

## Q3 (Mar–May 2027) — The bet: semantic retrieval

**Spike first, and be willing to lose** *(2 weeks, hard-timeboxed)*
- [ ] Embed 500+ real archived posts with `NLContextualEmbedding`.
- [ ] Measure: retrieval quality on 30 queries written from memory, index time
      per post, query latency, asset size, memory ceiling.
- [ ] **Gate:** if semantic retrieval is not *clearly* better than the existing
      keyword search on a real corpus, cut it. Ship no AI theatre.

**If the gate passes**
- [ ] Embed on save; backfill the archive in the background.
- [ ] Store vectors in SwiftData with external storage; sync via CloudKit as
      ordinary data — no architectural change.
- [ ] **Hybrid ranking.** Keyword *and* semantic, fused. Pure semantic is worse
      for exact terms — names, error strings, versions — and a library must nail
      those.
- [ ] **"Related in your library"** while reading: the three archived posts that
      connect to this one. Read-only, so it stays inside the trust rule. This is
      the feature that makes keeping an archive feel worthwhile.
- [ ] Explicitly **not** shipping: auto-tagging, auto-summaries, auto-filing.

**TestFlight throughout** — beta users are now the feedback loop that shapes
ranking quality. Use them.

---

## Q4 (Jun–Aug 2027) — App Store 1.0

**Committed**
- [ ] Performance and correctness at **5,000 posts**. The current design loads
      full `searchText` for every row, which is fine at 100 and probably not at
      5,000. Measure before optimising.
- [ ] **Tip jar** — one or two non-consumable IAPs. Nothing gated, no
      subscription. StoreKit work plus an App Review line item.
- [ ] App Store assets: description, keywords, screenshots. **The existing UI
      test screenshot pipeline generates these nearly for free** — it already
      captures library, reader, and highlights on both device classes.
- [ ] Age rating and App Review prep. Reader apps are well-established
      territory, but confirm the rating given the app displays arbitrary web
      content.
- [ ] **App Store 1.0 ships.**

**Stretch — cut this first if the quarter tightens**
- [ ] Native SwiftUI Mac app. Research and "find that thing" happen at a desk,
      and it's where an open-source project actually gets used. Depends on the
      Q1 text-architecture decision. Shipping a Mac app *and* an iOS 1.0 in one
      quarter is a lot; **iOS 1.0 is the commitment, Mac can slip to year two.**

---

## Explicitly not doing this year

| Not doing | Why |
|---|---|
| Newsletter ingestion | Requires a backend. Breaks the local-only story. The biggest content gap — revisit only if the no-server rule is reconsidered. |
| RSS / feed subscriptions | Turns a library into a firehose and the archive back into a landfill. |
| Audio / text-to-speech | Strongest **year two** candidate and the biggest behaviour unlock, but a large build competing directly with the AI bet. |
| Auto-tagging, AI summaries | Violates "AI never writes". Revisit only with strong evidence and an undo trail. |
| Sharing, collections, social | A personal library has no social surface. |
| Web app, Android | Requires a backend. |
| Subscriptions, ads, trackers, analytics SDKs | Non-negotiable. It's the product's stated identity and its privacy label depends on it. |
| Localization | Defer to year two unless TestFlight demand says otherwise. |

---

## Kill criteria

Written down now, while it's cheap to be honest.

1. **If the Q3 spike fails**, cut semantic search and spend the rest of the year
   on preservation, accessibility, and Mac. A library with excellent keyword
   search, real durability, and a great desktop app is still a good product.
   Shipping bad AI would be worse than shipping none.
2. **If you're saving fewer than three posts a week by month six**, the app isn't
   in your life and no feature will fix that. Diagnose capture friction first.
3. **If CloudKit sync proves unreliable across devices**, stop and rethink before
   the Mac app — a three-platform library on a sync layer you don't trust is a
   much worse problem than a two-platform one.
4. **If the extractor needs constant per-site patching**, it isn't a durable
   asset. Cap the negative-signal list and accept a quality ceiling rather than
   maintaining a rules engine forever.
5. **If TestFlight retention after 30 days is near zero**, the library thesis is
   wrong for other people even if it's right for you. That's fine — but then
   stop doing product work and go back to building it for yourself.

---

## Standing risks

- ~~**The reader's text architecture is unresolved.**~~ **Resolved 2026-08-25**
  in favour of per-block `UITextView`s. What remains open is narrower: the
  reader's *CPU cost* is still unprofiled (T-0001), and the decision carries a
  named failure condition — if VoiceOver reading order is bad across many small
  text views, revisit before the Mac app.
- **CloudKit sync is provisioned but unobserved.** Everything assumes it works.
- **`NLContextualEmbedding` document-level quality is unknown.** The Q3 bet rests
  on a spike that hasn't run.
- **No trackers means limited crash visibility.** Xcode Organizer only. Bugs
  will reach users that a normal app would have caught. Accepted deliberately.
- **Q4 is overloaded** if the Mac app stays in it. Protect the 1.0 date.
- **Apple could fold this into Safari Reading List.** Unlikely to be done well,
  but it's the existential case.

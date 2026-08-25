# Cairn — Roadmap

*Rewritten 2026-08-25, replacing the version written the day before. The display
name is still being settled; the bundle id, repo and code stay `Cairn` either
way.*

---

## What this is

A read-later app for one person who saves far more than he reads. Local-only, no
backend, no trackers, no third-party code, no AI. It is a passion project, not a
business, and it is not trying to beat anything.

**The measure is whether I open it tomorrow.** Not retention, not downloads, not
feature parity with GoodLinks.

---

## The reset

The previous roadmap was written for someone who searches a five-year archive.
That person isn't me. I save a lot, read little, don't go back and search, and
don't want the app writing or inferring anything.

That invalidates its first and loudest decision — *"a library, not a queue;
optimise retrieval, not throughput."* **It is a queue.** The pile is the enemy
and the win is converting saves into reads. Every retrieval feature the old plan
was built around — semantic search, related-articles, saved searches, intent
capture — was answering a question I don't have.

So the work is now exactly two things: **make reading pleasant, and make
capture effortless.** Plus tools I reach for when the pile gets stupid.

---

## Decisions that still stand

| Question | Decision |
|---|---|
| Backend | **Never.** CloudKit private database only. No server, no account. |
| Trackers, ads, analytics | **None, ever.** Data Not Collected, honestly. |
| Dependencies | **None.** Apple frameworks only; the extractor is our own. |
| Text sizing | **Dynamic Type is the base.** The reader's slider is a relative offset. |
| Guilt | **No badges, counts, streaks or nags.** Nothing speaks first. |
| Durability | Original HTML is stored, so a better parser can repair old saves. |

## Decisions that were overturned

| Was | Now |
|---|---|
| A library, not a queue | It is a queue. Optimise consumption, not retrieval. |
| The one bet: on-device semantic search | **Cut.** No AI at all. |
| Intent capture — the "why" at save time | **Cut.** I won't fill it in. |
| Export — Markdown bundle and EPUB | **Cut.** This is an import tool. |
| Make the backlog honest | **Cut.** Any depth-of-pile surface is a guilt engine. |
| TestFlight Feb 2027, App Store Aug 2027 | **No dates.** It ships when it's good. |
| Differentiate from GoodLinks | Not competing. It only has to be good for me. |

---

## What shipped

**Reading** — Dynamic Type end to end (77 hardcoded sizes → 0), the reader's
slider as a relative offset, a contrast audit that found real WCAG failures
(sepia secondary text at 4.45:1, the dock's active toggle at 2.28:1),
accessibility labels on every icon-only control.

**The archive** — original HTML stored compressed (LZFSE, ~23% of source), a
re-extraction command that rebuilds posts from it and re-anchors highlights only
on an unambiguous match, and **the truncation fix: articles whose content lived
in sibling sections were losing most of themselves at save time.** Frankenstein
extracted 8,239 of its 75,085 words. It now extracts 75,059.

**Retrieval** — search snippets with the matched phrase highlighted, ranked by
where the query's own words cluster.

**Hygiene** — the unread count is gone, `PrivacyInfo.xcprivacy` declares the
`UserDefaults` reason, and the extractor is asserted against 21 frozen fixtures
of real captured pages.

---

## Next

### Reading — the stated pain

- [ ] **Opening an article goes straight to full screen.** Reading is the point; asking for it every time is friction the app imposes on its own primary action.
- [ ] **Markup taps land.** A tap in markup mode places a text caret instead of highlighting roughly half the time — `UITextView`'s own recogniser races the custom one.
- [ ] **A scroll indicator that means something.** `LazyVStack` means only realised blocks count toward content height, so the bar measures a document that appears to grow as you scroll.
- [ ] **Profile the scroll cost.** 3.8s of CPU for 8 swipes, still unexplained. Cut once as "nobody is complaining" — reinstated, because *reading is unpleasant* is the complaint.
- [ ] **Images behave.** Tap to zoom, captions as captions, and galleries that currently yield nothing.
- [ ] **Reference lists are not prose.** Wikipedia backmatter is 40% of some pages and reads as article text.
- [ ] **VoiceOver through the reader.** Also the evidence that would overturn the per-block text architecture, if reading order turns out bad.

### Capture — the other stated pain

- [ ] **Failed saves are visible and retryable.** A paywalled save currently looks like a good one. For an app whose primary verb is *save*, silent failure is the worst possible bug.
- [ ] **Capture from anywhere.** Shortcuts, a widget, the Action Button — all through the one existing inbox. One pipeline, never two.
- [ ] **Import PDFs.** Papers and documents cannot get in at all. The largest hole, and now the largest build.
- [ ] **Titles and galleries.** Site suffixes left on titles, gallery images dropped, pages with no `<title>` falling back to the host.

### The pile — tools I reach for, never prompted

- [ ] **Time-to-read as a filter.** "What fits in seven minutes" turns a paralysing list into a menu. `wordCount` already exists.
- [ ] **Bulk archive.** Multi-select, archive-everything-before-a-date, never-opened as a filter. Invoked, never volunteered.

### Not a feature, but required

- [ ] **Watch sync work across two devices.** Never once observed. Everything assumes it.

---

## Explicitly not doing

| Not doing | Why |
|---|---|
| Any AI — search, tagging, summaries, answers | Decided. The fundamentals are the product. |
| Newsletters, RSS | Newsletters need a backend. RSS turns a pile into a firehose. |
| Audio / text-to-speech | Considered as the single biggest unlock for a big backlog, and rejected: I won't listen to articles. |
| Export | This is an import tool. |
| Sharing, collections, social | A personal library has no social surface. |
| Onboarding | There is one user and he wrote it. |
| Web, Android, a backend | Same reason as always. |
| Cross-block text selection | The accepted cost of per-block text views. Revisit with evidence, not before. |

---

## Kill criteria

1. **If I stop opening it, stop building features.** No feature fixes not wanting to use something. Find out why instead.
2. **If reading here is worse than Safari Reader**, nothing else matters. That is the whole product.
3. **If sync corrupts or loses data**, turn it off and ship local-only rather than debugging CloudKit forever.
4. **If the extractor needs constant per-site patching**, cap the rules and accept a quality ceiling.

---

## Standing risks

- **CloudKit sync has never been observed working.** Provisioned, entitled, assumed. Kill criterion 3 hangs off it.
- **Anything saved before the original-HTML change is permanently truncated.** No stored source means no repair. The damage stopped; it was not undone.
- **Scroll cost is unprofiled.** The prime suspect for reading feeling unpleasant.
- **The per-block text architecture is unproven for VoiceOver.** Decided on structure, not measurement, with a named failure condition.
- **The display name is unresolved.** Two candidates were already taken at reservation despite looking free in store search.

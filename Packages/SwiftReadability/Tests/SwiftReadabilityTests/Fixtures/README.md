# Fixtures

Frozen HTML the extractor is asserted against. Adding one is dropping in two
files: `<name>.html` and `<name>.json` (the expectation). `FixtureLoader`
enumerates the directory at runtime, so nothing needs registering.

## Two kinds, and the difference matters

**Real captures** are listed in `PROVENANCE.md`, which records the shape each
one covers, its licence, and its capture date. These exist because the
roadmap's complaint is that extraction "is currently validated only against
*live* sites, so the checks aren't repeatable" — fabricated inputs do not fix
that. Real pages carry the idiosyncrasies the extractor's heuristics were
actually tuned against.

**Hand-authored shapes** have no row in `PROVENANCE.md` — the absence of a row
is the signal that a fixture is synthetic. They are legitimate only for
*mechanical* edge cases where the parser's behaviour, not real-world prose, is
the subject: meta-refresh redirects, malformed nesting, paywall interstitials.
They are not a substitute for a real capture of an article, and are not added
for shapes the real corpus already covers.

## Not every real capture has an expectation

A `.html` file with no matching `.json` is a real capture the extractor
currently handles badly — recorded rather than silently made to look correct.
`FixtureLoader.allNames` derives its list from `.json` files, so these sit
inert until `ArticleExtractor` or `HTMLParser` is fixed; nothing here is a
placeholder waiting to be filled in with whatever the extractor happens to
produce today, because that would assert a bug as if it were the intended
shape. As of the last audit (T-0028), every real capture in the corpus has a
frozen expectation — see "Fixed by T-0028" below for the three that didn't
until now.

### Fixed by T-0027: sibling-section truncation

Until T-0027, `gutenberg_frankenstein`, `mdn_fetch_api`,
`python_docs_tutorial`, `w3c_html4_tables`, `wikipedia_readability`, and
`wikinews_story` had no expectation here for the same root cause: real
content spread across several sibling sections (`<section>`, `<div
class="chapter">`, wiki `<h2>` sections, or a chain of `<table>` boxes)
rather than one container, where `ArticleExtractor.bestCandidate` picked the
single best-scoring sibling and silently dropped the rest — on
`gutenberg_frankenstein` that meant keeping chapter 24 alone and losing 24
chapters and 4 letters. `bestCandidate` now climbs past a shared ancestor
when either the ancestor's own score is nearly as good as the winner's (the
original check, for recovering a wrapper holding excluded intro paragraphs),
or when more than one of the ancestor's children independently holds content
within the same order of magnitude as the winner — judged against the
richest score found *anywhere in that child's subtree*, not the ancestor's
own diluted aggregate, so it isn't defeated by extra wrapper levels (a
`<table><tbody><tr><td>` chain, say) the way the three-level ancestor-credit
limit was. Pure single-child scaffolding (a table row around one cell, a div
wrapping one div) is climbed through for free since there is no sibling to
compare against. All six now have expectations reflecting complete
extraction; `mdn_img_element` and `wikipedia_epub`, which already extracted
completely, are unaffected by the change.

`wikipedia_readability`'s frozen expectation is worth calling out
specifically: its category-footer links (`#catlinks`) stay out, because they
sit outside the `mw-parser-output` div entirely and are never part of the
climbed subtree — but its References, Further reading, and External links
sections stay *in*, alongside Definition, Applications, and the formula
sections. There is no way to exclude those sections generically without
also excluding the structurally-identical References/Notes/External-links
sections in `wikipedia_epub.json`, which is frozen with that content
included and must not regress. Any rule keyed on the `mw-references` class,
on a "References"/"External links" heading, or on list-shape (many short
list items) matches both pages' footnote sections equally; the only
observed difference between them (how large the citation cluster is
relative to the rest of the page) is proportionally similar on both pages
and would be threshold-tuning, not a structural distinction. Excluding
`wikipedia_readability`'s backmatter was not achieved for this reason — see
the T-0027 report.

The sibling-scoring cause was isolated with a synthetic page — several
`<div class="chapter">` elements as direct siblings of `<body>`, nothing else
— which reproduces the same single-chapter-survives behaviour seen on
`gutenberg_frankenstein`, confirming the shape of the page rather than its
prose is what triggers it. That reproduction is now
`ExtractorTests.siblingSectionsAllSurvive`.

While building `malformed_nesting.html`, an unclosed `<h1>` (no matching
`</h1>`) turned out to swallow every element after it as its own descendant:
`HTMLParser`'s implicit tag-closing only knows a fixed set of peer tags
(`p`/`li`/`dt`/`dd`/`tr`/`td`/`th`/`option`/`thead`/`tbody`/`tfoot` — see
`HTMLTag.selfClosingPeers`), and a heading opening a new `<p>` isn't one of
them, unlike a browser's implied-end-tag handling. Combined with
`ArticleExtractor.polish()`'s "drop a leading heading that repeats the title"
step — the swallowed heading's text *is* the title, character for character —
the entire page loses all of its content, not just its heading. The fixture
here keeps its `<h1>` closed so it exercises the nesting cases it's named for
instead of this unrelated one; the unclosed-heading behaviour is recorded here
rather than turned into a fixture of its own.

### Fixed by T-0028: gallery images, title suffixes, and the missing-title fallback

Three more real captures had no expectation for three unrelated reasons; all
three now do.

`commons_gallery`'s 28 real, non-lazy `<img>` elements sit inside
`<li class="gallerybox">`, each wrapping a `<div class="thumb">` (the image)
and a `<div class="gallerytext">` (a filename-and-size caption) rather than
being a `<ul>`/`<ol>` nested somewhere below the winning candidate — on this
page the gallery `<ul>` *is* the winning candidate, so `BlockBuilder` descends
straight into its `<li>` children as stray list items. Neither that `"li"`
case in `emit()` nor `appendList`'s per-item extraction ever looked inside an
item for an image, so every photo was dropped and only the caption text
survived. Both now check whether an item's image sits inside a genuine
block-level wrapper of its own — the same `cellHoldsBlockContent` test a table
cell is judged by, reused here — and if so pull it out as an image block with
the rest of the item's text riding along as its caption, instead of
flattening the item to a plain paragraph. An item whose image is stitched
inline into a run of prose instead (no block wrapper around it) is
untouched: this is what keeps `wikipedia_readability`'s MathJax
fallback-image list items — three `<li>`s under its "Artificial intelligence"
section, each an inline formula rendered as an `<img>` alongside surrounding
words with no wrapping `<div>` — reading as text, exactly as before.

`gnu_philosophy`'s title carried its full "Article - Section - Site" `<title>`
tag verbatim — `"What is Free Software? - GNU Project - Free Software
Foundation"` — because the page has no `<h1>` (its top heading is an `<h2>`)
and no `og:site_name`, so the only site-identity signal `trimmingSiteSuffix`
had to check the trailing segment against was the request host, and this
fixture's capture carries no `<link rel="canonical">` or `og:url` either,
so that host is the fixture harness's placeholder `example.com` — nothing
close to "Free Software Foundation". `trimmingSiteSuffix` now also collects
candidate site names from the page's own ARIA `role="banner"` landmark: every
link's text inside it, on the theory that a site's own banner conventionally
names it even when no meta tag does. On this page that pulls in "Free
Software Foundation" from a "Supported by the Free Software Foundation"
credit next to the GNU logo, which is enough to confirm the title's trailing
segment is site chrome. Once confirmed, the trimmer no longer stops at
stripping only that last segment: a title chained on the *same* separator
more than once is a breadcrumb, not prose that happens to contain a dash, so
it now cuts back to the first occurrence of that separator instead of the
last, dropping "GNU Project" along with "Free Software Foundation" rather
than leaving it stuck to the headline. None of the 18 previously-frozen
fixtures repeat the same separator twice in their title, so this only ever
changes behaviour here.

`rfc_editor_2616`'s capture has no `<html>`, `<head>`, `<title>`, or `<h1>` at
all — its visible heading is `<span class="h1">Hypertext Transfer Protocol --
HTTP/1.1</span>`, a styled span standing in for a real heading tag, and the
page in fact uses the same convention down through `class="h2"`/`"h3"`/`"h4"`
for its section headings. `ArticleMetadata`'s title fallback chain now ends
with one more entry, after `<title>` itself: the text of the first element
anywhere in the document carrying an exact `class="h1"` token. It only ever
fires when every earlier source — Open Graph, JSON-LD, a real `<h1>`, a real
`<title>` — has already come up empty, which no previously-frozen fixture
triggers, so this is a pure addition. The body text itself was already
captured completely and correctly (all 176 pages, none dropped); this was a
title-only defect.

## Licensing

This repository goes public. Every real capture is from a permissively licensed
or public-domain source — Wikimedia projects, MDN, GNU, W3C, IETF, Project
Gutenberg, Apache, Python docs. **Do not add a capture of an all-rights-reserved
page.** If a shape only exists on a proprietary site, hand-author the shape and
say so.

## Refreshing

Captures are frozen deliberately: a fixture that changes under you is not a
fixture. Re-capture only when a shape genuinely needs updating, and update the
`captured` date when you do.

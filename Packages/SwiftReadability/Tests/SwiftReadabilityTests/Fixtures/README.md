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
shape. As of the last audit (T-0006), these have no expectation:

- `commons_gallery` — the gallery's real, non-lazy `<img>` elements sit inside
  `<li class="gallerybox">`. `BlockBuilder`'s `"li"` case (a stray list item
  outside a list) always converts to a text paragraph and never looks for an
  image inside; the same is true for `appendList`'s per-item text extraction.
  Every one of the 28 photos is dropped; only the filename-and-size caption
  text survives.
- `gnu_philosophy` — content extraction is complete, but the title carries the
  page's full "Article - Section - Site" `<title>` tag verbatim
  (`"What is Free Software? - GNU Project - Free Software Foundation"`). The
  page has no `<h1>` (its top heading is an `<h2>`) and no `og:title`, so
  `ArticleMetadata` falls back to `<title>`; `trimmingSiteSuffix` only checks
  the text after the *last* separator, which here is "Free Software
  Foundation" and never matches any token derived from `gnu.org`.
- `rfc_editor_2616` — the capture has no `<html>`, `<head>`, `<title>`, or
  `<h1>` at all (the page's visible heading is a `<span class="h1">`, not a
  real heading element), so every entry in `ArticleMetadata`'s title fallback
  chain comes up empty and it lands on the request URL's host. The body text
  itself is captured completely and correctly — all 176 pages, none dropped —
  so this is a title-only defect.

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

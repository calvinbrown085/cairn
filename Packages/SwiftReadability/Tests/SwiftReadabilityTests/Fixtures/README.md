# Fixtures

Frozen HTML the extractor is asserted against. Adding one is dropping in two
files: `<name>.html` and `<name>.json` (the expectation). `FixtureLoader`
enumerates the directory at runtime, so nothing needs registering.

## Two kinds, and the difference matters

**Real captures** carry a `<name>.source.json` recording the source URL, the
shape they cover, the licence, and the capture date. These exist because the
roadmap's complaint is that extraction "is currently validated only against
*live* sites, so the checks aren't repeatable" — fabricated inputs do not fix
that. Real pages carry the idiosyncrasies the extractor's heuristics were
actually tuned against.

**Hand-authored shapes** have no `.source.json`. They are legitimate for
*mechanical* edge cases where the parser behaviour, not real-world prose, is
the subject: meta-refresh redirects, malformed nesting, paywall interstitials.
They are not a substitute for a real capture of an article.

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

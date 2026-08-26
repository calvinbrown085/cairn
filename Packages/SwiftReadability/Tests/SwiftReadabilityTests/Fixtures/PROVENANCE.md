# Provenance of real captures

Every fixture below is a frozen capture of a real page. Hand-authored
shapes are not listed here — the absence of a row *is* the signal that a
fixture is synthetic.

This lives in Markdown rather than in per-fixture JSON sidecars for a
concrete reason: `FixtureLoader.allNames` derives fixture names from every
`*.json` in this directory, so a sidecar named `<name>.source.json` is read
as a fixture called `<name>.source`, whose `.html` does not exist — which
crashes the whole suite through `fatalError`. That is exactly what happened
when these were first committed. Do not reintroduce `.json` files here that
are not fixture expectations.

| Fixture | Shape | Licence | Captured | HTTP |
|---|---|---|---|---|
| `apache_license` | legal prose, nested lists | Apache 2.0 | 2026-08-25 | 200 |
| `commons_gallery` | lazy-loaded image gallery, thumbnails | CC BY-SA 4.0 | 2026-08-25 | 200 |
| `gnu_philosophy` | 1990s markup, plain prose | CC BY-ND 4.0 | 2026-08-25 | 200 |
| `gutenberg_frankenstein` | very long document, br paragraphs | public domain | 2026-08-25 | 200 |
| `mdn_fetch_api` | code blocks, sidebars, nested lists | CC BY-SA 2.5 | 2026-08-25 | 200 |
| `mdn_img_element` | figures, captions, srcset, code | CC BY-SA 2.5 | 2026-08-25 | 200 |
| `notfound_404` | 404 page | CC BY-SA 4.0 | 2026-08-25 | 404 |
| `python_docs_tutorial` | sphinx layout, code blocks, sidebar nav | PSF, freely distributable | 2026-08-25 | 200 |
| `rfc_editor_2616` | pre-formatted text, anchors | IETF Trust, freely distributable | 2026-08-25 | 200 |
| `w3c_html4_tables` | table-era markup, prose in cells | W3C Document License | 2026-08-25 | 200 |
| `wikinews_story` | news layout, bylines, datelines | CC BY 2.5 | 2026-08-25 | 200 |
| `wikipedia_epub` | tables, infobox, footnotes | CC BY-SA 4.0 | 2026-08-25 | 200 |
| `wikipedia_readability` | infobox, references, edit links, categories | CC BY-SA 4.0 | 2026-08-25 | 200 |
| `wikisource_essay` | long prose, old typography, page anchors | public domain | 2026-08-25 | 200 |
| `gnu_make_manual` | very long single-page manual, code blocks, endnote-style index | GNU FDL 1.3 | 2026-08-25 | 200 |
| `gutenberg_the_prince` | very long document, translator's footnotes | public domain | 2026-08-25 | 200 |
| `rfc_editor_9110` | very long multi-section spec, code/ABNF blocks, split title heading | IETF Trust, freely distributable | 2026-08-25 | 200 |
| `wikibooks_python_programming` | doc chapter wrapped in TOC sidebar, code blocks | CC BY-SA 3.0 | 2026-08-25 | 200 |
| `wikipedia_ada_lovelace` | biography, dense inline footnote markers | CC BY-SA 4.0 | 2026-08-25 | 200 |
| `wikipedia_french_tour_eiffel` | non-English (French) prose, infobox | CC BY-SA 4.0 | 2026-08-25 | 200 |
| `wikipedia_world_war_two` | very long multi-section article, inline footnotes | CC BY-SA 4.0 | 2026-08-25 | 200 |

_21 real captures._

`wikipedia_flag_gallery` is also a real capture (CC BY-SA 4.0, 2026-08-25, HTTP 200,
https://en.wikipedia.org/wiki/List_of_national_flags_of_sovereign_states) but is
deliberately excluded from the count above and has no `.json` expectation — see
"Known but unfixed: the flag table" in `README.md`.

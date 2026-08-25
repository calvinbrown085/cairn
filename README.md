# Stacks

A native iOS and iPadOS app for saving blog posts and keeping them — the full
article text and images, extracted from the page, stored on device, and synced
across your devices with iCloud.

Built entirely in Swift: SwiftUI, SwiftData, and CloudKit, with no third-party
dependencies. The HTML parser and article extractor are part of the app.

## Getting started

The Xcode project is generated from `project.yml`, so it isn't checked in:

```sh
brew install xcodegen     # once
xcodegen generate
open Stacks.xcodeproj
```

Then build and run. Signing is already configured for team `ZM4J56DC3Q`.

## What it does

**Saving.** Share a link from Safari (or anywhere), paste one with the **+**
button, or let the app offer a URL it finds on your clipboard. Stacks fetches
the page, pulls out the article, downloads the images, and stores the lot.

**Finding.** Full-text search across every archived article — titles, authors,
tags, and body text. Filter by Unread, Starred, or Archived; group by tag or by
site. The library draws as cards — cover, headline, opening lines — or as rows
where you would rather see more of it at once.

**Reading.** A reader built for long text: New York or SF, three themes, and
adjustable size, leading, and column width. A floating dock holds the four
things you reach for without leaving the page, and full screen puts even that
away. Your position in each article is remembered, and shown as a hairline
rather than a percentage.

**Marking up.** Put the pen out and the dock becomes a tray: four highlight
tints, three inks, notes, and an eraser. Tap a sentence to highlight it — no
selection handles, no menu — or draw on the page freehand with Apple Pencil.
Everything you add is anchored to the text, not to the pixels.

**Syncing.** Posts, images, highlights, ink, and reading position sync through
your private CloudKit database. Reading preferences sync through iCloud key-value
storage. Nothing goes anywhere else.

## How it's put together

```
Stacks/
  App/          Entry point and the CloudKit-backed ModelContainer
  Models/       Post, StoredImage, Highlight, InkStroke  (SwiftData, CloudKit)
  Content/      HTML parser, article extractor, block model
  Services/     Fetching, image archiving, the share inbox, URL canonicalisation
  Design/       Palette, reader themes, typography, preferences
  Views/        Library, reader, sheets
StacksShareExtension/   The share sheet target
StacksUITests/          Launch-to-read smoke tests
```

### Extraction

`Stacks/Content` is the interesting part. A page arrives as HTML and leaves as a
flat list of typed blocks — headings, paragraphs, quotes, code, lists, images —
which the reader renders in whatever typography you've chosen.

1. **`HTMLParser`** builds a tree. Real-world blog HTML is rarely well-formed,
   so it handles implicit tag closing, unquoted attributes, raw-text elements,
   and stray `<`, preferring a reasonable tree over a correct rejection.
2. **`ArticleExtractor`** strips the furniture (navigation, share bars, comment
   sections, post indexes), then scores what remains by how much prose it holds:
   text length, comma count, and paragraph density, propagated up to parents.
   The highest-scoring subtree wins, discounted by how much of it is links.
3. **`BlockBuilder`** walks the winner and emits blocks, resolving lazy-loaded
   image sources and `srcset`, and splitting `<br><br>` paragraphs apart for
   sites that predate CSS.
4. **`ArticleMetadata`** reads the headline, byline, and dates from Open Graph,
   JSON-LD, and the markup, in that order of trust.

Extraction is checked against a spread of real sites — Wikipedia, Paul Graham's
table-based HTML, lazy-loading image galleries, Substack-era blogs — and runs in
tens of milliseconds off the main actor.

### Highlights and ink

Highlights anchor to a **block index plus a character range within that block's
plain text**, not to a pixel offset or a DOM path. That's what lets them survive
a font change, a theme change, a different device, and a re-extraction. Each
prose block is its own `UITextView`, which is what makes the anchor natural —
and is also the only way to learn what the reader selected, since SwiftUI's
`Text` won't report a selection.

A highlight can be made two ways. Dragging a selection and choosing **Highlight**
takes exactly what you chose. In markup mode, a tap resolves to the sentence it
landed in — the unit a reader actually decides about — and becomes the same kind
of character range.

Ink follows the same rule one level up: a stroke belongs to a block, and its
points are stored in that block's own unit space rather than in screen
coordinates. A line drawn at 19pt New York still sits over the same sentence at
26pt SF Rounded. Strokes are captured from `coalescedTouches`, so a pencil moving
faster than the display still draws a curve rather than a polygon.

### The share extension

The extension does no networking and never touches SwiftData or CloudKit. It
writes one small JSON file into the shared app-group inbox and exits. The app
drains that inbox when it next becomes active, then fetches and extracts. This
keeps sharing instant and stays well inside the extension's memory budget.

### CloudKit notes

Every model property has a default value and every relationship is optional,
which CloudKit requires. Article bodies and image bytes use
`@Attribute(.externalStorage)` so they sync as assets instead of bloating
records, and images are downscaled to 1600px before storage. If the iCloud
container isn't available, the app falls back to a local store rather than
failing to launch.

## Tests

```sh
xcodebuild test -project Stacks.xcodeproj -scheme Stacks \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`StacksUITests` drives the real flows — open the library, read a post, change
the typography, highlight a passage — and attaches screenshots to the result
bundle so a visual change can be reviewed, not just its exit code.

## Configuration

| | |
|---|---|
| Bundle ID | `com.calvinbrown.Stacks` |
| Share extension | `com.calvinbrown.Stacks.ShareExtension` |
| App group | `group.com.calvinbrown.Stacks` |
| CloudKit container | `iCloud.com.calvinbrown.Stacks` |
| Team | `ZM4J56DC3Q` |
| Minimum OS | iOS / iPadOS 18 |

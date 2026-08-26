# Checks only a person with the app can do

Five things are blocked on a screen and a pair of hands. None can be answered
in the build environment: there is no display session there, so `screencapture`
fails outright and no GUI automation is possible. One agent spent 152k tokens
discovering that.

They are ordered by what a wrong answer would cost.

---

## 1. Does tapping an image drop you out of full screen?  *(T-0048)*

**On iPad.** Open an article, tap an image, dismiss it.

- Is the reader still full screen?
- Is the library column still collapsed?

**Why it matters.** `ReaderView.onDisappear` calls `onImmersiveChange(false)`,
and `RootView` uses that to restore the split view. If SwiftUI fires
`onDisappear` when a *descendant* presents a `fullScreenCover` — which
`ArticleBlockView` now does for images — then every image tap quietly undoes
full screen. If the library comes back, it is real and becomes a fix.

## 2. Does the VoiceOver rotor see the whole article?  *(T-0013 / T-0002)*

**Turn VoiceOver on.** Open a long article. Twist two fingers to open the
rotor, choose **Headings**, and note what is listed. Now scroll deep into the
article and open the rotor again.

- Did the list change?

**Why it matters — this is the most consequential item here.** The reader's
architecture decision (per-block `UITextView`s rather than one TextKit 2 view)
was recorded with a named failure condition: it is wrong if rotor navigation is
bad. `LazyVStack` only materialises blocks near the viewport, so the rotor may
only ever list headings currently on screen. If the list changes with scroll
position instead of showing the document's outline, that confirms a defect no
accessibility attribute can fix, and the architecture call gets revisited.

## 3. Why does scrolling cost so much?  *(T-0001)*

**Instruments, Time Profiler.** Open a long article, swipe 8 times.

3.8s of CPU is unaccounted for. One hypothesis was tested and disproved
(attributed-string and height caching). The prime remaining suspect is
`.scrollPosition(id:)` forcing a full body re-evaluation per block crossing.

**Why it matters.** You said reading felt unpleasant. This is the only
unexplained performance number left, and it was nearly cut as "nobody is
complaining" before you said exactly that.

## 4. Do links still look right, and can VoiceOver open them?  *(T-0051)*

**In each of the three reader themes**, find an article with a link in the prose.

- Is it the theme's accent colour, not system blue?
- Does tapping it open the way it always did — no Safari hand-off, no
  long-press menu appearing?
- With VoiceOver on, find it via the **Links** rotor and double-tap. **Does it
  actually open?**

**Why it matters.** Links now carry the standard `.link` attribute so the rotor
can see them, with `linkTextAttributes` overridden to keep your colours and
UIKit's own tap handling declined so the app's handler still runs. The last
question is genuinely open: VoiceOver's synthetic activation may route through
the app's gesture recogniser, or dead-end on that declined action.

## 5. Does a PDF actually render?  *(T-0037 / T-0050)*

Share a PDF into Cairnfield from Files or Mail.

- Does it appear in the library, and does searching its text find it?
- Does tapping it show its pages?
- Does a damaged file say "Couldn't open this PDF" rather than showing blank?

**Why it matters.** The whole path was built and gate-verified but never once
run on a screen. It is the newest and least observed feature in the app.

# App Store listing — Cairnfield

Everything App Store Connect asks for, in one place. Copy from here.

---

## Name (30 char max)

    Cairnfield

*(10 characters. **Reserved in App Store Connect 2026-08-25.**)*

## Subtitle (30 char max)

    A quiet place for reading

*(25 characters.)* Alternatives, all within the limit:
`Read later, kept on device` (26) · `Your reading, kept private` (26) · `Save now, read properly` (23)

---

## Promotional text (170 char max, editable without review)

    Everything you save stays on your devices and syncs through your own iCloud.
    No account, no server, no trackers, no ads. Just a good place to read.

*(146 characters.)*

---

## Description (4000 char max)

    Cairnfield keeps what you read.

    Save an article and it becomes yours — the text, the pictures, and the
    original page underneath — stored on your own device and synced through
    your own iCloud. There is no account to create and no server of mine
    holding your reading.

    A cairnfield is a landscape scattered with stacked stones, each one marking
    something worth finding again. That is roughly the idea.

    READING FIRST

    Articles open clean and full screen, with the clutter stripped away. Three
    reading themes — paper, sepia and night. Type follows your system text
    size, so if you read large everywhere else, you read large here too, and
    the size slider adjusts from there rather than fighting it.

    KEEPS THE ORIGINAL

    Most read-later apps store only what their reader could extract on the day
    you saved. Cairnfield keeps the original page as well, compressed and out
    of the way, so a better reader later can rebuild an older save rather than
    leaving it frozen at whatever the parser managed at the time.

    FIND IT AGAIN

    Full-text search shows the matching phrase in context, so you can tell
    which result is the one you meant before opening it. Filter by tag, by
    site, by whether you have opened it — or by how long it will take, when
    you have seven minutes and want something that fits.

    MARK IT UP

    Highlight passages, write notes, and draw freehand over the page.
    Highlights anchor to the words themselves, not to a scroll position, so
    they stay put when the text reflows at a different size.

    QUIET BY DESIGN

    No unread badge counting at you. No streaks, no daily digests, no
    reminders to catch up on your own reading. The pile is just there, and you
    read what you feel like.

    PRIVATE BY CONSTRUCTION

    Cairnfield collects nothing. There are no analytics, no advertising, and no
    third-party code of any kind — the app uses only Apple's own frameworks.
    The only network requests it makes are fetching the pages you chose to
    save, directly from those sites. Sync runs through your personal iCloud
    database, which I cannot read.

    The whole app is open source.

*(~1,950 characters.)*

---

## Keywords (100 char max, comma separated, no spaces after commas)

    read later,reader,offline,save,article,bookmark,highlight,annotate,private,rss,readwise,pocket

*(94 characters.)* Deliberately includes competitor terms people actually search
for. Excludes the app name — Apple indexes that separately, so spending
characters on it is waste.

---

## Support URL

    https://github.com/calvinbrown085/cairn/issues

## Marketing URL

    https://cairn.calvinbrown.dev

## Privacy Policy URL  (required)

    https://cairn.calvinbrown.dev/privacy.html

---

## Age rating

**Answer: 4+.**

Every content question is No — no violence, profanity, sexual content, drugs,
gambling, or horror themes. The app ships no content of its own.

The one question that needs thought, and the honest answer:

> **Unrestricted Web Access — YES.**

Cairnfield displays pages the user chooses to save from the open web, so it can
render arbitrary content. Answering No would be false and is the kind of thing
App Review checks. Note that on current App Store rating rules, unrestricted
web access does **not** by itself force a 17+ rating the way it once did — the
questionnaire handles it — but answer it truthfully and let the rating fall out.

There is no user-generated content, no social features, no messaging, and no
way for one user to see another's anything, so none of those questions apply.

---

## App Privacy ("nutrition label")

**Data Not Collected**, for every category.

This is literally true rather than aspirational: there is no analytics SDK, no
crash reporter, no advertising identifier, and no third-party code at all. An
automated check in the repository rejects any change introducing an import
outside Apple's frameworks, so it stays true.

The app declares one required-reason API in its privacy manifest:
`UserDefaults`, reason `1C8F.1` — shared between the app and its share
extension so a link saved from another app arrives correctly.

---

## Screenshots

Run `Tools/screenshots.sh` from the repo root. Output lands in
`screenshots/<device>/`, numbered in upload order:

    screenshots/ipad-13/01-library.png
    screenshots/ipad-13/02-full-screen-article.png
    ...

Both `screenshots/` and `.dd-screenshots/` are gitignored — they are build
artefacts, and this repository is public.

Both devices work. The iPhone half was blocked on T-0049 (compact-width
navigation landed on the wrong column); that shipped, and the script now
targets iPhone 14 Plus at 1284×2778, one of the source sizes Apple accepts.

## Uploading a build

Run `Tools/upload-appstore.sh` from the repo root. It gates, archives, signs
for distribution, and uploads. Uploading is not submitting — the build sits in
App Store Connect until someone attaches it to a version in the web UI.

The team ID is `ZM4J56DC3Q`, from `DEVELOPMENT_TEAM` in `project.yml`. It is
not the ID in the certificate name (`VE8UL5JBLS`), which identifies the person
rather than the team; passing that one fails with "No Account for Team", which
sounds like a signed-out Xcode and is not.

The one credential the script cannot supply is Xcode's own Apple ID session —
`-allowProvisioningUpdates` uses it to mint the distribution certificate and
App Store profile on demand, and to authenticate the upload. If export starts
failing, check Xcode > Settings > Accounts first.

**Uploaded so far:** 1.0 (1), from `12eb31f`, on 2026-08-25.
Bump `CURRENT_PROJECT_VERSION` before re-uploading under the same version —
App Store Connect refuses a build number it has already seen.

## Category

Primary: **Productivity**. Secondary: **News**.

Reference (Productivity) rather than News as primary — this is a tool for
keeping and reading, not a feed.

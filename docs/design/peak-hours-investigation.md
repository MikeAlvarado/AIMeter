# Peak-hours investigation

Status: **Part 1 confirmed (b) — see Conclusion. Part 2 (recommendation)
written below. All four phases are implemented** — `PeakCalculator` +
`ClaudePeakSchedule` + tests (Phase 1), the Provider Detail "Peak hours"
card (Phase 2), menu bar/widget glance badges with the multi-entry
timeline auto-flip (Phase 3), and the off-by-default `peak.` notification
family (Phase 4). Both platforms build warning-free and the full UsageKit
suite (83 tests, including 15 for `PeakCalculator`) passes — see
"Implementation notes" after the phased plan.

Context: Anthropic's documented weekday-peak-usage policy (5-hour session
usage burns ~2x faster 5:00-11:00 AM PT / 8-2 ET / 12-6 GMT on weekdays,
weekends fully off-peak) has changed repeatedly — introduced ~March 2026,
reverted 2026-05-06, apparently back again (per a scheduler warning the
user has seen). This doc only records what was *verified empirically*
during this investigation. Nothing here should be read as a confirmed wire
format until marked "confirmed."

## 1. Endpoint payload inspection

**Tooling added:** `Scripts/probe-peak-hours.sh` — a sibling to the
existing `Scripts/probe-usage-endpoint.sh`. It calls both
`GET /api/oauth/usage` and `GET /api/oauth/profile` with the same
Claude-Code-mirroring auth headers, dumps the complete, unfiltered raw
JSON of both (not just the fields `ClaudeUsageResponse`/
`ClaudeProfileResponse` currently map), records capture time in UTC/local/
`America/Los_Angeles`, and greps both bodies for
`peak|multiplier|surge|off_peak|offpeak|schedule|tier|factor|weight|"rate"|cost`.
With `-o DIR` it also saves timestamped JSON so two captures can be
diffed later. Real captures (with account PII) are saved under
`docs/design/reference/peak-hours/` — gitignored, matching the existing
`docs/design/reference/` convention, **never commit these**.

**Captures compared:**

| Capture | When (UTC) | Local (Mexico, CST) | PT equivalent | Day | Peak per documented policy |
|---|---|---|---|---|---|
| `Scripts/sample-response.json` (pre-existing repo fixture) | unknown (predates this investigation; not controlled for peak state) | — | — | unknown | unknown |
| Capture A (off-peak baseline) | 2026-08-03T04:32:15Z | 2026-08-02 22:32 CST (Sun) | 2026-08-02 21:32 PDT (Sun) | Sunday | **Off-peak** (weekend — unambiguous) |
| Capture B (peak window) | 2026-08-03T15:03:09Z | 2026-08-03 09:03 CST (Mon) | 2026-08-03 08:03 PDT (Mon) | Monday | **Peak** (weekday, 08:03 PT is inside the documented 5-11 AM PT window) |

Files: `docs/design/reference/peak-hours/{usage,profile,meta}-20260803T043216Z.json` (A) and
`docs/design/reference/peak-hours/{usage,profile,meta}-20260803T150310Z.json` (B).

**A vs. B diff result — this is the key finding.** Ran a structural
key-path diff (`jq 'paths'`, sorted) plus a full value diff on both
`usage` and `profile` bodies:

- `profile` responses (A vs B): **byte-identical** after key-sorting.
  Zero diff, as expected for static account data.
- `usage` responses (A vs B): **identical key structure** — same keys
  present, same keys null, nothing added or removed. The only value
  differences are exactly what normal usage/time progression explains:
  `five_hour.utilization` and its `limits[0].percent` changed (20 → 0,
  because a new 5-hour session had started fresh by capture B),
  `resets_at` advanced on both the session and weekly windows (time
  passing), `seven_day.utilization` ticked 3 → 4 (normal usage), and
  `is_active` flipped between the session and weekly `limits[]` entries
  (session inactive at capture B vs. active at capture A — this is the
  existing, already-mapped "which window currently governs" flag,
  `ClaudeUsageResponse.Limit.isActive`; it tracks real session state, not
  time-of-day).
- No new key, no multiplier, no weight, no cost factor, no schedule
  object appeared during the peak window. The always-null codenamed
  fields (`tangelo`, `iguana_necktie`, etc.) were **still null** during
  peak, on this Pro account.
- Nothing in the peak-window body matched the same grep pattern beyond
  the same static `rate_limit_tier` hit already dismissed above.

**This directly confirms:** on this account (Claude Pro), the
`five_hour`/`session` `percent` **is a plain linear utilization number,
not something the server pre-multiplies for peak** — it read `0%` at the
start of a fresh session at 08:03 AM PT, inside the peak window, with no
extra field indicating "this session is currently burning 2x." Whatever
peak burn-rate effect exists, it must show up *implicitly*, over time, as
the same session's `percent` climbing faster per unit of actual usage
than it would off-peak — the endpoint does not annotate it explicitly.

**Field-by-field result (both captures, both endpoints):** no key or
string value anywhere in either full response matches `peak`,
`multiplier`, `surge`, `off_peak`/`off-peak`, `schedule`, `factor`,
`weight`, or `cost`. The one grep hit was `"rate_limit_tier":
"default_claude_ai"` in `/api/oauth/profile` — a **static plan-tier
label** (present in both captures, identical value), not a time-varying
signal; it classifies the account's rate-limit bucket (Pro vs Max vs
Team), unrelated to time-of-day.

**Confirmed absent from `/api/oauth/usage`, this account, both captures:**
`five_hour`, `seven_day`, `limits[]` (all kinds), `spend`, `extra_usage`
carry no field beyond what `ClaudeUsageResponse.swift` already maps.

**Present but unmapped, null in both captures on this Pro account:**
`seven_day_oauth_apps`, `seven_day_opus`, `seven_day_sonnet`,
`seven_day_cowork`, `seven_day_omelette`, `tangelo`, `iguana_necktie`,
`omelette_promotional`, `nimbus_quill`, `cinder_cove`, `amber_ladder`.
These are internal Anthropic codenames (non-descriptive by design, same
pattern as the `tengu_*` GrowthBook flags found in §3) and their presence
is stable across both captures. **Cannot rule out** that one of these is
peak-related — they've simply never been observed non-null on this
account. Flagged as an open question below; the exact probe needed is a
capture on an account/plan where one of these is populated (e.g. Max,
Team, or during a live peak window), or a public/leaked schema reference.

**Schema drift, unrelated to peak:** `extra_usage` gained three boolean
fields between the fixture and tonight's capture (`user_disabled`,
`spend_limit_reached`, `credits_ever_enabled`) — ordinary endpoint
evolution over the intervening weeks, about credits/extra-usage state,
not session rate.

**The peak-window capture that was missing is now done** (Capture B,
above), via a scheduled one-shot job that re-ran
`Scripts/probe-peak-hours.sh` automatically at 08:03 AM PT Monday
2026-08-03 — see the diff result above.

## 2. Claude Code CLI static inspection

The installed `claude` CLI (`@anthropic-ai/claude-code@2.1.220`) resolves
to a single compiled Mach-O arm64 executable
(`bin/claude.exe`, ~245 MB — a Bun-compiled bundle, not readable JS
source). Ran `strings -a` over it and grepped case-insensitively for:
`peak hour(s)`, `off[-_]?peak`, `burn rate`, `surge pricing`, `rate/usage
multiplier`, `"Daily Claude Session"`, `peakWindow`/`isPeak`/`peak_window`
(camel + snake), `usage may be higher`, `burns faster`, `peak demand`,
`peak times`, `Pacific`, `5:00...11:00`, `8:00 AM ET`.

**Zero product-relevant hits.** The only "peak" occurrences in the entire
binary:
- `peakActivityHour` — Claude Code's own `/stats` command has a "Peak
  hour" row (`` `${e.peakActivityHour}:00-${e.peakActivityHour+1}:00` ``,
  labeled `"Peak hour"` next to `"Active days"`) — this is **which hour
  the user personally is most active**, a usage-analytics feature,
  unrelated to Anthropic's server-side rate policy.
- `fleetViewPeakConcurrent` — a config field counting peak concurrent
  sessions in FleetView (Claude Code's multi-agent dashboard). Unrelated.
- Node/Bun internal memory-profiling fields (`memory.peak`,
  `peak_malloced_memory`). Unrelated.

**No trace of "Daily Claude Session" anywhere in this binary.**

**Important caveat — do not oversell this as proof of absence.**
`strings` on a compiled bundle only surfaces text that exists as a
literal at build time. It cannot see: copy fetched from a remote
config/feature flag at runtime, anything rendered by a different
Anthropic surface (claude.ai web, Claude Desktop, mobile apps), or a
string built by runtime concatenation instead of a literal.

That caveat isn't hypothetical here: this same binary embeds **1,747
distinct GrowthBook feature-flag codenames** (pattern `tengu_[a-z_]+`,
e.g. `tengu_cobalt_harbor`, `tengu_amber_relay`), plus a
`cachedGrowthBookFeatures` / `cachedDynamicConfigs` slot in its config
schema. Claude Code is architected to have large swaths of behavior (and,
per GrowthBook's model, potentially string/JSON *values* too) toggled
remotely without a client release. That's exactly the kind of mechanism
that would explain a policy being introduced/reverted/reintroduced within
months without a corresponding CLI version bump — and it also means a
genuine peak-hours warning could be 100% real, 100% server-driven, and
still invisible to this static check, because the copy itself would be a
flag *value*, not a compiled-in literal.

## 3. This repo (AIMeter)

`grep -ril "peak" .` across the entire repo (Swift, shell, JSON, Markdown)
returned **zero matches**. AIMeter has no pre-existing peak logic
anywhere to trace — confirmed, not assumed.

## 4. "Daily Claude Session" scheduler — unidentified

Neither this repo nor the installed Claude Code CLI contains this string
or anything resembling it. This surface is outside what I have access to
inspect from this machine. I don't know if it's a claude.ai web page, the
Claude Desktop app, a mobile app, or something else — and that materially
changes how strong a source-of-truth signal it is. See "What I need from
you."

## Conclusion

**(b), confirmed for the two endpoints AIMeter calls:** peak state is not
exposed by `/api/oauth/usage` or `/api/oauth/profile`, on this Pro
account, in either an off-peak or a peak-window snapshot. This is no
longer a leaning — it's a direct A/B diff across the actual boundary, not
just an absence noticed once.

Confidence, split honestly:
- **High, confirmed from the payload:** both endpoints carry no
  peak-related field, checked via full-payload grep AND a structural+value
  diff across an off-peak/peak-window pair (Capture A vs. B above), not
  just casual inspection of a single snapshot. This closes what was
  previously the single missing data point.
- **Still assumed, not verified:** that the always-null codenamed fields
  (`tangelo`, `iguana_necktie`, etc.) are unrelated to peak. They stayed
  null through both off-peak AND peak captures on this Pro account, which
  is stronger evidence than before but still doesn't rule out that one of
  them lights up only on a different plan (Max/Team) or a different
  session-usage pattern than mine happened to hit this morning.
- **Low/unknown, documented publicly only, not verified here:** the exact
  5:00-11:00 AM PT / weekday-only schedule itself — I have not
  independently confirmed Anthropic states this beyond what you told me;
  treat the schedule numbers as "documented," not "confirmed by me."
- **Unknown:** where "Daily Claude Session" lives, and therefore whether
  it constitutes server-side or client-side evidence at all. This is the
  one open question left blocking Part 2 — see below.

One important nuance the diff surfaced: this confirms the endpoint
doesn't *label* peak state, but a linear-utilization counter is exactly
what you'd expect to see either way — a 2x burn rate would still just
show up as `percent` climbing faster during the same wall-clock/token
usage, with no annotation. So this diff rules out an explicit signal
(flag, multiplier, weight), but doesn't by itself prove usage doesn't
burn faster right now — that would need a controlled same-token-count
comparison in vs. out of peak, which is a usage experiment, not a payload
inspection, and out of scope for what this investigation set out to
answer (which was: does the *server tell us* peak is active — it does
not).

## Open question, deferred by user decision

**Where "Daily Claude Session" lives is still unidentified.** The user
decided not to chase it further for now and to proceed on the confirmed
(b) conclusion above. If that surface is later identified and turns out
to hit a real, different endpoint with an actual peak signal, that would
upgrade the data-source decision below from "compute locally" to "also
call that endpoint" — revisit Part 2 if that surfaces.

# Part 2 — Recommendation

## Data source decision

**Compute peak state locally, from a hardcoded schedule.** Justification,
tied directly to Part 1's evidence: the two endpoints AIMeter already
calls were diffed across an actual peak/off-peak boundary and carry
nothing — no flag, multiplier, weight, or schedule object, on either side
of the transition. There is no confirmed server signal to key off. Adding
a network call to some *other*, undiscovered endpoint would mean
reverse-engineering an endpoint we have not observed even existing, which
contradicts the project's own rule against guessing wire formats — and
even if the "Daily Claude Session" surface is later found to use one,
"is it a weekday and is it 5-11 AM PT" is answerable from a clock with
zero ambiguity, so a server round-trip would be strictly more fragile
(one more network dependency, one more failure mode, one more thing that
can rate-limit) for a value that changes on a fully deterministic,
publicly documented timer.

## Schedule storage: hardcoded, release-updated, with a visible "last verified" date

Recommendation: a hardcoded constant, shipped in source, updated via
ordinary app releases whenever Anthropic changes the policy again — not
a remote-fetched config, not user-editable.

- **Not remote-fetched:** AIMeter's first line is "no dependencies, no
  server." Standing up any config endpoint — even a static JSON file on
  a CDN — is a new architectural category for this project: a new
  network dependency the app doesn't otherwise have, a new cache/staleness
  question, and a new thing to keep available forever for a single
  boolean-ish schedule. That's a disproportionate cost for data that's
  small, public, and changes a few times a year at most. This matches
  your own instinct going in.
- **Not user-editable:** most users have no way to know Anthropic changed
  the policy before AIMeter's release notes tell them; letting them
  hand-edit a schedule they can't verify just relocates the staleness
  problem onto them and invites support questions ("why is my peak
  indicator wrong") that a shipped update to the constant already answers
  more reliably.
- **The honesty mechanism for volatility:** ship a `lastVerified: Date`
  alongside the schedule constant, and surface it in the UI (Provider
  Detail, next to the indicator) — e.g. "Peak hours: weekdays 5-11 AM PT
  · schedule as of Aug 2026." This is the same shape as the existing
  "Updated X ago" staleness hint for snapshots (`AppConfig.staleAfter`) —
  reusing an idiom the app already has for "this might not reflect
  reality anymore," rather than pretending a hardcoded schedule is live
  truth. If Anthropic flips the policy again between releases, the date
  itself tells the user the app might be behind, without needing a
  network call to know it.

## Timezone/DST handling — the crux risk, and how to not get it wrong

The schedule is defined in PT wall-clock time, and PT itself observes
DST (PDT/PST) — so "5:00-11:00 AM PT" already shifts by an hour twice a
year *in UTC*, while staying fixed in Los Angeles local time. The
critical rule: **the calculation must never use the device's own
timezone for the boundary check** — only to convert the result for
display. A user in Mexico City (CST, UTC-6, no DST) sitting at, say,
2026-11-02 12:30 AM local time is still in *Sunday* 10:30 PM in Los
Angeles — if the code naively asked "what weekday is it here," it would
get Monday and wrongly compute a peak window that hasn't started in PT
yet.

Model: use `TimeZone(identifier: "America/Los_Angeles")` (Foundation's tz
database, which already encodes every historical and future DST rule for
that zone) to build a `Calendar` pinned to that zone, and pull
`weekday`/`hour` components from the arbitrary instant through *that*
calendar — never through `Calendar.current` / `TimeZone.current`. This
makes the device's own timezone irrelevant to whether peak is active; it
only matters when *displaying* "peak until 1 PM your time" as a
convenience.

Test plan (`PeakCalculatorTests`, matching `PaceCalculatorTests`'s style
of injecting `now:`): a table of fixed UTC instants covering — a weekday
mid-window (peak), a weekday one minute before/after each boundary
(off-peak/peak edges), Saturday and Sunday at a peak-equivalent hour
(off-peak, weekend overrides everything), and — the DST-specific
cases — a Monday morning immediately after the spring-forward and
fall-back transition Sundays for `America/Los_Angeles`, asserting the
UTC instant corresponding to 5 AM/11 AM PT is classified correctly on
both sides of the clock change. One more case worth asserting explicitly:
feed the *same* UTC instant through the calculator with `TimeZone.current`
forced to something far away (e.g. Tokyo) and confirm the result doesn't
change — proving the device timezone truly has zero influence, which is
exactly the risk this section is about.

## Smallest honest design

**`PeakCalculator`** — new pure type in
`Packages/UsageKit/Sources/UsageKit/Core/PeakCalculator.swift`, no
SwiftUI/WidgetKit/UIKit/Combine, matching `PaceCalculator`'s shape:

```swift
public enum PeakCalculator {
    public struct Schedule: Sendable {
        public let timeZoneIdentifier: String   // "America/Los_Angeles"
        public let weekdays: Set<Int>           // Calendar weekday ints, Mon-Fri = 2...6
        public let startHour: Int               // 5
        public let endHour: Int                 // 11 (exclusive, matching the documented "5:00-11:00")
        public let lastVerified: Date
    }

    public static func isPeak(at date: Date = Date(), schedule: Schedule) -> Bool { ... }

    /// Next boundary crossing after `date` (into or out of peak) — feeds
    /// the notification family below.
    public static func nextTransition(after date: Date = Date(), schedule: Schedule) -> Date? { ... }
}
```

The *mechanism* is provider-agnostic (any provider could describe its own
recurring named-timezone window this way), but the concrete PT/5-11/Mon-Fri
values are Anthropic's own policy, not a general truth — so the actual
`Schedule` instance lives with Claude, e.g. a `ClaudePeakSchedule` constant
in `Providers/Claude/`, the same split already used for `windowDuration`
(5h session / 7d weekly are noted in-line as "Claude's today... revisit
if a provider with different window lengths is added").

**Notification family — `peak.`, off by default.** Following
`NotificationScheduler`'s existing shape (`NotificationPreferences` gets
one new `notify.peak` boolean, same pattern as `runOutWarningsEnabled`),
add "Peak hours started" / "Peak hours ended" to the Smart Notifications
card. Implementation-wise this one is a deliberate *exception* to "all
rescheduled from scratch after every successful fetch": unlike
reset/run-out notifications, peak transitions don't depend on any
fetched snapshot — they're a fixed calendar fact — so rescheduling them
on every ~30-minute refresh would just be churn. Schedule them once at
launch and whenever the toggle changes, as 10 recurring
`UNCalendarNotificationTrigger`s (5 weekdays × start/end), each with
`DateComponents.timeZone` explicitly set to `America/Los_Angeles` — the
system re-evaluates named-zone components against the tz database at
each future fire, so this handles DST for free, for the same reason the
calculator itself does.

**Glance surfaces, zero extra network cost (peak is time-derived, not
fetched):**
- **Provider Detail** — the primary, most useful surface: a small
  indicator row ("Peak hours now" / next transition time) plus the
  `lastVerified` footnote. This alone satisfies "let the user know when
  we're off-peak" with the least new surface area, and is Claude-specific
  display, so it belongs here per the existing precedent (glanceMetric,
  Third-usage-row, Smart notifications are all Provider-Detail-scoped
  because they're Claude-specific, not app-wide).
- **macOS menu bar** — one extra pure call (`PeakCalculator.isPeak()`)
  alongside the existing gauge; e.g. a tinted accent or a small glyph,
  with the state spelled out in the `.help` tooltip (same rule the
  existing label already follows: the exact value must never live only
  in an icon).
- **Widget headers (`AIMeterUsage`, `AIMeterSingleUsage`)** — the nicest
  fit of all: since peak is a pure function of a `Date`, the timeline
  provider can emit a second `TimelineEntry` dated exactly at the next
  peak transition (`PeakCalculator.nextTransition`), and WidgetKit will
  switch to it automatically at that wall-clock moment — the badge flips
  for free, with no extra refresh, no widened refresh budget, no network
  call. This composes cleanly with the existing "single entry,
  `.after(interval)`" timeline; it just becomes two entries instead of
  one when a transition falls within the window.
- **Lock Screen circular gauge — skip for now** (see below). Too cramped
  for a second signal, lowest value of the four surfaces.

## Docs impact

- **`PrivacyView` needs no new disclosure.** This is the direct payoff of
  the (b) conclusion: `PeakCalculator` makes no network call and reads no
  new data, so every existing claim ("the exact OAuth scopes... and the
  two read-only endpoints called") stays true unchanged. Worth one small
  added line stating the peak indicator is computed on-device from a
  fixed schedule, purely so a curious reader isn't left to wonder — but
  it's an addition for clarity, not a correction.
- **`CLAUDE.md`** gets a new subsection (peer to "Pace warm-up" /
  "Run-out prediction") documenting `PeakCalculator`, the
  `ClaudePeakSchedule` constant + `lastVerified`, the `peak.` notification
  family and its deliberate exception to the "reschedule every fetch"
  rule, and the glance-surface behavior (especially the multi-entry
  timeline trick, since that's a non-obvious mechanism future-you should
  not have to rediscover).
- **`README`** gets a short mention alongside the existing
  undocumented-endpoint disclaimer: the peak-hours schedule reflects
  Anthropic's own publicly documented (and historically volatile) policy,
  hardcoded and updated via releases, with the in-app "last verified"
  date as the honesty mechanism.

## Phased, independently-shippable plan

1. **`PeakCalculator` + `ClaudePeakSchedule` + tests.** Pure, no UI, no
   notifications. Fully testable in isolation (the DST/timezone table
   above). Zero risk, ships invisibly.
2. **Provider Detail indicator** ("Peak hours now" / next transition +
   `lastVerified` footnote). The smallest UI slice that directly satisfies
   the ask in this conversation ("let the user know when we are off peak
   hours").
3. **Menu bar + widget header glance badges**, including the multi-entry
   timeline for auto-flip.
4. **`peak.` notification family**, off by default, in the Smart
   Notifications card.

Each phase stands alone and is shippable without the next.

## Implementation notes

All four phases are built, on top of what Phase 1 already shipped
(`PeakCalculator`, `ClaudePeakSchedule`, `PeakCalculatorTests`):

- **`Shared/ClaudePeakStatus.swift`** — the presentation wrapper
  (`isPeak`, `nextTransition`, `title`/`subtitle`/`lastVerifiedLabel`)
  every UI surface below reads from, so the copy and schedule stay in one
  place.
- **Provider Detail**: a new "Peak hours" card (`PeakHoursCard` in
  `ProviderDetailView.swift`) between Rate limits and Forecast — bolt
  icon, live status line, next-transition countdown, and a footnote with
  the schedule description + `lastVerified` date.
- **macOS menu bar**: the popover header (`MenuBarView.header`) shows a
  visible bolt badge when active. The status item itself
  (`MenuBarLabel`) deliberately does *not* get a second glyph — peak
  state folds into its existing `.help`/accessibility text instead, so
  the carefully-tuned single-gauge design isn't disturbed.
- **Widgets**: `UsageWidgetViews.swift`'s `WidgetHeader` and
  `SingleUsageWidgetView`'s header both show the same bolt badge (the
  single-window widget only when the picked kind is `.session`, since
  that's the one window the policy actually affects). Both timeline
  providers (`UsageWidget.swift`, `SingleUsageWidget.swift`) add a second
  `TimelineEntry` dated at `PeakCalculator.nextTransition` when that falls
  before the next scheduled reload — confirmed this compiles and threads
  correctly through `WindowBarList` → `SmallUsageView`/`MediumUsageView`.
  Lock Screen accessories were left untouched, as planned.
- **Notifications**: `NotificationPreferences.peakEnabled` +
  `NotificationScheduler.reschedulePeakNotifications` (10 recurring
  `UNCalendarNotificationTrigger`s, `DateComponents.timeZone` pinned to
  the schedule's zone). Wired into `UsageModel` as
  `peakNotificationsEnabled`/`setPeakNotificationsEnabled`, scheduled once
  in `init` (not per-fetch, per the design above), and surfaced as a
  "Peak-hours alerts" toggle in `SmartNotificationTogglesCard`.
- **Docs**: `CLAUDE.md` gained a full "Peak hours" bullet under
  Presentation rules plus touch-ups to the notification-family summary,
  the Provider Detail screen bullet, the widgets bullet, and the menu bar
  bullet; `README.md` gained a feature bullet; `PrivacyView` gained one
  sentence on the existing "Everything stays on your device" row (no new
  row needed — there's no new network call or data collection to
  disclose).
- **Verified**: `xcodebuild` for both `platform=macOS` and
  `generic/platform=iOS Simulator` succeed with zero errors and (checked
  by grep) zero warnings; `swift test` in `Packages/UsageKit` passes all
  83 tests. `Shared/` is a file-system-synchronized Xcode group, confirmed
  in `project.pbxproj`, so the new `ClaudePeakStatus.swift` needed no
  manual target-membership edit.

## What NOT to build yet

- **A remote-fetched schedule config** — contradicts "no server" and
  your own stated preference; only reconsider if the hardcoded schedule's
  maintenance burden turns out to be real in practice (e.g. Anthropic
  changes it again shortly after a release and users are visibly stuck
  stale for a while).
- **A user-editable override** — added complexity and support burden for
  a policy most users don't track closely; the `lastVerified` date plus
  release notes should be signal enough.
- **Lock Screen circular gauge peak indicator** — too cramped, lowest
  value; revisit only if the other three surfaces prove insufficient.
- **Inferring an actual burn-rate multiplier from `UsageHistoryStore`
  slope** — a genuinely different feature (measuring real burn rate)
  from what was asked (telling the user the *declared* schedule state);
  conflating the two risks asserting something Part 1 explicitly could
  not confirm (that usage really does burn faster right now).
- **Further reverse-engineering of "Daily Claude Session"** — deferred by
  the user; revisit only if that surface resurfaces with new information.

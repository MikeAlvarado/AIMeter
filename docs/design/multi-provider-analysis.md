# Multi-provider design review: Codex + Cursor

Scope: assess how true CLAUDE.md's "provider-agnostic architecture" claim
actually is, and what it costs to add Codex and Cursor as second/third
providers. No production code in this pass. Every claim below is cited to
a file and symbol as read on this branch; where the code disagrees with
CLAUDE.md or README.md, that's called out explicitly.

**Headline finding:** `Packages/UsageKit/Core` genuinely earns the
"provider-agnostic" claim — it has no Claude-specific types and no UI
imports. Nothing else does. `UsageModel`, `RefreshService`,
`NotificationScheduler`, `Preferences`, `ProviderIdentityView`, the
dashboard, and both widgets are all structurally single-provider today —
not "Claude-flavored," but literally unable to hold a second snapshot at
the same time. README.md:144-145 says "Adding a provider = implementing
`UsageProvider` (one folder under `Providers/`)"; that is false as
written — implementing `UsageProvider` is necessary but covers maybe a
third of the actual work.

---

## 1. Coupling audit

### Core package: clean

Verified by reading every file in `Packages/UsageKit/Sources/UsageKit/Core`,
`Storage`, and `Networking`, and grepping the whole package for `claude`
case-insensitively. No Claude-specific types leak in. The only hits are
doc comments explaining *why* a design choice exists today:

- `UsageSnapshot.swift:99-101` — the doc comment on `windowDuration`
  admits "These lengths (5h / 7d) are Claude's today... revisit if a
  provider with different window lengths is added." This is the code
  honestly flagging its own load-bearing assumption. See §3.
- `UsageProvider.swift:6,8` — doc comments using "claude"/"Claude" purely
  as an example value, not a hardcoded dependency.

These are not leaks. They're honest comments in a package that otherwise
has zero Claude coupling.

### Genuine abstraction leaks

**`Shared/ProviderIdentityView.swift:18`** — `Image("ClaudeIcon")` is
hardcoded. Every parameter CLAUDE.md describes (`iconSize`,
`iconCornerRadius`, `font`, `nameColor`) is real, but the icon asset name
is not one of them. Every call site (`DashboardView.swift:98-104`,
`MenuBarView.swift:76-83`, `LandscapeUsageView.swift:36-43`,
`UsageWidgetViews.swift:53-60`) can pass an arbitrary `name:` string, but
the starburst icon renders regardless. Add a second provider's header
anywhere today and it shows the Claude logo. This is the single sharpest
"looks done, isn't" leak in the codebase — the abstraction exists in
outline (parametrized name/plan) but not in substance (icon is fixed).
`SingleUsageWidgetView.swift:32-38` is the one caller that's already
correct — it threads `entry.providerName` from the widget's own
`AppIntent` selection, because that surface was built provider-aware from
the start (see the `UsageWindowOption` note below).

**Every non-widget caller also hardcodes the name literal**, not just the
icon: `DashboardView.swift:99` (`name: "Claude"`), `MenuBarView.swift:77`,
`LandscapeUsageView.swift:37`, `UsageWidgetViews.swift:54`. These are
acceptable *today* (there's one provider), but they're not reading from
any provider registry — there isn't one.

**`DashboardView.swift:96`** — `NavigationLink(value: "claude")` pushes a
hardcoded string, and `DashboardView.swift:25-27`'s
`.navigationDestination(for: String.self) { _ in ProviderDetailView() }`
**ignores the string entirely** and always pushes the one
`ProviderDetailView`. There is no routing mechanism from a tapped provider
row to "that provider's" detail screen — there's exactly one detail
screen, hardwired.

**`ProviderDetailView.swift`** is not just Claude-styled UI sitting on
generic data — it directly calls `model.snapshot` (singular),
`model.paceReady`, `model.notificationsEnabled(for:)`, and hardcodes
`.navigationTitle("Claude")` (line 101) and `Text("Disconnect Claude")`
(line 89). Same for `WindowRowsList`/`NotificationTogglesCard`/
`SmartNotificationTogglesCard`/`ForecastCard` — all bind to
`UsageModel`'s one singular snapshot, not a provider-scoped one. This is a
UI-layer leak that's a direct consequence of the `UsageModel` leak below,
not a separate problem.

**`AIMeter/Services/UsageModel.swift`** is the deepest leak in the app.
`snapshot: UsageSnapshot?` (line 10) is singular. `service = RefreshService()`
(line 17) is one Claude-only service (see next). `completeConnection(_
credentials: ClaudeCredentials)` (line 85) is typed to Claude's concrete
credential struct — it cannot accept a Codex credential without an
overload. `disconnect()` (line 96) disconnects the one provider. Every
notification API (`notificationsEnabled(for kind:)`,
`setNotificationsEnabled(_:for:)`, etc.) takes a bare `UsageWindow.Kind`
with no provider dimension — see §2. This struct is the app's entire data
layer, and it structurally cannot represent "two providers, one
connected, one not."

**`AIMeter/Services/RefreshService.swift`** — `let provider: ClaudeProvider`
(line 9, concrete type, not `any UsageProvider`), `let credentialSource:
any ClaudeCredentialSource` (line 10, Claude-specific protocol). `init()`
(lines 14-24) unconditionally builds exactly one Claude credential source
and one `ClaudeProvider`. `refresh()` (lines 51-67) fetches one provider,
diffs one previous/current pair, reschedules one set of notifications.
This needs to become a provider-list orchestrator, not an
additively-extended one (§6).

**`AIMeter/Services/NotificationScheduler.swift`** — every persistence key
and notification identifier is `kind.storageKey` with **no provider
component anywhere**: `NotificationPreferences.key(for kind:)` → `"notify.\(kind.storageKey)"`
(line 58-60); scheduled identifiers `identifierPrefix + window.kind.storageKey`
(line 135, and the `runout.`/`earlyreset.`/`nearlimit.`/`limitreached.`
equivalents). This is a real collision, not a hypothetical one — detailed
in §2.

**`Shared/PreferencesStore.swift`** — `glanceMetric: UsageWindow.Kind`
(line 96), `modelSlotFallback: ModelSlotFallback` (line 89), and
`showCreditsAmount: Bool` (line 101) are all **global, single-instance
preferences** living in the one shared `Preferences` struct alongside
genuinely universal prefs (`displayMode`, `resetStyle`, `appearance`).
CLAUDE.md's own "Provider detail" section already admits
`modelSlotFallback`/`showCreditsAmount` are "Claude-specific display
prefs, so they live here rather than in the app-wide Settings screen" —
but "here" is still the *shared, provider-unscoped* `Preferences` struct.
There's nowhere for a second provider's analogous preference (if it has
one) to live without colliding.

**`AIMeterWidgets/SingleUsageConfigurationIntent.swift:69`** —
`UsageWindowOptionQuery.currentOptions()` hardcodes `let providerID =
"claude"`. This is the one component that is *implementation-incomplete*
rather than *architecturally leaky*: `UsageWindowOption`'s own shape
(`providerID`, `kind`, `providerName`, and an `id` of
`"\(providerID)|\(kind.storageKey)"`, lines 9-46) was already built
provider-aware. Looping this over a real provider list instead of one
hardcoded string is the cheapest fix in the entire codebase — see §9.

**`AIMeterWidgets/UsageWidget.swift:51`** —
`.snapshot(for: "claude")` is hardcoded in the timeline provider's
`entry()`. The `AIMeterUsage` widget's whole view tree
(`UsageWidgetView`/`WindowBarList`/`WidgetHeader`, all in
`UsageWidgetViews.swift`) takes exactly one `UsageSnapshot`, not a
collection. Rendering N providers' three-bar sections in this widget is
not a config change, it's a layout redesign — see §7.

**`AIMeterWidgets/WidgetRefresher.swift:30-33`** — constructs exactly one
`ClaudeProvider` inline for the iOS self-fetch path. Single-provider by
construction — see §6 for what N providers does to this path's timing
budget.

**`AIMeter/Views/ConnectClaudeSheet.swift`** — entirely Claude-specific,
which is *correct*: this is provider-specific UI that just needs a second
implementation per provider, not an abstraction leak by itself. But
`DashboardView.swift:34-36` and `MenuBarView.swift:69-71` both hardwire
`.sheet(isPresented: $showingConnect) { ConnectClaudeSheet() }` with a
single `Bool` state var (`DashboardView.swift:10`) — there's no dispatch
mechanism for "which provider's connect sheet." See §5.

**`AIMeter/Views/PrivacyView.swift`** — the "What the connection can
access" card (lines 52-76) is hand-written prose about exactly Claude's
two endpoints and two OAuth scopes (`ScopeChip(name: "user:profile")` /
`"user:inference"`, lines 69-71), and the "How connecting works" card
(lines 35-49) is `#if os(macOS)`/`#else` prose describing exactly Claude
Code's mirror-vs-paste model. CLAUDE.md's own text says "Every claim must
stay true to the code" — today that's true because there's one provider
to describe. This view has no per-provider structure at all; it will need
to become either a loop over connected providers' own scope/endpoint
descriptions, or an explicit second card per provider.

**`Shared/Media.xcassets`** — contains exactly `ClaudeIcon` and
`ClaudeCodeIcon` (plus the unrelated `GitHubIcon`). No naming convention
or lookup abstraction exists for "provider icon asset name"; adding one is
required before `ProviderIdentityView`'s icon leak (above) can be fixed.

### Not leaks — already correctly scoped

**`Packages/UsageKit/Storage/SnapshotStore.swift`** and
**`UsageHistoryStore.swift`** are both keyed by `providerID` string
throughout (`"usage.snapshot.\(providerID)"`,
`"usage.history.\(providerID)"`, `"usage.history.since.\(providerID)"`).
`SnapshotStoreTests.swift:37-45`'s `testSnapshotsAreScopedPerProvider`
already exercises this with `providerID: "openai"` as a second value —
this layer was built multi-provider-ready from day one and there is
existing test evidence of it.

**`Packages/UsageKit/Storage/KeychainStore.swift`** is fully generic
(service + account key + `Codable` value, no Claude awareness). Claude's
own credential sources layer a specific account key
(`ClaudeKeychainCredentialSource.defaultKey = "claude.credentials"`,
line 7) on top of one shared service string
(`AppConfig.keychainService`). A second provider adding its own distinct
key under the same service needs no changes here — though nothing
*enforces* key uniqueness across providers; see §2's note on this.

**`SpendStatus`/`ExtraUsageStatus`** (`Core/SpendStatus.swift`) are
generically named (`enabled`, `percent`, `usedAmount`, `limitAmount`,
`currency`) and optional on `UsageSnapshot` — a provider that has no
analogous concept simply omits them. Low risk, reasonably general
already. The tighter coupling is `UsageSnapshot.creditsWindow`
(`Shared/WindowDisplay.swift:62-65`), which synthesizes the `.credits`
pseudo-window from `spend` specifically (not `extraUsage`) — a modeling
choice tied to Claude's exact "credits = spend cap enabled" shape, not a
generic "overflow usage" concept. Worth revisiting if a second provider's
overflow concept doesn't map onto `spend` the same way.

### Localization

`Shared/Localizable.xcstrings` has 137 keys; UsageKit's has 9 (errors
only, via `.module`). Not provider-namespaced, but that's fine for
genuinely generic strings ("Resets in…", "5-hour session"). Provider-named
strings ("Connect Claude Code", "Disconnect Claude") are literal string
keys embedded directly in `ConnectClaudeSheet`/`ProviderDetailView`
source — each new provider duplicates its own literal strings into its
own views. That's expected, acceptable work, not a leak.

---

## 2. Identity & keying

**Already provider-scoped, verified ready:**

| Store | Key shape | Status |
|---|---|---|
| `SnapshotStore` | `usage.snapshot.<providerID>` | Ready (tested) |
| `UsageHistoryStore` | `usage.history.<providerID>`, `usage.history.since.<providerID>`, then `kind.storageKey` within that bucket | Ready |
| `KeychainStore` | caller-chosen service + account key | Ready, but uniqueness across providers is a convention, not enforced — nothing stops a future `CodexCredentialSource` from picking `"claude.credentials"` by copy-paste accident and silently colliding. Worth a one-line comment or constant list, not a structural fix. |

**Not ready — concrete collisions if a second provider reports `.session`:**

CLAUDE.md's own §8 framing assumes Codex "appears to expose session +
weekly." If it does, every one of these breaks the moment Codex connects,
because none of them include a provider dimension:

1. **`NotificationPreferences.key(for kind:)`** (`NotificationScheduler.swift:58-60`)
   → `"notify.\(kind.storageKey)"`. Claude's `.session` toggle and
   Codex's `.session` toggle are the *same UserDefaults key*
   (`"notify.session"`). Flipping one flips both.
2. **Scheduled notification identifiers** — `identifierPrefix +
   window.kind.storageKey` (line 135) and the `runout.`/`earlyreset.`/
   `nearlimit.`/`limitreached.` equivalents (lines 179, 204, 226, 247).
   Same collision: `"reset.session"` is one specific
   `UNNotificationRequest`, not two. Worse: `rescheduleResets` (line 114)
   removes *all* pending requests under the `reset.` prefix before
   re-adding (line 116, `removePending(withPrefix:)`) — if
   `RefreshService.refresh()` is ever called per-provider in sequence (the
   natural multi-provider design, §6), the second provider's
   `rescheduleResets` call wipes the first provider's just-scheduled
   notifications for windows the second call never touches. This is a
   live bug waiting on the first multi-provider refresh, not a
   theoretical one.
3. **`Preferences.glanceMetric: UsageWindow.Kind`** (`PreferencesStore.swift:96`)
   — one bare `Kind`, no provider. Once two providers can both report
   `.session`, "the glance metric is `.session`" is ambiguous between
   them.
4. **`UsageModel.notificationsEnabled(for kind:)` /
   `setNotificationsEnabled(_:for:)`** (`UsageModel.swift:122-144`) — no
   provider parameter; inherits problem #1 up through the model layer.

**Minimal fix**, consistent throughout: prepend `providerID` to every one
of these storage keys and notification identifiers, mirroring the pattern
`UsageWindowOption.id` (`SingleUsageConfigurationIntent.swift:14`) already
uses: `"\(providerID)|\(kind.storageKey)"`. This is a naming-convention
change, not a data-model change — no new types needed, just wider key
strings. See §4 for what this does to existing installs' stored
preferences.

**`glanceMetric` specifically should NOT become "per-provider"** (N
separate stored prefs, one per provider) — there is exactly one glance
surface (menu bar label / Lock Screen gauge), so it needs one answer, not
N answers to reconcile. The fix is a single *provider-qualified* pref
(one stored value, richer key: `providerID` + `kind`), not N independent
prefs. This matters for §7 too.

**`UsageWindowOptionQuery.currentOptions()`** (`SingleUsageConfigurationIntent.swift:61-85`)
is the cheap one: replace the hardcoded `"claude"` with a loop over
`RefreshService`'s (or wherever the provider list lives after §6's
rewrite) provider IDs, calling `SnapshotStore.snapshot(for:)` for each.
The `UsageWindowOption` type needs no changes at all.

---

## 3. Data model fit

**`UsageWindow.Kind`** (`Core/UsageWindow.swift:9-19`): `.session`,
`.weekly`, `.modelSpecific(String)`, `.credits`. Codex's assumed
session+weekly shape maps directly onto the first two cases — but note
per §2, the *kind* alone doesn't disambiguate providers; only the
enclosing `UsageSnapshot.providerID` does.

**Load-bearing, self-admitted Claude-specific assumption:**
`windowDuration`/`nominalPeriod` (`UsageSnapshot.swift:80-112`) are
computed as a `switch` over `Kind` — session is hardcoded to 5 hours,
weekly/modelSpecific to 7 days. `PaceCalculator.pace` (`UsagePace.swift:64-66`)
and `RunOutPredictor.averageProjection` (`UsageProjection.swift:60-61`)
both depend on `windowDuration`; `UsageSnapshot.fillingMissingResets`
(`UsageSnapshot.swift:63`) depends on `nominalPeriod`. The doc comment
already flags this (lines 99-101): "These lengths (5h / 7d) are Claude's
today... revisit if a provider with different window lengths is added."
If Codex's actual session length differs from 5 hours (unverified — see
§8), pace and run-out projections will silently compute against the wrong
duration for every Codex window, because duration is inferred from
*kind*, not reported by the *provider*.

**Minimal type change:** move `windowDuration` (and, if needed,
`nominalPeriod`) off `UsageWindow.Kind` and onto `UsageWindow` itself as
an explicit field, set by each provider's own mapping code (each provider
already knows its own window's real length — `ClaudeUsageResponse.usageWindows()`
would just set it explicitly instead of leaving it implicit in `Kind`).
This is additive to `UsageWindow`'s Codable shape (see §4 for the
persistence consequence) and requires no change to `PaceCalculator`/
`RunOutPredictor`'s logic, only to where they read the duration from. It
also directly fixes the case where two providers both report `.session`
with genuinely different lengths — impossible to represent today since
duration is a pure function of `Kind`.

**Cursor's assumed shape — "Auto usage / Total usage / API usage," possibly
with no `resetsAt` at all.** Walking every consumer of `resetsAt == nil`
confirms the codebase already tolerates this gracefully *for existing
kinds*:

- `PaceCalculator.pace` guards `guard let resetsAt = window.resetsAt...
  else return nil` (`UsagePace.swift:64`) — pace silently becomes
  unavailable, same as today's idle-session case.
- `RunOutPredictor.averageProjection`/`recentProjection` — same guard
  (`UsageProjection.swift:60`, `104`) — survives.
- `WindowSlots.showsReset` — guards on `window?.resetsAt`
  (`WindowDisplay.swift:50`) — renders no reset line, same as any
  no-reset window.
- `NotificationScheduler.rescheduleResets` — guards `let resetsAt =
  window.resetsAt, resetsAt > Date()` (`NotificationScheduler.swift:122`)
  — no reset notification scheduled, correctly nothing to schedule
  against.
- `ResetDetector.earlyResets` — requires `let prevReset = prev.resetsAt`
  (`UsageProjection.swift:190`) — skipped, correctly can't detect an
  early reset with no known reset to compare against.

So a permanently-nil `resetsAt` is *not* the actual gap. The real gap is
that **no real provider can emit it under a legitimate kind today** —
`.credits` is the only kind designed for "no reset," and its own doc
comment explicitly forbids provider mapping code from producing it
(`UsageWindow.swift:16`: "Never produced by provider mapping code and
never appears in a persisted `UsageSnapshot.windows` array"). If Cursor's
"Total usage" is a genuine, provider-reported, non-resetting metric, it
needs its own `Kind` case (e.g. a new `.metered(String)` or similar) —
not reuse of `.credits`, which is reserved as a synthesized,
display-only concept derived from `spend`.

**Minimal change for §3 overall:** (a) move window duration from
`Kind`-inferred to provider-supplied explicit data on `UsageWindow`, and
(b) add one new `Kind` case for a real, provider-reported, non-resetting
usage metric, distinct from the synthesized `.credits`. Do not redesign
`WindowSlots`/pace/run-out — they already degrade correctly on missing
reset data; they just need a legitimate kind to degrade *for*.

**`WindowSlots`'s fixed three-slot layout is the bigger fit risk for
Cursor specifically**, and it's a presentation problem more than a data
one: `WindowSlots.init` (`WindowDisplay.swift:19-24`) hardcodes exactly
`.session` and `.weekly` as slots one and two. A provider whose reported
metrics are "Auto usage / Total usage / API usage" — three different
*flavors* of usage, not two rolling time periods plus an overflow model —
doesn't obviously map onto this triad at all. This is covered further in
§7; flagging here because it's a data-model-adjacent fit question that
`.credits`-vs-new-case alone doesn't resolve.

**`ResetDetector`/`ThresholdDetector`** match windows by `kind` only
within a `previous`/`current` snapshot pair (`UsageProjection.swift:164`,
`189`). This is safe *as long as* multi-provider refresh orchestration
always diffs a provider's own previous snapshot against its own current
one, never across providers — a constraint on §6's orchestration design,
not a change needed to these functions.

---

## 4. Persistence migration

| Store | Shape change needed | Migration risk |
|---|---|---|
| Keychain (`ClaudeCredentials` at `"claude.credentials"`) | None — a new provider adds a new key/type pair | None; purely additive |
| `SnapshotStore` (`UsageSnapshot` JSON per `providerID`) | None from adding a provider. If §3's `windowDuration` field is added to `UsageWindow`, that's a new optional-decodable field | Low — `SnapshotStore.snapshot(for:)` already does `try? decoder.decode(...)` (line 41) and returns `nil` on failure; an old cached snapshot missing the new field either decodes fine (if the field is optional) or is silently dropped until the next refresh overwrites it. This is the existing fallback, not a new mechanism — acceptable, but it's silent-nil-on-mismatch, not a real migration path, worth stating explicitly rather than assuming. |
| `UsageHistoryStore` (`[String: [UsageSample]]` per `providerID`) | None | None — already provider-keyed, shape unchanged |
| `NotificationPreferences` / `NotificationScheduler` keys | **Yes** — §2's fix renames every key from `"notify.<kind>"` to `"notify.<providerID>.<kind>"` (or equivalent) | **Real regression without a migration.** An existing user with `"notify.session" = true` and a scheduled `"reset.session"` request would silently read `false` from the new key on upgrade — every existing user's notification preferences reset to off. |
| `Preferences.glanceMetric` (`"pref.glanceMetric"` = bare storageKey) | **Yes**, if it becomes a compound `providerID`-qualified value | Same class of regression: an existing `"session"` value doesn't parse as `"claude|session"` |
| `ModelSlotFallback` / `showCreditsAmount`, if scoped per-provider | Possibly | Same class, if pursued |

**Proposed approach:** a one-time, idempotent migration run at
`RefreshService.init()` (or app launch), guarded by a completed-flag in
the App Group `UserDefaults` — the same shape as the migration
`RefreshService.migrateCredentialsToSharedGroup()`
(`RefreshService.swift:32-40`) already establishes for moving credentials
into the shared keychain access group (checks the destination is empty,
reads the legacy location, writes through, deletes the legacy copy). For
preference/notification keys specifically: since Claude is the only
provider that can have pre-migration data, any bare (unprefixed) key
found unambiguously belongs to `"claude"` — no disambiguation logic
needed, just a rewrite pass: read the old key, write it under
`"claude"`'s new prefixed key, leave the old key in place or delete it
(harmless either way once nothing reads it).

**Notification identifiers specifically don't need separate migration
code.** `rescheduleResets`/`rescheduleRunOuts` already do a full
remove-then-readd of everything under their prefix on every successful
fetch (`NotificationScheduler.swift:116`, `155`). As long as the
*preference*-key migration runs before the first post-upgrade refresh,
the *identifiers* self-heal to the new prefixed format on that refresh —
the stale old-format pending requests get cancelled as a side effect of
the reschedule, not because anything explicitly migrated them.

---

## 5. Auth abstraction

**What's already a clean, reusable seam:** `KeychainStore` (fully
generic) and `HTTPTransport` (fully generic protocol,
`Networking/HTTPTransport.swift`). Any provider's credential source can
build on both without changes.

**What's a pattern to copy, not a type to share:** `ClaudeCredentialSource`
(`ClaudeCredentials.swift:70-79`) is typed concretely to `ClaudeCredentials`
— it can't be reused verbatim for Codex. A `CodexCredentialSource`
protocol with its own `CodexCredentials` type, following the identical
`allowsRefresh`/`load()`/`save()` shape, is the right move — not
generalizing to `protocol CredentialSource<Credentials>` with associated
types, since the only consumer of `ClaudeCredentialSource` is
`ClaudeProvider` itself (`ClaudeProvider.swift:13`). Generalizing the
protocol buys nothing here and would cut against CLAUDE.md's own
provider-isolation philosophy ("provider mapping code never produces...").

**What's accidentally Claude-Code-specific, not accidentally general:**

- The paste-back flow's exact `"<code>#<state>"` splitting
  (`ClaudeOAuth.swift:54-57`) mirrors Claude Code's own CLI convention. It
  is very unlikely Codex or Cursor use this exact convention — Codex's
  CLI OAuth may use a local redirect server or device-code polling loop;
  Cursor (an IDE, not a terminal tool) likely uses a plain web session or
  an API key generated from a settings page. The *Connect sheet's form
  factor* (one paste field + one "Open Sign-In" button,
  `ConnectClaudeSheet.swift`) is Claude-shaped UX, not a generic "auth
  step" abstraction — it would be a mistake to assume every provider's
  Connect step looks like this.
- `ClaudeAutoCredentialSource`/`ClaudeCodeLocalCredentialSource`
  (`ClaudeAutoCredentialSource.swift`, `ClaudeCredentialDiscovery.swift`)
  — the "read a sibling CLI's own local credential store, read-only, so
  the user never signs in again" mechanic depends on knowing Claude
  Code's exact Keychain service name (`"Claude Code-credentials"`) and
  file path (`~/.claude/.credentials.json`). This is a genuinely nice
  zero-setup UX, but it is **not a reusable pattern** unless Codex CLI
  (and, much less plausibly, Cursor) maintains an analogous local store —
  unverified, see §8. Don't assume it carries over; verify per-provider.

**What the Connect sheet needs to become:** a per-provider dispatch point,
not a single view. `DashboardView.showingConnect: Bool`
(`DashboardView.swift:10`) and `MenuBarView`'s equivalent
(`MenuBarView.swift:27`) are single booleans — they can't represent
"which of N providers' connect sheets is open." Minimal fix: change the
state to a provider identifier (`showingConnect: String?` or a small
enum) and switch on it to present `ConnectClaudeSheet()` /
`ConnectCodexSheet()` / etc. Since `Packages/UsageKit` can't import
SwiftUI (CLAUDE.md's own architecture rule), this dispatch necessarily
lives in the app target, not the package — the package only ever exposes
`UsageProvider.fetchUsage()`; everything about *how a user connects* is
and remains app-layer, per-provider code.

---

## 6. Refresh orchestration

**Concurrency:** `RefreshService` needs to hold a list of `(any
UsageProvider, credential source)` pairs and fetch them concurrently —
nothing structurally prevents this today: `fetchUsage()` is already
`async`, each provider's `HTTPTransport` call is independent, and the
only shared-state write during a fetch is `credentialSource.save()` for
token rotation, which is already scoped to that provider's own storage
key. A `TaskGroup` returning `(providerID, Result<UsageSnapshot, Error>)`
per provider is the natural shape — one provider's thrown error becomes a
value in the result set, not a thrown error that cancels the group.

**Partial failure is a `UsageModel` rewrite, not an addition.**
`snapshot: UsageSnapshot?` and `lastError: String?`
(`UsageModel.swift:10,12`) are both singular. They need to become
provider-keyed (`[String: UsageSnapshot]` / `[String: String?]`, or an
array of per-provider state) so provider B's failure doesn't blank
provider A's card. Every view currently reading `model.snapshot`/
`model.lastError` directly — `DashboardView`, `ProviderDetailView`,
`MenuBarView`, `LandscapeUsageView`, `WindowRowsList`, `ForecastCard`,
`NotificationTogglesCard`, `SmartNotificationTogglesCard` — needs to
instead read `model.snapshot(for: providerID)`. This is mechanically
simple per call site but touches essentially every view in the app; it is
the single largest-surface refactor in this whole plan, though not the
riskiest (§9 covers sequencing this before any new provider ships).
`UsageStatusFooter` (`ThemeComponents.swift:108-127`) already takes an
explicit `error:`/`snapshot:` parameter per call site — no change needed
there, it just needs a provider-scoped caller, which falls out of the
`UsageModel` fix for free.

**WidgetKit refresh budget:** one `WidgetCenter.shared.reloadAllTimelines()`
call (`RefreshService.swift:58`) already reloads both widget kinds
regardless of how many providers changed — N providers doesn't multiply
this call. The actual risk is inside a *single timeline generation*:
`UsageTimelineProvider.getTimeline` (`UsageWidget.swift:29-46`)'s iOS
self-fetch path currently does one network call within a 15-second
per-request timeout (`WidgetRefresher.swift:16-19`). WidgetKit gives a
timeline provider a real, short wall-clock budget before the OS
terminates the extension process. **Yes — if the `AIMeterUsage` widget
is asked to render N providers, its self-fetch path means N network calls
in that same tight budget**, and today's design (one provider, one
timeout) does not account for that. Sequential fetches at 15s each blow
the budget with just two stale providers. Concurrent fetch (task group,
shared shorter combined timeout) is the minimal fix, and/or only
self-fetching the specific provider(s) whose snapshot is actually stale
rather than all N unconditionally — a straightforward extension of the
existing single-snapshot staleness check (`WidgetRefresher.fetchIfStale`,
line 22-24), just looped per provider instead of assumed singular.

**The single-window widget is unaffected by this.**
`SingleUsageTimelineProvider.entry(for:)` (`SingleUsageWidget.swift:67-78`)
already resolves exactly one `providerID` from the user's own
`AppIntent` selection — it stays O(1) regardless of how many providers
exist in the app. Worth noting as evidence the single-widget's design
already scales better than the three-window widget's.

**macOS has no self-fetch path at all** — the menu bar app feeds the
widget (per CLAUDE.md's own architecture rule: a sandboxed widget can't
read Claude Code's credential file). Multi-provider concurrency there is
purely inside `UsageModel`'s own timer-driven refresh; no WidgetKit
budget concern.

---

## 7. UI/UX implications

**Provider list/ordering:** nothing today represents "the set of
providers the user has." `UsageModel` has no array of providers at all.
Minimal starting point: a fixed compile-time ordered list (e.g.
`["claude", "codex", "cursor"]`), not a user-configurable reorder UI —
defer reordering until there's a product reason to need it with 3 real
providers in hand.

**Where per-provider display prefs live:** today `modelSlotFallback`/
`showCreditsAmount`/`glanceMetric` are edited from the one Claude
`ProviderDetailView` and stored globally (§1, §2). Once scoped
per-provider, each provider needs its own detail screen showing only the
config that provider actually has — Codex likely has no credits concept
at all, so no "Third usage row" card for it. The existing conditional
pattern already used for Spend/Extra usage cards
(`ProviderDetailView.swift:62,68` — `if let spend = model.snapshot?.spend`)
is the right template to extend: render config sections based on what
that provider's snapshot actually contains, not a fixed Claude-only
layout. `WindowRowsList`/`ForecastCard`/`NotificationTogglesCard` are
already reusable components taking a `snapshot:` parameter — the
detail-screen rewrite is about which provider's snapshot and which
config cards get passed in, not new row/card primitives.

**`AIMeterUsage` (three-bar widget) — needs a decision, not just a fix.**
It renders exactly one provider's snapshot today. Two real options:

1. Convert it to an `AppIntentConfiguration` exactly like
   `AIMeterSingleUsage` already is, letting the user pick *which
   provider's* three-window view a given widget instance shows. Smallest
   change — reuses the proven `UsageWindowOption`-style selection pattern,
   introduces no new widget kind. A user with 2 connected providers needs
   2 placed widgets to see both — no worse than today's implicit
   single-provider reality.
2. Ship one static widget kind per provider (`AIMeterClaudeUsage`,
   `AIMeterCodexUsage`, ...). More consistent with today's
   `.configurationDisplayName("Claude")` (`UsageWidget.swift:62`), but
   multiplies per-provider target/asset/config work and doesn't scale
   cleanly as more providers are added.

This analysis recommends (1) as the smaller, more scalable change, but
flags it explicitly as a product-taste call (widget gallery discoverability
differs materially between the two) — see §10, decision #3.

**Menu bar label / Lock Screen circular gauge:** both are single-number
surfaces already built around one `(kind)` selection
(`Preferences.glanceMetric`). Per §2, the fix here is making that one
selection provider-qualified (`(providerID, kind)`), not giving each
provider its own separate glance pref — there's one surface, so it needs
one answer. CLAUDE.md's existing framing ("no room for a fixed
three-slot layout") already implies a single glance value is the
intended design even at N providers; this analysis is not proposing a
new "combine/cycle multiple providers" feature, just widening the key
that identifies which single window is shown.

**Dashboard with 3 providers, 2 disconnected:** `DashboardView.providerSection`
(`DashboardView.swift:71-93`) renders exactly one `providerHeader` + one
`Card` for the hardcoded `"claude"` provider. This becomes a loop over the
provider list, each iteration rendering its own header and its own
connect-prompt-or-usage-card independently, using components
(`DisconnectedPrompt`, `Card`, `WindowRowsList`) that are already
per-call-site and reusable. This is mechanical ("wire the loop") once
§6's `UsageModel` rewrite gives each provider its own state to loop over
— no new UI primitive is required here.

---

## 8. Per-provider feasibility

**Nothing in this repository verifies anything about Codex's or Cursor's
actual usage endpoints, auth flows, or wire formats.** There is no
`Providers/Codex` or `Providers/Cursor` code, no captured fixture, no
probe script for either. Everything below is explicitly framed as open
questions to resolve via a probe, per CLAUDE.md's own workflow rule
("Never guess wire formats") — not as findings.

### Codex

Open questions, all unverified:

- Does Codex CLI maintain a local credential store analogous to Claude
  Code's Keychain item / `~/.claude/.credentials.json`, that could be read
  read-only the way `ClaudeCodeLocalCredentialSource` does? Needs
  inspection of a real Codex CLI install (its config directory, and a
  Keychain dump on macOS) by someone with an active account.
- What's the actual OAuth/API-key model — PKCE like Claude, a
  device-code flow, a long-lived API key, or a ChatGPT-session-cookie
  model? Unverified.
- Does its usage data actually take a "session + weekly" rolling-window
  shape, as this task's own framing assumes? That framing should be
  treated as a hypothesis to validate, not a confirmed fact — nothing in
  this codebase or its history establishes it.
- Does whichever endpoint exists have the same User-Agent-sensitive
  rate-limiting Claude's does (`ClaudeProvider.swift:17-19`'s comment:
  "other agents hit an aggressively rate-limited bucket")? Unverified,
  must be probed carefully to avoid tripping it during discovery.

**Probe needed:** a `Scripts/probe-codex-usage-endpoint.sh` mirroring
`Scripts/probe-usage-endpoint.sh`'s shape — locate Codex CLI's local
credential store (once its location is known), extract a token, call
whatever usage endpoint exists (URL currently unknown) with plausible
headers, capture the raw JSON as a fixture. The blocking unknown is the
credential-store location and the endpoint URL — both require hands-on
inspection of a real Codex CLI installation (or its source, if
inspectable) before a probe script can even be written.

### Cursor

Open questions, all unverified:

- Cursor is an IDE (a VS Code fork), not a terminal-first CLI tool like
  Claude Code — does it have *any* local credential file comparable to
  `~/.claude/.credentials.json`, or is usage only ever visible through the
  cursor.com web dashboard? This distinction matters structurally: if
  usage is dashboard-only, there is no Cursor equivalent of
  `ClaudeAutoCredentialSource`'s zero-setup read-only mirror at all — an
  interactive OAuth or pasted-API-key flow (like `ClaudeKeychainCredentialSource`'s
  iOS path) would be required on **every** platform, not just iOS, which
  changes the macOS Connect story materially from Claude's.
- Does Cursor expose "Auto usage / Total usage / API usage" (this task's
  framing) via any documented or reverse-engineerable API? Unverified —
  would likely require inspecting the dashboard's own network requests
  while logged in to find its auth mechanism and endpoint shape, since
  there's no CLI source to read.
- Do any of these figures carry a `resetsAt`? If genuinely not (per this
  task's own framing), §3's new non-resetting `Kind` case is a hard
  prerequisite for Cursor specifically, not an optional nicety.

**Probe needed:** `Scripts/probe-cursor-usage-endpoint.sh` — inherently
harder to scope than Codex's, because there's no CLI tool whose local
storage is inspectable; the starting point would be capturing the
dashboard's own authenticated network calls (browser dev tools) rather
than reading a config file.

**Neither probe script should be written in this pass** — both require
first establishing basic facts (credential storage location, endpoint
URL) that only someone with a live account can determine.

---

## 9. Phased plan

**Vertical slice: Codex first — tentatively, conditional on its probe.**
Reasoning: this task's framing places Codex's assumed shape
("session + weekly") structurally closer to Claude's existing
`Kind`/`WindowSlots`/pace/run-out model than Cursor's assumed shape
("Auto/Total/API usage," possibly no `resetsAt`). Shipping Codex first
would validate the multi-provider *plumbing* (§2's key-scoping, §6's
`RefreshService`/`UsageModel` rewrite, §7's dashboard loop) without also
having to solve §3's harder non-resetting-window question in the same
pass — don't conflate "does the app support N providers" with "does the
data model support a fundamentally different usage shape" in one change.
If Codex plausibly has a local-credential-mirror pattern (unverified,
§8), its Connect story might also be nicer to validate against than
Cursor's likely dashboard-only auth.

**This recommendation is explicitly conditional on Phase 0's probe.** If
Codex's real shape turns out to be as awkward as Cursor's assumed shape
(or worse), the "ship the structurally-simpler one first" logic reverses.
Don't commit to Codex-before-Cursor until the probe confirms the premise.

- **Phase 0 — probe, no code.** Write and run
  `probe-codex-usage-endpoint.sh` (and Cursor's, if/when pursued),
  capture real fixtures, confirm or refute every "appears to expose"
  assumption in this task's own framing. This gates everything else, per
  CLAUDE.md's existing workflow rule.

- **Phase 1 — refactor only, zero new provider, Claude-only behavior
  unchanged.**
  - Provider-scope every notification preference key and notification
    identifier (§2), plus the migration from §4.
  - Move `windowDuration`/`nominalPeriod` off `Kind` onto explicit
    provider-supplied data on `UsageWindow` (§3); update
    `ClaudeUsageResponse.usageWindows()` to populate it — pure refactor,
    behavior-preserving, covered by existing `ClaudeResponseMappingTests`.
  - Rewrite `RefreshService` to hold a provider list + concurrent fetch +
    per-provider `Result` (§6) — still exactly one element (Claude) in
    that list.
  - Rewrite `UsageModel` to key `snapshot`/`lastError`/notification state
    by `providerID` (§6) — still exactly one provider's worth of state,
    just keyed instead of singular.
  - Update every view reading `model.snapshot` to read
    `model.snapshot(for: "claude")` explicitly — mechanical, wide-surface
    (§6).
  - Fix `UsageWindowOptionQuery.currentOptions()` to loop over the
    provider list instead of the hardcoded string (§2).
  - Ship this as an internal, behavior-identical release. This is the
    single riskiest phase for silent regressions (it rewrites the app's
    core data model) and needs full manual verification on both
    platforms plus expanded `swift test` coverage for the new key shapes
    and the migration — before any second provider exists to complicate
    the picture.

- **Phase 2 — Codex feature, additive.** `Providers/Codex/` following the
  exact isolation pattern of `Providers/Claude/` (whatever credential
  model the Phase 0 probe found, response mapping, provider struct); a
  `ConnectCodexSheet`; wire into the now-generic dashboard loop and
  `RefreshService`'s provider list; add a `providerIcon`/asset parameter
  to `ProviderIdentityView` (§1's fix is a prerequisite here, not
  optional — otherwise Codex's header shows the Claude starburst); a
  Codex icon asset; `Providers/Codex` test fixtures mirroring
  `ClaudeResponseMappingTests`. Do the `AIMeterUsage`
  `AppIntentConfiguration` conversion (§7, option 1) in this phase too,
  since otherwise Codex has no three-bar widget option at all.

- **Phase 3 — harden multi-provider UX**, once there are two real,
  connectable providers to test against: provider ordering, per-provider
  detail-screen generalization (§7), dashboard mixed-connection-state
  polish, the WidgetKit self-fetch concurrency fix for N providers (§6).
  Deliberately deferred past Phase 2 rather than built speculatively.

- **Phase 4 — Cursor**, gated on Phase 0's Cursor probe *and* on Phase
  1/3's data-model flexibility for non-resetting windows actually
  existing. Likely needs the new `Kind` case from §3, likely needs an
  interactive-only Connect flow (no local-mirror credential source per
  §8's open question), likely needs a bespoke slot layout since
  `WindowSlots`'s session/weekly/model triad may not fit "Auto/Total/API
  usage" at all (§3, §7). Flag this explicitly as the phase most likely
  to reveal that §3's "minimal type change" wasn't sufficient once real
  Cursor data is in hand — budget for it to require more than a new enum
  case.

**What should NOT be built yet:**

- No general plugin/dynamic-provider-discovery system — a compile-time
  array literal is enough for 2-3 providers; CLAUDE.md's own instruction
  is to prefer the smallest change over a general framework.
- No user-facing provider-reordering UI before Phase 3, and no strong
  case for it even then without a concrete product ask.
- No generalized "Connect flow" protocol/abstraction beyond simple
  per-provider dispatch (§5) — with a sample size of one provider today,
  it's not yet knowable what's actually shared vs. provider-specific
  about Connect UX; premature abstraction here is exactly the kind of
  thing CLAUDE.md's own conventions warn against.
- No wholesale redesign of `SpendStatus`/`ExtraUsageStatus`/
  `ModelSlotFallback` into a generic "provider capabilities" system —
  extend `Preferences` additively (provider-scoped keys) rather than
  redesigning the preference model before there's a second real data
  point.
- No Cursor-shaped non-resetting-window support built speculatively ahead
  of Phase 0's Cursor probe confirming it's actually needed in the form
  assumed here.

---

## 10. Risks & open decisions

**What could make this analysis wrong:**

- Everything in §8 is unverified by construction — if Codex's real shape
  isn't session+weekly (e.g. a single rolling quota, or token-count-based
  rather than percentage-based), §9's "validate the easy case first"
  premise weakens and the Codex-before-Cursor ordering should be
  revisited.
- The claim that `SnapshotStore`/`UsageHistoryStore` are "already ready"
  rests on their current string-keying scheme plus one existing test
  (`testSnapshotsAreScopedPerProvider`). It assumes provider IDs stay
  simple lowercase tokens with no delimiter characters — `UsageWindowOption.id`'s
  `"\(providerID)|\(kind.storageKey)"` scheme (`SingleUsageConfigurationIntent.swift:14`)
  would break if a `providerID` ever contained `|`. Low risk since
  provider IDs are hardcoded by us, not user-supplied, but worth a
  one-line constraint if that ever changes.
- This analysis assumes `UsageProvider.fetchUsage()`'s single-shot,
  no-pagination async model generalizes to Codex/Cursor. If either
  requires multiple paginated calls, or an OAuth device-code polling loop
  rather than a single paste-back exchange, `UsageProvider` itself is
  still fine (it only describes the *result*), but §5's Connect-UX effort
  estimate is likely too small.
- §2/§7's recommendation to keep `glanceMetric` a single
  provider-qualified value (not per-provider) assumes the menu bar/Lock
  Screen gauge should stay a single number even at N providers. If the
  actual product intent is "show a combined or per-provider glance
  somewhere," that's a materially larger feature than scoped here.

**Decisions needed before implementation starts:**

1. Confirm Codex-first ordering (§9), or prioritize Cursor instead — a
   product call, not something this analysis can settle; §9's ordering
   is conditional on the Phase 0 probe regardless.
2. Whether to start Phase 1 (Claude-only refactor) now, in parallel with
   Phase 0 probing, or wait for probe results first. Recommend starting
   Phase 1 now — it's valuable and low-risk independent of what
   Codex/Cursor turn out to look like.
3. Whether `AIMeterUsage` becomes an `AppIntentConfiguration` (§7 option
   1, this analysis's recommendation) or gets a widget kind per provider
   (§7 option 2) — a real product/discoverability call with App Store
   surface-area implications this analysis shouldn't decide unilaterally.
4. Whether `ModelSlotFallback`/`showCreditsAmount` are Claude-specific
   enough to simply not exist for Codex/Cursor (this analysis's working
   assumption), or are actually a more general "overflow/credits"
   concept every provider might need — affects whether §2's
   per-provider-scoping of these prefs is the right frame at all, versus
   retiring them as Claude-only special cases.
5. CLAUDE.md and README.md both need edits reflecting this review
   regardless of which phase ships first — specifically README.md:144-145
   ("Adding a provider = implementing `UsageProvider`... one folder under
   `Providers/`") is false as currently written and should either be
   corrected now or explicitly marked aspirational until Phase 1 lands.

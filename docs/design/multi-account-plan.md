# Multi-account Claude support — design plan

Status: approved, implementation in progress (see CLAUDE.md once each phase
lands — this document is the durable design record; CLAUDE.md is updated to
match reality only as each phase is actually implemented, not ahead of it).

## Context

Today AIMeter supports exactly **one** connected Claude account. The
single-account assumption is baked in at several levels: `ClaudeProvider.id`
is a fixed `"claude"` literal, `RefreshService`/`UsageModel` hold a single
`provider`/`snapshot`, Keychain/SnapshotStore/UsageHistoryStore keys are a
single fixed string, and notification identifiers carry no account concept
at all. The goal is to let a user connect **several Claude accounts
simultaneously**, all "live" (each refreshed independently), viewable from
the dashboard, the macOS menu bar, and widgets — with widgets able to pick
which account they point at.

Investigation of the actual code confirmed the low-level storage layer
(`KeychainStore`, and the `key`/`providerID` parameter of
`SnapshotStore`/`UsageHistoryStore`/`ClaudeKeychainCredentialSource`) is
already generic — the "one account" assumption lives in the *callers*
(`RefreshService`, `NotificationScheduler`, the widgets), not in the storage
APIs themselves. That makes this change more contained than it first
appears.

## Confirmed product decisions

1. **macOS menu bar**: one status item (one gauge, a selectable "primary"
   account); the popover expands to show **all** accounts as stacked
   sections (same visual pattern as the Dashboard).
2. **3-window widget (`AIMeterUsage`)**: becomes configurable per account —
   converts to `AppIntentConfiguration` (like `AIMeterSingleUsage` already
   is), with an account picker in "Edit Widget".
3. **Smart notifications** (near-limit, limit-reached, run-out,
   early-reset): become **per account** — each account gets its own "Smart
   notifications" card in its own Provider Detail. `peak.` (peak hours)
   stays **global** — it's a Claude-wide policy, not tied to a specific
   account, and firing it once per account would just be duplicate noise.

## Core architectural decision: Account ≠ Provider

- `providerID` keeps meaning what it means today: the provider *family*
  (`"claude"`), reusable the day Codex/Cursor get added.
- A new `accountID: String` key is introduced, but **outside**
  `UsageProvider`/`UsageSnapshot`/`ClaudeProvider` — it lives one layer up,
  only in storage/orchestration/widgets:
  - `SnapshotStore`/`UsageHistoryStore` already work as "the caller already
    knows which account it asked for" — the pattern already exists today in
    `SingleUsageEntry`, which carries `providerID` as a field *sibling* to
    the snapshot, not read from inside it. Extending that same pattern to
    `accountID` is one extra field per type, not a schema change.
  - `UsageSnapshot` is `Codable` and persisted to disk today with no
    versioning — adding a required field would force a lenient decoder just
    to keep old persisted blobs readable, for no functional gain.
  - `ClaudeProvider`, its protocol, and its whole test suite stay
    **untouched** — no account changes its init signature. A future
    provider (Codex/Cursor) still only needs to implement `fetchUsage()`;
    "which account is this" stays the host app's bookkeeping, consistent
    with the existing rule that each provider isolates its own endpoint
    specifics.
- **Key migration simplification**: the existing account of a user who
  upgrades is migrated with the **literal accountID `"claude"`** (not a
  fresh UUID). New accounts (2nd, 3rd... or even the 1st on a clean
  post-feature install) get `UUID().uuidString`. Because the key formulas
  (`"usage.snapshot.\(accountID)"`, `"usage.history.\(accountID)"`, the
  widget composite id `"\(accountID)|\(kind.storageKey)"`) don't change,
  three of four migration hazards become **structurally impossible**
  instead of something to handle: saved snapshots, history, and any
  already-placed `AIMeterSingleUsage` widget (which today persists its
  selection as `"claude|kind"`) keep resolving exactly the same, with zero
  migration code for them. Only the Keychain (one special-cased key
  formula) and account-unscoped preferences/toggles need an actual copy
  step.

## New component: `AccountRegistryStore`

No enumeration API exists today for "which accounts are connected" — every
store is a point lookup by a key the caller must already know. A real list
is needed so the Dashboard, menu bar, and widget `AppIntent`s can populate
themselves.

New file:
`Packages/UsageKit/Sources/UsageKit/Storage/AccountRegistryStore.swift`
(pure Foundation, no SwiftUI/WidgetKit/Combine — respects the UsageKit
rule; App Group UserDefaults, same pattern as `SnapshotStore`).

```swift
public struct ConnectedAccount: Codable, Hashable, Sendable, Identifiable {
    public var id: String { accountID }
    public let accountID: String        // "claude" (migrated) or a UUID (new)
    public let providerID: String       // "claude" today — provider family
    public var displayName: String      // user-editable nickname, default "Claude"
    public var credentialStrategy: CredentialStrategy   // .managed | .autoDetected
    public var connectedAt: Date
    public enum CredentialStrategy: String, Codable, Sendable { case managed, autoDetected }
}

public struct AccountRegistryStore: Sendable {
    public func accounts() -> [ConnectedAccount]              // order = display order
    public func account(for accountID: String) -> ConnectedAccount?
    public func add(_ account: ConnectedAccount) -> Bool       // no-op if id exists
    public func rename(_ accountID: String, to displayName: String)
    public func remove(_ accountID: String)                    // list membership only — no cascade
    public func replaceAll(_ accounts: [ConnectedAccount])
}
```

One JSON array under one key (`"usage.accounts"`) — array order *is*
display order, no extra field needed if reordering is ever added.

**Concurrency contract** (documented in CLAUDE.md alongside the existing
`SnapshotStore` rule): only the **app** calls
`add`/`rename`/`remove`/`replaceAll`; the **widget extension** only ever
calls `accounts()`/`account(for:)`. Same "only the app writes" invariant
that already exists today, so no new write-write race is introduced.
`remove()` deliberately does **not** cascade to Keychain/Snapshot/History/
notifications — that orchestration lives in `UsageModel.disconnect(accountID:)`,
keeping this store as "dumb" as `SnapshotStore` already is.

**Empty-registry fallback** (important for the app-vs-widget startup race,
see Risks): any read-only consumer (the widgets) must treat "0 registered
accounts" as "assume the single implicit legacy account, `accountID ==
"claude"`" instead of "show nothing" — covers both "genuinely nothing
connected yet" and "the app hasn't run the migration since the update" with
the same code path, with the widget never needing to write.

## Effect layer by layer

- **UsageKit Core** (`UsageProvider`, `UsageSnapshot`, `ClaudeProvider`,
  `PaceCalculator`, `RunOutPredictor`, `PeakCalculator`...): **no changes**.
  These pure functions already operate on "one snapshot at a time"; they
  just get invoked once per account instead of once globally.
- **UsageKit Storage**: new `AccountRegistryStore` (above).
  `SnapshotStore`/`UsageHistoryStore` keep their signatures — only their
  `providerID` parameter is reinterpreted as `accountID` in comments (the
  caller already passes the right string).
- **Credentials**: new pure helper
  `ClaudeKeychainCredentialSource.storageKey(for accountID:) -> String`
  (`"claude.credentials"` when `accountID == "claude"`, else
  `"claude.credentials.\(accountID)"`) — used by both the app and the
  widget so they never diverge. `ClaudeAutoCredentialSource` (macOS) stays
  structurally capped at **one account** — an external limit of the Claude
  Code CLI itself (one login per machine), not something AIMeter can
  resolve. So account #1 on macOS can be "auto-detected"; account #2+
  always goes through the manual OAuth/paste flow (the same one iOS
  already uses for its one account today).
- **`RefreshService`**: goes from constructing once (`init()`) to
  constructing **per account** (`init(account: ConnectedAccount)`),
  choosing `ClaudeAutoCredentialSource`/`ClaudeKeychainCredentialSource`
  based on `account.credentialStrategy`.
- **`UsageModel`**: goes from a single `snapshot: UsageSnapshot?` to
  `accounts: [AccountUsage]` (account + snapshot + error + isRefreshing);
  `needsConnection` becomes `accounts.isEmpty`; `refresh()` becomes
  `refreshAll()` using a `TaskGroup` (safe to run concurrently — each
  account uses a different bearer token, no shared rate-limit bucket
  between accounts). Notification logic splits out to
  `UsageModel+Notifications.swift` since the file is already near the
  project's ~300-line convention.
- **`NotificationScheduler`**: every identifier/prefix gains an account
  component (`reset.<accountID>.<kind>`, `runout.<accountID>.<kind>`, etc.
  — `peak.` stays as-is, it's global). Toggles (`NotificationPreferences`)
  also gain `accountID` in their key. Notification bodies include the
  account's `displayName` when more than one is connected, so they're
  distinguishable in Notification Center.
- **Account-scoped preferences** (`modelSlotFallback`, `showCreditsAmount`
  in `Shared/PreferencesStore.swift`): already conceptually "per account"
  (they interpret *that* account's windows/spend) but stored unkeyed today
  — become `"pref.<accountID>.modelSlotFallback"` etc. `displayMode`,
  `resetStyle`, `refreshCadence`, `appearance`, and the 3 macOS-chrome
  prefs stay **global**, unchanged — legitimately app-wide.
- **`glanceMetric`**: a real platform split worth stating explicitly:
  - **iOS**: becomes **obsolete**. Once `AIMeterUsage` becomes
    `AppIntentConfiguration` (decision #2 above), that applies
    automatically to all its families, including Lock Screen accessories
    (circular/rectangular/inline) — every instance the user places, Home
    Screen or Lock Screen, already carries its own account+window picker
    via Edit Widget, same as `AIMeterSingleUsage` already does. No more
    global pref needed for "what the circular gauge shows."
  - **macOS**: no such mechanism — `MenuBarExtra` is a single scene, no
    per-instance configuration. Stays a **global** pref
    (`"pref.glanceMetric"`), paired with a new `"pref.primaryAccountID"` —
    together they decide which account and which window the one status
    item shows. Both relocate from Provider Detail to `MacChromeSettings`
    (there's no longer "the" account that owns that control).
- **Widgets**:
  - `AIMeterSingleUsage`: `UsageWindowOption`'s composite id goes from
    `"providerID|kind"` to `"accountID|kind"` — the plumbing already
    exists almost completely (`SingleUsageEntry` already carries an
    identity field sibling to the snapshot; `UsageWindowOptionQuery.currentOptions()`
    already hardcodes the exact literal that needs replacing with an
    enumeration of `AccountRegistryStore.accounts()`). The label shown in
    Edit Widget includes the account nickname ("Personal · Weekly") so two
    Claude accounts are distinguishable.
  - `AIMeterUsage`: goes from a static `TimelineProvider` to
    `AppIntentConfiguration` with a new, simpler `AppEntity` (account only,
    no window — always shows all 3). Default account when unconfigured =
    the first in the registry (which, thanks to the `"claude"` accountID
    trick, is exactly the account the widget already showed before the
    update — already-placed widgets don't go blank).
  - iOS's self-fetch (`WidgetRefresher`/`getTimeline`) builds credentials
    with the same `ClaudeKeychainCredentialSource.storageKey(for:)` the app
    uses, for that specific instance's account.
- **Dashboard / Provider Detail**: `providerSection` (today a fixed
  section) becomes `ForEach(model.accounts)`, each rendering a new shared
  `AccountSectionView` (reusable later by the menu bar popover).
  `ProviderDetailView` takes `accountID:` as a required parameter. The
  disconnect button, which today **only exists on iOS**, is added to macOS
  too — with several accounts, macOS needs a way to remove one without
  being the only management surface.
- **Connect sheet**: gains a nickname field (default "Claude", or "Claude
  2" suggested based on how many already exist) — there's no signal from
  the API (email, name) to auto-generate a distinctive name, so the user
  has to set it. On macOS, the "auto-detect from Claude Code" option hides
  once an account with `credentialStrategy == .autoDetected` already
  exists.
- **Settings**: notification cards are removed entirely (today duplicated
  there and in Provider Detail) — with no single "the" app account
  anymore, there's no unambiguous target for them; they live only in each
  account's Provider Detail.
- **macOS menu bar**: the popover goes from one section to
  `ForEach(model.accounts)` reusing `AccountSectionView`, wrapped in a
  height-capped `ScrollView` (today's fixed `VStack` doesn't scroll). The
  status item's gauge uses the account marked primary
  (`primaryAccountID`, falling back to the first account if unset or
  stale).

## Migration (existing single-account users)

Runs once per launch, in a new `AIMeter/Services/AccountMigration.swift`,
invoked at the start of `UsageModel` — same place
`RefreshService.migrateCredentialsToSharedGroup()` already runs today.
**Each step gates itself independently** (not one shared "migrated" flag),
so a crash between steps can never skip a later step on the next launch:

1. **Register the legacy account** — if `registry.account(for: "claude")`
   doesn't exist AND there's a legacy signal (a Keychain item at the
   default key, or — macOS — the Claude Code CLI resolves): add
   `ConnectedAccount(accountID: "claude", providerID: "claude", displayName:
   "Claude", credentialStrategy: .autoDetected/.managed as appropriate)`.
   The only real mutation — Keychain, SnapshotStore, and UsageHistoryStore
   already work untouched, thanks to the literal `"claude"` accountID.
2. **Copy unscoped preferences to their per-account key** — for each
   existing flat key (`notify.session`, `notify.weekly`, `notify.runout`,
   `notify.earlyReset`, `notify.nearLimit`, `notify.nearLimitThreshold`,
   `notify.limitReached`, `pref.modelSlotFallback`, `pref.showCreditsAmount`)
   whose `<prefix>.claude.<rest>` equivalent doesn't exist yet: copy the
   value. `notify.peak` is not copied — stays global on purpose.
3. **No action, verified**: SnapshotStore/UsageHistoryStore blobs and any
   already-saved widget `AppIntent` — compatible by construction, untouched.
4. **Old keys are never deleted** — they stay inert indefinitely; deleting
   them buys nothing and adds a failure mode.

## Implementation phases

- **Phase 0** — save this document (done).
- **Phase 1** — `AccountRegistryStore` + credential key helper in UsageKit,
  fully unit-tested.
- **Phase 2** — `RefreshService`/`UsageModel` multi-account orchestration +
  migration.
- **Phase 3** — Dashboard/Provider Detail/Connect UI.
- **Phase 4** — per-account notifications.
- **Phase 5** — widgets (account picker on both kinds).
- **Phase 6** — macOS menu bar (primary account + all-accounts popover).
- **Verification** — `swift test` + `xcodebuild` both platforms, warning-free;
  update CLAUDE.md to describe the shipped architecture.

## Risks and edge cases

- **"App hasn't migrated yet / widget launches first" race**: resolved by
  the empty-registry fallback above rather than letting the widget write
  too — keeps the "only the app writes" invariant clean.
- **Notification permission is one OS-level toggle, not per account** —
  enabling any smart notification on any account triggers the same system
  prompt; a denial blocks every account identically. The "blocked, open
  Settings" warning must read global state, not something that could drift
  per account.
- **`ClaudeAutoCredentialSource` stays capped at one account** — enforced
  at the "Add account" UI layer (hide/disable once an `.autoDetected`
  account already exists), not in the registry.
- **WidgetKit's per-kind refresh budget** (already documented in CLAUDE.md
  as shared per widget *kind*) gets more pressure with N accounts × M
  widgets — no code fix, just a documented tradeoff; the app's foreground
  `reloadAllTimelines()` push stays the primary freshness path regardless
  of account count.
- **File length**: `UsageModel.swift` and `NotificationScheduler.swift` are
  already near the project's ~300-line convention — both split as part of
  Phases 2 and 4.
- **`PrivacyInfo.xcprivacy` / entitlements**: no change — the new registry
  is still `UserDefaults` in the same already-declared App Group; Keychain
  uses the same `service`/`accessGroup`, just more items under distinct
  keys.

## Verification checklist

- [ ] `swift test` green in `Packages/UsageKit`, including `AccountRegistryStoreTests`.
- [ ] Clean install → Connect → one account, identical behavior to today.
- [ ] Existing single-account install, upgraded → the account appears alone as "Claude", no re-login, no lost history/pace/toggles.
- [ ] A previously-placed `AIMeterSingleUsage` widget keeps working post-update with zero user action.
- [ ] Add a 2nd account (manual OAuth) → both refresh independently; disconnecting one doesn't touch the other.
- [ ] near-limit/limit-reached/run-out/early-reset toggles are independently settable per account without cross-clobbering identifiers.
- [ ] Both widgets' pickers distinguish accounts by nickname.
- [ ] macOS menu bar tracks the chosen primary account; popover lists and scrolls all accounts.
- [ ] Disconnect exists and works on macOS (didn't before).
- [ ] Settings no longer shows notification cards (live only in each account's Provider Detail).

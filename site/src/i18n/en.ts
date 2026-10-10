import type { Dictionary } from './types'

export const en = {
  meta: {
    title: 'AIMeter — Your AI limits, at a glance',
    description:
      'AIMeter shows how much of your AI subscription is left: session, weekly and per-model limits in widgets, on the Lock Screen and in the Mac menu bar. Free, open source, no server.',
  },
  nav: {
    features: 'Features',
    widgets: 'Widgets',
    privacy: 'Privacy',
    openSource: 'Open source',
    support: 'Support',
    cta: 'Get the app',
    openMenu: 'Open menu',
    closeMenu: 'Close menu',
    langLabel: 'Language',
    navLabel: 'Main navigation',
    home: 'AIMeter home',
  },
  hero: {
    pills: ['Free', 'Open source', 'No account'],
    line1: 'Know what is left',
    line2: '*before* you hit the wall.',
    sub: 'AIMeter shows your AI subscription’s session, weekly and per-model limits where you already look: widgets, the Lock Screen and the Mac menu bar.',
    appStore: 'Download on the App Store',
    appStoreSmall: 'Download on the',
    github: 'View on GitHub',
    scroll: 'Scroll to explore',
    platforms: 'iPhone · iPad · Mac',
    version: 'Version',
    phoneAlt: 'AIMeter dashboard on iPhone: two accounts, each with session, weekly and model limits as bars with reset countdowns.',
    widgetAlt: 'Medium widget with two columns: Session 42% left and Week 11% left, each with a bar and its reset time.',
  },
  statement:
    'Every limit you pay for, in one place. No server, no account, no analytics. Nothing leaves your device but the request that reads your own usage.',
  features: {
    heading: 'What it *does*',
    sub: 'Everything the app shows comes straight from your provider’s own numbers.',
    listLabel: 'Features',
    items: [
      {
        id: 'limits',
        title: 'All your limits, one glance',
        body: 'Session, weekly and per-model windows for every account you connect, each with a bar, the exact percentage and a countdown to its reset.',
        points: ['Remaining or used, your pick', 'Relative or absolute reset times', 'Plan badge and spend caps, as reported'],
        imageAlt: 'Dashboard with two accounts and their limit bars.',
      },
      {
        id: 'widgets',
        title: 'Widgets that keep score',
        body: 'Small, medium and large Home Screen widgets, Lock Screen accessories and a single-number widget for the one limit you care about. On iOS they refresh themselves in the background.',
        points: ['One account or all of them', 'Lock Screen gauge for your glance metric', 'Manual refresh right on the widget'],
        imageAlt: 'Home Screen with the small, medium and large AIMeter widgets.',
      },
      {
        id: 'history',
        title: 'Every reset, charted',
        body: 'A history chart per account: the percent of each limit used over the last day, week or month, with every reset marked, drawn from samples kept on your device for 30 days.',
        points: ['24 hours, 7 days or 30 days', 'A sparkline per row on the dashboard', 'Spoken summary for VoiceOver'],
        imageAlt: 'History chart of weekly usage over 30 days with reset markers.',
      },
      {
        id: 'alerts',
        title: 'Alerts before the wall',
        body: 'Local notifications, per account: near a limit, projected to run out early, a limit reached, an early reset, and the one alert that is on by default, when a sign-in stops working.',
        points: ['Your own near-limit threshold', 'Reset reminders per window', 'Generated on-device, no push service'],
        imageAlt: 'Notification toggles for one account.',
      },
      {
        id: 'pace',
        title: 'Know your pace',
        body: 'Each window says whether you are on pace, ahead or behind a steady burn to the next reset, and a Forecast card projects which ones will run out early.',
        points: ['Learns your pace before asserting it', 'Average and recent-rate projections', 'Nothing guessed from missing data'],
        imageAlt: 'Account detail with pace captions and the Forecast card.',
      },
      {
        id: 'accounts',
        title: 'Every account, its own icon',
        body: 'Connect as many logins as you like. Each gets a name and an icon of your choosing, shown on the dashboard, in the menu bar, in every widget and in the Live Activity. Dark mode included.',
        points: ['Drag to reorder, everywhere at once', 'Rename or re-icon any time', 'Sign in again repairs an account in place'],
        imageAlt: 'Dashboard in dark mode with two accounts and custom icons.',
      },
    ],
  },
  widgets: {
    heading: 'Widgets, *everywhere* you look',
    sub: 'Three widget kinds, the Lock Screen and a Live Activity, all drawn from the same snapshot the app keeps.',
    kinds: [
      { title: 'Usage Limits', body: 'One account. Rows in the small size, side-by-side columns with a big figure in the medium.' },
      { title: 'Single Limit', body: 'One number: pick the account and the window from the widget’s own configuration.' },
      { title: 'All Accounts', body: 'Every connected account at once, in the large size.' },
    ],
    homeAlt: 'iPhone Home Screen with the three AIMeter widget kinds.',
    lockScreen: 'Lock Screen',
    liveActivity: 'Live Activity',
    liveActivityBody: 'Opt in per account to keep the session countdown on the Lock Screen and in the Dynamic Island while it runs. The countdown ticks on-device; the percentage updates whenever the app or a widget fetches next.',
    ipadAlt: 'AIMeter on iPad.',
  },
  mac: {
    heading: 'On the Mac, it lives in the *notch*',
    sub: 'A black island fused to the MacBook’s notch shows every window in one line: a peek of your figures when the cursor rests on it, every account when you stay or click, never taking focus. No notch? A floating pill under the menu bar. Prefer a status item? Six styles, fed by the app itself, so Notification Center widgets stay fresh with no icon on screen at all.',
    styles: ['Gauge with the number', 'Gauge only', 'Number only', 'Bar', 'Battery', 'Two or three windows side by side'],
    extras: [
      'Notch island: 5h 42% 2h 58m | 7d 61% 3d 3h beside the notch, every account with bars and resets when it opens',
      'Pick which side of the notch the wings use and which windows they list; turning it on hides the menu bar icon',
      'Optional reset countdown and account name',
      'Red once a window passes 80 %',
      'Hide the Dock icon, the menu bar icon, or both',
      'Open at login, opt-in and visibly toggleable',
      '⌘R refresh, ⌘N add account, and two Shortcuts actions you can bind to any key',
    ],
    note: 'The Mac app is not on the Mac App Store: it reads the login your command-line tools already keep, which the store’s sandbox does not allow.',
    build: 'Build it from source',
  },
  privacy: {
    heading: 'Private *by design*',
    sub: 'Small enough to read. Every claim here is verifiable in the code.',
    points: [
      { title: 'No server, no account', body: 'Usage is read directly from your provider and cached on your device so widgets can show it. AIMeter has nothing of its own in between.' },
      { title: 'Tokens stay in the Keychain', body: 'Your sign-in token is stored encrypted by the system and used for one thing: reading your usage. AIMeter asks for a read-only scope and never one that could run prompts.' },
      { title: 'No analytics, no tracking', body: 'No analytics SDKs, no ad networks, no crash reporting. This website is static and makes no third-party requests either.' },
      { title: 'Yours to delete', body: 'Disconnecting an account deletes its token, its cached snapshot and its history. Nothing lingers in the cloud, because nothing was ever there.' },
    ],
    cta: 'Read the privacy policy',
  },
  openSource: {
    heading: 'Open source, *free for good*',
    sub: 'MIT licensed. No tiers, no subscription, no locked features. What other trackers charge for is simply there.',
    points: [
      { title: 'Audit it yourself', body: 'The repo ships scripts that print the exact JSON the app reads from your own login. The token is never printed or written to disk.' },
      { title: 'Build the Mac app', body: 'Clone, set your Team ID in one gitignored file, build. A free developer account is enough for your own devices.' },
      { title: 'Pure SwiftUI', body: 'iOS 17+ and macOS 14+, no dependencies, one provider-agnostic Swift package. More providers can plug in as new sections.' },
    ],
    languagesLabel: 'Available in',
    languages: 'English, Spanish, German, French, Japanese, Korean, Brazilian Portuguese and Simplified Chinese',
    github: 'Star it on GitHub',
  },
  closing: {
    eyebrow: 'Free on the App Store for iPhone and iPad. Build it yourself for the Mac.',
    heading: 'Your limits, *on your terms*.',
    appStore: 'Download on the App Store',
    github: 'View the source',
    rights: 'MIT licensed.',
    trademark:
      'AIMeter is an independent open source project. It is not affiliated with, endorsed by, or sponsored by any AI provider; product names are trademarks of their respective owners.',
    madeBy: 'Made by',
    links: { privacy: 'Privacy', support: 'Support', source: 'Source' },
  },
  privacyPage: {
    title: 'Privacy policy',
    description: 'What AIMeter reads, what it stores on your device, and what never leaves it.',
    intro:
      'AIMeter has no server and no account of its own. It reads your usage from your AI provider with the login you grant it, keeps a copy on your device so widgets can render, and sends nothing anywhere else. This page lists every data flow so you can check each one against the source.',
    updated: 'Last updated: 7 October 2026',
    sections: [
      {
        heading: 'What leaves your device',
        paragraphs: ['Only HTTPS requests to the provider whose usage you asked AIMeter to read, and nothing to us, because there is no “us” to send it to.'],
        bullets: [
          'api.anthropic.com — /api/oauth/usage for your limits and spend numbers, and /api/oauth/profile to resolve your plan name (re-checked at most every 6 hours).',
          'claude.ai and console.anthropic.com — the standard OAuth sign-in exchange when you connect an account through the app. You sign in on the provider’s own page in your browser, never in an embedded web view, and paste back the code it shows.',
          'status.claude.com — one anonymous request to the public status page on each refresh, to tell a service incident apart from a problem with your account. It carries nothing about you and can be turned off in Settings.',
          'This website is static: no analytics, no cookies, fonts are self-hosted and no third-party request is made. It is served by GitHub Pages, whose ordinary server logs are GitHub’s.',
        ],
      },
      {
        heading: 'What is stored, and where',
        paragraphs: ['Everything below lives on the device, in storage only AIMeter and its widget can read.'],
        bullets: [
          'Sign-in tokens: in the system Keychain only, encrypted, available after first unlock. On iOS the widget shares them through the App Group’s keychain access group so it can refresh usage by itself. On the Mac, a first account can simply read the login your command-line tool already keeps, read-only, without ever modifying it.',
          'The last usage snapshot (percentages, reset dates, spend numbers) and your display preferences: in the App Group container, so widgets can render without fetching.',
          'Up to 30 days of usage percentages per window (the numbers, their dates and the reset dates), as a small file per account in the same container, for the history chart.',
          'Nothing is ever written anywhere else on the device, unencrypted, or outside the app’s own containers.',
        ],
      },
      {
        heading: 'What the connection can access',
        paragraphs: [
          'When you sign in through AIMeter it requests a single OAuth scope, user:profile, which is what the usage and profile endpoints need. It never requests the inference scope, so a token issued to AIMeter cannot send prompts or spend usage on your behalf, even in theory. The app only ever calls two read-only endpoints: your usage windows and your profile.',
        ],
      },
      {
        heading: 'Command-line usage logs (Mac, opt-in)',
        paragraphs: [
          'Off by default. If you turn on “Read Claude Code’s local usage logs” in Settings, AIMeter reads the session logs that tool keeps in ~/.claude/projects on that Mac to add up tokens per model and price them at public list rates. It decodes only the usage fields of each record, never prompts or replies, keeps a small index of counts in its own Application Support folder, deletes that index when you turn the option off, and sends nothing anywhere. The feature does not exist on iOS.',
        ],
      },
      {
        heading: 'Notifications',
        paragraphs: [
          'All alerts are generated locally on the device from the reset dates and percentages already in the snapshot. No push service is involved, and nothing is delivered unless you granted notification permission.',
        ],
      },
      {
        heading: 'Opening at login (Mac, opt-in)',
        paragraphs: [
          'AIMeter never adds itself to your login items. Turning on “Open at Login” in Settings registers it with macOS, which asks you to approve it; turning it off removes the registration. All it does when it starts is read your usage.',
        ],
      },
      {
        heading: 'Deleting your data',
        paragraphs: [
          'Disconnecting an account from its detail screen deletes its stored token, cached snapshot, history and notification preferences. Deleting the app removes its containers; disconnect first if you want to be sure no Keychain item remains. There is nothing to delete on any server.',
        ],
      },
      {
        heading: 'Children',
        paragraphs: ['AIMeter is not directed at children under 13 and, as described above, collects no personal data from anyone.'],
      },
      {
        heading: 'Changes',
        paragraphs: [
          'Changes to this policy are published on this page with a new date. The full history of this page, like the app, is in the public repository.',
        ],
      },
      {
        heading: 'Contact and trademarks',
        paragraphs: [
          'Questions go to the support page. AIMeter is an independent open source project (MIT). It is not affiliated with, endorsed by, or sponsored by Anthropic. “Claude” and “Anthropic” are trademarks of Anthropic, PBC, used only to identify the service whose usage the app displays.',
        ],
      },
    ],
  },
  supportPage: {
    title: 'Support',
    description: 'How to connect an account, what the alerts mean, and where to ask for help.',
    intro: 'AIMeter is built and maintained by one person, in the open. Most answers are below; anything else is a GitHub issue or an email away.',
    updated: 'For AIMeter 2.0',
    sections: [
      {
        heading: 'Connecting on iPhone and iPad',
        paragraphs: [
          'Tap Connect. AIMeter opens your provider’s sign-in page in your browser (any sign-in method works), you approve, copy the code it shows and paste it back. Optionally give the account a nickname; you can rename it later from the card’s menu. The token is stored in the Keychain and the app keeps it refreshed on its own.',
        ],
      },
      {
        heading: 'Connecting on the Mac',
        paragraphs: [
          'Zero setup for your first account if Claude Code is installed and logged in: AIMeter reads the login it already keeps, read-only, and never modifies it. Any further account, or a Mac without the CLI, signs in the same way as on iPhone. Add account on the dashboard repeats the flow per login.',
        ],
      },
    ],
    faqHeading: 'Frequently asked',
    faqs: [
      {
        q: 'The card says “Sign in again”. What happened?',
        a: 'The provider rotates the refresh token on every use, so a login shared with another client (the CLI on another machine, a second Mac) can stop working for AIMeter. Tap Sign in again on the card: it repairs the account in place, so its history, alerts and already-placed widgets keep working. Do not disconnect and re-add; that creates a new account and orphans all of it.',
      },
      {
        q: 'My widget shows “updated 2 h ago”.',
        a: 'On iOS, widgets refresh themselves in the background within the budget the system gives them, and the app refreshes them every time it comes to the foreground. On the Mac, widgets only show what the menu bar app last wrote, so keep the app running (it can run with no icons at all) and they stay fresh.',
      },
      {
        q: 'Where is the Mac version?',
        a: 'Not on the Mac App Store: the Mac app reads the login your command-line tool keeps, which the store’s sandbox forbids. Build it from the source in a few minutes; a free developer account is enough for your own machines. The README walks through it.',
      },
      {
        q: 'What does the third row show?',
        a: 'The real per-model window when your plan reports one. When it does not, the row can be hidden, or show your usage credits instead, from the account’s detail screen (“Third usage row”). Auto picks for you.',
      },
      {
        q: 'Does the app see my conversations?',
        a: 'No. It calls two read-only endpoints, your usage windows and your profile, with a token that cannot run prompts. The optional Mac feature that reads the CLI’s local logs decodes only token counts, never content.',
      },
      {
        q: 'How do I delete my data?',
        a: 'Disconnect the account from its detail screen. That deletes its token, snapshot, history and preferences from the device. There is no server-side copy.',
      },
      {
        q: 'Which languages does it speak?',
        a: 'English, Spanish, German, French, Japanese, Korean, Brazilian Portuguese and Simplified Chinese, following the device language.',
      },
      {
        q: 'Is AIMeter affiliated with the provider?',
        a: 'No. It is an independent open source project, and it reads an undocumented endpoint that may change at any time. The app says so in its own Privacy screen.',
      },
    ],
    contactHeading: 'Still stuck?',
    contact: 'Open an issue with what you expected and what you saw, or write an email. Both reach the same person.',
    email: 'Email support',
    issues: 'Open a GitHub issue',
  },
  notFound: { title: 'Nothing here', body: 'That page does not exist, or moved.', cta: 'Back to the start' },
  backHome: 'Back to AIMeter',
} satisfies Dictionary

import AppIntents

/// How the all-accounts widget lays its accounts out: the standard full
/// rows (two accounts, every reset line), or condensed, one line per
/// account with its bars side by side (six, `CondensedAccountsView`).
enum AllAccountsLayout: String, AppEnum {
    case standard
    case condensed

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static var caseDisplayRepresentations: [AllAccountsLayout: DisplayRepresentation] = [
        .standard: "Standard",
        .condensed: "Condensed",
    ]
}

/// The all-accounts widget's one Edit Widget choice. No account to pick:
/// it always shows every connected account.
struct AllAccountsConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "All Accounts"
    static var description = IntentDescription("Choose how the accounts are laid out.")

    @Parameter(title: "Layout", default: .standard)
    var layout: AllAccountsLayout
}

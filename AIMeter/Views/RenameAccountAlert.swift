import SwiftUI

/// The one rename UI, shared by the Dashboard header's context menu and
/// Provider Detail's Name row so both ask the same way. An alert rather
/// than a sheet: a single field and two buttons, and both callers are
/// already inside a screen the alert can sit on top of. `name` is the
/// caller's draft — seeded with the current nickname as it presents, so
/// the field opens editable rather than blank. Talks to `UsageModel`
/// itself (validation and the save) rather than through closures, so a
/// caller only says which account.
extension View {
    func renameAccountAlert(
        for accountID: String, isPresented: Binding<Bool>, name: Binding<String>
    ) -> some View {
        modifier(RenameAccountAlert(accountID: accountID, isPresented: isPresented, name: name))
    }
}

private struct RenameAccountAlert: ViewModifier {
    let accountID: String
    @Binding var isPresented: Bool
    @Binding var name: String
    @Environment(UsageModel.self) private var model

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another account already goes by this name — the one rule a nickname
    /// has to satisfy, since it's all that tells accounts apart in widget
    /// pickers and notification titles.
    private var isTaken: Bool {
        model.isNameTaken(trimmed, excluding: accountID)
    }

    func body(content: Content) -> some View {
        content.alert("Rename account", isPresented: $isPresented) {
            TextField("Name", text: $name)
            Button("Save") {
                if !model.rename(accountID, to: trimmed) {
                    // Alert buttons re-evaluate `.disabled` as the field
                    // changes on some OS versions and not on others, so a
                    // rejected name can still reach here. The alert has
                    // already dismissed by the time the action runs; bring
                    // it back with the message line saying what's wrong
                    // rather than drop the edit silently.
                    Task { @MainActor in isPresented = true }
                }
            }
            .disabled(trimmed.isEmpty || isTaken)
            Button("Cancel", role: .cancel) {}
        } message: {
            if trimmed.isEmpty {
                Text("A name can't be empty.")
            } else if isTaken {
                Text("Another account is already called that.")
            } else {
                Text("Shown on the dashboard, in widgets, and in notification titles.")
            }
        }
    }
}

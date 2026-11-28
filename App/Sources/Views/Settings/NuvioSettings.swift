import SwiftUI
import PlayerCore

/// plan_nuvio_konto T8: the „Nuvio-Konto“ row under „Konten“. Value and detail follow `AppModel.nuvioStatus`; OK opens
/// the options page (sign-in, sync now, profile, sign-out, status line). Texts: `NuvioTexts` (plan section 4).
struct NuvioAccountRow: View {
    @Environment(AppModel.self) var model
    let tint: Color

    var body: some View {
        let status = model.nuvioStatus
        SettingsLinkRow(symbol: "person.crop.circle.badge.checkmark", tint: tint, title: NuvioTexts.rowTitle,
                        detail: NuvioTexts.detail(status, localProfile: model.profile.name),
                        value: NuvioTexts.value(status)) {
            NuvioSettingsPage(tint: tint)
        }
    }
}

/// Options of the Nuvio account.
struct NuvioSettingsPage: View {
    @Environment(AppModel.self) var model
    let tint: Color
    @State private var page: NuvioSettingsRoute?
    @State private var confirmSignOut = false
    /// The sign-in request already handled (a new one after a sign-in opens the profile picker).
    @State private var seenRequest: Int?

    private enum NuvioSettingsRoute: Hashable, Identifiable {
        case signIn
        case profiles
        var id: Self { self }
    }

    private static func hasProfile(_ s: NuvioStatus) -> Bool {
        if case .connected = s { return true }
        return false
    }

    var body: some View {
        let status = model.nuvioStatus
        let local = model.profile.name
        SettingsSubpage(title: NuvioTexts.rowTitle, summary: NuvioTexts.detail(status, localProfile: local)) {
            SettingsSection {
                SettingsInfoRow(symbol: "info.circle", tint: tint, title: NuvioTexts.value(status),
                                detail: model.nuvioStatusLine, detailAlwaysVisible: true)
                if status.isSignedIn {
                    SettingsRow(symbol: "arrow.triangle.2.circlepath", tint: tint, title: NuvioTexts.syncNow,
                                accessory: .none, reserveDetailSpace: false) {
                        RemoteLog.info("einstellung", "nuvio: jetzt abgleichen")
                        Task { await model.syncNuvio(.full, reason: "manuell", manual: true) }
                    }
                    SettingsRow(symbol: "person.2", tint: tint,
                                title: Self.hasProfile(status) ? NuvioTexts.changeProfile : NuvioTexts.chooseProfile,
                                accessory: .chevron, reserveDetailSpace: false) {
                        page = .profiles
                    }
                    if Self.hasProfile(status) { NuvioImportRow() }
                    SettingsRow(symbol: "rectangle.portrait.and.arrow.right", tint: tint, title: NuvioTexts.signOutVerb,
                                detail: NuvioTexts.signOutHint, accessory: .none, detailAlwaysVisible: true,
                                reserveDetailSpace: false) {
                        confirmSignOut = true
                    }
                } else {
                    SettingsRow(symbol: "qrcode", tint: tint, title: NuvioTexts.signIn,
                                detail: NuvioTexts.detail(status == .busy ? .busy : .signedOut, localProfile: local),
                                accessory: .chevron, reserveDetailSpace: false) {
                        page = .signIn
                    }
                    .settingsUnavailable(status == .busy)
                }
            }
        }
        .navigationDestination(item: $page) { p in
            switch p {
            case .signIn: PhoneInputView(section: .nuvio)
            case .profiles: NuvioProfilePicker(tint: tint)
            }
        }
        .settingsConfirmation(NuvioTexts.signOutTitle, isPresented: $confirmSignOut, message: NuvioTexts.signOutMessage,
                              verb: NuvioTexts.signOutVerb, symbol: "rectangle.portrait.and.arrow.right") {
            Task { await model.nuvioSignOut() }
        }
        .onAppear { if seenRequest == nil { seenRequest = NuvioHolder.shared.profileRequest } }
        // After a sign-in on the phone page without a chosen profile: straight on to the picker.
        .onChange(of: NuvioHolder.shared.profileRequest) { _, n in
            guard n != seenRequest else { return }
            seenRequest = n
            page = .profiles
        }
    }
}

/// „Nuvio-Profil wählen“: the account's profiles; a PIN profile is listed but cannot be chosen (D3).
struct NuvioProfilePicker: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss
    let tint: Color
    @State private var profiles: [NuvioProfile]?
    @State private var failed = false
    @FocusState private var focus: Int?

    /// An account without profile rows syncs its index 1 (plan section 7.10).
    private var shown: [NuvioProfile] {
        guard let profiles else { return [] }
        return profiles.isEmpty ? [NuvioProfile(profileIndex: 1, name: "")] : profiles
    }

    private static func title(_ p: NuvioProfile) -> String { p.name.isEmpty ? "Profil \(p.profileIndex)" : p.name }

    var body: some View {
        let chosen = model.nuvioState(for: model.profile.id).profileIndex
        SettingsSubpage(title: NuvioTexts.chooseProfile, summary: NuvioTexts.pickerText(localProfile: model.profile.name)) {
            if profiles == nil {
                SettingsInfoRow(symbol: failed ? "exclamationmark.triangle" : "hourglass", tint: tint,
                                title: failed ? "Profile nicht geladen" : "Profile werden geladen …",
                                detail: failed ? model.lastError : nil, detailAlwaysVisible: failed)
            }
            ForEach(shown, id: \.profileIndex) { p in
                let on = p.profileIndex == chosen
                let detail: String? = p.pinEnabled ? NuvioTexts.pinDetail : nil
                Button {
                    guard !p.pinEnabled else { return }
                    model.chooseNuvioProfile(p)
                    dismiss()
                } label: {
                    SettingsRowLabel(symbol: on ? "checkmark" : (p.pinEnabled ? "lock" : "person"), tint: tint,
                                     title: Self.title(p), detail: detail, accessory: .value(on ? "Gewählt" : ""),
                                     detailAlwaysVisible: p.pinEnabled, reserveDetailSpace: false)
                }
                .buttonStyle(ThemeRowButtonStyle())
                .focused($focus, equals: p.profileIndex)
                .settingsUnavailable(p.pinEnabled)
                .settingsRowAccessibility(title: Self.title(p), detail: detail, accessory: .none)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .defaultFocus($focus, chosen)
        .task {
            let list = await model.nuvioProfiles()
            profiles = list
            failed = list == nil
        }
    }
}

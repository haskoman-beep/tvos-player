import Foundation

/// Task 4.3 (04-system-design §8.4): reads a configurator export (`docs/design/konfigurator/export.json`, schema
/// `player.appearance.preset`) that arrives through the phone page.
///
/// The file's `preset` is not taken over: the app knows only "Mein Look" (`.appleTV`). `values` are turned into
/// overrides against it, so an export from any configurator preset can be imported (the app then shows
/// "Mein Look · angepasst"). `version` is a hint, not a lock: a higher version is read like a known one. Unknown keys
/// are ignored; an unknown value or a wrong type leaves the preset value in place and is noted in the report
/// (path such as `values.global.accent`). Parsing never throws because of one value.
public enum LookImport {
    public static let schema = "player.appearance.preset"

    public enum Failure: Error, Equatable, Sendable {
        /// Not JSON, not an object, no `schema` text or no `values` object.
        case notAnExport
        /// A JSON object with another `schema`.
        case foreignSchema(String)

        /// Short code for the phone page's answer (`lk=` in the redirect).
        public var code: String {
            switch self {
            case .notAnExport: "kaputt"
            case .foreignSchema: "fremd"
            }
        }

        public var text: String {
            switch self {
            case .notAnExport: "Keine Aussehen-Datei aus dem Konfigurator."
            case .foreignSchema(let s): "Fremdes Format „\(s)“: keine Aussehen-Datei aus dem Konfigurator."
            }
        }
    }

    /// Whether `data` is a JSON object whose `schema` is the configurator's (the phone's quick import routes it here).
    public static func claims(_ data: Data) -> Bool {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return top["schema"] as? String == schema
    }

    public static func parse(_ data: Data) throws -> (look: Look, report: DecodeReport) {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let found = top["schema"] as? String else { throw Failure.notAnExport }
        guard found == schema else { throw Failure.foreignSchema(found) }
        guard top["values"] is [String: Any] else { throw Failure.notAnExport }
        let (file, report) = try JSONDecoder().decodeReporting(ExportFile.self, from: data)
        let base = LookPreset.values(.appleTV)
        let values = file.values.applied(to: base)
        let look = Look(preset: .appleTV, overrides: LookOverrides.difference(values, from: base))
        return (look, report)
    }

    /// The part of the export the app reads. `values` has the shape of `LookOverrides` (all options set), whose
    /// decoder is lenient per value.
    private struct ExportFile: Decodable {
        var values: LookOverrides
    }
}

extension Look {
    /// Task 4.3 (controller ruling): an imported look also writes the old fields it maps to
    /// (`LookMigration.oldValues`), so the views that still read `appearance` and `player` show the effect. An old
    /// accent that already stands for the look's accent is kept (koralle keeps pink). Fields the look does not cover
    /// stay untouched.
    public func writeOldFields(appearance: inout Appearance, player: inout PlayerComfortSettings) {
        let old = LookMigration.oldValues(for: resolved())
        appearance.navigation = old.navigation
        if !old.accents.contains(appearance.accent), let first = old.accents.first { appearance.accent = first }
        appearance.cardSize = old.cardSize
        appearance.heroEnabled = old.heroEnabled
        appearance.expandPosters = old.expandPosters
        appearance.badges.style = old.badgeStyle
        player.trackPanelStyle = old.trackPanelStyle
    }
}

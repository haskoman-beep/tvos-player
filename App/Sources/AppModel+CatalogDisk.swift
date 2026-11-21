import Foundation
import PlayerCore

/// Welle C-b (#22): Startseite aus dem Plattencache. Beim Start (und nach einem Profilwechsel) wird der
/// gespeicherte Katalog-Stand des Profils abseits des Hauptthreads gelesen; die ersten Reihen warten darauf
/// (`awaitCatalogSnapshot`) und zeigen ihn sofort. Übernommene Reihen gelten als erneuerungsbedürftig
/// (`TimedCache.restore`), die Erneuerung läuft im Hintergrund wie beim 24-h-Ablauf (AppModel+CatalogCache).
/// Geschrieben wird gebündelt 3 s nach der letzten Änderung, ebenfalls abseits des Hauptthreads.
/// Die Datei liegt unter Caches/Player/Kataloge: löscht tvOS sie, startet die Startseite wie früher leer.
@MainActor
final class CatalogDiskStore {
    static let saveDelay: Duration = .seconds(3)

    let files: FileBlobStorage
    /// Laufendes Lesen; solange gesetzt, wird nichts geschrieben (sonst überschriebe ein halber Stand den alten).
    var pending: Task<CatalogSnapshot?, Never>?
    var pendingGeneration = 0
    var pendingProfile: UUID?
    var saveTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Player", isDirectory: true).appendingPathComponent("Kataloge", isDirectory: true)
        files = FileBlobStorage(directory: dir)
    }
}

extension AppModel {
    /// Lesen anstoßen (Start, Profilwechsel). Ein noch nicht übernommener alter Lesevorgang wird verworfen.
    func restoreCatalogSnapshot() {
        let disk = catalogDisk
        let profileID = profile.id
        let name = CatalogSnapshot.fileName(profile: profileID)
        let files = disk.files
        disk.saveTask?.cancel()
        disk.saveTask = nil
        disk.pendingGeneration = cache.generation
        disk.pendingProfile = profileID
        disk.pending = Task.detached(priority: .userInitiated) {
            guard let data = files.read(name) else { return nil }
            guard let snap = CatalogSnapshot.decode(data) else {
                files.remove(name)   // unlesbar oder alte Version: weg damit, beim nächsten Schreiben neu
                return nil
            }
            return snap
        }
    }

    /// Erste Reihen warten hier auf das Lesen; nur die erste übernimmt den Stand.
    func awaitCatalogSnapshot() async {
        guard let task = catalogDisk.pending else { return }
        let t0 = Date()
        let snap = await task.value
        guard catalogDisk.pending == task else { return }   // schon übernommen oder durch neueres Lesen ersetzt
        catalogDisk.pending = nil
        guard catalogDisk.pendingProfile == profile.id, let snap else {
            RemoteLog.info("katalog", "Plattencache: kein Stand")
            return
        }
        let n = snap.restore(into: &cache, generation: catalogDisk.pendingGeneration)
        let age = snap.oldestAge().map { " · ältester \(Int($0 / 60)) min" } ?? ""
        RemoteLog.info("katalog", "Plattencache: \(n) Reihen sofort gezeigt (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)\(age), Erneuerung im Hintergrund")
    }

    /// Nach jeder Ablage: gebündelt schreiben. Leerer Cache (frisch geleert) schreibt nichts.
    func scheduleCatalogSave() {
        let disk = catalogDisk
        guard disk.pending == nil else { return }
        disk.saveTask?.cancel()
        disk.saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: CatalogDiskStore.saveDelay)
            guard !Task.isCancelled, let self, self.catalogDisk.pending == nil else { return }
            let entries = self.cache.entries
            let name = CatalogSnapshot.fileName(profile: self.profile.id)
            let files = disk.files
            disk.saveTask = nil
            guard !entries.isEmpty else { return }
            let bytes = await Task.detached(priority: .utility) { () -> Int? in
                guard let data = CatalogSnapshot.encode(entries: entries) else { return nil }
                do { try files.write(name, data); return data.count } catch { return -1 }
            }.value
            switch bytes {
            case nil: RemoteLog.info("katalog", "Plattencache: nichts zu schreiben")
            case -1?: RemoteLog.error("katalog", "Plattencache: Schreiben fehlgeschlagen")
            case let b?: RemoteLog.info("katalog", "Plattencache geschrieben: \(entries.count) Reihen, \(b / 1024) KB")
            }
        }
    }
}

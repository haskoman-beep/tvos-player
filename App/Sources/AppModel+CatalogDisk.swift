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

    /// Katalog-Cache verwerfen (Addon, Anmeldung, Schlüssel oder Sicherung geändert): Speicher leeren,
    /// laufendes Lesen und geplantes Schreiben verwerfen und die Profildatei löschen. Sonst käme der alte
    /// Stand beim nächsten Start zurück (eine schon geladene Reihe fragt nicht neu an, schreibt also nichts).
    func clearCatalogCache() {
        cache.removeAll()
        catalogDisk.saveTask?.cancel()
        catalogDisk.saveTask = nil
        catalogDisk.pending = nil
        catalogDisk.files.remove(CatalogSnapshot.fileName(profile: profile.id))
        RemoteLog.info("katalog", "Plattencache verworfen")
    }

    /// Datei eines Profils löschen (Profil gelöscht).
    func removeCatalogFile(profile id: UUID) {
        catalogDisk.files.remove(CatalogSnapshot.fileName(profile: id))
    }

    /// Nach jeder Ablage: gebündelt schreiben. Profil und Cache-Stand werden beim Planen festgehalten;
    /// hat sich bis zum Schreiben eines davon geändert (Profilwechsel, Leeren), wird verworfen.
    /// Passt nichts in die Größengrenze, wird die alte Datei gelöscht statt stehen gelassen.
    func scheduleCatalogSave() {
        let disk = catalogDisk
        guard disk.pending == nil else { return }
        let profileID = profile.id
        let generation = cache.generation
        disk.saveTask?.cancel()
        disk.saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: CatalogDiskStore.saveDelay)
            guard !Task.isCancelled, let self, self.catalogDisk.pending == nil else { return }
            guard self.profile.id == profileID, self.cache.generation == generation else { return }
            let entries = self.cache.entries
            let name = CatalogSnapshot.fileName(profile: profileID)
            let files = disk.files
            disk.saveTask = nil
            guard !entries.isEmpty else { return }
            let data = await Task.detached(priority: .utility) { CatalogSnapshot.encode(entries: entries) }.value
            // Während des Kodierens gewechselt oder geleert: nicht mehr schreiben.
            guard self.profile.id == profileID, self.cache.generation == generation, self.catalogDisk.pending == nil else { return }
            guard let data else {
                files.remove(name)
                RemoteLog.info("katalog", "Plattencache: nichts Passendes zu schreiben, alte Datei entfernt")
                return
            }
            let ok = await Task.detached(priority: .utility) { () -> Bool in
                do { try files.write(name, data); return true } catch { return false }
            }.value
            if ok {
                RemoteLog.info("katalog", "Plattencache geschrieben: \(entries.count) Reihen, \(data.count / 1024) KB")
            } else {
                RemoteLog.error("katalog", "Plattencache: Schreiben fehlgeschlagen")
            }
        }
    }
}

import Testing
import Foundation
@testable import PlayerCore

// Build 7 (folder): folder row page – duplicate requests once, shared titles get the media type, page phase and text,
// focus prefetch choice, per-source log line.

private func addon(_ id: String, _ title: String, _ type: String, catalog: String = "streaming.a") -> CatalogSource {
    CatalogSource(id: id, title: title, kind: .addon(addonId: "x", catalogId: catalog, type: type),
                  mediaType: type == "movie" ? .movie : type == "series" ? .series : .both)
}

@Test func folderRowsNameSharedTitlesByType() {
    // Kit folder: films and series catalog, both named after the tile.
    let rows = FolderPage.rows([addon("f.0", "Shudder", "movie"), addon("f.1", "Shudder", "series")])
    #expect(rows.map(\.title) == ["Shudder · Filme", "Shudder · Serien"])
    #expect(rows.map(\.id) == ["f.0", "f.1"])   // ids (cache keys) unchanged
    // Different titles stay as they are; a single source too.
    #expect(FolderPage.rows([addon("a", "A", "movie"), addon("b", "B", "series")]).map(\.title) == ["A", "B"])
    #expect(FolderPage.rows([addon("a", "Studio", "movie")]).map(\.title) == ["Studio"])
    // Already suffixed (TMDB discover titles) or mixed type: no second suffix.
    let both = FolderPage.rows([addon("a", "X", "anime"), addon("b", "X", "all")])
    #expect(both.map(\.title) == ["X", "X"])
    let pre = CatalogSource(id: "p", title: "Netflix · Filme", kind: .tmdbDiscover(filters: ["a": "1"]), mediaType: .movie)
    let pre2 = CatalogSource(id: "q", title: "Netflix · Filme", kind: .tmdbDiscover(filters: ["a": "2"]), mediaType: .movie)
    #expect(FolderPage.rows([pre, pre2]).map(\.title) == ["Netflix · Filme", "Netflix · Filme"])
}

@Test func folderRowsDropSameRequest() {
    // Same catalog, same type listed twice (other id / title): one row, the first.
    let rows = FolderPage.rows([addon("f.0", "Shudder", "movie"), addon("f.1", "Shudder Filme", "movie"),
                                addon("f.2", "Shudder", "series")])
    #expect(rows.map(\.id) == ["f.0", "f.2"])
    #expect(rows.map(\.title) == ["Shudder · Filme", "Shudder · Serien"])
    // Same kind but other limit or sort: different requests, both kept.
    var limited = addon("f.3", "Shudder", "movie"); limited.limit = 10
    #expect(FolderPage.rows([addon("f.0", "Shudder", "movie"), limited]).count == 2)
}

@Test func folderPrefetchSkipsCachedAndLocal() {
    let s = [addon("a", "A", "movie", catalog: "a"), addon("b", "B", "series", catalog: "b"), .watchlist,
             addon("c", "C", "movie", catalog: "c"), addon("d", "D", "movie", catalog: "d"),
             addon("e", "E", "movie", catalog: "e"), addon("f", "F", "movie", catalog: "f")]
    let picked = FolderPage.prefetchSources(s, isCached: { $0 == "b" })
    #expect(picked.map(\.id) == ["a", "c", "d", "e"])   // b cached, watchlist local, at most 4
    #expect(FolderPage.prefetchSources(s, isCached: { _ in true }).isEmpty)
    #expect(FolderPage.prefetchSources(s, isCached: { _ in false }, limit: 2).map(\.id) == ["a", "b"])
}

@Test func folderPagePhase() {
    #expect(FolderPagePhase.of([]) == .noSources)
    #expect(FolderPagePhase.of([.loading, .loading]) == .loading)
    // One row with titles: content at once, even while the other still loads or failed.
    #expect(FolderPagePhase.of([.loading, .loaded(count: 3, ms: 10, cached: false)]) == .content)
    #expect(FolderPagePhase.of([.failed(ms: 5), .loaded(count: 1, ms: 10, cached: true)]) == .content)
    // An empty row does not end the wait while another loads.
    #expect(FolderPagePhase.of([.loaded(count: 0, ms: 10, cached: false), .loading]) == .loading)
    #expect(FolderPagePhase.of([.loaded(count: 0, ms: 10, cached: false), .loaded(count: 0, ms: 9, cached: false)]) == .empty)
    #expect(FolderPagePhase.of([.loaded(count: 0, ms: 10, cached: false), .failed(ms: 3)]) == .empty)
    #expect(FolderPagePhase.of([.failed(ms: 1), .failed(ms: 2)]) == .failed)
    #expect(FolderPagePhase.of([.failed(ms: 1), .noAddon]) == .failed)
    #expect(FolderPagePhase.of([.noAddon, .noAddon]) == .noAddon)
    #expect(FolderPagePhase.loading.text == "Titel werden geladen …")
    #expect(FolderPagePhase.content.text == nil)
    for p in [FolderPagePhase.empty, .failed, .noAddon, .noSources] { #expect(p.text != nil && p.isFinished) }
    #expect(!FolderPagePhase.loading.isFinished)
}

@Test func folderLoadLogLine() {
    let line = FolderLoadLog.line(folder: "Shudder", rows: [
        ("Shudder · Filme", .loaded(count: 36, ms: 7760, cached: false)),
        ("Shudder · Serien", .loaded(count: 50, ms: 0, cached: true)),
        ("X", .failed(ms: 15000)), ("Y", .noAddon)], totalMs: 15000, prefetched: 1)
    #expect(line == "Ordner Shudder: 4 Quellen in 15000 ms · 1 beim Fokus vorgeladen · Shudder · Filme 36 (7760 ms) · Shudder · Serien 50 (Cache) · X Fehler (15000 ms) · Y ohne Addon")
    #expect(FolderLoadLog.line(folder: "A24", rows: [("A24", .loaded(count: 50, ms: 379, cached: false))], totalMs: 379)
            == "Ordner A24: 1 Quelle in 379 ms · A24 50 (379 ms)")
}

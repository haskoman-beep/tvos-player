import Foundation

/// Build 5 (b5f): Omni/UME snapshot (`{"values":{…}}`, e.g. the UME template of the Fusion Widget Manager) → widget
/// export, converted the way the manager does it (`convertOmniToFusion`), then read like any widget export.
/// Groups become tile rows (one tile per subgroup, its catalogs as sources), the ordered/selected catalogs become
/// list rows. All catalogs are AIOMetadata catalogs (`YOUR_AIOMETADATA`, see `AddonCatalogResolver`).
/// IDs are derived from group ids, subgroup names and catalog ids, so a new import of the same snapshot keeps them.
enum OmniImport {
    /// True for a snapshot object (has a `values` object and no `widgets`).
    static func claims(_ obj: [String: Any]) -> Bool { obj["values"] is [String: Any] && obj["widgets"] == nil }

    /// Widget export (`fusionWidgets`) as a JSON object.
    static func widgets(_ snapshot: [String: Any]) -> [String: Any] {
        let values = resolve(snapshot["values"], depth: 0) as? [String: Any] ?? [:]
        var widgets: [[String: Any]] = []

        // 1. Groups → tile rows.
        let groups = values["main_catalog_groups"] as? [String: Any] ?? [:]
        var order: [String] = []
        for id in strings(values["main_group_order"]) + groups.keys.sorted() where !order.contains(id) && !id.isEmpty { order.append(id) }
        let subgroups = values["catalog_groups"] as? [String: Any] ?? [:]
        let subgroupOrder = values["subgroup_order"] as? [String: Any] ?? [:]
        let images = values["catalog_group_image_urls"] as? [String: Any] ?? [:]
        for gid in order {
            guard let g = groups[gid] as? [String: Any] else { continue }
            let name = g["name"] as? String ?? "Untitled Group"
            if name.contains("❗️") { continue }   // structural placeholder labels
            let base = !strings(g["subgroupNames"]).isEmpty ? strings(g["subgroupNames"])
                : !strings(g["catalog_group_order"]).isEmpty ? strings(g["catalog_group_order"]) : strings(g["subgroup_order"])
            let authoritative = strings(subgroupOrder[gid])
            let names = authoritative.filter(base.contains) + base.filter { !authoritative.contains($0) }
            let poster = ((g["posterType"] ?? g["poster_type"]) as? String ?? "poster").lowercased()
            let aspect = poster.contains("landscape") ? "wide" : poster.contains("square") ? "square" : "poster"
            var items: [[String: Any]] = []
            var seen = Set<String>()
            for sub in names where !sub.contains("❗️") && seen.insert(sub).inserted {
                let raw = subgroups[sub]
                let ids = (raw as? [Any]).map(strings) ?? strings((raw as? [String: Any])?["catalogs"])
                guard !ids.isEmpty else { continue }
                var item: [String: Any] = ["id": NuvioImport.stableHash(sub), "title": sub, "imageAspect": aspect,
                                           "dataSources": ids.map(source)]
                if let img = images[sub] as? String, !img.isEmpty { item["imageURL"] = img }
                items.append(item)
            }
            guard !items.isEmpty else { continue }
            widgets.append(["id": "omni.group." + gid, "title": name, "type": "collection.row",
                            "dataSource": ["kind": "collection", "payload": ["items": items]]])
        }

        // 2. Ordered and selected catalogs → list rows.
        let hidden = Set(strings(values["disabled_shelves"]))
        let names = values["custom_catalog_names"] as? [String: Any] ?? [:]
        var rows: [String] = []
        for id in strings(values["catalog_ordering"]) + strings(values["selected_catalogs"]) + strings(values["top_row_catalogs"])
            + strings(values["small_toprow_catalogs"]) where !rows.contains(id) { rows.append(id) }
        for id in rows where !id.isEmpty && !hidden.contains(id) && !isInternal(id) {
            let custom = names[id] as? String ?? ""
            let low = custom.lowercased()
            if low.contains("header") || (low.contains("top") && low.contains("week")) { continue }
            let full = normalizedID(id)
            let upNext = id.contains("mdblist.upnext")
            let title = upNext ? "MDBList Up Next Series" : (custom.isEmpty ? (full.components(separatedBy: "::").last ?? id) : custom)
            widgets.append(["id": "omni.catalog." + NuvioImport.stableHash(id), "title": title, "type": "row.classic", "limit": 20,
                            "presentation": ["aspectRatio": "poster"], "dataSource": source(id)])
        }
        return ["exportType": "fusionWidgets", "exportVersion": 1, "widgets": widgets]
    }

    /// `addonCatalog` source of an Omni catalog id (`type:source.id` or a bare id).
    static func source(_ omniID: String) -> [String: Any] {
        let id = normalizedID(omniID)
        return ["kind": "addonCatalog", "payload": ["addonId": AddonCatalogResolver.placeholder, "catalogId": id, "type": catalogType(id)]]
    }

    /// `type:rest` → `type::rest` (type in lower case); ids with `::` or without `:` stay.
    static func normalizedID(_ s: String) -> String {
        guard !s.contains("::"), let colon = s.firstIndex(of: ":") else { return s }
        return s[..<colon].lowercased() + "::" + s[s.index(after: colon)...]
    }

    /// Type of a normalized id, as the manager guesses it (prefix, then known ids and keywords; `all::` kept).
    static func catalogType(_ id: String) -> String {
        let low = id.lowercased()
        if low.hasPrefix("all::trakt.list.") || (low.hasPrefix("all::mdblist.") && low.contains(".unified")) { return "series" }
        if low.hasPrefix("all::") { return "all" }
        if low.contains("mdblist.upnext") { return "series" }
        if low.hasPrefix("series::") || low.hasPrefix("shows::") || low.hasPrefix("anime::") { return "series" }
        if low.hasPrefix("movie::") || low.hasPrefix("movies::") { return "movie" }
        // Whole words as in the manager's `\b` regex (`_` counts as a word character there).
        let words = Set(low.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted))
        if !words.isDisjoint(with: ["show", "shows", "series"]) { return "series" }
        return "movie"
    }

    /// Omni's own helper catalogs (AI search) that sit in the ordering fields.
    static func isInternal(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespaces).lowercased()
        let key = t.firstIndex(of: ":").map { String(t[t.index(after: $0)...]) } ?? t
        if key.hasPrefix("omni.ai.search.") || key == "aisearch.top" { return true }
        let parts = key.split(separator: ".")
        return parts.count == 4 && parts[0] == "aisearch" && parts[1] == "home" && Int(parts[2]) != nil
            && ["movie", "series", "anime"].contains(String(parts[3]))
    }

    static func strings(_ v: Any?) -> [String] { (v as? [Any])?.compactMap { $0 as? String } ?? [] }

    /// Decodes `{"_data":"<base64 JSON>"}` wrappers anywhere in the tree (nested at most 32 deep).
    static func resolve(_ v: Any?, depth: Int) -> Any? {
        guard depth < 32 else { return nil }
        if let d = v as? [String: Any] {
            if let s = d["_data"] as? String {
                guard let raw = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
                      let j = try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed]) else { return nil }
                return resolve(j, depth: depth + 1)
            }
            var out: [String: Any] = [:]
            for (k, x) in d { if let r = resolve(x, depth: depth + 1) { out[k] = r } }
            return out
        }
        if let a = v as? [Any] { return a.compactMap { resolve($0, depth: depth + 1) } }
        return v
    }
}

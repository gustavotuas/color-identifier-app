//
//  CatalogDataLayer.swift
//  Colorit
//
//  Data layer: loader & registry for NamedColor catalogs.
//
//  Coloca tus JSON en:
//  - Resources/NamedColors.json
//  - catalogs/catalog_sherwin_williams.json     (o en Resources/catalogs/... si usas folder reference)
//  - (agrega más vendors repitiendo el patrón)
//

import Foundation
import Combine

// MARK: - Models

public struct NamedColor: Codable, Identifiable, Hashable {
    public var id: String { vendor?.code ?? "\(name)|\(hex.lowercased())" }

    public let name: String
    public let hex: String
    public let vendor: VendorInfo?
    public let rgb: [Int]?

    public struct VendorInfo: Codable, Hashable {
        public let brand: String?
        public let line: String?
        public let code: String?
        public let locator: String?
        public let domain: String?   // e.g. "paint_architectural", "print", etc.
        public let source: String?
    }
}

// MARK: - Catalog identifiers & locations

public enum CatalogID: String, CaseIterable, Hashable {
    case generic
    case sherwinWilliams
    case behr
    case benjamin

    /// File name (WITHOUT ".json")
    public var filename: String {
        switch self {
        case .generic:          return "NamedColors"
        case .sherwinWilliams:  return "catalog_sherwin_williams"   // <- coincide con tu archivo
        case .behr: return "catalog_sherwin_williams"
        case .benjamin: return "catalog_sherwin_williams"
        }
    }

    /// Subdirectory inside bundle if it exists as a real folder (folder reference)
    public var subdirectory: String? {
        switch self {
        case .generic:          return nil
        case .sherwinWilliams:  return "catalogs"
        case .behr: return "catalogs"
        case .benjamin: return "catalogs"
        }
    }

    public var displayName: String {
        switch self {
        case .generic:          return "General"
        case .sherwinWilliams:  return "Sherwin-Williams"
        case .behr: return "Behr"
        case .benjamin: return "Benjamin Moore"
        }
    }
}

// MARK: - Errors

public enum CatalogLoadError: LocalizedError {
    case fileNotFound(CatalogID)
    case badEncoding(CatalogID)
    case decodeFailed(CatalogID, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let id):   return "File not found for catalog: \(id.displayName)"
        case .badEncoding(let id):    return "Bad encoding for catalog: \(id.displayName)"
        case .decodeFailed(let id, let err):
            return "Decode failed for catalog \(id.displayName): \(err.localizedDescription)"
        }
    }
}

// MARK: - Store / Registry

public final class CatalogStore: ObservableObject {

    /// Loaded items by catalog
    @Published public private(set) var loaded: [CatalogID: [NamedColor]] = [:]

    /// Last error per catalog (if any)
    @Published public private(set) var errors: [CatalogID: Error] = [:]

    /// Loading flags to avoid duplicate work
    @Published public private(set) var isLoading: Set<CatalogID> = []

    /// Optional external overrides: if present, load from here instead of the app bundle
    private var externalOverrides: [CatalogID: URL] = [:]

    public init(preload: Set<CatalogID> = [.generic]) {
        preload.forEach { load($0) }
    }

    // MARK: Public API

    /// Load a catalog (idempotent). Will no-op if it's already loaded or currently loading.
    public func load(_ id: CatalogID) {
        if loaded[id] != nil || isLoading.contains(id) { return }
        isLoading.insert(id)
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let items = try self.readCatalog(id)
                await MainActor.run {
                    self.loaded[id] = items
                    self.errors[id] = nil
                    self.isLoading.remove(id)
                }
            } catch {
                await MainActor.run {
                    self.errors[id] = error
                    self.isLoading.remove(id)
                }
            }
        }
    }

    /// Force reload a catalog (ignore cache).
    public func reload(_ id: CatalogID) {
        loaded[id] = nil
        errors[id] = nil
        load(id)
    }

    /// Unload a catalog to free memory.
    public func unload(_ id: CatalogID) {
        loaded[id] = nil
        errors[id] = nil
        isLoading.remove(id)
    }

    /// Provide an external URL override (e.g., user-imported file in Documents).
    /// Call before `load(_:)`. Pass `nil` to remove override.
    public func setExternalURL(_ url: URL?, for id: CatalogID) {
        if let url { externalOverrides[id] = url } else { externalOverrides[id] = nil }
    }

    /// All colors for the active catalogs (merged, unique).
    public func colors(for active: Set<CatalogID>) -> [NamedColor] {
        mergeUnique(active.compactMap { loaded[$0] })
    }

    /// Simple local search on active catalogs.
    public func search(_ query: String, in active: Set<CatalogID>) -> [NamedColor] {
        let base = colors(for: active)
        guard !query.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q)
            || $0.hex.lowercased().contains(q)
            || ($0.vendor?.code?.lowercased().contains(q) ?? false)
            || ($0.vendor?.brand?.lowercased().contains(q) ?? false)
        }
    }

    /// Quick boolean to know if a catalog is ready.
    public func isLoaded(_ id: CatalogID) -> Bool { loaded[id] != nil }

    // MARK: Internals

    private func readCatalog(_ id: CatalogID) throws -> [NamedColor] {
        // 1) If an external override exists, prefer it
        if let url = externalOverrides[id] {
            return try decodeJSON(at: url, catalog: id)
        }

        // 2) Try with subdirectory (if the folder exists as a real subdirectory in bundle)
        if let sub = id.subdirectory,
           let url = Bundle.main.url(forResource: id.filename, withExtension: "json", subdirectory: sub) {
            return try decodeJSON(at: url, catalog: id)
        }

        // 3) Try at bundle root (Xcode may flatten groups)
        if let url = Bundle.main.url(forResource: id.filename, withExtension: "json") {
            return try decodeJSON(at: url, catalog: id)
        }

        // 4) Not found
        throw CatalogLoadError.fileNotFound(id)
    }

    private func decodeJSON(at url: URL, catalog id: CatalogID) throws -> [NamedColor] {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        do {
            return try dec.decode([NamedColor].self, from: data)
        } catch {
            if String(data: data, encoding: .utf8) == nil {
                throw CatalogLoadError.badEncoding(id)
            }
            throw CatalogLoadError.decodeFailed(id, underlying: error)
        }
    }

    private func mergeUnique(_ arrays: [[NamedColor]]) -> [NamedColor] {
        var seen = Set<String>()
        var out: [NamedColor] = []
        for arr in arrays {
            for item in arr {
                let key = item.vendor?.code ?? "\(item.name)|\(item.hex.lowercased())"
                if seen.insert(key).inserted { out.append(item) }
            }
        }
        return out
    }
}

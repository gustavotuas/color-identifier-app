import Foundation

public enum CatalogSelection: Hashable, Equatable {
    case genericOnly
    case vendor(CatalogID)

    public var title: String {
        switch self {
        case .genericOnly: return "Generic"
        case .vendor(let id): return id.displayName
        }
    }

    public var isFiltered: Bool {
        return true
    }

    public var filterSubtitle: String {
        switch self {
        case .genericOnly:
            return "Generic palette"
        case .vendor(let id):
            return "Filtered by \(id.displayName)"
        }
    }
}

public enum VendorSelectionStorage {
    private static let key = "last_vendor_selection_v1"

    public static func save(_ sel: CatalogSelection) {
        let raw: String
        switch sel {
        case .genericOnly:
            raw = "generic"
        case .vendor(let id):
            raw = "vendor:\(id.rawValue)"
        }
        UserDefaults.standard.set(raw, forKey: key)
    }

    public static func load() -> CatalogSelection? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return .genericOnly }
        if raw == "generic" { return .genericOnly }
        if raw.hasPrefix("vendor:") {
            let val = raw.replacingOccurrences(of: "vendor:", with: "")
            if let id = CatalogID(rawValue: val) { return .vendor(id) }
        }
        return .genericOnly
    }
}

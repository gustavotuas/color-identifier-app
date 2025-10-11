import Foundation

public enum CatalogSelection: Hashable, Equatable {
    case all
    case genericOnly
    case vendor(CatalogID)

    // Título para Navigation (ya no dice Vendors)
    public var title: String {
        switch self {
        case .all:              return "All Colors"
        case .genericOnly:      return "Generic"
        case .vendor(let id):   return id.displayName
        }
    }

    // ¿Hay filtro activo?
    public var isFiltered: Bool {
        switch self {
        case .all:  return false
        default:    return true
        }
    }

    // Subtítulo descriptivo para mostrar bajo el título
    public var filterSubtitle: String {
        switch self {
        case .all:
            return "Showing all catalogs"
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
        case .all:             raw = "all"
        case .genericOnly:     raw = "generic"
        case .vendor(let id):  raw = "vendor:\(id.rawValue)"
        }
        UserDefaults.standard.set(raw, forKey: key)
    }

    public static func load() -> CatalogSelection? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        if raw == "all"      { return .all }
        if raw == "generic"  { return .genericOnly }
        if raw.hasPrefix("vendor:") {
            let val = raw.replacingOccurrences(of: "vendor:", with: "")
            if let id = CatalogID(rawValue: val) { return .vendor(id) }
        }
        return nil
    }
}

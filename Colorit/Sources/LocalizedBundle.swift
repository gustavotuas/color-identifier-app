import Foundation

private var bundleKey: UInt8 = 0

extension Bundle {
    static func setLanguage(_ language: String) {
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
        let value = path.flatMap { Bundle(path: $0) } ?? .main
        objc_setAssociatedObject(Bundle.main, &bundleKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static var localized: Bundle {
        if let bundle = objc_getAssociatedObject(Bundle.main, &bundleKey) as? Bundle {
            return bundle
        }
        return .main
    }
}

extension String {
    var localized: String {
        NSLocalizedString(self, bundle: .localized, comment: "")
    }
}

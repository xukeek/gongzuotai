import Foundation

/// Resource bundle that holds compiled `Localizable.strings` (from the
/// String Catalog). SPM's synthesized `Bundle.module` looks next to the
/// executable / at `App/Search_Search.bundle`, which misses a normal
/// `.app` layout — so prefer `Contents/Resources` first.
private enum LocBundle {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Search_Search", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}

/// Localized copy from the String Catalog. Semantic keys stay stable across
/// languages — add a locale in `Localizable.xcstrings` and `LOCALES` in
/// `build.sh`; call sites do not change.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: LocBundle.bundle)
}

/// Lookup by semantic key string (same catalog as `L(_:)`).
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(stringLiteral: key), bundle: LocBundle.bundle)
}

/// Format a catalog string that contains `%@` / `%lld` placeholders.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}

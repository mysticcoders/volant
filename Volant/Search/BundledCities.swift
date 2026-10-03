import Foundation
import VolantCore

extension CityDirectory {
    /// GeoNames city time zones from the app bundle, decompressed on the first lookup the
    /// built-in names cannot answer. A missing or damaged table answers nothing.
    static func bundled(_ bundle: Bundle = .main) -> CityDirectory {
        CityDirectory(load: {
            guard let url = bundle.url(forResource: "cities.tsv", withExtension: "deflate"),
                  let data = try? (Data(contentsOf: url) as NSData).decompressed(using: .zlib) else { return nil }
            return String(data: data as Data, encoding: .utf8)
        })
    }
}

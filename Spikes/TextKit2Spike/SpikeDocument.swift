import Foundation
import Observation

/// Minimal document model for the spike: canonical markdown source string,
/// atomic save/load, revision counter. The G1 `MarkdownDocument` will grow
/// from this shape.
@MainActor
@Observable
final class SpikeDocument {
    private(set) var source: String
    private(set) var revision: Int = 0
    let url: URL

    init(source: String, url: URL) {
        self.source = source
        self.url = url
    }

    func update(source newSource: String) {
        guard newSource != source else { return }
        source = newSource
        revision += 1
    }

    func save() throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    func reload() throws {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        update(source: text)
    }
}

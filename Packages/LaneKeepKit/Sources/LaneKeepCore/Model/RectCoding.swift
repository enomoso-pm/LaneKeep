import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Encodes a `CGRect` as `{"x": …, "y": …, "width": …, "height": …}` so that `workspaces.json`
/// stays readable. Decoding also accepts Foundation's default `[[x, y], [width, height]]` form.
struct CodableRect: Codable, Equatable {
    var rect: CGRect

    init(_ rect: CGRect) {
        self.rect = rect
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            rect = CGRect(
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y),
                width: try container.decode(Double.self, forKey: .width),
                height: try container.decode(Double.self, forKey: .height)
            )
        } else {
            rect = try CGRect(from: decoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Double(rect.origin.x), forKey: .x)
        try container.encode(Double(rect.origin.y), forKey: .y)
        try container.encode(Double(rect.size.width), forKey: .width)
        try container.encode(Double(rect.size.height), forKey: .height)
    }
}

extension KeyedDecodingContainer {
    func decodeRect(forKey key: Key) throws -> CGRect {
        try decode(CodableRect.self, forKey: key).rect
    }

    func decodeRectIfPresent(forKey key: Key) throws -> CGRect? {
        try decodeIfPresent(CodableRect.self, forKey: key)?.rect
    }
}

extension KeyedEncodingContainer {
    mutating func encodeRect(_ rect: CGRect, forKey key: Key) throws {
        try encode(CodableRect(rect), forKey: key)
    }

    mutating func encodeRectIfPresent(_ rect: CGRect?, forKey key: Key) throws {
        if let rect {
            try encode(CodableRect(rect), forKey: key)
        }
    }
}

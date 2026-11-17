import Foundation
public enum URLValidator {
    public static func validate(_ value: String) -> URL? {
        guard !value.isEmpty, value.utf8.count <= 8192,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !value.contains("\\"),
              let strictURL = URL(string: value, encodingInvalidCharacters: false),
              let parts = URLComponents(url: strictURL, resolvingAgainstBaseURL: false), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.port == nil || (1...65535).contains(parts.port!),
              let url = parts.url else { return nil }
        return url
    }
    public static func decode(_ value: String?) -> URL? {
        guard let value else { return nil }
        if let url = validate(value) { return url }

        guard let data = try? Ascii85Decoder.decode(value),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return validate(string)
    }
}

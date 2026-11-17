import Foundation
public enum Ascii85Decoder {
    public enum Failure: Error { case malformed }
    // Adobe Ascii85, optional <~ ~> framing, ASCII whitespace and z supported.
    // RFC1924/Base85 and btoa y shorthand are deliberately unsupported.
    public static func decode(_ input: String) throws -> Data {
        guard input.utf8.count <= 32768 else { throw Failure.malformed }
        var bytes = Array(input.utf8.filter { ![9, 10, 11, 12, 13, 32].contains($0) })
        if bytes.starts(with: [60, 126]) {
            guard bytes.suffix(2) == [126, 62] else { throw Failure.malformed }
            bytes = Array(bytes.dropFirst(2).dropLast(2))
        }
        guard bytes.count <= 32768 else { throw Failure.malformed }
        var output = Data(), group: [UInt8] = []
        func append(_ digits: [UInt8], count: Int) throws {
            var value: UInt64 = 0
            for digit in digits { value = value * 85 + UInt64(digit - 33) }
            guard value <= UInt64(UInt32.max) else { throw Failure.malformed }
            for shift in (0..<count) { output.append(UInt8((value >> (24 - shift * 8)) & 255)) }
        }
        for byte in bytes {
            if byte == 122 {
                guard group.isEmpty else { throw Failure.malformed }
                output.append(contentsOf: [0,0,0,0]); continue
            }
            guard (33...117).contains(byte) else { throw Failure.malformed }
            group.append(byte)
            if group.count == 5 { try append(group, count: 4); group.removeAll(keepingCapacity: true) }
        }
        guard group.count != 1 else { throw Failure.malformed }
        if !group.isEmpty {
            let count = group.count - 1
            group += Array(repeating: 117, count: 5 - group.count)
            try append(group, count: count)
        }
        return output
    }
}

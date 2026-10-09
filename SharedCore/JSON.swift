import Foundation

/// Lenient JSON value. The Athom/Homey APIs are loosely documented and fields
/// vary per endpoint, so we parse into this tree and read what we need,
/// just like the Developer Checker Homey app does in JavaScript.
enum JSON: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    static func parse(_ data: Data) -> JSON {
        guard !data.isEmpty else { return .null }
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return JSON(any: obj)
        }
        if let text = String(data: data, encoding: .utf8) { return .string(text) }
        return .null
    }

    init(any value: Any?) {
        switch value {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSON(any: $0) })
        case let d as [String: Any]: self = .object(d.mapValues { JSON(any: $0) })
        default: self = .null
        }
    }

    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.anyValue)
        case .object(let o): return o.mapValues(\.anyValue)
        }
    }

    func data(pretty: Bool = false) -> Data {
        if case .string(let s) = self { return Data(s.utf8) }
        let opts: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed] : [.fragmentsAllowed]
        return (try? JSONSerialization.data(withJSONObject: anyValue, options: opts)) ?? Data()
    }

    var prettyString: String { String(data: data(pretty: true), encoding: .utf8) ?? "" }

    subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    var isNull: Bool { if case .null = self { return true }; return false }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number: return displayString
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    var int: Int? { double.flatMap { $0.isFinite ? Int(exactly: $0.rounded(.towardZero)) : nil } }

    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return ["true", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }

    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSON] { if case .object(let o) = self { return o }; return [:] }

    /// For collections returned by Homey as `{ id: item }` dictionaries *or* arrays.
    var items: [JSON] {
        switch self {
        case .array(let a): return a
        case .object(let o): return Array(o.values)
        default: return []
        }
    }

    /// Localised strings come as `{ "en": "...", "nl": "..." }`.
    var localized: String {
        switch self {
        case .string(let s): return s
        case .object(let o):
            let lang = Locale.current.language.languageCode?.identifier ?? "en"
            return o[lang]?.string ?? o["en"]?.string ?? o["nl"]?.string ?? o.values.compactMap(\.string).first ?? ""
        default: return string ?? ""
        }
    }

    var displayString: String {
        switch self {
        case .null: return "—"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            if n.rounded() == n && abs(n) < 1e15 { return String(Int64(n)) }
            return String(format: "%.2f", n)
        case .string(let s): return s
        case .array(let a): return "[\(a.count)]"
        case .object(let o): return "{\(o.count)}"
        }
    }

    var isContainer: Bool {
        switch self { case .array, .object: return true; default: return false }
    }
}

extension JSON {
    /// First non-empty string among several keys.
    func firstString(_ keys: String...) -> String {
        for k in keys { if let s = self[k].string, !s.isEmpty { return s } }
        return ""
    }

    var date: Date? {
        if case .number(let n) = self { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        guard let s = string, !s.isEmpty else { return nil }
        return DateParsing.parse(s)
    }
}

enum DateParsing {
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func parse(_ s: String) -> Date? {
        iso.date(from: s) ?? isoNoFrac.date(from: s) ?? Double(s).map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) }
    }
}

/// The localized "title" of a Homey object, or its id when it has none.
func titleOrID(_ json: JSON) -> String {
    let title: String = json["title"].localized
    return title.isEmpty ? json.firstString("id") : title
}

import Foundation

/// Fetches SuperGrok / Grok consumer credit usage from grok.com.
///
/// Endpoint (undocumented but used by grok.com + Grok Build):
/// `POST https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig`
/// Auth: `Authorization: Bearer <token from ~/.grok/auth.json>`
/// Body: empty gRPC-web frame
final class GrokCreditsClient: UsageFetching, Sendable {
    let provider: ProviderID = .grok
    var isConfigured: Bool { GrokAuthStore.isConfigured }

    static let endpoint = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetchUsage()
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let (token, identity) = try GrokAuthStore.load()
        let parsed = try await fetchCredits(token: token)
        return UsageSnapshot(
            provider: .grok,
            usedPercent: parsed.usedPercent,
            periodStart: parsed.periodStart,
            resetsAt: parsed.resetsAt,
            features: parsed.features,
            identity: identity,
            source: "grok.com credits",
            fetchedAt: Date()
        )
    }

    private func fetchCredits(token: String) async throws -> ParsedCredits {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        // Empty gRPC-web data frame: flags(0) + length(0)
        request.httpBody = Data([0x00, 0x00, 0x00, 0x00, 0x00])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.setValue("connect-es/2.1.1", forHTTPHeaderField: "x-user-agent")
        request.setValue("TokenPanel", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TokenPanelError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TokenPanelError.http(status: -1, body: "Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw TokenPanelError.http(status: http.statusCode, body: body)
        }

        try validateGRPCStatus(headerFields: http.allHeaderFields)
        try Self.validateGRPCWebTrailers(data)

        return try Self.parseResponse(data)
    }

    // MARK: - Parse

    struct ParsedCredits {
        var usedPercent: Double?
        var periodStart: Date?
        var resetsAt: Date?
        var features: [FeatureUsage]
    }

    static func parseResponse(_ data: Data, now: Date = Date()) throws -> ParsedCredits {
        var payloads = grpcWebDataFrames(from: data)
        if payloads.isEmpty, looksLikeProtobuf(data) {
            payloads = [data]
        }
        guard !payloads.isEmpty else { throw TokenPanelError.emptyResponse }

        var scan = ProtobufScan()
        for payload in payloads {
            scan.merge(scanProtobuf(payload, depth: 0, path: [], order: 0).scan)
        }

        // credit_usage_percent lives at path [1, 1] as fixed32 float (0...100)
        let percentCandidates = scan.fixed32Fields.filter { field in
            field.path == [1, 1] || (field.path.last == 1 && field.value.isFinite && field.value >= 0 && field.value <= 100)
        }
        let usedPercent = percentCandidates
            .sorted { lhs, rhs in
                if lhs.path == [1, 1] { return true }
                if rhs.path == [1, 1] { return false }
                return lhs.path.count < rhs.path.count
            }
            .first
            .map { Double($0.value) }

        // period start [1,4,1], reset [1,5,1] as unix seconds varints
        let periodStart = scan.timestamp(at: [1, 4, 1])
        let resetsAt = scan.timestamp(at: [1, 5, 1])
            ?? scan.varintFields
                .compactMap { field -> Date? in
                    guard field.value >= 1_700_000_000, field.value <= 2_100_000_000 else { return nil }
                    let date = Date(timeIntervalSince1970: TimeInterval(field.value))
                    return date > now ? date : nil
                }
                .min()

        // feature buckets: repeated message at [1,7] with id varint field 1 and percent float field 2
        var features: [FeatureUsage] = []
        for group in scan.featureGroups {
            features.append(FeatureUsage(id: String(group.id), percent: group.percent))
        }
        features.sort { $0.percent > $1.percent }

        let hasPeriod = periodStart != nil || resetsAt != nil
        let resolvedPercent = usedPercent ?? (hasPeriod && scan.fixed32Fields.isEmpty ? 0 : usedPercent)
        guard resolvedPercent != nil || !features.isEmpty else {
            throw TokenPanelError.parseFailed
        }

        return ParsedCredits(
            usedPercent: resolvedPercent,
            periodStart: periodStart,
            resetsAt: resetsAt,
            features: features
        )
    }

    // MARK: - gRPC-web framing

    private static func grpcWebDataFrames(from data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var frames: [Data] = []
        var index = 0
        while index + 5 <= bytes.count {
            let flags = bytes[index]
            let length = (Int(bytes[index + 1]) << 24)
                | (Int(bytes[index + 2]) << 16)
                | (Int(bytes[index + 3]) << 8)
                | Int(bytes[index + 4])
            let start = index + 5
            let end = start + length
            guard length >= 0, end <= bytes.count else { return [] }
            if flags & 0x80 == 0 {
                frames.append(Data(bytes[start..<end]))
            }
            index = end
        }
        return frames
    }

    private static func looksLikeProtobuf(_ data: Data) -> Bool {
        guard let first = data.first else { return false }
        let fieldNumber = first >> 3
        let wireType = first & 0x07
        return fieldNumber > 0 && (wireType == 0 || wireType == 1 || wireType == 2 || wireType == 5)
    }

    private func validateGRPCStatus(headerFields: [AnyHashable: Any]) throws {
        var fields: [String: String] = [:]
        for (key, value) in headerFields {
            let k = String(describing: key).lowercased()
            if k.hasPrefix("grpc-") {
                fields[k] = String(describing: value)
            }
        }
        try Self.validateGRPCStatusFields(fields)
    }

    private static func validateGRPCWebTrailers(_ data: Data) throws {
        try validateGRPCStatusFields(grpcWebTrailerFields(from: data))
    }

    private static func validateGRPCStatusFields(_ fields: [String: String]) throws {
        guard let raw = fields["grpc-status"], let status = Int(raw), status != 0 else { return }
        let message = fields["grpc-message"]?
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        throw TokenPanelError.grpc(status: status, message: message)
    }

    private static func grpcWebTrailerFields(from data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        var fields: [String: String] = [:]
        var index = 0
        while index + 5 <= bytes.count {
            let flags = bytes[index]
            let length = (Int(bytes[index + 1]) << 24)
                | (Int(bytes[index + 2]) << 16)
                | (Int(bytes[index + 3]) << 8)
                | Int(bytes[index + 4])
            let start = index + 5
            let end = start + length
            guard length >= 0, end <= bytes.count else { break }
            if flags & 0x80 != 0, let text = String(data: Data(bytes[start..<end]), encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    guard let sep = line.firstIndex(of: ":") else { continue }
                    let key = line[..<sep].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let value = line[line.index(after: sep)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .removingPercentEncoding ?? ""
                    fields[key] = value
                }
            }
            index = end
        }
        return fields
    }

    // MARK: - Minimal protobuf scanner

    private struct ProtobufScan {
        struct Fixed32Field {
            var path: [UInt64]
            var value: Float
            var order: Int
        }

        struct VarintField {
            var path: [UInt64]
            var value: UInt64
        }

        struct FeatureGroup {
            var id: UInt64
            var percent: Double
        }

        var fixed32Fields: [Fixed32Field] = []
        var varintFields: [VarintField] = []
        var featureGroups: [FeatureGroup] = []

        mutating func merge(_ other: ProtobufScan) {
            fixed32Fields.append(contentsOf: other.fixed32Fields)
            varintFields.append(contentsOf: other.varintFields)
            featureGroups.append(contentsOf: other.featureGroups)
        }

        func timestamp(at path: [UInt64]) -> Date? {
            guard let value = varintFields.first(where: { $0.path == path })?.value,
                  value >= 1_700_000_000, value <= 2_100_000_000
            else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
    }

    private static func scanProtobuf(
        _ data: Data,
        depth: Int,
        path: [UInt64],
        order: Int
    ) -> (scan: ProtobufScan, order: Int) {
        let bytes = [UInt8](data)
        var scan = ProtobufScan()
        var index = 0
        var nextOrder = order

        while index < bytes.count {
            let fieldStart = index
            guard let key = readVarint(bytes, index: &index), key != 0 else {
                index = fieldStart + 1
                continue
            }
            let fieldNumber = key >> 3
            let wireType = key & 0x07
            let fieldPath = path + [fieldNumber]

            switch wireType {
            case 0:
                if let value = readVarint(bytes, index: &index) {
                    scan.varintFields.append(.init(path: fieldPath, value: value))
                } else {
                    index = fieldStart + 1
                }
            case 1:
                guard index + 8 <= bytes.count else { return (scan, nextOrder) }
                index += 8
            case 2:
                guard let length = readVarint(bytes, index: &index),
                      length <= UInt64(bytes.count - index)
                else {
                    index = fieldStart + 1
                    continue
                }
                let start = index
                let end = index + Int(length)
                let chunk = Data(bytes[start..<end])

                // Feature usage messages live under path [1, 7]
                if fieldPath == [1, 7] {
                    if let feature = parseFeatureMessage(chunk) {
                        scan.featureGroups.append(feature)
                    }
                }

                if depth < 5 {
                    let nested = scanProtobuf(chunk, depth: depth + 1, path: fieldPath, order: nextOrder)
                    scan.merge(nested.scan)
                    nextOrder = nested.order
                }
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return (scan, nextOrder) }
                let bits = UInt32(bytes[index])
                    | (UInt32(bytes[index + 1]) << 8)
                    | (UInt32(bytes[index + 2]) << 16)
                    | (UInt32(bytes[index + 3]) << 24)
                scan.fixed32Fields.append(.init(
                    path: fieldPath,
                    value: Float(bitPattern: bits),
                    order: nextOrder
                ))
                nextOrder += 1
                index += 4
            default:
                index = fieldStart + 1
            }
        }
        return (scan, nextOrder)
    }

    private static func parseFeatureMessage(_ data: Data) -> ProtobufScan.FeatureGroup? {
        let bytes = [UInt8](data)
        var index = 0
        var id: UInt64?
        var percent: Double = 0

        while index < bytes.count {
            let start = index
            guard let key = readVarint(bytes, index: &index) else { break }
            let field = key >> 3
            let wire = key & 0x07
            switch wire {
            case 0:
                guard let value = readVarint(bytes, index: &index) else { return nil }
                if field == 1 { id = value }
            case 5:
                guard index + 4 <= bytes.count else { return nil }
                let bits = UInt32(bytes[index])
                    | (UInt32(bytes[index + 1]) << 8)
                    | (UInt32(bytes[index + 2]) << 16)
                    | (UInt32(bytes[index + 3]) << 24)
                let value = Double(Float(bitPattern: bits))
                if field == 2, value.isFinite, value >= 0, value <= 100 {
                    percent = value
                }
                index += 4
            case 2:
                guard let length = readVarint(bytes, index: &index),
                      length <= UInt64(bytes.count - index)
                else { return nil }
                index += Int(length)
            case 1:
                guard index + 8 <= bytes.count else { return nil }
                index += 8
            default:
                index = start + 1
            }
        }

        guard let id else { return nil }
        return .init(id: id, percent: percent)
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}

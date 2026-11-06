import CryptoKit
import Foundation

// MARK: - Credentials

public struct AWSCredentials: Sendable, CustomStringConvertible {
    public var accessKeyId: String
    public var secretAccessKey: String
    public var sessionToken: String?
    public var expiration: Date?

    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String?, expiration: Date?) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    /// Never print secrets.
    public var description: String {
        "AWSCredentials(<redacted>, expires: \(expiration.map { "\($0)" } ?? "never"))"
    }
}

/// Fetches credentials via `aws configure export-credentials --profile X --format process`, caching per profile
/// until 5 minutes before `Expiration`. Concurrent callers share one in-flight fetch.
actor AWSCredentialStore {
    static let shared = AWSCredentialStore()

    private var cache: [String: AWSCredentials] = [:]
    private var inflight: [String: Task<AWSCredentials, Error>] = [:]

    func credentials(profile: String) async throws -> AWSCredentials {
        if let c = cache[profile], Self.isFresh(c) { return c }
        if let t = inflight[profile] { return try await t.value }
        let t = Task.detached { try AWSCLI.exportCredentials(profile: profile) }
        inflight[profile] = t
        defer { inflight[profile] = nil }
        let c = try await t.value
        cache[profile] = c
        return c
    }

    func invalidate(profile: String) { cache[profile] = nil }

    static func isFresh(_ c: AWSCredentials) -> Bool {
        guard let exp = c.expiration else { return true }
        return exp.timeIntervalSinceNow > 5 * 60
    }
}

enum AWSCLI {
    struct Located: Sendable { let path: String; let env: [String: String] }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var located: Located?

    /// GUI apps get a minimal PATH; probe the usual install dirs, then ask a login shell.
    static func locate() throws -> Located {
        lock.lock(); defer { lock.unlock() }
        if let l = located { return l }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.aki/bin", "\(home)/.toolbox/bin"]
        var env = ProcessInfo.processInfo.environment
        let basePath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // aws may shell out to credential_process helpers (ada, isengardcli…), so give the child a full PATH.
        env["PATH"] = (dirs + [basePath]).joined(separator: ":")
        env["AWS_PAGER"] = ""
        for d in dirs where FileManager.default.isExecutableFile(atPath: "\(d)/aws") {
            let l = Located(path: "\(d)/aws", env: env)
            located = l
            return l
        }
        // Login shell fallback: also adopt its PATH.
        let out = try? run("/bin/zsh", ["-lc", "command -v aws; print -r -- \"$PATH\""], env: env, timeout: 10)
        let lines = (out?.stdout).map { String(decoding: $0, as: UTF8.self) }?
            .split(separator: "\n").map(String.init) ?? []
        if lines.count >= 2, FileManager.default.isExecutableFile(atPath: lines[0]) {
            env["PATH"] = (dirs + [lines[1]]).joined(separator: ":")
            let l = Located(path: lines[0], env: env)
            located = l
            return l
        }
        throw LLMError.awsCLINotFound
    }

    static func exportCredentials(profile: String) throws -> AWSCredentials {
        let aws = try locate()
        let started = Date()
        let r = try run(aws.path, ["configure", "export-credentials", "--profile", profile, "--format", "process"],
                        env: aws.env, timeout: 45)
        LLMDebug.log("aws export-credentials (\(profile)) took \(Int(Date().timeIntervalSince(started) * 1000)) ms, exit \(r.status)")
        guard r.status == 0 else {
            let err = String(decoding: r.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw LLMError.credentials("profile '\(profile)': \(err.isEmpty ? "aws exited \(r.status)" : String(err.prefix(500)))")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: r.stdout) as? [String: Any],
              let akid = obj["AccessKeyId"] as? String, let secret = obj["SecretAccessKey"] as? String else {
            throw LLMError.credentials("profile '\(profile)': unexpected output from aws configure export-credentials")
        }
        let exp = (obj["Expiration"] as? String).flatMap(parseISO8601)
        if let exp, exp.timeIntervalSinceNow <= 0 {
            throw LLMError.credentials("profile '\(profile)': credentials expired at \(exp)")
        }
        return AWSCredentials(accessKeyId: akid, secretAccessKey: secret, sessionToken: obj["SessionToken"] as? String, expiration: exp)
    }

    static func parseISO8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    struct RunResult { let status: Int32; let stdout: Data; let stderr: Data }

    private final class ProcBox: @unchecked Sendable { let p: Process; init(_ p: Process) { self.p = p } }

    /// Blocking subprocess run with a timeout. Call off the main thread.
    static func run(_ exe: String, _ args: [String], env: [String: String], timeout: TimeInterval) throws -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let box = ProcBox(p)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if box.p.isRunning { box.p.terminate() }
        }
        // Drain stderr concurrently so a chatty helper can't block on a full pipe.
        let errData = LockedData()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData.set(err.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        group.wait()
        return RunResult(status: p.terminationStatus, stdout: outData, stderr: errData.get())
    }

    private final class LockedData: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}

// MARK: - SigV4

public enum SigV4 {
    /// RFC 3986 unreserved characters; everything else is %XX-encoded (UTF-8).
    public static func uriEncode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                 UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.append(Character(UnicodeScalar(b)))
            default:
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    /// Canonical URI for non-S3 services: each segment of the (already percent-encoded) request path is encoded again,
    /// so `%3A` in the URL becomes `%253A` here.
    public static func canonicalURI(encodedPath: String) -> String {
        if encodedPath.isEmpty { return "/" }
        return encodedPath.split(separator: "/", omittingEmptySubsequences: false)
            .map { uriEncode(String($0)) }
            .joined(separator: "/")
    }

    static func canonicalQuery(_ q: String?) -> String {
        guard let q, !q.isEmpty else { return "" }
        var pairs: [(key: String, value: String)] = []
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(kv[0])
            let value = kv.count > 1 ? String(kv[1]) : ""
            pairs.append((key, value))
        }
        pairs.sort { a, b in a.key == b.key ? a.value < b.value : a.key < b.key }
        return pairs.map { p in p.key + "=" + p.value }.joined(separator: "&")
    }

    public static func amzDate(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the headers to add (`x-amz-date`, `x-amz-security-token`?, `authorization`).
    /// `headers` are the other headers to sign (host is added from the URL). `encodedPath`/`query` are as sent.
    public static func sign(
        method: String, host: String, encodedPath: String, query: String?,
        headers: [String: String], body: Data,
        region: String, service: String, credentials: AWSCredentials, date: Date = Date()
    ) -> [String: String] {
        let amz = amzDate(date)
        let day = String(amz.prefix(8))
        var toSign: [String: String] = [:]
        for (k, v) in headers { toSign[k.lowercased()] = v.trimmingCharacters(in: .whitespaces) }
        toSign["host"] = host
        toSign["x-amz-date"] = amz
        if let t = credentials.sessionToken { toSign["x-amz-security-token"] = t }
        let names = toSign.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(toSign[$0]!)\n" }.joined()
        let signedHeaders = names.joined(separator: ";")
        let canonicalRequest = [
            method, canonicalURI(encodedPath: encodedPath), canonicalQuery(query),
            canonicalHeaders, signedHeaders, sha256Hex(body),
        ].joined(separator: "\n")
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amz, scope, sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")

        func hmac(_ key: SymmetricKey, _ s: String) -> SymmetricKey {
            SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(s.utf8), using: key)))
        }
        var key = SymmetricKey(data: Data("AWS4\(credentials.secretAccessKey)".utf8))
        for part in [day, region, service, "aws4_request"] { key = hmac(key, part) }
        let sig = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()

        var out = ["x-amz-date": amz,
                   "authorization": "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(sig)"]
        if let t = credentials.sessionToken { out["x-amz-security-token"] = t }
        return out
    }
}

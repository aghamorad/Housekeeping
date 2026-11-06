import Foundation
import Security

/// The token-bearing URL never goes into preferences, logs, or process arguments.
enum ExpressVPNMCPSettings {
    private static let service = "com.housekeeping.expressvpn-mcp"
    static func endpoint() -> URL? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "endpoint",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let text = String(data: data, encoding: .utf8)
        else { return nil }
        return validatedURL(text)
    }

    static func validatedURL(_ text: String) -> URL? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard var parts = URLComponents(string: clean), parts.scheme == "http",
              ["127.0.0.1", "localhost"].contains(parts.host ?? ""),
              let port = parts.port, (1...65535).contains(port), parts.path == "/mcp",
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.queryItems?.contains(where: { $0.name == "token" && !($0.value ?? "").isEmpty }) == true
        else { return nil }
        parts.host = "127.0.0.1"
        return parts.url
    }

    static func save(_ text: String) throws {
        guard let url = validatedURL(text) else { throw MCPError.message("Copy the full local MCP address from ExpressVPN, including its token.") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "endpoint"]
        let data = Data(url.absoluteString.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MCPError.message("macOS could not save the connection in Keychain.") }
        } else if update != errSecSuccess { throw MCPError.message("macOS could not update the connection in Keychain.") }
    }

    static func clear() throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "endpoint"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MCPError.message("macOS could not remove the saved connection.") }
    }
}

enum MCPError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Never forward the secret URL through a redirect or a system proxy.
private final class MCPRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor ExpressVPNMCP {
    let endpoint: URL
    private var sessionID: String?
    private var version = "2025-03-26"
    private var nextID = 0
    private let session: URLSession

    init(endpoint: URL) {
        self.endpoint = endpoint
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config, delegate: MCPRedirectGuard(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    static func decode(_ data: Data, id: Int) throws -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self)
        var candidates = [data]
        // A streamed MCP response may contain notifications before the result.
        for event in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n") {
            let payload = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            if !payload.isEmpty { candidates.append(Data(payload.utf8)) }
        }
        for candidate in candidates {
            guard let root = try? JSONSerialization.jsonObject(with: candidate) as? [String: Any],
                  (root["id"] as? Int) == id else { continue }
            guard root["error"] == nil, let result = root["result"] as? [String: Any] else {
                throw MCPError.message("ExpressVPN refused the request. Check its MCP settings and copied address.")
            }
            return result
        }
        throw MCPError.message("ExpressVPN returned an unreadable MCP response.")
    }

    private func request(_ method: String, params: [String: Any] = [:], notification: Bool = false) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if !notification { body["id"] = id }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if method != "initialize" { request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw MCPError.message("ExpressVPN MCP is not responding. Open ExpressVPN and check that MCP is enabled.") }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 2_000_000 else {
            throw MCPError.message("ExpressVPN MCP rejected the connection. Copy its current address again if the token changed.")
        }
        if method == "initialize" { sessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") }
        if notification { return [:] }
        return try Self.decode(data, id: id)
    }

    /// Discover parameter names from the installed server, rather than guessing
    /// which release calls a location `region` versus `location`.
    func call(_ tool: String, value: String? = nil) async throws -> String {
        do {
            let text = try await performCall(tool, value: value)
            await closeSession()
            return text
        } catch {
            await closeSession()
            throw error
        }
    }

    private func closeSession() async {
        guard let sessionID else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 2
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
        // This closes the MCP session, never the VPN tunnel. Servers may return
        // 405 if they expire sessions themselves; cleanup is best effort.
        _ = try? await session.data(for: request)
        self.sessionID = nil
    }

    private func performCall(_ tool: String, value: String?) async throws -> String {
        let allowed = ["expressvpn_ping", "expressvpn_status", "expressvpn_get_connectionstate",
                       "expressvpn_get_protocol", "expressvpn_get_vpnip", "expressvpn_get_regions",
                       "expressvpn_set_protocol", "expressvpn_connect", "expressvpn_disconnect"]
        guard allowed.contains(tool) else { throw MCPError.message("This ExpressVPN action is unavailable in RouteSweep.") }
        let initialized = try await request("initialize", params: ["protocolVersion": version,
            "capabilities": [:], "clientInfo": ["name": "Housekeeping", "version": "1.0"]])
        if let negotiated = initialized["protocolVersion"] as? String { version = negotiated }
        _ = try await request("notifications/initialized", notification: true)
        var tools: [[String: Any]] = []
        var cursor: String?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 10 else { throw MCPError.message("ExpressVPN returned too many tool pages.") }
            let page = try await request("tools/list", params: cursor.map { ["cursor": $0] } ?? [:])
            tools += page["tools"] as? [[String: Any]] ?? []
            cursor = page["nextCursor"] as? String
            if tools.count > 500 { throw MCPError.message("ExpressVPN returned an unexpected tool list.") }
        } while cursor != nil
        guard let description = tools.first(where: { $0["name"] as? String == tool }) else { throw MCPError.message("This ExpressVPN version does not offer the requested MCP action.") }
        var arguments: [String: Any] = [:]
        if let value {
            let schema = description["inputSchema"] as? [String: Any] ?? [:]
            let properties = schema["properties"] as? [String: Any] ?? [:]
            let names = tool == "expressvpn_connect" ? ["region", "location"] : ["protocol", "value"]
            guard let key = names.first(where: { properties[$0] != nil }) else { throw MCPError.message("ExpressVPN changed this action's input format. Use the CLI connection until Housekeeping is updated.") }
            arguments[key] = value
        }
        let result = try await request("tools/call", params: ["name": tool, "arguments": arguments])
        guard (result["isError"] as? Bool) != true else { throw MCPError.message("ExpressVPN could not complete the requested action.") }
        let content = result["content"] as? [[String: Any]] ?? []
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

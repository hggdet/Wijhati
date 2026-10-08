import Foundation

// MARK: - Wijhati community backend (Supabase REST)
//
// Local Intelligence lives here: shared road reports + community places.
// Fill baseURL + anonKey with the Supabase project values to activate sync.
// Until then everything works on-device only (graceful fallback).
enum Backend {
    static let baseURL = ""
    static let anonKey = ""

    static var isConfigured: Bool { !baseURL.isEmpty && !anonKey.isEmpty }

    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "wijhati.deviceID") {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: "wijhati.deviceID")
        return fresh
    }

    private static func makeRequest(path: String, method: String) -> URLRequest? {
        guard isConfigured, let url = URL(string: "\(baseURL)/rest/v1/\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    static func fetchRows(_ path: String) async -> [[String: Any]] {
        guard var req = makeRequest(path: path, method: "GET") else { return [] }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows
    }

    static func insert(table: String, payload: [String: Any]) async {
        guard var req = makeRequest(path: table, method: "POST") else { return }
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - ISO8601 helpers for PostgREST timestamps
enum ISOTime {
    static func parse(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

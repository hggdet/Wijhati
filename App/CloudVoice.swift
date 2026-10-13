import Foundation
import AVFoundation
import CryptoKit
import Security

private enum CloudVoiceKeychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.hggdet.wijhati"
    private static let account = "azure-speech-subscription-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            let deleted = SecItemDelete(query as CFDictionary)
            return deleted == errSecSuccess || deleted == errSecItemNotFound
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var item = query
        item.merge(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

/// Optional Microsoft neural speech. The app contains no provider secret;
/// an optional user key is stored in Keychain. Without one, VoiceGuide uses
/// the built-in iOS speech voice. Audio is cached by (voice, text) for offline reuse.
final class CloudVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = CloudVoice()

    private struct PendingSpeech {
        let voice: String
        let text: String
        let completion: (Bool) -> Void
    }

    private var player: AVAudioPlayer?
    private var pending: [PendingSpeech] = []
    private var activeTask: Task<Void, Never>?
    private var generation = 0

    private override init() { super.init() }

    struct VoiceOption { let name: String; let label: String }
    static let voices: [VoiceOption] = [
        VoiceOption(name: "ar-IQ-BasselNeural", label: "باسل — عراقي"),
        VoiceOption(name: "ar-IQ-RanaNeural", label: "رنا — عراقية"),
        VoiceOption(name: "ar-SA-HamedNeural", label: "حامد — سعودي"),
        VoiceOption(name: "ar-SA-LailaNeural", label: "ليلى — سعودية"),
        VoiceOption(name: "ar-EG-ShakirNeural", label: "شاكر — مصري"),
        VoiceOption(name: "ar-EG-SalmaNeural", label: "سلمى — مصرية"),
        VoiceOption(name: "ar-AE-FatimaNeural", label: "فاطمة — إماراتية"),
    ]

    static var key: String {
        if let stored = CloudVoiceKeychain.load(), !stored.isEmpty { return stored }
        // Migrate a user-entered key from older builds out of UserDefaults.
        let legacy = UserDefaults.standard.string(forKey: "wijhati.azureKey") ?? ""
        guard !legacy.isEmpty else { return "" }
        if CloudVoiceKeychain.save(legacy) {
            UserDefaults.standard.removeObject(forKey: "wijhati.azureKey")
        }
        return legacy
    }

    @discardableResult
    static func storeKey(_ value: String) -> Bool {
        let success = CloudVoiceKeychain.save(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if success { UserDefaults.standard.removeObject(forKey: "wijhati.azureKey") }
        return success
    }

    static var region: String {
        let entered = UserDefaults.standard.string(forKey: "wijhati.azureRegion") ?? "eastus"
        let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "eastus" }
        let normalized = trimmed.lowercased()
        guard normalized.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { return "" }
        return normalized
    }
    static var configured: Bool { !key.isEmpty && !region.isEmpty }
    static var selectedVoice: String {
        UserDefaults.standard.string(forKey: "wijhati.azureVoice") ?? "ar-IQ-BasselNeural"
    }

    private func cacheFile(voice: String, text: String) -> URL {
        let digest = SHA256.hash(data: Data("\(voice)\n\(text)".utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wijhati-voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name + ".mp3")
    }

    private func fetch(voice: String, text: String) async -> Data? {
        let file = cacheFile(voice: voice, text: text)
        if let data = try? Data(contentsOf: file), !data.isEmpty { return data }
        let subscriptionKey = Self.key
        let serviceRegion = Self.region
        let safeVoice = Self.voices.first(where: { $0.name == voice })?.name ?? Self.voices[0].name
        guard !subscriptionKey.isEmpty,
              !serviceRegion.isEmpty,
              let url = URL(string: "https://\(serviceRegion).tts.speech.microsoft.com/cognitiveservices/v1")
        else { return nil }
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let lang = String(safeVoice.prefix(5))
        let ssml = "<speak version='1.0' xml:lang='\(lang)'><voice name='\(safeVoice)'>\(escaped)</voice></speak>"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        req.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        req.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        req.setValue("Wijhati", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(ssml.utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        try? data.write(to: file)
        return data
    }

    private func play(_ data: Data) -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(data: data)
            next.delegate = self
            next.volume = Float(UserDefaults.standard.object(forKey: "wijhati.voiceVolume") as? Double ?? 1.0)
            next.prepareToPlay()
            player = next
            if next.play() { return true }
            player = nil
            return false
        } catch {
            return false
        }
    }

    func speak(_ text: String, completion: @escaping (Bool) -> Void) {
        let item = PendingSpeech(voice: Self.selectedVoice, text: text, completion: completion)
        runOnMain { [weak self] in
            guard let self else { return }
            self.pending.append(item)
            self.playNextIfNeeded()
        }
    }

    private func playNextIfNeeded() {
        guard player?.isPlaying != true, activeTask == nil, !pending.isEmpty else { return }
        let item = pending.removeFirst()
        let token = generation
        activeTask = Task { [weak self] in
            guard let self else { return }
            let data = await self.fetch(voice: item.voice, text: item.text)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.generation == token else { return }
                self.activeTask = nil
                guard let data, self.play(data) else {
                    item.completion(false)
                    self.playNextIfNeeded()
                    return
                }
                item.completion(true)
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        playNextIfNeeded()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        playNextIfNeeded()
    }

    /// Preview a specific neural voice in the picker.
    func preview(voiceName: String) {
        stop()
        runOnMain { [weak self] in
            guard let self else { return }
            self.pending.append(PendingSpeech(voice: voiceName, text: "صوت المرشد", completion: { _ in }))
            self.playNextIfNeeded()
        }
    }

    /// Warm the cache for an instruction that will be spoken soon.
    func prefetch(_ text: String) {
        guard Self.configured else { return }
        let voice = Self.selectedVoice
        Task { _ = await fetch(voice: voice, text: text) }
    }

    func stop() {
        runOnMain { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.activeTask?.cancel()
            self.activeTask = nil
            self.pending.removeAll()
            self.player?.stop()
            self.player = nil
        }
    }

    private func runOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread { action() }
        else { DispatchQueue.main.async(execute: action) }
    }
}

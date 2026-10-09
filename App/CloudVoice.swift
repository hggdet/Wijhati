import Foundation
import AVFoundation
import CryptoKit

/// Real human neural voices from Microsoft Azure Speech — including
/// genuine Iraqi voices (Bassel & Rana). Uses the user's own free
/// Azure key (Settings ← voice picker); without a key the app falls
/// back to the device voice. Audio is cached on disk per (voice,
/// text), so repeated instructions play instantly and even offline.
final class CloudVoice {
    static let shared = CloudVoice()
    private var player: AVAudioPlayer?

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

    // Built-in default credentials so the Iraqi voices work out of
    // the box with zero setup. The key is stored lightly masked (not
    // plain text) and a user-entered key in Settings overrides it.
    // If the free quota is ever drained or the key leaks, regenerate
    // it in the Azure portal and ship an update.
    private static let maskedDefaultKey = "eN6mbppOQvdp34MOkkQwjkDhgzSLMWz5Q+GBJYY9Z/x7x5cP1QBH4UnLggSkDV/cQ/i+G6gmWfwDqIcXozRR03j7ggWoRH+Fe9CFBKM0R/FDp6o8"
    private static let maskBytes: [UInt8] = [0x3A, 0x91, 0xC4, 0x5D, 0xE2, 0x77, 0x08, 0xB6]
    static var defaultKey: String {
        guard let data = Data(base64Encoded: maskedDefaultKey), !data.isEmpty else { return "" }
        let bytes = data.enumerated().map { $0.element ^ maskBytes[$0.offset % maskBytes.count] }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    static var key: String {
        let entered = UserDefaults.standard.string(forKey: "wijhati.azureKey") ?? ""
        return entered.isEmpty ? defaultKey : entered
    }
    static var region: String {
        let entered = UserDefaults.standard.string(forKey: "wijhati.azureRegion") ?? ""
        return entered.isEmpty ? "eastus" : entered
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
        guard Self.configured,
              let url = URL(string: "https://\(Self.region).tts.speech.microsoft.com/cognitiveservices/v1")
        else { return nil }
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let lang = String(voice.prefix(5))
        let ssml = "<speak version='1.0' xml:lang='\(lang)'><voice name='\(voice)'>\(escaped)</voice></speak>"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue(Self.key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        req.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        req.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        req.setValue("Wijhati", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(ssml.utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        try? data.write(to: file)
        return data
    }

    private func play(_ data: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let p = try AVAudioPlayer(data: data)
            p.volume = Float(UserDefaults.standard.object(forKey: "wijhati.voiceVolume") as? Double ?? 1.0)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            // silent — the caller keeps the device voice as fallback
        }
    }

    /// Speak via the cloud voice; completion(false) means the caller
    /// should fall back to the device voice.
    func speak(_ text: String, completion: @escaping (Bool) -> Void) {
        let voice = Self.selectedVoice
        Task {
            guard let data = await fetch(voice: voice, text: text) else {
                completion(false)
                return
            }
            await MainActor.run {
                self.play(data)
                completion(true)
            }
        }
    }

    /// Preview a specific voice (voice-picker rows).
    func preview(voiceName: String) {
        stop()
        Task {
            guard let data = await fetch(voice: voiceName, text: "صوت المرشد") else { return }
            await MainActor.run { self.play(data) }
        }
    }

    /// Warm the cache for an instruction that will be spoken soon.
    func prefetch(_ text: String) {
        guard Self.configured else { return }
        let voice = Self.selectedVoice
        Task { _ = await fetch(voice: voice, text: text) }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

import Foundation
import AVFoundation
import UIKit
import CoreLocation

/// Offline Arabic voice + haptic guidance that walks a route's steps
/// using live GPS — no need to look at the screen.
final class VoiceGuide: ObservableObject {
    @Published var active = false
    @Published var currentInstruction = ""
    @Published var distanceToNext: Double = 0
    @Published var arrived = false

    private let synth = AVSpeechSynthesizer()
    private var steps: [StepData] = []
    private var destination: CLLocationCoordinate2D?
    private var nextIndex = 0
    private var announcedApproach = false
    private var offRouteCount = 0

    func start(steps: [StepData], destination: CLLocationCoordinate2D) {
        let filtered = steps.filter { $0.distance > 0 }
        self.steps = filtered.isEmpty ? steps : filtered
        self.destination = destination
        nextIndex = 0
        announcedApproach = false
        arrived = false
        active = true
        speak("بدأت الملاحة بالجيب. حطّ الهاتف بجيبك واسمع الإرشادات.")
        if let first = self.steps.first {
            currentInstruction = first.instruction
            speak("بعد \(formatDistance(first.distance)): \(first.instruction)")
        }
    }

    /// One-off spoken alert (proximity warnings, report confirmations).
    func announce(_ text: String) {
        speak(text)
        vibrate(pattern: [0, 80, 60, 80])
    }

    /// Coordinate the user is currently being guided toward (AR view target).
    var nextTargetCoordinate: CLLocationCoordinate2D? {
        if nextIndex < steps.count { return steps[nextIndex].coordinate }
        return destination
    }

    func stop() {
        active = false
        synth.stopSpeaking(at: .immediate)
    }

    func update(userLocation: CLLocation) {
        guard active, !arrived else { return }
        if let dest = destination {
            let d = userLocation.distance(from: CLLocation(coordinate: dest))
            if d < 25 {
                arrived = true
                currentInstruction = "وصلت إلى وجهتك"
                speak("وصلت إلى وجهتك. مبروك!")
                vibrate(pattern: [0, 400, 120, 400])
                return
            }
        }
        guard nextIndex < steps.count else { return }
        let step = steps[nextIndex]
        let target = CLLocation(coordinate: step.coordinate)
        let dist = userLocation.distance(from: target)
        distanceToNext = dist

        if dist < 120 && !announcedApproach {
            announcedApproach = true
            currentInstruction = step.instruction
            speak("بعد \(formatDistance(max(dist, 20))): \(step.instruction)")
            vibrateFor(step.instruction)
        }
        if dist < 30 {
            speak(step.instruction)
            vibrateFor(step.instruction)
            nextIndex += 1
            announcedApproach = false
            if nextIndex < steps.count {
                currentInstruction = steps[nextIndex].instruction
            }
        }
        if dist > 400 {
            offRouteCount += 1
            if offRouteCount == 6 {
                speak("يبدو أنك بعيد عن المسار. ارجع للمسار بالخريطة.")
                vibrate(pattern: [0, 120, 80, 120, 80, 120])
            }
        } else {
            offRouteCount = 0
        }
    }

    /// The most human-sounding Arabic voice installed on the device:
    /// premium > enhanced > default. Users can download an enhanced
    /// Arabic voice in iOS Settings for an even more natural sound.
    /// Arabic voices installed on the device, best quality first — the
    /// user picks one in Settings (stored as wijhati.voiceID).
    static var arabicVoiceInfos: [(id: String, name: String, language: String, quality: Int)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ar") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .map { (id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue) }
    }

    // MARK: - Voice styles
    // The phone may carry only one Arabic voice, so on top of it the user
    // gets four "personas" (pitch + rate characters). The default changed
    // from the flat natural read to the deeper, calmer one.
    struct VoiceStyle {
        var id: String
        var name: String
        var pitch: Float
        var rate: Float
    }
    static let styles: [VoiceStyle] = [
        VoiceStyle(id: "calm", name: "هادئ", pitch: 0.93, rate: 0.45),
        VoiceStyle(id: "natural", name: "طبيعي", pitch: 1.0, rate: 0.47),
        VoiceStyle(id: "clear", name: "واضح", pitch: 1.06, rate: 0.44),
        VoiceStyle(id: "lively", name: "نشيط", pitch: 1.13, rate: 0.50),
    ]
    static var selectedStyle: VoiceStyle {
        let id = UserDefaults.standard.string(forKey: "wijhati.voiceStyle") ?? "calm"
        return styles.first { $0.id == id } ?? styles[0]
    }

    static var selectedVoice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: "wijhati.voiceID"),
           let voice = AVSpeechSynthesisVoice(identifier: id) { return voice }
        return bestArabicVoice
    }

    /// Speak a short sample in the given voice (voice-picker preview).
    func preview(voiceID: String) {
        synth.stopSpeaking(at: .immediate)
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID) else { return }
        let style = Self.selectedStyle
        let utterance = AVSpeechUtterance(string: "صوت المرشد")
        utterance.voice = voice
        utterance.rate = style.rate
        utterance.pitchMultiplier = style.pitch
        utterance.volume = Float(UserDefaults.standard.object(forKey: "wijhati.voiceVolume") as? Double ?? 1.0)
        synth.speak(utterance)
    }

    /// Speak a short sample in the given style (style-picker preview).
    func previewStyle(_ style: VoiceStyle) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "صوت المرشد")
        utterance.voice = Self.selectedVoice
        utterance.rate = style.rate
        utterance.pitchMultiplier = style.pitch
        utterance.volume = Float(UserDefaults.standard.object(forKey: "wijhati.voiceVolume") as? Double ?? 1.0)
        synth.speak(utterance)
    }

    private static let bestArabicVoice: AVSpeechSynthesisVoice? = {
        let arabic = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ar") }
        return arabic.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "ar-SA")
    }()

    private func speak(_ text: String) {
        let style = Self.selectedStyle
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.selectedVoice
        utterance.rate = style.rate
        utterance.pitchMultiplier = style.pitch
        utterance.volume = Float(UserDefaults.standard.object(forKey: "wijhati.voiceVolume") as? Double ?? 1.0)
        synth.speak(utterance)
    }

    private func vibrateFor(_ instruction: String) {
        if instruction.contains("يسار") {
            vibrate(pattern: [0, 90, 70, 90])
        } else if instruction.contains("يمين") {
            vibrate(pattern: [0, 90, 70, 90, 70, 90])
        } else {
            vibrate(pattern: [0, 130])
        }
    }

    private func vibrate(pattern: [Int]) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        var delay: Double = 0
        var toggle = false
        for value in pattern {
            if toggle {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    generator.notificationOccurred(.warning)
                }
            }
            delay += Double(value) / 1000.0
            toggle.toggle()
        }
    }
}

extension CLLocation {
    convenience init(coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

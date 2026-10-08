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
    private static let bestArabicVoice: AVSpeechSynthesisVoice? = {
        let arabic = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ar") }
        return arabic.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "ar-SA")
    }()

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestArabicVoice
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.0
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

import Foundation
import AVFoundation
import CoreLocation
import MapKit
import UIKit

/// Pocket navigation: Arabic voice + haptic patterns, minimal screen.
final class VoiceGuide: ObservableObject {
    @Published var active: Bool = false
    @Published var currentInstruction: String = ""
    @Published var distanceToNext: Double = 0

    private let synth = AVSpeechSynthesizer()
    private var steps: [MKRoute.Step] = []
    private var stepIndex: Int = 0
    private var announcedMilestones: Set<String> = []

    func start(route: MKRoute) {
        steps = route.steps.filter { !$0.instructions.isEmpty }
        stepIndex = 0
        announcedMilestones = []
        active = true
        if let first = steps.first {
            currentInstruction = first.instructions
            speak("بدأت الملاحة. \(first.instructions)")
        }
    }

    func stop() {
        active = false
        synth.stopSpeaking(at: .immediate)
        steps = []
    }

    func update(location: CLLocation) {
        guard active, stepIndex < steps.count else { return }
        let step = steps[stepIndex]
        let target = CLLocation(latitude: step.polyline.coordinate.latitude,
                                longitude: step.polyline.coordinate.longitude)
        let d = location.distance(from: target)
        distanceToNext = d

        let milestone: Int
        if d > 400 { milestone = 400 }
        else if d > 150 { milestone = 150 }
        else if d > 60 { milestone = 60 }
        else { milestone = 0 }

        let key = "\(stepIndex)-\(milestone)"
        if milestone > 0, !announcedMilestones.contains(key) {
            announcedMilestones.insert(key)
            speak("بعد \(formatDistance(d))، \(step.instructions)")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        if d <= 35 {
            let generator = UINotificationFeedbackGenerator()
            if step.instructions.contains("يمين") || step.instructions.contains("right") {
                generator.notificationOccurred(.success)
            } else if step.instructions.contains("يسار") || step.instructions.contains("left") {
                generator.notificationOccurred(.error)
            } else {
                generator.notificationOccurred(.warning)
            }
            stepIndex += 1
            if stepIndex < steps.count {
                currentInstruction = steps[stepIndex].instructions
            } else {
                speak("وصلت إلى وجهتك. أحسنت!")
                let long = UIImpactFeedbackGenerator(style: .heavy)
                long.impactOccurred(intensity: 1.0)
                stop()
            }
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ar-SA")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }
}

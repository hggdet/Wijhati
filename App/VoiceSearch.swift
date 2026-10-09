import Foundation
import Speech
import AVFoundation

/// Arabic voice search for the search overlay: tap the mic, say a place
/// name, and the transcript streams into the search field live. Iraqi
/// locale first, Saudi as fallback (they share the same recognizer
/// family). Any denial or failure simply does nothing.
final class VoiceSearch: ObservableObject {
    @Published var isListening = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-IQ"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))

    func toggle(onText: @escaping (String) -> Void) {
        if isListening { stop(); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                guard ok else { return }
                DispatchQueue.main.async { self?.start(onText: onText) }
            }
        }
    }

    private func start(onText: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable, !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isListening = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                if let result {
                    onText(result.bestTranscription.formattedString)
                    if result.isFinal { self?.stop() }
                }
                if error != nil { self?.stop() }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if isListening { isListening = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

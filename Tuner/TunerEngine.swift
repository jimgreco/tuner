import AVFoundation
import QuartzCore

/// The tap retains recent audio while one analysis is in flight. Slow processing
/// drops intermediate windows instead of building a queue of increasingly old notes.
final class AudioAnalysisState {
    struct Batch {
        let samples: [Float]
        let signal: SignalSnapshot
        let tuning: TuningPreset
        let generation: Int
        let receivedAt: TimeInterval
    }

    private let lock = NSLock()
    private var tuning = TuningMath.standardPreset
    private var rollingSamples: [Float] = []
    private var runID = UUID()
    private var generation = 0
    private var busy = false

    func reset(runID: UUID, tuning: TuningPreset) {
        lock.lock()
        defer { lock.unlock() }
        self.runID = runID
        self.tuning = tuning
        generation += 1
        rollingSamples.removeAll(keepingCapacity: true)
    }

    func setTuning(_ tuning: TuningPreset) {
        lock.lock()
        defer { lock.unlock() }
        self.tuning = tuning
        generation += 1
        rollingSamples.removeAll(keepingCapacity: true)
    }

    func append(_ samples: [Float], sampleRate: Double, runID: UUID, at time: TimeInterval) -> Batch? {
        lock.lock()
        defer { lock.unlock() }
        guard self.runID == runID else { return nil }
        rollingSamples.append(contentsOf: samples)
        let maxCount = Int(sampleRate * 0.19)
        if rollingSamples.count > maxCount {
            rollingSamples.removeFirst(rollingSamples.count - maxCount)
        }
        guard !busy else { return nil }
        busy = true
        return Batch(samples: rollingSamples,
                     signal: TuningMath.signalSnapshot(samples: samples, sampleRate: sampleRate),
                     tuning: tuning, generation: generation, receivedAt: time)
    }

    func isCurrent(_ batch: Batch) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return batch.generation == generation
    }

    func complete() {
        lock.lock()
        busy = false
        lock.unlock()
    }
}

@MainActor
final class TunerEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var selectedTuning = TuningMath.standardPreset
    @Published private(set) var reading: TuningReading?
    @Published private(set) var stableStringID: String?
    @Published private(set) var stableProgress = 0.0
    @Published private(set) var isHoldingReading = false
    @Published private(set) var signal = SignalSnapshot(volume: 0, sampleRate: 0)

    private var engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "com.jgreco.tuner.analysis", qos: .userInitiated)
    private let analysisState = AudioAnalysisState()
    private var tracker = TuningTracker()
    private var runID = UUID()
    private var hasTap = false
    private var wantsListening = false
    private var isForeground = true
    private var isInterrupted = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.isInterrupted = true
                    self.stopAudio()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    self.isInterrupted = false
                    if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        await self.resumeIfNeeded()
                    } else if self.wantsListening {
                        self.state = .failed("Microphone interrupted. Tap the microphone to resume.")
                    }
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            // Category changes caused by our own setup must not trigger restart loops.
            guard let reason, [AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
                               AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                               AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue].contains(reason) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                self.stopAudio()
                await self.resumeIfNeeded()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasTap = false
                self.engine = AVAudioEngine()
                self.stopAudio()
                self.wantsListening = false
                self.state = .failed("Audio was reset. Tap the microphone to resume.")
            }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    var isListening: Bool { state == .listening }

    func toggleListening() async {
        if isListening || state == .requestingPermission { stop() } else { await start() }
    }

    func startIfNeeded() async {
        guard state == .idle else { return }
        await start()
    }

    func setForeground(_ foreground: Bool) async {
        isForeground = foreground
        if foreground { await resumeIfNeeded() } else { stopAudio() }
    }

    private func resumeIfNeeded() async {
        guard wantsListening, isForeground, !isInterrupted else { return }
        await start()
    }

    func start() async {
        wantsListening = true
        guard isForeground, !isInterrupted,
              state != .listening, state != .requestingPermission else { return }
        runID = UUID()
        let requestID = runID
        state = .requestingPermission
        let granted = await requestMicrophoneAccess()
        // Permission can finish after the user leaves the app or presses pause.
        guard runID == requestID, wantsListening, isForeground else { return }
        guard granted else {
            state = .failed("Allow microphone access in Settings to tune your guitar.")
            return
        }
        do {
            try configureAudioSession()
            try startEngine()
            state = .listening
        } catch {
            stopAudio()
            state = .failed("Could not start the microphone. Tap to try again.")
        }
    }

    func stop() {
        wantsListening = false
        stopAudio()
    }

    private func stopAudio() {
        runID = UUID()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        analysisState.reset(runID: runID, tuning: selectedTuning)
        tracker = TuningTracker()
        publishTracker()
        signal = SignalSnapshot(volume: 0, sampleRate: 0)
        state = .idle
    }

    func resetLock() {
        tracker.resetLock()
        publishTracker()
    }

    func selectTuning(id: String) {
        guard let tuning = TuningMath.presets.first(where: { $0.id == id }),
              tuning.id != selectedTuning.id else { return }
        selectedTuning = tuning
        analysisState.setTuning(tuning)
        tracker = TuningTracker()
        publishTracker()
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default: return false
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        // Prefer the phone microphone over a headset's speech-processed input.
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtIn)
        }
        try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
    }

    private func startEngine() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "TunerAudio", code: 1)
        }
        let queue = analysisQueue
        let analysisState = analysisState
        let runID = runID
        analysisState.reset(runID: runID, tuning: selectedTuning)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            let sampleRate = buffer.format.sampleRate
            guard let batch = analysisState.append(samples, sampleRate: sampleRate, runID: runID, at: CACurrentMediaTime()) else { return }
            queue.async { [weak self] in
                // Silence pauses confirmation instead of re-analyzing the old ringing string.
                let reading = batch.signal.volume >= 0.0015
                    ? TuningMath.reading(from: batch.samples, sampleRate: sampleRate, tuning: batch.tuning) : nil
                Task { @MainActor [weak self] in
                    defer { analysisState.complete() }
                    guard let self, self.isListening, analysisState.isCurrent(batch) else { return }
                    let now = CACurrentMediaTime()
                    self.signal = batch.signal
                    self.tracker.update(now - batch.receivedAt < 0.25 ? reading : nil, at: now)
                    self.publishTracker()
                }
            }
        }
        hasTap = true
        engine.prepare()
        try engine.start()
    }

    private func publishTracker() {
        reading = tracker.reading
        stableStringID = tracker.stableStringID
        stableProgress = tracker.stableProgress
        isHoldingReading = tracker.isHoldingReading
    }
}

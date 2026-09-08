import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var engine = TunerEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var lockedStringIDs = Set<String>()

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.12)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        tuningPicker
                        errorBanner
                        TuningStageView(
                            statusText: directionText,
                            isHoldingReading: engine.isHoldingReading,
                            strings: engine.selectedTuning.strings,
                            reading: engine.reading,
                            stableStringID: engine.stableStringID,
                            stableProgress: engine.stableProgress,
                            lockedStringIDs: lockedStringIDs,
                            resetLock: resetLock(for:),
                            clearAllLocks: clearAllLocks
                        )
                        .frame(height: max(620, proxy.size.height - 190))

                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            await engine.startIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .background { await engine.setForeground(false) }
                if phase == .active { await engine.setForeground(true) }
            }
        }
        .onChange(of: engine.selectedTuning.id) { _, _ in
            clearAllLocks()
        }
        .onChange(of: engine.stableStringID) { _, stableStringID in
            guard let stableStringID else {
                return
            }

            var didInsert = false
            withAnimation(.snappy(duration: 0.22)) {
                didInsert = lockedStringIDs.insert(stableStringID).inserted
            }

            if didInsert {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                (
                    Text("guitar")
                        .foregroundStyle(.white)
                    + Text(" tuner")
                        .foregroundStyle(Color.tunerGreen)
                )
                .font(.system(size: 38, weight: .black, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Guitar 6-string")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.black))
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))

                    Text(engine.selectedTuning.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    Task { await engine.toggleListening() }
                } label: {
                    AutoStatusPill(volume: engine.signal.volume, isListening: engine.isListening)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isListening ? "Pause microphone" : "Start microphone")
                .accessibilityIdentifier("microphoneToggle")
            }
        }
    }

    private var errorBanner: some View {
        Group {
            if case .failed(let message) = engine.state {
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                    if AVAudioApplication.shared.recordPermission == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.62, blue: 0.52))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(red: 0.72, green: 0.27, blue: 0.22).opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var tuningPicker: some View {
        HStack(spacing: 4) {
            ForEach(TuningMath.presets) { preset in
                Button {
                    engine.selectTuning(id: preset.id)
                } label: {
                    Text(preset.shortName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(preset.id == engine.selectedTuning.id ? Color(red: 0.08, green: 0.11, blue: 0.10) : Color.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            Capsule()
                                .fill(preset.id == engine.selectedTuning.id ? Color.tunerGreen : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.name) tuning")
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var topSignalBar: some View {
        SignalLevelBar(volume: engine.signal.volume, isListening: engine.isListening)
            .padding(12)
            .background(Color.white.opacity(0.54))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var readout: some View {
        VStack(spacing: 14) {
            ClipOnTunerReadout(
                note: engine.reading.map { displayNote(for: $0.string) } ?? "--",
                stringLabel: engine.reading?.string.label ?? "Waiting",
                cents: engine.reading?.cents,
                frequency: engine.reading?.frequency,
                statusText: directionText,
                isStable: engine.stableStringID != nil
            )

            VStack(spacing: 6) {
                HStack {
                    Text("Stable lock")
                    Spacer()
                    Text("\(Int((engine.stableProgress * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

                ProgressView(value: engine.stableProgress)
                    .tint(Color(red: 0.21, green: 0.70, blue: 0.42))
            }

            if case .failed(let message) = engine.state {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.18, blue: 0.14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(red: 0.72, green: 0.27, blue: 0.22).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var signalGrid: some View {
        VStack(spacing: 10) {
            SignalLevelBar(volume: engine.signal.volume, isListening: engine.isListening)

            HStack(spacing: 10) {
                SignalTile(
                    icon: "waveform",
                    label: "Input",
                    value: inputLevelText
                )
                SignalTile(
                    icon: "gauge.with.dots.needle.67percent",
                    label: "Frequency",
                    value: engine.reading.map { String(format: "%.1f Hz", $0.frequency) } ?? "--"
                )
                SignalTile(
                    icon: "bolt.fill",
                    label: "Clarity",
                    value: engine.reading.map { "\(Int(($0.clarity * 100).rounded()))%" } ?? "--"
                )
            }
        }
    }

    private var inputLevelText: String {
        guard engine.isListening else {
            return "--"
        }

        return "\(Int(inputLevelPercent.rounded()))%"
    }

    private var inputLevelPercent: Double {
        min(100, max(0, sqrt(engine.signal.volume) * 260))
    }

    private var stringTargets: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(lockedStringIDs.count)/\(engine.selectedTuning.strings.count) locked")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    clearAllLocks()
                } label: {
                    Label("Clear All", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .disabled(lockedStringIDs.isEmpty)
                .opacity(lockedStringIDs.isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 2)

            ForEach(engine.selectedTuning.strings) { string in
                StringTargetRow(
                    string: string,
                    reading: engine.reading,
                    isStable: lockedStringIDs.contains(string.id)
                )
            }
        }
    }

    private var directionText: String {
        guard let reading = engine.reading else {
            if engine.isListening {
                return engine.signal.volume >= 0.003 ? "Finding pitch" : "Listening"
            }

            switch engine.state {
            case .idle:
                return "Microphone paused"
            case .requestingPermission:
                return "Waiting for access"
            case .failed:
                return "Microphone unavailable"
            case .listening:
                return "Listening"
            }
        }

        if engine.stableStringID != nil {
            return "\(reading.string.label) in tune"
        }

        if engine.isHoldingReading { return "Pluck again to continue" }

        if reading.cents < -TuningMath.centTolerance {
            return "Tune up"
        }

        if reading.cents > TuningMath.centTolerance {
            return "Tune down"
        }

        return "In tune · let it settle"
    }

    private func displayNote(for string: GuitarString) -> String {
        string.number == 1 ? string.note.lowercased() : string.note
    }

    private func resetLock(for string: GuitarString) {
        if engine.stableStringID == string.id { engine.resetLock() }
        withAnimation(.snappy(duration: 0.20)) {
            _ = lockedStringIDs.remove(string.id)
        }
    }

    private func clearAllLocks() {
        engine.resetLock()
        withAnimation(.snappy(duration: 0.20)) {
            lockedStringIDs.removeAll()
        }
    }
}

private struct AutoStatusPill: View {
    let volume: Double
    let isListening: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("AUTO")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.78))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isListening ? Color.tunerGreen : Color.white.opacity(0.18))

                Circle()
                    .fill(.white)
                    .frame(width: 32, height: 32)
                    .padding(3)
                    .frame(maxWidth: .infinity, alignment: isListening ? .trailing : .leading)
            }
            .frame(width: 68, height: 38)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .overlay(alignment: .bottomTrailing) {
            SignalPulse(volume: volume, isListening: isListening)
                .offset(y: 13)
        }
    }
}

private struct SignalPulse: View {
    let volume: Double
    let isListening: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(isListening ? Color.tunerGreen.opacity(0.35 + Double(index) * 0.13) : Color.white.opacity(0.16))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isListening else {
            return 5 + CGFloat(index) * 3
        }

        let level = min(1.0, max(0.0, sqrt(volume) * 2.6))
        return 5 + CGFloat(index + 1) * 4 + CGFloat(level) * CGFloat(index + 1) * 4
    }
}

struct TuningStageView: View {
    let statusText: String
    let isHoldingReading: Bool
    let strings: [GuitarString]
    let reading: TuningReading?
    let stableStringID: String?
    let stableProgress: Double
    let lockedStringIDs: Set<String>
    let resetLock: (GuitarString) -> Void
    let clearAllLocks: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let centerX = width / 2
            let markerY = height * 0.21
            let noteY = height * 0.34
            let guitarHeight = height * 0.74

            ZStack {
                TunerGridBackground()

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tunerGreen.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.tunerGreen.opacity(0.25), lineWidth: 1))
                    .frame(width: min(width * 0.34, 126) * CGFloat(TuningMath.centTolerance / 50) * 2,
                           height: height * 0.30)
                    .position(x: centerX, y: height * 0.32)
                    .accessibilityHidden(true)

                Text("±\(Int(TuningMath.centTolerance)) cents")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.tunerGreen.opacity(0.85))
                    .position(x: centerX, y: height * 0.135)

                VStack(spacing: 5) {
                    Text(statusText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(isHoldingReading ? "Last reading · pluck again" : (reading.map { String(format: "%@ · %.1f Hz", $0.string.label, $0.frequency) } ?? "Pluck one open string at a time"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
                .accessibilityIdentifier("tuningStatus")

                Path { path in
                    path.move(to: CGPoint(x: centerX, y: height * 0.18))
                    path.addLine(to: CGPoint(x: centerX, y: height))
                }
                .stroke(Color.tunerGreen.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                FlatSharpLabels()
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, height * 0.22)

                LockProgressBadge(isStable: stableStringID != nil, isInTune: reading?.isInTune == true, progress: stableProgress)
                    .position(x: centerX, y: markerY)

                CurrentNoteBubble(
                    note: currentNote,
                    cents: reading?.cents,
                    isStable: stableStringID != nil,
                    isInTune: reading?.isInTune == true
                )
                .position(x: pitchX(centerX: centerX, width: width), y: noteY)

                GuitarView(
                    strings: strings,
                    reading: reading,
                    lockedStringIDs: lockedStringIDs,
                    resetLock: resetLock
                )
                .frame(height: guitarHeight)
                .position(x: centerX, y: height * 0.78)

                startOverButton
                    .position(x: centerX, y: height * 0.84)
            }
            .clipped()
            .accessibilityElement(children: .contain)
        }
    }

    private var startOverButton: some View {
        Button {
            clearAllLocks()
        } label: {
            Text("Start over")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.08, green: 0.12, blue: 0.11))
                .frame(width: 178, height: 58)
                .background(Color.tunerGreen)
                .clipShape(Capsule())
                .shadow(color: Color.tunerGreen.opacity(0.28), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear all locked strings")
    }

    private var currentNote: String {
        guard let string = reading?.string else {
            return "--"
        }

        return string.number == 1 ? string.note.lowercased() : string.note
    }

    private func pitchX(centerX: CGFloat, width: CGFloat) -> CGFloat {
        guard let cents = reading?.cents else {
            return centerX
        }

        let clampedCents = min(50.0, max(-50.0, cents))
        let maxOffset = min(width * 0.34, 126)
        return centerX + CGFloat(clampedCents / 50.0) * maxOffset
    }
}

private struct TunerGridBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let minor: CGFloat = 24
            let major: CGFloat = 72

            ZStack {
                Color(red: 0.10, green: 0.11, blue: 0.12)

                Path { path in
                    for x in stride(from: 0, through: width, by: minor) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }

                    for y in stride(from: 0, through: height, by: minor) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.035), lineWidth: 1)

                Path { path in
                    for x in stride(from: 0, through: width, by: major) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }

                    for y in stride(from: 0, through: height, by: major) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.055), lineWidth: 1)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.clear,
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

private struct FlatSharpLabels: View {
    var body: some View {
        HStack {
            Text("♭")
            Spacer()
            Text("#")
        }
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.64))
    }
}

private struct LockProgressBadge: View {
    let isStable: Bool
    let isInTune: Bool
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.12, green: 0.13, blue: 0.15))
                .frame(width: 70, height: 70)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 5)
                )

            Circle()
                .trim(from: 0, to: max(0.0, min(1.0, progress)))
                .stroke(Color.tunerGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(-90))

            Image(systemName: isStable ? "checkmark" : "waveform")
                .font(.system(size: isStable ? 30 : 22, weight: .bold))
                .foregroundStyle(isStable || isInTune ? Color.tunerGreen : Color.white.opacity(0.58))
        }
        .shadow(color: Color.tunerGreen.opacity(isStable ? 0.34 : 0), radius: 16)
    }
}

private struct CurrentNoteBubble: View {
    let note: String
    let cents: Double?
    let isStable: Bool
    let isInTune: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(note)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(cents.map { "\(TuningMath.signedCents($0))c" } ?? "listening")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.white.opacity(0.54))
        }
        .foregroundStyle(isStable || isInTune ? Color.tunerGreen : Color.white.opacity(cents == nil ? 0.54 : 0.88))
        .frame(width: 76, height: 76)
        .background(
            Circle()
                .fill(Color(red: 0.13, green: 0.14, blue: 0.16).opacity(0.96))
                .shadow(color: .black.opacity(0.30), radius: 12, y: 5)
        )
        .overlay(
            Circle()
                .stroke(isStable || isInTune ? Color.tunerGreen : Color.white.opacity(0.10), lineWidth: isStable || isInTune ? 3 : 2)
        )
    }
}

private struct ClipOnTunerReadout: View {
    let note: String
    let stringLabel: String
    let cents: Double?
    let frequency: Double?
    let statusText: String
    let isStable: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.095),
                            Color(red: 0.02, green: 0.02, blue: 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 58, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .padding(1)
                )
                .shadow(color: .black.opacity(0.28), radius: 20, y: 12)

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tuner")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                    Spacer()
                    Text(frequency.map { String(format: "%.1f Hz", $0) } ?? "-- Hz")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(Color(red: 0.53, green: 0.83, blue: 0.73))
                }

                VStack(spacing: 10) {
                    SegmentedTunerMeter(cents: cents, isStable: isStable)
                        .frame(height: 82)

                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusText)
                                .font(.caption.weight(.black))
                                .foregroundStyle(statusColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(cents.map { "\(TuningMath.signedCents($0)) cents" } ?? "-- cents")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(Color.white.opacity(0.64))
                        }

                        Spacer(minLength: 4)

                        Text(note)
                            .font(.system(size: 78, weight: .black, design: .rounded))
                            .foregroundStyle(noteColor)
                            .minimumScaleFactor(0.48)
                            .lineLimit(1)
                            .shadow(color: noteColor.opacity(isStable ? 0.62 : 0.25), radius: isStable ? 10 : 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stringLabel)
                                .font(.caption.weight(.black))
                                .foregroundStyle(Color(red: 0.49, green: 0.87, blue: 0.82))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(isStable ? "LOCK" : "AUTO")
                                .font(.caption2.monospaced().weight(.bold))
                                .foregroundStyle(isStable ? Color(red: 0.33, green: 0.93, blue: 0.56) : Color.white.opacity(0.54))
                        }
                        .frame(width: 58, alignment: .leading)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.01, green: 0.025, blue: 0.025),
                                    Color(red: 0.025, green: 0.045, blue: 0.040)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isStable ? Color(red: 0.25, green: 0.86, blue: 0.43).opacity(0.68) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black,
                                Color(red: 0.16, green: 0.16, blue: 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 54, height: 18)
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .padding(.top, 1)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 274)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stringLabel), \(statusText)")
    }

    private var noteColor: Color {
        if isStable {
            return Color(red: 0.32, green: 0.94, blue: 0.55)
        }

        return Color(red: 0.47, green: 0.83, blue: 0.78)
    }

    private var statusColor: Color {
        if isStable {
            return Color(red: 0.33, green: 0.93, blue: 0.56)
        }

        guard let cents else {
            return Color(red: 0.95, green: 0.77, blue: 0.28)
        }

        if abs(cents) <= TuningMath.centTolerance {
            return Color(red: 0.33, green: 0.93, blue: 0.56)
        }

        return Color(red: 0.98, green: 0.67, blue: 0.24)
    }
}

private struct SegmentedTunerMeter: View {
    let cents: Double?
    let isStable: Bool

    private let segmentCount = 23

    var body: some View {
        GeometryReader { proxy in
            let activeIndex = currentIndex

            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        let distance = abs(index - midpoint)
                        let height = proxy.size.height * (0.34 + CGFloat(midpoint - distance) / CGFloat(midpoint) * 0.44)
                        let activeDistance = activeIndex.map { abs(index - $0) } ?? 99

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(segmentColor(for: index))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(20, height))
                            .opacity(activeDistance <= 1 ? 1 : 0.34)
                            .shadow(color: segmentColor(for: index).opacity(activeDistance <= 1 ? 0.58 : 0), radius: 7)
                            .rotationEffect(.degrees(Double(index - midpoint) * 1.15), anchor: .bottom)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                HStack {
                    Text("-50")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("+50")
                }
                .font(.caption2.monospacedDigit().weight(.black))
                .foregroundStyle(Color.white.opacity(0.62))
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity, alignment: .top)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(isStable ? Color(red: 0.33, green: 0.93, blue: 0.56) : Color(red: 0.14, green: 0.42, blue: 0.96))
                    .rotationEffect(.degrees(180))
                    .position(x: needleX(in: proxy.size.width), y: proxy.size.height - 3)
                    .opacity(cents == nil ? 0.35 : 1)
            }
        }
    }

    private var midpoint: Int {
        segmentCount / 2
    }

    private var currentIndex: Int? {
        guard let cents else {
            return nil
        }

        let normalized = min(1.0, max(0.0, (cents + 50.0) / 100.0))
        return Int((normalized * Double(segmentCount - 1)).rounded())
    }

    private func needleX(in width: CGFloat) -> CGFloat {
        guard let cents else {
            return width / 2
        }

        let normalized = min(1.0, max(0.0, (cents + 50.0) / 100.0))
        return 18 + (width - 36) * normalized
    }

    private func segmentColor(for index: Int) -> Color {
        let distance = abs(index - midpoint)

        if distance <= 2 {
            return Color(red: 0.30, green: 0.86, blue: 0.48)
        }

        if distance <= 5 {
            return Color(red: 0.95, green: 0.79, blue: 0.25)
        }

        return Color(red: 0.89, green: 0.24, blue: 0.17)
    }
}

private struct SignalLevelBar: View {
    let volume: Double
    let isListening: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(isListening ? "Mic input" : "Mic idle")
                Spacer()
                Text("\(Int(levelPercent.rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let width = proxy.size.width * levelPercent / 100

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.10))

                    if width > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.21, green: 0.70, blue: 0.42),
                                        Color(red: 0.95, green: 0.76, blue: 0.31),
                                        Color(red: 0.72, green: 0.27, blue: 0.22)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: width)
                    }
                }
                .animation(.snappy(duration: 0.16), value: levelPercent)
            }
            .frame(height: 12)
        }
    }

    private var levelPercent: Double {
        guard isListening else {
            return 0
        }

        return min(100, max(0, sqrt(volume) * 260))
    }
}

private struct GuitarView: View {
    let strings: [GuitarString]
    let reading: TuningReading?
    let lockedStringIDs: Set<String>
    let resetLock: (GuitarString) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let centerX = width / 2
            let headWidth = min(width * 0.58, 238)
            let headHeight = height * 0.66
            let headY = height * 0.02
            let nutY = headY + headHeight * 0.86
            let fretboardBottom = height - 20
            let nutWidth = headWidth * 0.72
            let neckBottomWidth = min(width * 0.48, 180)

            ZStack {
                FretboardShape(
                    topWidth: nutWidth,
                    bottomWidth: neckBottomWidth,
                    topY: nutY,
                    bottomY: fretboardBottom,
                    centerX: centerX
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.09, blue: 0.045),
                            Color(red: 0.37, green: 0.20, blue: 0.11),
                            Color(red: 0.20, green: 0.10, blue: 0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                ForEach(0..<4, id: \.self) { index in
                    let progress = CGFloat(index) / 3
                    let y = nutY + 18 + progress * (fretboardBottom - nutY - 26)
                    let fretWidth = nutWidth + progress * (neckBottomWidth - nutWidth)

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color(red: 0.83, green: 0.72, blue: 0.48).opacity(0.88))
                        .frame(width: fretWidth - 12, height: 2)
                        .position(x: centerX, y: y)
                }

                HeadstockBody()
                    .frame(width: headWidth, height: headHeight)
                    .position(x: centerX, y: headY + headHeight / 2)
                    .shadow(color: .black.opacity(0.38), radius: 16, y: 9)

                ForEach([-0.18, 0.18], id: \.self) { offset in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.20))
                        .frame(width: headWidth * 0.15, height: headHeight * 0.55)
                        .position(x: centerX + headWidth * offset, y: headY + headHeight * 0.48)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.86, blue: 0.68))
                    .frame(width: nutWidth + 18, height: 12)
                    .position(x: centerX, y: nutY)

                ForEach(strings) { string in
                    let index = CGFloat(6 - string.number)
                    let nutX = centerX - nutWidth * 0.40 + index * (nutWidth * 0.80 / 5)
                    let bottomX = centerX - neckBottomWidth * 0.38 + index * (neckBottomWidth * 0.76 / 5)
                    let peg = pegAnchor(
                        for: string,
                        centerX: centerX,
                        headWidth: headWidth,
                        headY: headY,
                        headHeight: headHeight,
                        viewWidth: width
                    )
                    let isActive = reading?.string.id == string.id
                    let isLocked = lockedStringIDs.contains(string.id)

                    Path { path in
                        path.move(to: peg.post)
                        path.addLine(to: CGPoint(x: nutX, y: nutY))
                        path.addLine(to: CGPoint(x: bottomX, y: fretboardBottom))
                    }
                    .stroke(
                        stringColor(active: isActive, stable: isLocked),
                        style: StrokeStyle(lineWidth: 1.6 + string.gauge * 2.6, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(
                        color: stringColor(active: isActive, stable: isLocked).opacity(isActive || isLocked ? 0.75 : 0),
                        radius: 8
                    )

                    if isActive || isLocked {
                        Circle()
                            .fill(stringColor(active: isActive, stable: isLocked).opacity(0.18))
                            .frame(width: 62, height: 62)
                            .position(peg.badge)
                    }

                    Button {
                        resetLock(string)
                    } label: {
                        TuningPeg(side: peg.side, active: isActive, stable: isLocked)
                            .frame(width: 70, height: 40)
                            .frame(width: 84, height: 54)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset \(string.label) lock")
                        .position(peg.handle)

                    StringNoteBadge(string: string, active: isActive, stable: isLocked)
                        .position(peg.badge)
                }
            }
        }
    }

    private func pegAnchor(
        for string: GuitarString,
        centerX: CGFloat,
        headWidth: CGFloat,
        headY: CGFloat,
        headHeight: CGFloat,
        viewWidth: CGFloat
    ) -> PegAnchor {
        let isLeft = string.number >= 4
        let row: CGFloat

        switch string.number {
        case 4, 3:
            row = 0
        case 5, 2:
            row = 1
        default:
            row = 2
        }

        let y = headY + headHeight * (0.22 + row * 0.27)
        let direction: CGFloat = isLeft ? -1 : 1
        let post = CGPoint(x: centerX + direction * headWidth * 0.31, y: y)
        let handle = CGPoint(x: centerX + direction * headWidth * 0.49, y: y)
        let badgeX: CGFloat = isLeft ? 32 : viewWidth - 32

        return PegAnchor(
            post: post,
            handle: handle,
            badge: CGPoint(x: badgeX, y: y),
            side: isLeft ? .left : .right
        )
    }

    private func stringColor(active: Bool, stable: Bool) -> Color {
        if stable {
            return Color(red: 0.21, green: 0.70, blue: 0.42)
        }

        if active {
            return Color(red: 0.95, green: 0.76, blue: 0.31)
        }

        return Color(red: 0.92, green: 0.88, blue: 0.72)
    }
}

private struct PegAnchor {
    let post: CGPoint
    let handle: CGPoint
    let badge: CGPoint
    let side: PegSide
}

private enum PegSide {
    case left
    case right
}

private struct FretboardShape: Shape {
    let topWidth: CGFloat
    let bottomWidth: CGFloat
    let topY: CGFloat
    let bottomY: CGFloat
    let centerX: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centerX - topWidth / 2, y: topY))
        path.addLine(to: CGPoint(x: centerX + topWidth / 2, y: topY))
        path.addLine(to: CGPoint(x: centerX + bottomWidth / 2, y: bottomY))
        path.addLine(to: CGPoint(x: centerX - bottomWidth / 2, y: bottomY))
        path.closeSubpath()
        return path
    }
}

private struct HeadstockShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.13, y: rect.minY + rect.height * 0.26),
            control1: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.05)
        )
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY - rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY - rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.minY + rect.height * 0.26))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.05),
            control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct HeadstockBody: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                HeadstockShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.50, green: 0.25, blue: 0.11),
                                Color(red: 0.72, green: 0.39, blue: 0.18),
                                Color(red: 0.36, green: 0.16, blue: 0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ForEach(0..<10, id: \.self) { index in
                    let x = width * (0.16 + CGFloat(index) * 0.075)

                    Path { path in
                        path.move(to: CGPoint(x: x, y: height * 0.12))
                        path.addCurve(
                            to: CGPoint(x: x + CGFloat(sin(Double(index))) * 10, y: height * 0.88),
                            control1: CGPoint(x: x - 10, y: height * 0.36),
                            control2: CGPoint(x: x + 12, y: height * 0.62)
                        )
                    }
                    .stroke(Color.white.opacity(index.isMultiple(of: 2) ? 0.09 : 0.045), lineWidth: 1)
                }

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.clear,
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(HeadstockShape())
            .overlay(
                HeadstockShape()
                    .stroke(Color(red: 0.94, green: 0.89, blue: 0.78), lineWidth: 3)
            )
            .overlay(
                HeadstockShape()
                    .stroke(Color(red: 0.28, green: 0.12, blue: 0.06).opacity(0.64), lineWidth: 1)
                    .padding(5)
            )
        }
    }
}

private struct StringNoteBadge: View {
    let string: GuitarString
    let active: Bool
    let stable: Bool

    var body: some View {
        VStack(spacing: -1) {
            Text(displayLabel)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text("#\(string.number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(stable ? Color.white.opacity(0.76) : Color.white.opacity(0.46))
        }
        .foregroundStyle(stable ? .white : Color.white.opacity(0.90))
        .frame(width: 58, height: 58)
        .background(
            Circle()
                .fill(badgeFill)
                .shadow(color: badgeGlow, radius: active || stable ? 12 : 3, y: 4)
        )
        .overlay(
            Circle()
                .stroke(borderColor, lineWidth: active || stable ? 2 : 1)
        )
        .accessibilityLabel("\(string.label) string")
    }

    private var displayLabel: String {
        string.number == 1 ? string.note.lowercased() : string.note
    }

    private var badgeFill: Color {
        if stable {
            return Color(red: 0.21, green: 0.70, blue: 0.42)
        }

        if active {
            return Color(red: 0.20, green: 0.21, blue: 0.24)
        }

        return Color(red: 0.18, green: 0.19, blue: 0.22)
    }

    private var borderColor: Color {
        if stable {
            return Color(red: 0.14, green: 0.55, blue: 0.33)
        }

        if active {
            return Color.tunerGreen.opacity(0.76)
        }

        return Color.white.opacity(0.06)
    }

    private var badgeGlow: Color {
        if stable {
            return Color(red: 0.21, green: 0.70, blue: 0.42).opacity(0.36)
        }

        if active {
            return Color.tunerGreen.opacity(0.24)
        }

        return Color.black.opacity(0.20)
    }
}

private struct TuningPeg: View {
    let side: PegSide
    let active: Bool
    let stable: Bool

    var body: some View {
        HStack(spacing: 0) {
            if side == .left {
                knob
                shaft
            } else {
                shaft
                knob
            }
        }
    }

    private var shaft: some View {
        Capsule()
            .fill(metalGradient)
            .frame(width: 26, height: 8)
            .overlay(Capsule().stroke(Color.black.opacity(0.28), lineWidth: 1))
    }

    private var knob: some View {
        Capsule()
            .fill(metalGradient)
            .overlay(Capsule().stroke(outlineColor, lineWidth: active || stable ? 2 : 1))
            .frame(width: 42, height: 30)
            .shadow(color: outlineColor.opacity(active || stable ? 0.35 : 0.12), radius: active || stable ? 8 : 2, y: 2)
    }

    private var metalGradient: LinearGradient {
        LinearGradient(
            colors: [
                metalColor.opacity(0.52),
                Color.white.opacity(stable ? 0.76 : 0.88),
                metalColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var metalColor: Color {
        if stable {
            return Color.tunerGreen
        }

        if active {
            return Color(red: 0.80, green: 0.92, blue: 0.90)
        }

        return Color(red: 0.58, green: 0.64, blue: 0.62)
    }

    private var outlineColor: Color {
        if stable {
            return Color(red: 0.12, green: 0.46, blue: 0.27)
        }

        if active {
            return Color(red: 0.54, green: 0.36, blue: 0.08)
        }

        return Color.black.opacity(0.28)
    }
}

private struct MeterView: View {
    let cents: Double?
    let isStable: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("-50")
                Spacer()
                Text("0")
                Spacer()
                Text("+50")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let normalized = min(1.0, max(0.0, ((cents ?? 0) + 50.0) / 100.0))
                let x = proxy.size.width * normalized

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.72, green: 0.27, blue: 0.22),
                                    Color(red: 0.95, green: 0.76, blue: 0.31),
                                    Color(red: 0.21, green: 0.70, blue: 0.42),
                                    Color(red: 0.95, green: 0.76, blue: 0.31),
                                    Color(red: 0.72, green: 0.27, blue: 0.22)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Capsule()
                        .fill(Color.white.opacity(isStable ? 0.36 : 0.62))
                        .padding(8)

                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 2)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    Capsule()
                        .fill(Color.black)
                        .frame(width: 5, height: proxy.size.height - 12)
                        .position(x: x, y: proxy.size.height / 2)
                        .opacity(cents == nil ? 0.3 : 1)
                }
            }
            .frame(height: 54)
        }
    }
}

private struct SignalTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(Color(red: 0.15, green: 0.35, blue: 0.33))
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Text(value)
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.68)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StringTargetRow: View {
    let string: GuitarString
    let reading: TuningReading?
    let isStable: Bool

    var body: some View {
        let isActive = reading?.string.id == string.id

        HStack(spacing: 12) {
            VStack(spacing: -2) {
                Text(displayNote)
                    .font(.title2.weight(.black))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("#\(string.number)")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(isStable ? Color(red: 0.21, green: 0.70, blue: 0.42) : .black)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(string.label)
                    .font(.headline.weight(.bold))
                Text(String(format: "%.1f Hz", string.frequency))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isActive ? "\(TuningMath.signedCents(reading?.cents ?? 0))c" : "--")
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(isStable ? Color(red: 0.21, green: 0.70, blue: 0.42) : .secondary)
        }
        .padding(12)
        .background(isStable ? Color(red: 0.89, green: 0.98, blue: 0.92) : Color.white.opacity(isActive ? 0.86 : 0.64))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isStable ? Color(red: 0.21, green: 0.70, blue: 0.42) : (isActive ? Color(red: 0.95, green: 0.76, blue: 0.31) : Color.black.opacity(0.08)), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayNote: String {
        string.number == 1 ? string.note.lowercased() : string.note
    }
}

private extension Color {
    static let tunerGreen = Color(red: 0.38, green: 0.82, blue: 0.60)
}

#Preview {
    ContentView()
}

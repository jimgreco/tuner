import Foundation
import Accelerate

struct GuitarString: Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let note: String
    let octave: Int
    let label: String
    let frequency: Double
    let gauge: Double
}

struct TuningPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let strings: [GuitarString]
}

struct PitchResult: Equatable, Sendable {
    let frequency: Double
    let clarity: Double
    let volume: Double
}

struct SignalSnapshot: Equatable, Sendable {
    let volume: Double
    let sampleRate: Double
}

struct TuningReading: Equatable, Sendable {
    let frequency: Double
    let string: GuitarString
    let cents: Double
    let clarity: Double
    let volume: Double

    var isInTune: Bool {
        abs(cents) <= TuningMath.centTolerance
    }
}

enum TuningMath {
    static let centTolerance = 8.0
    static let stableDuration = 0.7
    static let lockReleaseTolerance = 12.0
    static let dropoutGrace = 0.2
    static let readingHoldDuration = 1.5

    static let standardPreset = TuningPreset(
        id: "standard",
        name: "Standard",
        shortName: "Std",
        strings: [
            makeString(number: 6, note: "E", octave: 2, label: "Low E", frequency: 82.4069, gauge: 0.96),
            makeString(number: 5, note: "A", octave: 2, label: "A", frequency: 110.0, gauge: 0.82),
            makeString(number: 4, note: "D", octave: 3, label: "D", frequency: 146.8324, gauge: 0.68),
            makeString(number: 3, note: "G", octave: 3, label: "G", frequency: 195.9977, gauge: 0.54),
            makeString(number: 2, note: "B", octave: 3, label: "B", frequency: 246.9417, gauge: 0.40),
            makeString(number: 1, note: "E", octave: 4, label: "High E", frequency: 329.6276, gauge: 0.28)
        ]
    )

    static let dropDPreset = TuningPreset(
        id: "drop-d",
        name: "Drop D",
        shortName: "Drop D",
        strings: [
            makeString(number: 6, note: "D", octave: 2, label: "Low D", frequency: shiftedFrequency(82.4069, semitones: -2), gauge: 0.96),
            standardPreset.strings[1],
            standardPreset.strings[2],
            standardPreset.strings[3],
            standardPreset.strings[4],
            standardPreset.strings[5]
        ]
    )

    static let halfStepDownPreset = TuningPreset(
        id: "half-step-down",
        name: "1/2 Step Down",
        shortName: "1/2",
        strings: [
            makeString(number: 6, note: "Eb", octave: 2, label: "Low Eb", frequency: shiftedFrequency(82.4069, semitones: -1), gauge: 0.96),
            makeString(number: 5, note: "Ab", octave: 2, label: "Ab", frequency: shiftedFrequency(110.0, semitones: -1), gauge: 0.82),
            makeString(number: 4, note: "Db", octave: 3, label: "Db", frequency: shiftedFrequency(146.8324, semitones: -1), gauge: 0.68),
            makeString(number: 3, note: "Gb", octave: 3, label: "Gb", frequency: shiftedFrequency(195.9977, semitones: -1), gauge: 0.54),
            makeString(number: 2, note: "Bb", octave: 3, label: "Bb", frequency: shiftedFrequency(246.9417, semitones: -1), gauge: 0.40),
            makeString(number: 1, note: "Eb", octave: 4, label: "High Eb", frequency: shiftedFrequency(329.6276, semitones: -1), gauge: 0.28)
        ]
    )

    static let wholeStepDownPreset = TuningPreset(
        id: "whole-step-down",
        name: "1 Step Down",
        shortName: "1 Step",
        strings: [
            makeString(number: 6, note: "D", octave: 2, label: "Low D", frequency: shiftedFrequency(82.4069, semitones: -2), gauge: 0.96),
            makeString(number: 5, note: "G", octave: 2, label: "G", frequency: shiftedFrequency(110.0, semitones: -2), gauge: 0.82),
            makeString(number: 4, note: "C", octave: 3, label: "C", frequency: shiftedFrequency(146.8324, semitones: -2), gauge: 0.68),
            makeString(number: 3, note: "F", octave: 3, label: "F", frequency: shiftedFrequency(195.9977, semitones: -2), gauge: 0.54),
            makeString(number: 2, note: "A", octave: 3, label: "A", frequency: shiftedFrequency(246.9417, semitones: -2), gauge: 0.40),
            makeString(number: 1, note: "D", octave: 4, label: "High D", frequency: shiftedFrequency(329.6276, semitones: -2), gauge: 0.28)
        ]
    )

    static let presets = [
        standardPreset,
        dropDPreset,
        halfStepDownPreset,
        wholeStepDownPreset
    ]

    static var standardStrings: [GuitarString] {
        standardPreset.strings
    }

    static func centsOff(_ frequency: Double, targetFrequency: Double) -> Double {
        1200.0 * log2(frequency / targetFrequency)
    }

    static func closestString(to frequency: Double, tuning: TuningPreset) -> (string: GuitarString, cents: Double)? {
        tuning.strings
            .map { ($0, centsOff(frequency, targetFrequency: $0.frequency)) }
            .min { abs($0.1) < abs($1.1) }
    }

    static func closestString(to frequency: Double) -> (string: GuitarString, cents: Double)? {
        closestString(to: frequency, tuning: standardPreset)
    }

    static func reading(for pitch: PitchResult, tuning: TuningPreset) -> TuningReading? {
        guard let closest = closestString(to: pitch.frequency, tuning: tuning) else {
            return nil
        }

        return TuningReading(
            frequency: pitch.frequency,
            string: closest.string,
            cents: closest.cents,
            clarity: pitch.clarity,
            volume: pitch.volume
        )
    }

    static func reading(for pitch: PitchResult) -> TuningReading? {
        reading(for: pitch, tuning: standardPreset)
    }

    static func reading(from samples: [Float], sampleRate: Double, tuning: TuningPreset) -> TuningReading? {
        guard let pitch = detectPitch(samples: samples, sampleRate: sampleRate),
              let reading = reading(for: pitch, tuning: tuning),
              abs(reading.cents) <= 250 else {
            return nil
        }
        return reading
    }

    static func signedCents(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    static func signalSnapshot(samples: [Float], sampleRate: Double) -> SignalSnapshot {
        guard samples.isEmpty == false else {
            return SignalSnapshot(volume: 0, sampleRate: sampleRate)
        }

        var sumSquares = 0.0
        for sample in samples {
            let value = Double(sample)
            sumSquares += value * value
        }

        return SignalSnapshot(
            volume: sqrt(sumSquares / Double(samples.count)),
            sampleRate: sampleRate
        )
    }

    static func detectPitch(samples: [Float], sampleRate: Double) -> PitchResult? {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              samples.count >= Int(sampleRate * 0.085),
              samples.allSatisfy({ $0.isFinite }) else {
            return nil
        }

        // Remove DC and low-pass before decimating. Pitch needs several periods,
        // not the full microphone bandwidth; this keeps analysis below a tap interval.
        let input = Array(samples.suffix(Int(sampleRate * 0.19)))
        let mean = input.reduce(0.0) { $0 + Double($1) } / Double(input.count)
        let centered = input.map { Double($0) - mean }
        let rms = sqrt(centered.reduce(0.0) { $0 + $1 * $1 } / Double(centered.count))
        guard rms >= 0.0015 else { return nil }

        let factor = max(1, Int(sampleRate / 12_000))
        let rate = sampleRate / Double(factor)
        let radius = 31
        let cutoff = min(2_500.0 / sampleRate, 0.4)
        var kernel = (-radius...radius).map { offset -> Double in
            let sinc = offset == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * Double(offset)) / (.pi * Double(offset))
            return sinc * (0.5 + 0.5 * cos(.pi * Double(offset) / Double(radius)))
        }
        let gain = kernel.reduce(0, +)
        kernel = kernel.map { $0 / gain }
        var signal: [Double] = []
        signal.reserveCapacity(centered.count / factor)
        centered.withUnsafeBufferPointer { input in
            kernel.withUnsafeBufferPointer { filter in
                guard let inputBase = input.baseAddress, let filterBase = filter.baseAddress else { return }
                for index in stride(from: radius, to: centered.count - radius, by: factor) {
                    var value = 0.0
                    vDSP_dotprD(inputBase + index - radius, 1, filterBase, 1, &value, vDSP_Length(kernel.count))
                    signal.append(value)
                }
            }
        }

        // YIN's cumulative mean normalized difference measures periodicity without
        // assuming that the loudest partial is the string's fundamental.
        // Search short periods too, so an out-of-range tone is rejected rather
        // than reported at an in-range subharmonic.
        let minLag = 2
        let maxLag = min(Int(ceil(rate / 55)), signal.count / 2 - 2)
        guard minLag < maxLag else { return nil }
        let window = signal.count - maxLag - 1
        var normalized = Array(repeating: 1.0, count: maxLag + 2)
        var total = 0.0
        signal.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for lag in 1...(maxLag + 1) {
                var difference = 0.0
                vDSP_distancesqD(base, 1, base + lag, 1, &difference, vDSP_Length(window))
                total += difference
                normalized[lag] = total > 0 ? difference * Double(lag) / total : 1
            }
        }

        func minimumScore(at lag: Int) -> Double {
            let left = normalized[lag - 1]
            let middle = normalized[lag]
            let right = normalized[lag + 1]
            let curvature = left - 2 * middle + right
            guard curvature > 0 else { return middle }
            return max(0, middle - pow(left - right, 2) / (8 * curvature))
        }

        var bestLag: Int?
        for lag in minLag...maxLag {
            guard normalized[lag] < 0.20,
                  normalized[lag] <= normalized[lag - 1],
                  normalized[lag] < normalized[lag + 1] else { continue }
            if let previous = bestLag {
                // A substantially stronger longer period resolves a weak fundamental.
                // Tiny numerical improvements at multiples must not cause octave drops.
                if minimumScore(at: lag) < minimumScore(at: previous) * 0.25,
                   minimumScore(at: previous) - minimumScore(at: lag) > 0.005 {
                    bestLag = lag
                }
            } else {
                bestLag = lag
            }
        }
        guard let lag = bestLag else { return nil }
        let previous = normalized[lag - 1]
        let current = normalized[lag]
        let next = normalized[lag + 1]
        let divisor = previous - 2 * current + next
        let shift = divisor == 0 ? 0 : max(-0.5, min(0.5, (previous - next) / (2 * divisor)))
        let frequency = rate / (Double(lag) + shift)
        guard frequency.isFinite, (55...450).contains(frequency) else { return nil }
        return PitchResult(frequency: frequency, clarity: 1 - current, volume: rms)
    }

    private static func makeString(
        number: Int,
        note: String,
        octave: Int,
        label: String,
        frequency: Double,
        gauge: Double
    ) -> GuitarString {
        GuitarString(
            id: "string-\(number)",
            number: number,
            note: note,
            octave: octave,
            label: label,
            frequency: frequency,
            gauge: gauge
        )
    }

    private static func shiftedFrequency(_ frequency: Double, semitones: Double) -> Double {
        frequency * pow(2.0, semitones / 12.0)
    }

}

/// Confirmation counts observed in-range time. Brief gaps pause progress;
/// a completed result remains readable through the string's decay.
struct TuningTracker {
    private(set) var reading: TuningReading?
    private(set) var stableStringID: String?
    private(set) var stableProgress = 0.0
    private(set) var isHoldingReading = false
    private var qualifiedDuration = 0.0
    private var previousQualifiedAt: TimeInterval?
    private var lastQualifiedAt: TimeInterval?
    private var lastReadingAt: TimeInterval?

    mutating func resetLock() {
        qualifiedDuration = 0
        previousQualifiedAt = nil
        lastQualifiedAt = nil
        stableStringID = nil
        stableProgress = 0
    }

    mutating func update(_ next: TuningReading?, at now: TimeInterval) {
        if let lastReadingAt, now - lastReadingAt > TuningMath.readingHoldDuration {
            reading = nil
            resetLock()
        }
        if stableStringID == nil, let lastQualifiedAt,
           now - lastQualifiedAt > TuningMath.dropoutGrace {
            resetLock()
        }
        guard let next else {
            // Held visuals and missing observations never advance confirmation.
            isHoldingReading = reading != nil
            previousQualifiedAt = nil
            return
        }
        isHoldingReading = false
        let previous = reading
        let elapsed = lastReadingAt.map { now - $0 } ?? .infinity
        lastReadingAt = now
        if previous?.string.id != next.string.id { resetLock() }
        var cents = next.cents
        if let previous, previous.string.id == next.string.id,
           elapsed <= TuningMath.dropoutGrace,
           abs(previous.cents - next.cents) < 45 {
            // Calm the needle near the target, while following larger adjustments quickly.
            let smoothing = abs(next.cents) < 15 ? 0.30 : 0.50
            cents = previous.cents + (next.cents - previous.cents) * smoothing
        }
        reading = TuningReading(
            frequency: next.string.frequency * pow(2, cents / 1200),
            string: next.string, cents: cents, clarity: next.clarity, volume: next.volume
        )

        if stableStringID != nil {
            // Hysteresis prevents a confirmed note flickering at the acceptance edge.
            if abs(next.cents) <= TuningMath.lockReleaseTolerance,
               abs(cents) <= TuningMath.lockReleaseTolerance { return }
            resetLock()
        }

        guard next.isInTune, abs(cents) <= TuningMath.centTolerance else {
            previousQualifiedAt = nil
            if abs(next.cents) > TuningMath.lockReleaseTolerance { resetLock() }
            return
        }
        if let previousQualifiedAt {
            qualifiedDuration += max(0, min(TuningMath.dropoutGrace, now - previousQualifiedAt))
        }
        previousQualifiedAt = now
        lastQualifiedAt = now
        stableProgress = min(1, qualifiedDuration / TuningMath.stableDuration)
        stableStringID = stableProgress >= 1 ? next.string.id : nil
    }
}

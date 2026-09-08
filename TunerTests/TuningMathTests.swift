import XCTest
import SwiftUI
@testable import Tuner

final class TuningMathTests: XCTestCase {
    func testClosestStringForStandardTuning() {
        for string in TuningMath.standardStrings {
            let closest = TuningMath.closestString(to: string.frequency)
            XCTAssertEqual(closest?.string.id, string.id)
            XCTAssertEqual(closest?.cents ?? 999, 0, accuracy: 0.01)
        }
    }

    func testCentsAreSigned() {
        let sharpA = 110.0 * pow(2.0, 12.0 / 1200.0)
        XCTAssertEqual(TuningMath.closestString(to: sharpA)?.string.number, 5)
        XCTAssertEqual(TuningMath.centsOff(sharpA, targetFrequency: 110.0), 12.0, accuracy: 0.01)
        XCTAssertEqual(TuningMath.signedCents(12.2), "+12")
        XCTAssertEqual(TuningMath.signedCents(-4.6), "-5")
    }

    func testCommonTuningPresets() {
        XCTAssertEqual(TuningMath.presets.map(\.id), ["standard", "drop-d", "half-step-down", "whole-step-down"])
        XCTAssertEqual(TuningMath.dropDPreset.strings.map(\.note), ["D", "A", "D", "G", "B", "E"])
        XCTAssertEqual(TuningMath.halfStepDownPreset.strings.map(\.note), ["Eb", "Ab", "Db", "Gb", "Bb", "Eb"])
        XCTAssertEqual(TuningMath.wholeStepDownPreset.strings.map(\.note), ["D", "G", "C", "F", "A", "D"])

        XCTAssertEqual(TuningMath.dropDPreset.strings[0].frequency, 73.416, accuracy: 0.01)
        XCTAssertEqual(TuningMath.halfStepDownPreset.strings[0].frequency, 77.782, accuracy: 0.01)
        XCTAssertEqual(TuningMath.wholeStepDownPreset.strings[5].frequency, 293.665, accuracy: 0.01)
    }

    func testPitchDetectorFindsAllOpenStrings() throws {
        let sampleRate = 44_100.0
        let count = 4096

        for string in TuningMath.standardStrings {
            let samples = sineWave(frequency: string.frequency, sampleRate: sampleRate, count: count)
            let pitch = try XCTUnwrap(TuningMath.detectPitch(samples: samples, sampleRate: sampleRate))
            let reading = try XCTUnwrap(TuningMath.reading(for: pitch, tuning: TuningMath.standardPreset))

            XCTAssertEqual(reading.string.id, string.id)
            XCTAssertEqual(reading.cents, 0, accuracy: 2.0)
        }
    }

    func testSignalSnapshotTracksQuietInput() {
        let snapshot = TuningMath.signalSnapshot(
            samples: [0.04, -0.04, 0.02, -0.02],
            sampleRate: 48_000
        )

        XCTAssertEqual(snapshot.volume, 0.0316, accuracy: 0.0001)
        XCTAssertEqual(snapshot.sampleRate, 48_000)
    }

    func testPitchDetectorHandlesQuietHarmonicString() throws {
        let sampleRate = 44_100.0
        let count = 4096
        let samples = harmonicString(
            frequency: TuningMath.standardStrings[0].frequency,
            sampleRate: sampleRate,
            count: count
        )

        let pitch = try XCTUnwrap(TuningMath.detectPitch(samples: samples, sampleRate: sampleRate))
        let reading = try XCTUnwrap(TuningMath.reading(for: pitch, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 6)
        XCTAssertEqual(reading.cents, 0, accuracy: 3.0)
    }

    func testGuitarDetectorFindsLowEWhenHarmonicsAreLouderThanFundamental() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let samples = harmonicString(
            frequency: TuningMath.standardStrings[0].frequency,
            sampleRate: sampleRate,
            count: count,
            fundamentalAmplitude: 0.012,
            secondAmplitude: 0.090,
            thirdAmplitude: 0.070,
            pickNoiseAmplitude: 0.010
        )

        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 6)
        XCTAssertEqual(reading.cents, 0, accuracy: 3.0)
    }

    func testGuitarDetectorDoesNotMistakeBForLowEHarmonic() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let samples = sineWave(
            frequency: TuningMath.standardPreset.strings[4].frequency,
            sampleRate: sampleRate,
            count: count,
            amplitude: 0.080
        )

        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 2)
        XCTAssertEqual(reading.cents, 0, accuracy: 2.0)
    }

    func testGuitarDetectorDoesNotMistakeHighEForLowEHarmonic() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let samples = harmonicString(
            frequency: TuningMath.standardPreset.strings[5].frequency,
            sampleRate: sampleRate,
            count: count,
            fundamentalAmplitude: 0.032,
            secondAmplitude: 0.070,
            thirdAmplitude: 0.045,
            pickNoiseAmplitude: 0.008
        )

        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 1)
        XCTAssertEqual(reading.cents, 0, accuracy: 2.0)
    }

    func testGuitarDetectorFindsLowEWhenFourthHarmonicIsStrong() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let samples = harmonicString(
            frequency: TuningMath.standardPreset.strings[0].frequency,
            sampleRate: sampleRate,
            count: count,
            fundamentalAmplitude: 0.010,
            secondAmplitude: 0.042,
            thirdAmplitude: 0.034,
            fourthAmplitude: 0.085,
            pickNoiseAmplitude: 0.010
        )

        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 6)
        XCTAssertEqual(reading.cents, 0, accuracy: 3.0)
    }

    func testGuitarDetectorReportsDetunedHighE() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let frequency = TuningMath.standardPreset.strings[5].frequency * pow(2.0, 11.0 / 1200.0)
        let samples = harmonicString(
            frequency: frequency,
            sampleRate: sampleRate,
            count: count,
            fundamentalAmplitude: 0.040,
            secondAmplitude: 0.060,
            thirdAmplitude: 0.034
        )

        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 1)
        XCTAssertEqual(reading.cents, 11.0, accuracy: 3.0)
    }

    func testGuitarDetectorKeepsQuietOuterStringsReadable() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let quietLowE = harmonicString(
            frequency: TuningMath.standardPreset.strings[0].frequency,
            sampleRate: sampleRate,
            count: count,
            fundamentalAmplitude: 0.006,
            secondAmplitude: 0.011,
            thirdAmplitude: 0.008,
            fourthAmplitude: 0.012,
            pickNoiseAmplitude: 0.004
        )
        let quietHighE = harmonicString(
            frequency: TuningMath.standardPreset.strings[5].frequency,
            sampleRate: sampleRate,
            count: count,
            fundamentalAmplitude: 0.007,
            secondAmplitude: 0.004,
            thirdAmplitude: 0.003,
            pickNoiseAmplitude: 0.004
        )

        let lowReading = try XCTUnwrap(TuningMath.reading(from: quietLowE, sampleRate: sampleRate, tuning: TuningMath.standardPreset))
        let highReading = try XCTUnwrap(TuningMath.reading(from: quietHighE, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(lowReading.string.number, 6)
        XCTAssertEqual(highReading.string.number, 1)
        XCTAssertEqual(lowReading.cents, 0, accuracy: 3.0)
        XCTAssertEqual(highReading.cents, 0, accuracy: 3.0)
    }

    func testGuitarDetectorReportsDetunedLowE() throws {
        let sampleRate = 44_100.0
        let count = 8192
        let frequency = TuningMath.standardStrings[0].frequency * pow(2.0, -14.0 / 1200.0)
        let samples = harmonicString(frequency: frequency, sampleRate: sampleRate, count: count)

        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: TuningMath.standardPreset))

        XCTAssertEqual(reading.string.number, 6)
        XCTAssertEqual(reading.cents, -14.0, accuracy: 3.0)
    }

    func testDetunedStringsAcrossEveryPresetAndMicrophoneRate() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            for tuning in TuningMath.presets {
                for string in tuning.strings {
                    for cents in [-180.0, -60, 0, 35, 180] {
                        let samples = harmonicString(
                            frequency: string.frequency * pow(2, cents / 1200),
                            sampleRate: sampleRate, count: 8192,
                            fundamentalAmplitude: 0.04, secondAmplitude: 0.07,
                            thirdAmplitude: 0.045
                        )
                        let context = "\(tuning.id) string \(string.number), \(cents)c at \(sampleRate)"
                        let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: sampleRate, tuning: tuning), context)
                        XCTAssertEqual(reading.string.id, string.id, context)
                        XCTAssertEqual(reading.cents, cents, accuracy: 3, context)
                    }
                }
            }
        }
    }

    func testRejectsSilenceDCNoiseAndOutOfRangeTones() {
        let rate = 48_000.0
        var seed: UInt64 = 42
        let noise: [Float] = (0..<8192).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5) * 0.1
        }
        let invalidSignals = [Array(repeating: Float.zero, count: 8192),
                              Array(repeating: Float(0.05), count: 8192), noise]
            + [50.0, 60, 440, 660, 880, 1000, 1600, 8000, 12000, 16000].map {
                sineWave(frequency: $0, sampleRate: rate, count: 8192, amplitude: 0.1)
            }
        for (index, samples) in invalidSignals.enumerated() {
            XCTAssertNil(TuningMath.reading(from: samples, sampleRate: rate, tuning: TuningMath.standardPreset), "signal \(index)")
        }
        XCTAssertNil(TuningMath.detectPitch(samples: [Float](repeating: .nan, count: 8192), sampleRate: rate))
        XCTAssertNil(TuningMath.detectPitch(samples: noise, sampleRate: .infinity))
        XCTAssertNil(TuningMath.detectPitch(samples: noise, sampleRate: 0))
    }

    func testQuietDecayingStringsWithNoiseAndDCOffset() throws {
        let rate = 48_000.0
        for string in TuningMath.standardStrings {
            var seed: UInt64 = 37
            let clean = harmonicString(frequency: string.frequency, sampleRate: rate, count: 8192,
                                       fundamentalAmplitude: 0.007, secondAmplitude: 0.012,
                                       thirdAmplitude: 0.008, fourthAmplitude: 0.006)
            let samples = clean.enumerated().map { index, sample -> Float in
                seed = seed &* 6364136223846793005 &+ 1
                let noise = (Double(seed >> 32) / Double(UInt32.max) - 0.5) * 0.004
                return Float(Double(sample) * exp(-Double(index) / rate * 5) + noise + 0.03)
            }
            let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: rate, tuning: TuningMath.standardPreset))
            XCTAssertEqual(reading.string.id, string.id)
            XCTAssertEqual(reading.cents, 0, accuracy: 3)
        }
    }

    func testWeakFundamentalWithDominantSecondHarmonic() throws {
        for string in TuningMath.standardStrings {
            let samples = harmonicString(frequency: string.frequency, sampleRate: 48_000, count: 8192,
                                         fundamentalAmplitude: 0.012, secondAmplitude: 0.09,
                                         thirdAmplitude: 0, pickNoiseAmplitude: 0)
            let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: 48_000, tuning: TuningMath.standardPreset))
            XCTAssertEqual(reading.string.id, string.id)
            XCTAssertEqual(reading.cents, 0, accuracy: 3)
        }
    }

    func testMissingFundamentalStillUsesOvertonePeriod() throws {
        for string in TuningMath.standardStrings {
            let samples = harmonicString(frequency: string.frequency, sampleRate: 48_000, count: 8192,
                                         fundamentalAmplitude: 0, secondAmplitude: 0.09, thirdAmplitude: 0.07)
            let reading = try XCTUnwrap(TuningMath.reading(from: samples, sampleRate: 48_000, tuning: TuningMath.standardPreset))
            XCTAssertEqual(reading.string.id, string.id)
            XCTAssertEqual(reading.cents, 0, accuracy: 3)
        }
    }

    private func trackerNote(cents: Double = 0, stringIndex: Int = 1) -> TuningReading {
        let string = TuningMath.standardStrings[stringIndex]
        return TuningReading(frequency: string.frequency * pow(2, cents / 1200),
                             string: string, cents: cents, clarity: 0.99, volume: 0.1)
    }

    func testWiderBandConfirmsInLessThanOneSecond() {
        for cents in [-8.0, 0, 8] {
            var tracker = TuningTracker()
            let note = trackerNote(cents: cents)
            for tick in 0...6 { tracker.update(note, at: Double(tick) * 0.1) }
            XCTAssertNil(tracker.stableStringID)
            tracker.update(note, at: 0.71)
            XCTAssertEqual(tracker.stableStringID, note.string.id)
        }
        var outside = TuningTracker()
        for tick in 0...20 { outside.update(trackerNote(cents: 9), at: Double(tick) * 0.1) }
        XCTAssertNil(outside.stableStringID, "A sustained note outside the entry band cannot confirm")
    }

    func testConfirmedNoteHoldsThroughDecayThenClears() {
        var tracker = TuningTracker()
        let note = trackerNote()
        for tick in 0...8 { tracker.update(note, at: Double(tick) * 0.1) }
        tracker.update(nil, at: 1.0)
        XCTAssertEqual(tracker.stableStringID, note.string.id)
        XCTAssertEqual(tracker.stableProgress, 1)
        XCTAssertTrue(tracker.isHoldingReading)
        tracker.update(nil, at: 2.2)
        XCTAssertNotNil(tracker.reading)
        tracker.update(nil, at: 2.31)
        XCTAssertNil(tracker.reading)
        XCTAssertNil(tracker.stableStringID)
        XCTAssertFalse(tracker.isHoldingReading)
    }

    func testShortDropoutPausesConfirmationWithoutResettingOrAdvancingIt() {
        var tracker = TuningTracker()
        let note = trackerNote()
        for tick in 0...4 { tracker.update(note, at: Double(tick) * 0.1) }
        let progress = tracker.stableProgress
        tracker.update(nil, at: 0.45)
        XCTAssertEqual(tracker.stableProgress, progress)
        tracker.update(note, at: 0.5)
        XCTAssertEqual(tracker.stableProgress, progress, "Missing time cannot count as in-tune audio")
        tracker.update(note, at: 0.6)
        tracker.update(note, at: 0.7)
        XCTAssertNil(tracker.stableStringID)
        tracker.update(note, at: 0.81)
        XCTAssertEqual(tracker.stableStringID, note.string.id)
    }

    func testLongGapsAndSilenceCannotCompleteConfirmation() {
        var tracker = TuningTracker()
        let note = trackerNote()
        for tick in 0...4 { tracker.update(note, at: Double(tick) * 0.1) }
        tracker.update(nil, at: 0.7)
        XCTAssertEqual(tracker.stableProgress, 0)
        XCTAssertNotNil(tracker.reading, "Keep the last measurement readable")
        tracker.update(nil, at: 1.0)
        XCTAssertNil(tracker.stableStringID)
        tracker.update(note, at: 1.1)
        XCTAssertEqual(tracker.stableProgress, 0)
        tracker.update(note, at: 2.0)
        XCTAssertEqual(tracker.stableProgress, 0, "A callback stall cannot advance confirmation")
    }

    func testConfirmedNoteToleratesSmallDriftButReleasesOnRealAdjustment() {
        var tracker = TuningTracker()
        for tick in 0...8 { tracker.update(trackerNote(cents: 7), at: Double(tick) * 0.1) }
        tracker.update(trackerNote(cents: 10), at: 0.9)
        XCTAssertNotNil(tracker.stableStringID)
        tracker.update(trackerNote(cents: 13), at: 1.0)
        XCTAssertNil(tracker.stableStringID, "Fresh detuning must override a held result immediately")
        XCTAssertEqual(tracker.stableProgress, 0)
    }

    func testDifferentStringAndResetImmediatelyClearConfirmation() {
        var tracker = TuningTracker()
        for tick in 0...8 { tracker.update(trackerNote(), at: Double(tick) * 0.1) }
        tracker.update(trackerNote(stringIndex: 2), at: 0.9)
        XCTAssertNil(tracker.stableStringID)
        XCTAssertEqual(tracker.stableProgress, 0)
        XCTAssertEqual(tracker.reading?.string.number, 4)
        for tick in 10...18 { tracker.update(trackerNote(stringIndex: 2), at: Double(tick) * 0.1) }
        XCTAssertNotNil(tracker.stableStringID)
        tracker.resetLock()
        XCTAssertNil(tracker.stableStringID)
        XCTAssertEqual(tracker.stableProgress, 0)
    }

    func testAudioBackpressureKeepsRecentSamplesAndInvalidatesOldWork() throws {
        let state = AudioAnalysisState()
        let run = UUID()
        state.reset(runID: run, tuning: TuningMath.standardPreset)
        let batch = try XCTUnwrap(state.append([Float](repeating: 0.1, count: 8192), sampleRate: 48_000, runID: run, at: 0))
        XCTAssertNil(state.append([Float](repeating: 0.2, count: 8192), sampleRate: 48_000, runID: run, at: 0.1))
        state.complete()
        let recent = try XCTUnwrap(state.append([0.3], sampleRate: 48_000, runID: run, at: 0.2))
        XCTAssertEqual(recent.samples.count, 9120)
        XCTAssertEqual(recent.samples.last, 0.3)
        XCTAssertEqual(recent.samples.suffix(8193).first, 0.2)
        state.setTuning(TuningMath.dropDPreset)
        XCTAssertFalse(state.isCurrent(batch))
        XCTAssertFalse(state.isCurrent(recent))
        state.complete()
        let changed = try XCTUnwrap(state.append([0.4], sampleRate: 48_000, runID: run, at: 0.3))
        XCTAssertEqual(changed.samples, [0.4])
        XCTAssertEqual(changed.tuning.id, "drop-d")
        state.reset(runID: UUID(), tuning: TuningMath.standardPreset)
        XCTAssertFalse(state.isCurrent(changed))
        state.complete()
        XCTAssertNil(state.append([0.5], sampleRate: 48_000, runID: run, at: 0.4))
    }

    private func sineWave(
        frequency: Double,
        sampleRate: Double,
        count: Int,
        amplitude: Double = 0.7
    ) -> [Float] {
        (0..<count).map { index in
            Float(sin(2.0 * Double.pi * frequency * Double(index) / sampleRate) * amplitude)
        }
    }

    private func harmonicString(
        frequency: Double,
        sampleRate: Double,
        count: Int,
        fundamentalAmplitude: Double = 0.055,
        secondAmplitude: Double = 0.025,
        thirdAmplitude: Double = 0.016,
        fourthAmplitude: Double = 0.0,
        pickNoiseAmplitude: Double = 0.008
    ) -> [Float] {
        (0..<count).map { index in
            let time = Double(index) / sampleRate
            let fundamental = sin(2.0 * Double.pi * frequency * time) * fundamentalAmplitude
            let second = sin(2.0 * Double.pi * frequency * 2.0 * time) * secondAmplitude
            let third = sin(2.0 * Double.pi * frequency * 3.0 * time) * thirdAmplitude
            let fourth = sin(2.0 * Double.pi * frequency * 4.0 * time) * fourthAmplitude
            let pickNoise = index < 96 ? (Double(96 - index) / 96.0) * pickNoiseAmplitude : 0

            return Float(fundamental + second + third + fourth + pickNoise)
        }
    }
}


final class TuningFeedbackSnapshots: XCTestCase {
    @MainActor
    func testFeedbackStatesRender() throws {
        let string = TuningMath.standardStrings[1]
        for (name, cents, confirmed, holding) in [
            ("within-target", 6.0, false, false),
            ("confirmed-held", 6.0, true, true),
            ("tune-down", 18.0, false, false)
        ] {
            let reading = TuningReading(frequency: string.frequency * pow(2, cents / 1200),
                                        string: string, cents: cents, clarity: 0.99, volume: 0.1)
            let view = TuningStageView(
                statusText: confirmed ? "A in tune" : (cents <= 8 ? "In tune · let it settle" : "Tune down"),
                isHoldingReading: holding,
                strings: TuningMath.standardStrings, reading: reading,
                stableStringID: confirmed ? string.id : nil, stableProgress: confirmed ? 1 : 0.5,
                lockedStringIDs: confirmed ? [string.id] : [], resetLock: { _ in }, clearAllLocks: {}
            ).frame(width: 366, height: 620)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

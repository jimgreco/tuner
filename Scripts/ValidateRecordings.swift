import Foundation
import AVFoundation
@main
struct ValidateRecordings {
static func main() throws {
let directory = CommandLine.arguments[1]
let names = ["sulE.E2B2", "sulA.A2B2", "sulD.D3B3", "sulG.G3B3", "sulB.B3", "sul_E.E4B4"]
for (index, name) in names.enumerated() {
 let file = try AVAudioFile(forReading: URL(fileURLWithPath: "\(directory)/Guitar.mf.\(name).mono.aif"))
 let rate = file.processingFormat.sampleRate
 let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(rate * 8))!
 try file.read(into: buffer)
 let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0],count:Int(buffer.frameLength)))
 let onset = stride(from:0,to:samples.count-Int(rate*0.05),by:Int(rate*0.01)).first { offset in
   TuningMath.signalSnapshot(samples:Array(samples[offset..<offset+Int(rate*0.05)]),sampleRate:rate).volume > 0.005
 } ?? 0
 var detected = [TuningReading]()
 var missed = 0
 for offset in stride(from:onset+Int(rate*0.12), to:min(samples.count-Int(rate*0.19),onset+Int(rate*0.9)),by:Int(rate*0.05)) {
  let r = TuningMath.reading(from:Array(samples[offset..<offset+Int(rate*0.19)]),sampleRate:rate,tuning:TuningMath.standardPreset)
  if let r { detected.append(r) } else { missed += 1 }
 }
 let correct = detected.filter { $0.string.number == 6-index }
 precondition(correct.count == 16 && missed == 0, "Failed recorded string \(name)")
 let cents = correct.map(\.cents).sorted()
 print("\(name): onset \(Double(onset)/rate)s rate \(rate) correct \(correct.count)/\(detected.count) missed \(missed) median cents \(cents.isEmpty ? 999 : cents[cents.count/2]) other \(detected.filter {$0.string.number != 6-index}.map { $0.string.label })")
}

}
}

# Guitar Tuner

A native iPhone tuner for six-string guitar (iOS 17+). Open `Tuner.xcodeproj`, select your iPhone, and run the Tuner scheme. Allow microphone access when prompted.

Choose Standard, Drop D, half-step down, or whole-step down. Pluck one open string at a time and mute the others. Follow **Tune up** or **Tune down**; the note turns green within ±8 cents and confirms after about 0.7 seconds of good readings. Brief gaps pause progress, and the last reading stays visible for 1.5 seconds after the sound fades. A confirmed note tolerates small drift up to ±12 cents to avoid flickering. Tap the AUTO control to pause/resume the microphone. Start over clears completed strings; changing tuning also clears them.

Pitch is measured from waveform periodicity before choosing the nearest string. Automatic string selection is intended for open strings within roughly two semitones of their target. It cannot infer the intended string when two target notes are equally close, or reliably separate multiple ringing strings.

## Verification

Run the Tuner scheme's tests in Xcode, or use `xcodebuild test -project Tuner.xcodeproj -scheme Tuner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` with an available simulator name.

`python3 Scripts/validate-recordings.py` downloads six University of Iowa guitar recordings to a temporary cache and checks their initial attack/sustain windows through the production detector. Requires macOS and Xcode command-line tools. The samples are approximately 85 MB in total and are not included in the app. See [validation notes](docs/validation.md) for results and limitations.

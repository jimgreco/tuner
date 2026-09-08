# Tuner repair verification — September 8, 2026

## Reproduced defects

- The previous detector searched only within ±100 cents of each target. In a 60-case standard-tuning matrix, all 24 cases at ±180 cents were assigned to other strings. The revised detector passed all 60.
- A pure 440 Hz tone was reported as D3 at −2 cents. The revised detector rejects it instead of matching a hypothetical lower fundamental.
- Original debug analysis took approximately 200 ms for an 8192-sample guitar window, exceeding the microphone buffer interval. The serial queue had no backpressure. The revised vectorized detector runs in approximately 1–3 ms in these simulator checks; analysis accepts at most one outstanding job while retaining current samples. These timings are development-machine measurements, not iPhone benchmarks.
- Queued analysis was not invalidated when changing tunings or restarting the microphone. Tune confirmation could bridge missing observations. Completed string marks survived tuning changes.
- Audio interruptions/background transitions had no recovery path. The apparent AUTO switch was not interactive, and denied microphone access had no Settings link.

## Implemented behavior

The detector removes DC, filters before downsampling, and measures waveform periodicity with a normalized difference function. Interpolated minima distinguish a weak fundamental from a strong second harmonic. String targets are chosen after pitch detection. White noise, silence, DC and out-of-range tones are rejected.

The audio pipeline caps its window at 190 ms and discards stale work. Following hands-on feedback that tuning was too demanding, confirmation now accepts ±8 cents for 0.7 seconds of observed good audio. Gaps up to 200 ms pause progress without advancing it; longer gaps reset an unfinished confirmation. A completed result and the last measurement stay visible for 1.5 seconds after the sound fades, with a Last reading label. Fresh detuning beyond ±12 cents or a different string immediately clears confirmation. The wider release band prevents flicker after confirmation. Near-target smoothing calms the needle. A green target zone and immediate green note highlight distinguish entering the band from completing confirmation. Lifecycle handling stops recording in the background, recovers on foreground/resumable interruptions and input route changes, and offers retry after media-service reset. Confirmation uses haptic feedback in place of an audible tone that could enter the microphone.

## Passed checks

- 26 XCTest tests, zero failures, on iPhone 17 Pro Simulator (iOS 26.2).
- 240 synthetic combinations: all six strings, four tuning presets, 44.1/48 kHz input, offsets −180/−60/0/+35/+180 cents. Correct target and pitch within three cents.
- Strong second/fourth harmonics, missing fundamental, quiet decaying strings with noise/DC offset, silence and invalid input, rejection of out-of-range tones, fresh-observation locking, backpressure and stale-generation invalidation.
- Six recorded guitar strings from the [University of Iowa Musical Instrument Samples](https://theremin.music.uiowa.edu/MISguitar.html). For each mezzo-forte mono recording, the first open note was checked at 16 overlapping windows from 120–870 ms after onset, each 190 ms long: 96/96 windows identified the expected string. These recordings are not exactly concert-tuned, so this verifies string identification rather than absolute cents calibration. Very late decay windows may correctly return no pitch.
- Feedback snapshots: rendered the actual SwiftUI tuning stage with in-range, confirmed/held, and sharp readings; checked the target band, immediate green note, confirmation checkmark, and held-reading label.
- Manual simulator UI: microphone permission/start, pause/resume, Drop D target update, and automatic microphone recovery after background/foreground. Final layout visually inspected.
- Signed Release build for physical iPhone succeeded.

## Still requiring a physical phone

The initial installation attempt was blocked by `kAMDMobileImageMounterDeviceLocked`. After the user unlocked the paired iPhone 17 Pro, the signed Release build was successfully installed on September 8, 2026 (bundle identifier `com.jgreco.tuner`). The user then tested the app and reported that tuning felt too demanding. The more forgiving confirmation/hold update described above was installed successfully at 14:39 EDT. Its tuning feel still needs a further hands-on check; speaker/headset changes and incoming-call recovery also remain unverified on the phone. Simulator startup and offline recordings do not establish this physical microphone path.

Audio lifecycle implementation follows Apple's [interruption guidance](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions), [route-change guidance](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes), and [media-services reset guidance](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification).

# CareAI original audio

All four files were synthesized specifically for this CareAI video using
`tools/generate_music.py`, numpy and the Python standard library. No recording,
download, third-party composition, voice, heartbeat or alarm sample was used.

`music.wav` is a new 70-second instrumental composition in D major at 76 BPM,
using soft felt-piano-like synthesis, a warm pad, a quiet bass and a sparse
original melody. This is a synthesized instrument, not a sampled piano.
The ending resolves to D with a 3.3-second fade. The beginning fades in for 1 s.

Suggested background music volume under narration: **0.15–0.22**.
Suggested UI SFX volume: **0.4–0.6**. Use the notification at the caregiver alert,
tap at the illustrated SOS tap, and accepted at the acknowledged state.
The notification sound is a presentation accent, not a recording of the app.

Output format: stereo, 44,100 Hz, PCM16 WAV. Measured before PCM quantization:

| File | Duration | Peak | RMS |
| --- | ---: | ---: | ---: |
| `music.wav` | 70.000 s | -4.62 dBFS | -18.50 dBFS |
| `tap.wav` | 0.190 s | -17.28 dBFS | -33.44 dBFS |
| `notification.wav` | 0.950 s | -12.47 dBFS | -22.44 dBFS |
| `accepted.wav` | 1.200 s | -10.36 dBFS | -21.81 dBFS |

All measured peaks are below 0 dBFS; no clipping. Regeneration is deterministic.
The final combined mix should retain headroom with narration added.

## Full 70-second mix review

`review-mix.wav` is an audio-only review, matching the current React audio
placement and gains as of this check: voice at 0.9, music at 0.18 after
1.5 seconds fading to 0.12 by 69 seconds and 0 at 70 seconds; UI SFX at 0.28.
Each voice clip starts 0.25 seconds after its scene begins.
The voice files were decoded locally with Remotion's bundled FFmpeg. No video
was exported. This review file is not used by the React composition.

The closing uses `audio/voice/Closing-v2.mp3` from the updated manifest, replacing the
previous ending. The closing text is: "Care AI. Kết nối quan tâm, cùng gia đình chăm sóc. Hỗ trợ theo dõi và cảnh báo."
The removed sentence is absent from this audio-only review. Music and the
other eight source voice clips were read without modification.

- Duration: 70.000 seconds; stereo 44,100 Hz PCM16 WAV.
- Mixed sample peak: -6.12 dBFS. No sample clipping.
- Mixed RMS, including pauses: -23.50 dBFS.
- Active speech RMS (100 ms windows above -40 dBFS): -21.00 dBFS.
- Music RMS in the same speech windows: -33.40 dBFS.
- Average speech-to-music margin: 12.40 dB.
- FFmpeg `loudnorm` input measurement: **-19.99 LUFS integrated**,
  **-6.12 dBTP**, and **9.60 LU loudness range**.
  The measurement analyzed to a null output and did not normalize source audio.

The 0.18 music gain is suitably restrained compared with this voice track
based on the measured speech/music separation. These are signal measurements,
not a claim of a human listening assessment or a device playback test.

## Current 55-second male-voice mix review

`review-mix-male.wav` is an audio-only review using all nine updated
`vi-VN-NamMinhNeural` voice clips, generated at +18% speaking rate. Each voice
clip starts 0.15 seconds after its scene begins and plays at native rate 1,
with voice gain 0.9. Music uses the original `music.wav` at natural rate 1,
trimmed to 55 seconds. Music gain fades from 0 at 0 s to 0.18 at 0.8 s, holds
until 46.5 s, falls to 0.12 at 54 s, then to 0 at 55 s. SFX gain is 0.28.

Global SFX times: taps at 17.16, 22.86, 33.74, 40.18 seconds; notification
at 25.48 seconds; accepted at 42.22 seconds. No source audio was modified.
This review file is not imported by the React composition. The previous
`review-mix.wav` is a historical 70-second female-voice review only.

- Duration: 55.000 seconds; stereo 44,100 Hz PCM16 WAV.
- Mixed sample peak: -6.70 dBFS. No sample clipping.
- Mixed RMS, including pauses: -24.65 dBFS.
- Active speech RMS (100 ms windows above -40 dBFS): -22.78 dBFS.
- Music RMS in the same speech windows: -33.26 dBFS.
- Average speech-to-music margin: 10.48 dB.
- FFmpeg `loudnorm` input measurement: **-21.78 LUFS integrated**,
  **-6.68 dBTP**, and **6.50 LU loudness range**.
  Measurement used a null output and did not normalize or modify source audio.

The music remains quiet relative to narration at gain 0.18. These are signal
measurements, not a claim of a human listening assessment or device testing.
No app builds, tests, analysis, or video export were performed.

## Current continuous-narration mix review

`review-mix-continuous.wav` matches the new continuous narration revision.
It mixes **only the master `audio/north/narration-continuous.wav` once**, starting at 0 with gain 0.9.
The nine individual scene clips are not mixed again.

Music uses the original `music.wav` at natural rate 1 trimmed to 37.400
seconds, fades from 0 to 0.18 during the first 0.5 s, holds until
35.900 s, then fades to 0 at the end. SFX gain is 0.28.
Global SFX times: tap.wav at 12.099 s, tap.wav at 15.908 s, notification.wav at 17.650 s, tap.wav at 23.038 s, tap.wav at 27.200 s, accepted.wav at 28.600 s.

- Duration: 37.400 seconds (1122 frames at 30 fps);
  stereo 44,100 Hz PCM16 WAV.
- Mixed sample peak: -6.63 dBFS. No sample clipping.
- Mixed RMS, including pauses: -23.22 dBFS.
- Active speech RMS (100 ms windows above -40 dBFS): -22.78 dBFS.
- Music RMS in the same speech windows: -33.48 dBFS.
- Average speech-to-music margin: 10.70 dB.
- FFmpeg `loudnorm` input measurement: **-20.95 LUFS integrated**,
  **-6.63 dBTP**, and **2.30 LU loudness range**.
- Inter-scene speech gaps from the voice agent's word-boundary metadata:
  **65.833–89.542 ms**, average **78.396 ms**.
  Initial speech delay: **60.000 ms**;
  final logo hold: **473.417 ms**.

Source audio files were read without modification. This review file is not
imported into React. Earlier review WAVs are historical previous revisions.
Measurements used local FFmpeg and a null loudness-analysis output; they did
not normalize source audio. These are signal measurements and source metadata,
not a claim of a human listening assessment. No app build, test, analyze or
video export was performed.

## Current watch-focused mix at 92% playback

`review-mix-current.wav` is the current audio-only review. It uses
`audio/north-v2/narration-continuous.wav` once at gain 0.9, the original `music.wav` at gain 0.18
with the source-clock 0.5-second fade-in and final 1.5-second fade-out, plus
the six SFX placements read directly from the current scene TSX files.

The source duration is 37.300 s. All audio was then slowed together to
0.92 playback using FFmpeg `asetrate=44160,aresample=48000` from 48 kHz,
matching pitch-changing playback rather than preserving pitch. The final
review is padded to the composition duration, **1217 frames at 30 fps
= 40.566667 s**. No additional gaps were inserted between scenes.

Current key narration, taken directly from the updated manifest:

- Connection: CareAI kết nối đồng hồ của người cao tuổi với ứng dụng trên điện thoại người thân.
- Monitoring: Dữ liệu sức khỏe và cảnh báo từ đồng hồ giúp người thân theo dõi, hỏi thăm và phản hồi khi cần.
- Sos: Khi cần giúp, người cao tuổi có thể gửi SOS từ đồng hồ hoặc điện thoại.
- FallAlert: Trong tình huống khác, khi đồng hồ báo té ngã, người thân mở thông tin sự cố để kiểm tra.

Measurements for the final slowed mix:

- Stereo 48,000 Hz PCM16 WAV.
- Mixed sample peak: -6.81 dBFS. No sample clipping.
- Mixed RMS: -23.32 dBFS.
- Active speech RMS: -22.93 dBFS.
- Music in the same active-speech windows: -33.54 dBFS.
- Speech-to-music margin: 10.61 dB.
- FFmpeg input loudness: **-21.08 LUFS integrated**,
  true peak **-6.80 dBTP**, LRA **2.10 LU**.
- Metadata speech gaps after 0.92 playback: **73.370–102.672 ms**.

Earlier review WAVs describe historical revisions. This review is not imported
into React. No audio source, scene, app code or video export was changed.
These are signal measurements and narration metadata, not a listening test.

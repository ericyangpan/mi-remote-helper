# Performance

**English** · [简体中文](performance.zh-CN.md)

## CPU measurement (2026-10-07)

Environment: Mac Studio, Apple Silicon, macOS 27.0.1, Debug build. RC003 connected, mapping enabled, mapping page visible, no remote buttons held. Each measurement uses six `top` intervals of two seconds; the initial cumulative sample is excluded. No stack sampler ran during these intervals. CPU percentages use one logical core as 100%.

| Mapping-page idle | Mean CPU | Range |
| --- | ---: | ---: |
| Before optimization | 4.47% | 3.6–6.7% |
| After optimization | 0.53% | 0.3–1.6% |

This short local measurement represents an approximately 88% reduction. It does not measure continuous remote voice capture, other Macs, or long-term energy use. Process restart and system workload can affect results.

## Runtime behavior

- Unchanged permission, audio-device-list, and unavailable-mapping states do not publish UI updates.
- The one-second health check queries the selected audio device's liveness and output binding instead of enumerating all input and output devices.
- Audio sample counts accumulate for every packet; UI progress is published at most every 80 milliseconds and the exact final count is published on stream stop.
- Audio completion callbacks retain the frame count instead of the decoded sample array.
- Debug keyboard-event observation is opt-in via `MI_REMOTE_VOICE_DIAGNOSTICS=1` in the launch environment.

Validation recorded for the 2026-10-07 optimization: 78 unit tests passed; Debug and arm64 Release builds passed. The connected app displayed Ready, and the BlackHole test-tone playback completion callback completed. End-to-end remote dictation CPU was not measured.

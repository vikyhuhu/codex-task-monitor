#!/bin/bash
# Optional local audio check; plays two short tones. Requires a macOS audio session.
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_SOUND_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_SOUND_TMP"' EXIT
sed '/^import MonitorCore$/d' Sources/CodexTaskMonitor/ReminderSoundPlayer.swift > "$TASK_SOUND_TMP/ReminderSoundPlayer.swift"
cat > "$TASK_SOUND_TMP/main.swift" <<'SWIFT'
import AppKit
let player = ReminderSoundPlayer()
for cue in SoundCue.allCases {
    guard let sound = NSSound(named: NSSound.Name(cue.systemSoundName)), sound.duration > 0 else { exit(1) }
    print("Loaded \(cue.systemSoundName), duration \(sound.duration)")
}
let tink = NSSound(named: NSSound.Name("Tink"))!
player.play(.needsInput) { print("FAIL playback"); exit(1) }
DispatchQueue.main.asyncAfter(deadline: .now() + tink.duration + 0.22) {
    guard tink.isPlaying else { print("FAIL second tone did not start"); exit(1) }
    print("PASS second tone started")
    player.play(.needsInput) { exit(1) }
    player.stop()
    DispatchQueue.main.asyncAfter(deadline: .now() + tink.duration + 0.22) {
        guard !tink.isPlaying else { print("FAIL canceled tone played"); exit(1) }
        print("PASS stop cancels pending second tone")
        exit(0)
    }
}
// AppKit audio needs the same main run loop used by the actual application.
RunLoop.main.run()
SWIFT
swiftc Sources/MonitorCore/TaskState.swift Sources/MonitorCore/SoundCue.swift \
    "$TASK_SOUND_TMP/ReminderSoundPlayer.swift" "$TASK_SOUND_TMP/main.swift" -o "$TASK_SOUND_TMP/check"
"$TASK_SOUND_TMP/check"

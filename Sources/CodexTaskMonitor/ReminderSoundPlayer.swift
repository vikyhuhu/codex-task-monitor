import AppKit
import MonitorCore

/// Main-queue player: a new cue or mute cancels the previous double-tone sequence.
final class ReminderSoundPlayer {
    private var sound: NSSound?
    private var secondTone: DispatchWorkItem?
    private var generation = UUID()

    func stop() {
        generation = UUID()
        secondTone?.cancel()
        secondTone = nil
        sound?.stop()
        sound = nil
    }

    func play(_ cue: SoundCue, onFailure: @escaping () -> Void) {
        stop()
        guard let next = NSSound(named: NSSound.Name(cue.systemSoundName)) else {
            onFailure(); return
        }
        sound = next
        guard next.play() else { onFailure(); return }
        guard cue.repeatCount == 2 else { return }
        let current = generation
        let replay = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.secondTone = nil
            if !next.play() { onFailure() }
        }
        secondTone = replay
        DispatchQueue.main.asyncAfter(deadline: .now() + next.duration + 0.12, execute: replay)
    }
}

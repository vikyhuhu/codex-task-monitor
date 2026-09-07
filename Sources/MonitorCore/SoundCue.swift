import Foundation

public enum SoundCue: Int, CaseIterable {
    case ended = 0, needsInput = 1, exception = 2

    public var label: String {
        switch self {
        case .ended: return "本轮结束 · 清脆单音"
        case .needsInput: return "等你处理 · 两声短音"
        case .exception: return "异常 · 低沉提示音"
        }
    }
    public var systemSoundName: String {
        switch self {
        case .ended: return "Glass"
        case .needsInput: return "Tink"
        case .exception: return "Basso"
        }
    }
    public var repeatCount: Int { self == .needsInput ? 2 : 1 }

    /// Select one cue per batch, independent of task ordering.
    public static func select<S: Sequence>(for statuses: S) -> SoundCue? where S.Element == TaskStatus {
        statuses.compactMap { status -> SoundCue? in
            switch status {
            case .running: return nil
            case .ended: return .ended
            case .needsInput: return .needsInput
            case .failed, .interrupted, .uncertain: return .exception
            }
        }.max { $0.rawValue < $1.rawValue }
    }
}

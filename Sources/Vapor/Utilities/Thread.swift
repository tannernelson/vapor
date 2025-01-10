import Foundation

extension Thread {
    /// Convenience wrapper around `Thread.detachNewThread`.
    public static func async(_ work: @Sendable @escaping () -> ()) {
        Thread.detachNewThread {
            work()
        }
    }
}

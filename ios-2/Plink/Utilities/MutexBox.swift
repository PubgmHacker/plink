import Foundation

// MARK: - MutexBox
//
// 🔧 SWIFT 6 strict-mode workaround for mutable state accessed from nonisolated
// contexts (deinit, nonisolated methods, background queues).
//
// PROBLEM:
// Swift 6 emits CONTRADICTORY diagnostics for mutable stored `var` accessed from
// nonisolated contexts:
//   - `nonisolated(unsafe) private var x: T` → warning "has no effect, consider
//     using nonisolated"
//   - `nonisolated private var x: T` → error "cannot be applied to mutable
//     stored properties"
// There is no way to satisfy both diagnostics on a mutable stored property.
//
// SOLUTION:
// Wrap the storage in a `final class` marked `@unchecked Sendable`. The class
// itself is a `let` property of the owner (Sendable, no `nonisolated(unsafe)`
// needed). Internal mutation is guarded by NSLock. The owner exposes a
// `nonisolated` COMPUTED property that delegates to the box — computed properties
// accept plain `nonisolated` without warnings or errors.
//
// This pattern is the official Swift 6 escape hatch for "I have mutable state
// that I promise to access thread-safely via my own synchronization".
final class MutexBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }

    /// Mutate the value under the lock, atomically. Useful for compound updates.
    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&_value)
    }
}

import Foundation

enum MemoryHealthState: String, Sendable {
    case normal
    case warning
    case critical
}

struct MemoryHealthEvaluator {
    static let recoveryPersistence: Duration = .seconds(30)

    private(set) var state: MemoryHealthState = .normal
    private var pending: (state: MemoryHealthState, since: ContinuousClock.Instant)?

    mutating func observe(_ observed: MemoryHealthState, at now: ContinuousClock.Instant) -> MemoryHealthState {
        if observed == state {
            pending = nil
            return state
        }

        if observed == .critical || (state == .normal && observed == .warning) {
            state = observed
            pending = nil
            return state
        }

        if pending?.state != observed {
            pending = (observed, now)
            return state
        }

        if let pending, now - pending.since >= Self.recoveryPersistence {
            state = observed
            self.pending = nil
        }
        return state
    }
}

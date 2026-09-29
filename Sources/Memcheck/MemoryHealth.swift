import Foundation

enum MemoryHealthState: String, Sendable {
    case normal
    case warning
    case critical
}

struct MemoryHealthEvaluator {
    static let warningPersistence: Duration = .seconds(20)
    static let recoveryPersistence: Duration = .seconds(30)

    private(set) var state: MemoryHealthState = .normal
    private var pending: (state: MemoryHealthState, since: ContinuousClock.Instant)?

    mutating func observe(_ observed: MemoryHealthState, at now: ContinuousClock.Instant) -> MemoryHealthState {
        if observed == state {
            pending = nil
            return state
        }

        if observed == .critical {
            state = .critical
            pending = nil
            return state
        }

        if pending?.state != observed {
            pending = (observed, now)
            return state
        }

        let required = state == .normal ? Self.warningPersistence : Self.recoveryPersistence
        if let pending, now - pending.since >= required {
            state = observed
            self.pending = nil
        }
        return state
    }
}

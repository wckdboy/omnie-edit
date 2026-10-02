import Foundation

public struct EditorSession: Equatable, Sendable {
    public private(set) var baseline: String
    public var draft: String

    public init(text: String) {
        baseline = text
        draft = text
    }

    public var isDirty: Bool {
        draft != baseline
    }

    public mutating func noteSaved(snapshot: String) {
        baseline = snapshot
    }
}

public struct AutosaveClock: Equatable, Sendable {
    public var delay: TimeInterval
    public private(set) var dueAt: Date?

    public init(delay: TimeInterval) {
        self.delay = delay
    }

    public mutating func markEdited(at now: Date) {
        dueAt = now.addingTimeInterval(delay)
    }

    public mutating func cancel() {
        dueAt = nil
    }

    public func isDue(at now: Date) -> Bool {
        guard let dueAt else { return false }
        return now >= dueAt
    }
}

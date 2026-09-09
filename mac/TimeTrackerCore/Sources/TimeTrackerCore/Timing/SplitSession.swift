import Foundation

/// Splitting one recorded session into consecutive parts.
///
/// Active time is distributed in proportion to each part's share of wall time,
/// with the last part absorbing the rounding remainder so the totals still add
/// up exactly. Time that was already tracked must never change amount just
/// because it was reorganised.
public enum SplitSession {
    public struct Part: Hashable, Sendable {
        public var projectId: String?
        public var projectName: String?
        public var tagIds: [String]
        public var billable: Bool

        public init(
            projectId: String? = nil, projectName: String? = nil,
            tagIds: [String] = [], billable: Bool = false
        ) {
            self.projectId = projectId
            self.projectName = projectName
            self.tagIds = tagIds
            self.billable = billable
        }
    }

    public enum SplitError: Error, Equatable, CustomStringConvertible {
        case tooFewParts
        case boundaryCountMismatch
        case boundaryOutsideSession
        case boundariesOutOfOrder

        public var description: String {
            switch self {
            case .tooFewParts: return "A split needs at least two parts."
            case .boundaryCountMismatch: return "There must be one split point fewer than parts."
            case .boundaryOutsideSession: return "Split points must fall inside the session."
            case .boundariesOutOfOrder: return "Split points must be in order."
            }
        }
    }

    public static func split(
        _ original: Session,
        at boundaries: [Date],
        into parts: [Part],
        now: Date = Date()
    ) -> Result<[Session], SplitError> {
        guard parts.count >= 2 else { return .failure(.tooFewParts) }
        guard boundaries.count == parts.count - 1 else { return .failure(.boundaryCountMismatch) }

        for (index, boundary) in boundaries.enumerated() {
            guard boundary > original.startTime, boundary < original.endTime else {
                return .failure(.boundaryOutsideSession)
            }
            if index > 0, boundary <= boundaries[index - 1] {
                return .failure(.boundariesOutOfOrder)
            }
        }

        let edges = [original.startTime] + boundaries + [original.endTime]
        let totalWall = original.endTime.timeIntervalSince(original.startTime)
        guard totalWall > 0 else { return .failure(.boundaryOutsideSession) }

        var allocated = 0
        var results: [Session] = []

        for (index, part) in parts.enumerated() {
            let partStart = edges[index]
            let partEnd = edges[index + 1]

            let duration: Int
            if index == parts.count - 1 {
                // The last part takes whatever is left, so rounding can never
                // lose or invent a second.
                duration = original.durationSeconds - allocated
            } else {
                let share = partEnd.timeIntervalSince(partStart) / totalWall
                duration = Int((Double(original.durationSeconds) * share).rounded())
                allocated += duration
            }

            var piece = original
            piece.id = UUID().uuidString
            piece.projectId = part.projectId
            piece.projectName = part.projectName
            piece.assignmentSource = .manualDashboard
            piece.assignmentConfidence = Confidence.manual
            piece.matchedRuleId = nil
            piece.tagIds = part.tagIds
            piece.billable = part.billable
            // A part the user gave a project to is reviewed by definition.
            piece.reviewed = part.projectId != nil
            piece.startTime = partStart
            piece.endTime = partEnd
            piece.durationSeconds = duration
            piece.createdAt = now
            piece.updatedAt = now
            results.append(piece)
        }

        return .success(results)
    }
}

import EventKit
import Foundation

struct MeetingCalendarContext: Equatable, Sendable {
    let title: String
    let calendarName: String
    let startDate: Date
    let endDate: Date
    let location: String?

    var scheduledDisplay: String {
        "\(Self.dateFormatter.string(from: startDate)) - \(Self.timeFormatter.string(from: endDate))"
    }

    var cleanLocation: String? {
        let trimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct CalendarEventCandidate: Equatable, Sendable {
    let title: String
    let calendarName: String
    let startDate: Date
    let endDate: Date
    let location: String?
}

enum CalendarEventMatcher {
    static func context(
        from candidates: [CalendarEventCandidate],
        recordingStart: Date,
        recordingEnd: Date
    ) -> MeetingCalendarContext? {
        guard recordingEnd > recordingStart else { return nil }

        let validCandidates = candidates
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let currentCandidate = validCandidates
            .filter { $0.startDate <= recordingStart && $0.endDate > recordingStart }
            .max { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }

        let upcomingCandidate = validCandidates
            .filter {
                $0.startDate > recordingStart
                    && $0.startDate <= recordingStart.addingTimeInterval(CalendarContextPolicy.upcomingMeetingWindow)
            }
            .min { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.startDate < rhs.startDate
            }

        let matchingCandidate = currentCandidate ?? upcomingCandidate

        guard let matchingCandidate else { return nil }
        return MeetingCalendarContext(
            title: matchingCandidate.title,
            calendarName: matchingCandidate.calendarName,
            startDate: matchingCandidate.startDate,
            endDate: matchingCandidate.endDate,
            location: matchingCandidate.location
        )
    }
}

enum CalendarAccessState: Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted

    init(authorizationStatus: EKAuthorizationStatus) {
        switch authorizationStatus {
        case .fullAccess:
            self = .fullAccess
        case .denied:
            self = .denied
        case .restricted, .writeOnly:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .restricted
        }
    }

    var canReadEvents: Bool {
        self == .fullAccess
    }
}

enum CalendarContextPolicy {
    static let preferenceKey = "includeCalendarContextInRecordedMeetingMarkdown"
    static let upcomingMeetingWindow: TimeInterval = 10 * 60
    static let matchingRule = "Adds current calendar meeting, or next in 10 min, to .MD."
}

@MainActor
final class CalendarContextStore {
    private let eventStore = EKEventStore()

    func authorizationState() -> CalendarAccessState {
        CalendarAccessState(authorizationStatus: EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func context(for recording: MeetingRecordingArtifacts) -> MeetingCalendarContext? {
        let queryStart = recording.startedAt
        let queryEnd = recording.startedAt.addingTimeInterval(CalendarContextPolicy.upcomingMeetingWindow)
        let predicate = eventStore.predicateForEvents(withStart: queryStart, end: queryEnd, calendars: nil)
        let candidates = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map {
                CalendarEventCandidate(
                    title: $0.title,
                    calendarName: $0.calendar.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    location: $0.location
                )
            }

        return CalendarEventMatcher.context(
            from: candidates,
            recordingStart: recording.startedAt,
            recordingEnd: recording.stoppedAt
        )
    }
}

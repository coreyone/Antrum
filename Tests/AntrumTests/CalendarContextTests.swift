import Foundation
import Testing
@testable import Antrum

@Suite("Calendar context")
struct CalendarContextTests {
    @Test
    func matchingRuleIsDisclosedInTheProductCopy() {
        #expect(CalendarContextPolicy.matchingRule == "Adds current calendar meeting, or next in 10 min, to .MD.")
    }

    @Test
    func meetingCalendarContextFormatsScheduleAndCleansBlankLocation() {
        let context = MeetingCalendarContext(
            title: "Design review",
            calendarName: "Work",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            location: "   "
        )

        #expect(context.scheduledDisplay.contains(" - "))
        #expect(context.cleanLocation == nil)
    }

    @Test
    func choosesTheCurrentMeetingWhenRecordingStartsInsideIt() {
        let recordingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let recordingEnd = recordingStart.addingTimeInterval(3_600)
        let context = CalendarEventMatcher.context(
            from: [
                CalendarEventCandidate(
                    title: "Earlier meeting",
                    calendarName: "Work",
                    startDate: recordingStart.addingTimeInterval(-3_600),
                    endDate: recordingStart.addingTimeInterval(-300),
                    location: nil
                ),
                CalendarEventCandidate(
                    title: "Design review",
                    calendarName: "Work",
                    startDate: recordingStart.addingTimeInterval(-300),
                    endDate: recordingEnd.addingTimeInterval(600),
                    location: "Studio A"
                )
            ],
            recordingStart: recordingStart,
            recordingEnd: recordingEnd
        )

        #expect(context?.title == "Design review")
        #expect(context?.location == "Studio A")
    }

    @Test
    func choosesTheNextMeetingWithinTenMinutesWhenNoCurrentMeetingExists() {
        let recordingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let context = CalendarEventMatcher.context(
            from: [
                CalendarEventCandidate(
                    title: "Later meeting",
                    calendarName: "Work",
                    startDate: recordingStart.addingTimeInterval(9 * 60),
                    endDate: recordingStart.addingTimeInterval(60 * 60),
                    location: nil
                )
            ],
            recordingStart: recordingStart,
            recordingEnd: recordingStart.addingTimeInterval(1_800)
        )

        #expect(context?.title == "Later meeting")
    }

    @Test
    func ignoresEventsStartingAfterTheTenMinuteWindow() {
        let recordingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let context = CalendarEventMatcher.context(
            from: [
                CalendarEventCandidate(
                    title: "Later meeting",
                    calendarName: "Work",
                    startDate: recordingStart.addingTimeInterval(11 * 60),
                    endDate: recordingStart.addingTimeInterval(60 * 60),
                    location: nil
                )
            ],
            recordingStart: recordingStart,
            recordingEnd: recordingStart.addingTimeInterval(1_800)
        )

        #expect(context == nil)
    }
}

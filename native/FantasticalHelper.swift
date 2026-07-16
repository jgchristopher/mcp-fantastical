import EventKit
import Foundation

// Args: <command> [<param>] [--output <path>]
//   command: today | upcoming | calendars
//   param:   for 'upcoming', the number of days (default 7)
//   --output <path>: if given, JSON is written to this file instead of stdout.
//                    Required when launched via `open -W` because `open` detaches stdio.

let allArgs = CommandLine.arguments
var positional: [String] = []
var outputPath: String? = nil

var i = 1
while i < allArgs.count {
    let a = allArgs[i]
    if a == "--output", i + 1 < allArgs.count {
        outputPath = allArgs[i + 1]
        i += 2
    } else {
        positional.append(a)
        i += 1
    }
}

let command = positional.count > 0 ? positional[0] : "today"
let param = positional.count > 1 ? positional[1] : "7"

let store = EKEventStore()
let sema = DispatchSemaphore(value: 0)

func emit(_ json: String) {
    if let path = outputPath {
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    } else {
        print(json)
    }
}

func emit(_ obj: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let str = String(data: data, encoding: .utf8) else {
        emit("{\"error\":\"JSON serialization failed\"}")
        return
    }
    emit(str)
}

func toISO(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

func participantStatusString(_ status: EKParticipantStatus) -> String {
    switch status {
    case .unknown: return "unknown"
    case .pending: return "pending"
    case .accepted: return "accepted"
    case .declined: return "declined"
    case .tentative: return "tentative"
    case .delegated: return "delegated"
    case .completed: return "completed"
    case .inProcess: return "inProcess"
    @unknown default: return "unknown"
    }
}

func participantRoleString(_ role: EKParticipantRole) -> String {
    switch role {
    case .unknown: return "unknown"
    case .required: return "required"
    case .optional: return "optional"
    case .chair: return "chair"
    case .nonParticipant: return "nonParticipant"
    @unknown default: return "unknown"
    }
}

func eventStatusString(_ status: EKEventStatus) -> String {
    switch status {
    case .none: return "none"
    case .confirmed: return "confirmed"
    case .tentative: return "tentative"
    case .canceled: return "canceled"
    @unknown default: return "unknown"
    }
}

func availabilityString(_ availability: EKEventAvailability) -> String {
    switch availability {
    case .notSupported: return "notSupported"
    case .busy: return "busy"
    case .free: return "free"
    case .tentative: return "tentative"
    case .unavailable: return "unavailable"
    @unknown default: return "unknown"
    }
}

// Conferencing links hide in three different places depending on the provider:
// Google Meet writes them into notes, Zoom invites often put them in location,
// and some clients set the event URL. Check all three rather than assume.
let conferenceRegex = try? NSRegularExpression(
    pattern: #"https?://(?:[A-Za-z0-9-]+\.)*(?:meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|meet\.jit\.si|whereby\.com|chime\.aws)/[^\s<>"']*"#,
    options: [.caseInsensitive]
)

func firstConferenceURL(in text: String?) -> String? {
    guard let text, !text.isEmpty, let regex = conferenceRegex else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let matched = Range(match.range, in: text) else { return nil }
    return String(text[matched])
}

func conferenceURL(for evt: EKEvent) -> String? {
    firstConferenceURL(in: evt.url?.absoluteString)
        ?? firstConferenceURL(in: evt.location)
        ?? firstConferenceURL(in: evt.notes)
}

func serializeParticipant(_ p: EKParticipant) -> [String: Any] {
    var out: [String: Any] = [
        "status": participantStatusString(p.participantStatus),
        "role": participantRoleString(p.participantRole),
        "isCurrentUser": p.isCurrentUser,
        "email": p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
    ]
    if let name = p.name { out["name"] = name }
    return out
}

func serialize(_ evt: EKEvent) -> [String: Any] {
    var out: [String: Any] = [
        "title": evt.title ?? "",
        "calendar": evt.calendar.title,
        "calendarSource": evt.calendar.source.title,
        "calendarId": evt.calendar.calendarIdentifier,
        "start": toISO(evt.startDate),
        "end": toISO(evt.endDate),
        "isAllDay": evt.isAllDay,
        "location": evt.location ?? "",
        "status": eventStatusString(evt.status),
        "availability": availabilityString(evt.availability),
        "notes": evt.notes ?? ""
    ]
    if let url = conferenceURL(for: evt) { out["conferenceURL"] = url }
    if let attendees = evt.attendees, !attendees.isEmpty {
        out["attendees"] = attendees.map(serializeParticipant)
    }
    if let organizer = evt.organizer {
        out["organizer"] = serializeParticipant(organizer)
    }
    return out
}

store.requestFullAccessToEvents { granted, _ in
    guard granted else {
        emit(["error": "Calendar access denied. Open System Settings > Privacy & Security > Calendars and enable FantasticalHelper."])
        sema.signal()
        return
    }

    let cal = Calendar.current

    switch command {
    case "today":
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            emit("{\"error\":\"Date calculation failed\"}")
            sema.signal()
            return
        }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
        let result = events.map(serialize)
        emit([
            "date": formatDate(Date()),
            "count": events.count,
            "events": result
        ] as [String: Any])

    case "upcoming":
        let days = Int(param) ?? 7
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: days, to: start) else {
            emit("{\"error\":\"Date calculation failed\"}")
            sema.signal()
            return
        }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
        let result = events.map(serialize)
        emit([
            "range": [
                "start": formatDate(start),
                "end": formatDate(end),
                "days": days
            ],
            "count": events.count,
            "events": result
        ] as [String: Any])

    case "calendars":
        let cals = store.calendars(for: .event)
        // Several calendars share a title ("Holidays in United States" appears once
        // per account), so the source is what actually disambiguates them.
        let result = cals.map { cal -> [String: Any] in
            [
                "name": cal.title,
                "id": cal.calendarIdentifier,
                "source": cal.source.title,
                "allowsModify": cal.allowsContentModifications
            ]
        }
        emit(["count": cals.count, "calendars": result] as [String: Any])

    default:
        emit("{\"error\":\"Unknown command. Use: today, upcoming [days], calendars\"}")
    }

    sema.signal()
}

sema.wait()

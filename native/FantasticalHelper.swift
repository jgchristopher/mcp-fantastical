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
        let result: [[String: String]] = events.map { evt in
            [
                "title": evt.title ?? "",
                "calendar": evt.calendar.title,
                "start": toISO(evt.startDate),
                "end": toISO(evt.endDate),
                "location": evt.location ?? ""
            ]
        }
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
        let result: [[String: String]] = events.map { evt in
            [
                "title": evt.title ?? "",
                "calendar": evt.calendar.title,
                "start": toISO(evt.startDate),
                "end": toISO(evt.endDate),
                "location": evt.location ?? ""
            ]
        }
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
        let result = cals.map { ["name": $0.title, "id": $0.calendarIdentifier] }
        emit(["count": cals.count, "calendars": result] as [String: Any])

    default:
        emit("{\"error\":\"Unknown command. Use: today, upcoming [days], calendars\"}")
    }

    sema.signal()
}

sema.wait()

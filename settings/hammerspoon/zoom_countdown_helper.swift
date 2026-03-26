import EventKit
import Foundation

// Parse look-ahead seconds from command line (default 600)
let lookAhead: TimeInterval = CommandLine.arguments.count > 1
    ? (Double(CommandLine.arguments[1]) ?? 600)
    : 600

// "list-calendars" mode for diagnostics
let listMode = CommandLine.arguments.contains("--list-calendars")
// "diagnose" mode shows events in next hour
let diagnoseMode = CommandLine.arguments.contains("--diagnose")

let store = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)
var accessGranted = false

// Request access synchronously using a semaphore
if #available(macOS 14.0, *) {
    store.requestFullAccessToEvents { granted, error in
        accessGranted = granted
        semaphore.signal()
    }
} else {
    store.requestAccess(to: .event) { granted, error in
        accessGranted = granted
        semaphore.signal()
    }
}
semaphore.wait()

if listMode {
    // Output calendar list as JSON
    let cals = store.calendars(for: .event)
    var names: [[String: Any]] = []
    for cal in cals {
        names.append(["name": cal.title, "source": cal.source?.title ?? ""])
    }
    let status = EKEventStore.authorizationStatus(for: .event)
    let result: [String: Any] = [
        "authorized": accessGranted,
        "status": status.rawValue,
        "calendars": names
    ]
    if let data = try? JSONSerialization.data(withJSONObject: result),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
    exit(0)
}

guard accessGranted else {
    let status = EKEventStore.authorizationStatus(for: .event)
    print("{\"error\":\"not_authorized\",\"status\":\(status.rawValue)}")
    exit(1)
}

let now = Date()
let start = now.addingTimeInterval(-60)
let effectiveLookAhead = diagnoseMode ? 3600.0 : lookAhead
let horizon = now.addingTimeInterval(effectiveLookAhead)

let predicate = store.predicateForEvents(withStart: start, end: horizon, calendars: nil)
let events = store.events(matching: predicate)

var results: [[String: Any]] = []
for event in events {
    var dict: [String: Any] = [
        "title": event.title ?? "",
        "startEpoch": Int(event.startDate.timeIntervalSince1970),
        "location": event.location ?? "",
        "notes": (event.notes ?? ""),
        "calendar": event.calendar?.title ?? ""
    ]
    if let url = event.url {
        dict["url"] = url.absoluteString
    } else {
        dict["url"] = ""
    }
    if diagnoseMode {
        dict["start"] = ISO8601DateFormatter().string(from: event.startDate)
    }
    results.append(dict)
}

results.sort { ($0["startEpoch"] as? Int ?? 0) < ($1["startEpoch"] as? Int ?? 0) }

if let data = try? JSONSerialization.data(withJSONObject: results),
   let str = String(data: data, encoding: .utf8) {
    print(str)
}

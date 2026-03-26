ObjC.import('EventKit');
ObjC.import('Foundation');

var store = $.EKEventStore.alloc.init;

// Check authorization status (0=notDetermined, 1=restricted, 2=denied, 3=authorized, 4=fullAccess)
var status = $.EKEventStore.authorizationStatusForEntityType(0); // 0 = EKEntityTypeEvent
if (status < 3) {
  // Not authorized — output a diagnostic marker so Lua knows
  JSON.stringify({ error: "not_authorized", status: status });
} else {
  var start   = $.NSDate.dateWithTimeIntervalSinceNow(-60);
  var horizon = $.NSDate.dateWithTimeIntervalSinceNow(600);
  var pred    = store.predicateForEventsWithStartDateEndDateCalendars(start, horizon, null);
  var nsEvents = store.eventsMatchingPredicate(pred);

  var results = [];
  for (var i = 0; i < nsEvents.count; i++) {
    var evt = nsEvents.objectAtIndex(i);
    var startEpoch = Math.floor(evt.startDate.timeIntervalSince1970);

    var title    = ObjC.unwrap(evt.title)    || "";
    var location = ObjC.unwrap(evt.location) || "";
    var url      = evt.URL ? (ObjC.unwrap(evt.URL.absoluteString) || "") : "";
    var notes    = ObjC.unwrap(evt.notes)    || "";
    var calName  = ObjC.unwrap(evt.calendar.title) || "";

    results.push({
      title:      title,
      startEpoch: startEpoch,
      location:   location,
      url:        url,
      notes:      notes,
      calendar:   calName
    });
  }

  results.sort(function(a, b) { return a.startEpoch - b.startEpoch; });
  JSON.stringify(results);
}
  
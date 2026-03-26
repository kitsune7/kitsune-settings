ObjC.import('EventKit');
ObjC.import('Foundation');

var store = $.EKEventStore.alloc.init;
var status = $.EKEventStore.authorizationStatusForEntityType(0);
if (status < 3) {
  JSON.stringify([]);
} else {
  var start   = $.NSDate.dateWithTimeIntervalSinceNow(-60);
  var horizon = $.NSDate.dateWithTimeIntervalSinceNow(3600);
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
      title:    title,
      start:    ObjC.unwrap(evt.startDate.description),
      epoch:    startEpoch,
      location: location.substring(0, 100),
      url:      url.substring(0, 100),
      notes:    notes.substring(0, 100),
      calendar: calName
    });
  }
  results.sort(function(a, b) { return a.epoch - b.epoch; });
  JSON.stringify(results, null, 2);
}
  
var calApp = Application("Calendar");
var now = new Date();
var horizon = new Date(now.getTime() + 3600000);

var results = [];
var calendars = calApp.calendars();
for (var ci = 0; ci < calendars.length; ci++) {
  var cal = calendars[ci];
  var calName = cal.name();
  var events;
  try {
    events = cal.events.whose({
      _and: [
        { startDate: { _greaterThan: new Date(now.getTime() - 60000) } },
        { startDate: { _lessThanEquals: horizon } }
      ]
    })();
  } catch(e) { continue; }
  for (var ei = 0; ei < events.length; ei++) {
    var evt = events[ei];
    try {
      results.push({
        title:    evt.summary()  || "(no title)",
        start:    evt.startDate().toISOString(),
        epoch:    Math.floor(evt.startDate().getTime() / 1000),
        location: (evt.location()    || "").substring(0, 100),
        url:      (evt.url()         || "").substring(0, 100),
        notes:    (evt.description() || "").substring(0, 100),
        calendar: calName
      });
    } catch(e) {}
  }
}
results.sort(function(a, b) { return a.epoch - b.epoch; });
JSON.stringify(results, null, 2);
  
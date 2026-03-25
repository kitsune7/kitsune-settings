var calApp = Application("Calendar");
var now = new Date();
var horizon = new Date(now.getTime() + 600 * 1000);

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
  } catch(e) {
    continue;
  }

  for (var ei = 0; ei < events.length; ei++) {
    var evt = events[ei];
    var startEpoch;
    try {
      startEpoch = Math.floor(evt.startDate().getTime() / 1000);
    } catch(e) { continue; }

    var summary = "", location = "", url = "", description = "";
    try { summary     = evt.summary()     || ""; } catch(e) {}
    try { location    = evt.location()    || ""; } catch(e) {}
    try { url         = evt.url()         || ""; } catch(e) {}
    try { description = evt.description() || ""; } catch(e) {}

    results.push({
      title:      summary,
      startEpoch: startEpoch,
      location:   location,
      url:        url,
      notes:      description,
      calendar:   calName
    });
  }
}

results.sort(function(a, b) { return a.startEpoch - b.startEpoch; });
JSON.stringify(results);
  
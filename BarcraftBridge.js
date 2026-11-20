.pragma library

// Shared in-process bridge between Bar.qml (kind: "bar") and BarWidget.qml
// (kind: "bar-widget"). Both run inside omarchy-shell, so updates made in
// Barcraft Studio reflect on the live bar immediately with zero file polling.

var _engine = null
var _listeners = []

function registerEngine(engine) {
  _engine = engine
  notify()
}

function unregisterEngine(engine) {
  if (_engine === engine) {
    _engine = null
    notify()
  }
}

function engine() {
  return _engine
}

function subscribe(fn) {
  if (typeof fn !== "function") return
  if (_listeners.indexOf(fn) === -1) _listeners.push(fn)
}

function unsubscribe(fn) {
  var idx = _listeners.indexOf(fn)
  if (idx !== -1) _listeners.splice(idx, 1)
}

function notify() {
  for (var i = 0; i < _listeners.length; i++) {
    try {
      _listeners[i](_engine)
    } catch (e) {
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "SkinParser.js" as SkinParser

// Saved-skin storage, verified atomic file I/O, and live directory watching.
// Keeps disk operations and watcher lifecycles separate from SkinEngine state
// so save/rename/delete only update Studio after confirmed disk results.
Item {
  id: store

  visible: false
  width: 0
  height: 0

  property bool isPrimary: true
  property string configDir: ""
  property string userSkinsDir: ""
  property string legacySkinsDir: ""
  property var builtinSkins: []
  property var pinnedSlugs: []
  property int truncatedSkinCount: 0

  // path -> md5 of the content Barcraft last read or wrote for that skin file.
  property var skinHashes: ({})
  // Barcraft's own writes and removals, counted, so a scan that started before
  // one never puts back the hash it replaced.
  property int _hashGen: 0
  property var _hashGenByPath: ({})
  property int _scanStartGen: 0
  property var lastDiagnostics: []

  signal skinsScanned(var skins, var diagnostics, var renamedIds, int truncatedCount)

  function allowedDirs() {
    return [userSkinsDir, legacySkinsDir]
  }

  function hashForPath(filePath) {
    var key = String(filePath || "")
    return key && skinHashes && skinHashes[key] ? String(skinHashes[key]) : ""
  }

  function recordHash(filePath, content) {
    var key = String(filePath || "")
    if (!key) return
    var next = {}
    for (var k in skinHashes) next[k] = skinHashes[k]
    next[key] = Qt.md5(String(content === undefined || content === null ? "" : content))
    _touchHash(key)
    skinHashes = next
  }

  function _touchHash(key) {
    var gens = {}
    for (var k in _hashGenByPath) gens[k] = _hashGenByPath[k]
    _hashGen++
    gens[key] = _hashGen
    _hashGenByPath = gens
  }

  // Scan results for the files, except where Barcraft wrote or removed a file
  // after the scan began: what Barcraft recorded then is newer.
  function _mergeScanHashes(scanned) {
    var next = {}
    for (var p in scanned) {
      if (!((_hashGenByPath[p] || 0) > _scanStartGen)) next[p] = scanned[p]
    }
    for (var q in _hashGenByPath) {
      if (_hashGenByPath[q] > _scanStartGen && skinHashes[q]) next[q] = skinHashes[q]
    }
    return next
  }

  function clearHash(filePath) {
    var key = String(filePath || "")
    if (!key || !skinHashes || !(key in skinHashes)) return
    var next = {}
    for (var k in skinHashes) if (k !== key) next[k] = skinHashes[k]
    _touchHash(key)
    skinHashes = next
  }

  // If a skin lives in userSkinsDir and a legacy copy with the same filename
  // exists in legacySkinsDir, return that safe sibling path so deleting a skin
  // cannot resurrect an older shadowed copy on the next rescan.
  function legacySiblingPath(filePath) {
    var p = String(filePath || "")
    var prefix = String(userSkinsDir || "").replace(/\/+$/, "") + "/"
    if (!userSkinsDir || !legacySkinsDir || p.indexOf(prefix) !== 0) return ""
    var candidate = String(legacySkinsDir).replace(/\/+$/, "") + "/" + p.slice(prefix.length)
    return SkinParser.isSafeSkinPath(candidate, [legacySkinsDir]) ? candidate : ""
  }

  // Best-effort cleanup after a delete or rename: the shadowed legacy copy
  // with the same file name. The scan skips symlinks, so one never comes back.
  function removeLegacySibling(filePath) {
    var sibling = legacySiblingPath(filePath)
    if (sibling) removeSkinFiles([sibling], function(ok) { if (!ok) store.rescan() })
  }

  // ---- Verified subprocess jobs --------------------------------------------

  // One short shell job with its own watchdog. `input`, when set, goes in over
  // stdin and never onto the command line.
  Component {
    id: pipeJob
    Item {
      id: job
      visible: false
      property var command: []
      property var input: null
      property var callback: null
      property bool finished: false
      function start() {
        proc.running = true
        watchdog.start()
      }
      function finish(code) {
        if (finished) return
        finished = true
        watchdog.stop()
        if (callback) callback(code)
        destroy()
      }
      Timer {
        id: watchdog
        interval: 8000
        repeat: false
        onTriggered: {
          proc.running = false
          job.finish(-1)
        }
      }
      Process {
        id: proc
        command: job.command
        stdinEnabled: job.input !== null
        onStarted: {
          if (job.input === null) return
          write(String(job.input))
          stdinEnabled = false
        }
        onExited: function(code, status) { job.finish(code) }
      }
    }
  }

  // done(code): exit code, or -1 when it could not run in time.
  function runJob(argv, input, done) {
    var job = pipeJob.createObject(store, {
      command: argv,
      input: input === undefined ? null : input,
      callback: done || null
    })
    if (!job) {
      if (done) done(-1)
      return
    }
    job.start()
  }

  // Atomic write verified by MD5. Exit codes:
  //   0 written (and removeAfter unlinked if requested)
  //   1 failed (or rolled back when removeAfter could not be removed)
  //   2 target exists (noClobber)
  //   3 target or removeAfter changed since it was read (expect / expectOld mismatch)
  //   4 target written, removeAfter could not be removed and rollback failed
  function writeFile(filePath, content, done, options) {
    var opts = options || {}
    var text = String(content === undefined || content === null ? "" : content)
    var want = Qt.md5(text)
    runJob(["sh", "-c", SkinParser.WRITE_FILE_SCRIPT, "sh", String(filePath || ""), want,
            opts.noClobber ? "1" : "0", opts.chmodExec ? "1" : "0",
            String(opts.removeAfter || ""), String(opts.expect || ""),
            String(opts.expectOld || "")],
      text,
      function(code) {
        if (code === 0) {
          store.recordHash(filePath, text)
          if (opts.removeAfter && opts.removeAfter !== filePath) store.clearHash(opts.removeAfter)
        } else if (code !== 3) {
          console.warn("Barcraft: could not write " + filePath + " (code " + code + ")")
        }
        if (done) done(code === 0, code)
      })
  }

  // Removes one or more regular non-symlink skin files inside allowedDirs and
  // confirms they are gone before reporting success.
  function removeSkinFiles(paths, done) {
    var list = Array.isArray(paths) ? paths : [paths]
    var safe = []
    var dirs = allowedDirs()
    for (var i = 0; i < list.length; i++) {
      var p = String(list[i] || "")
      if (p && SkinParser.isSafeSkinPath(p, dirs) && safe.indexOf(p) === -1) safe.push(p)
    }
    if (safe.length === 0) {
      if (done) done(false, 1)
      return
    }
    var argv = ["sh", "-c", SkinParser.REMOVE_SKIN_FILES_SCRIPT, "sh"].concat(safe)
    runJob(argv, null, function(code) {
      if (code === 0) {
        for (var j = 0; j < safe.length; j++) store.clearHash(safe[j])
      } else {
        console.warn("Barcraft: could not remove skin file(s) " + JSON.stringify(safe) + " (code " + code + ")")
      }
      if (done) done(code === 0, code)
    })
  }

  // Removes a regular file only while it still has the MD5 Barcraft checked.
  function removeFileIfUnchanged(filePath, expect, done) {
    runJob(["sh", "-c", SkinParser.REMOVE_IF_UNCHANGED_SCRIPT, "sh", String(filePath || ""), String(expect || "")], null, function(code) {
      if (done) done(code === 0, code)
    })
  }

  // Fresh, uncached read of a regular non-symlink file from disk.
  // Calls done(status, text) with status "ok" | "missing" | "error".
  Component {
    id: freshReadProc
    Item {
      id: reader
      visible: false
      property var command: []
      property var callback: null
      property bool finished: false
      property string captured: ""
      property bool streamDone: false
      property bool procExited: false
      property int exitCode: -1

      function start() {
        readProc.running = true
        readWatchdog.start()
      }

      function maybeFinish() {
        if (finished || !streamDone || !procExited) return
        finished = true
        readWatchdog.stop()
        // READ_FILE_SCRIPT already rejects files exceeding MAX_READ_FILE_BYTES
        // in bytes before writing stdout; keep a QML-side guard as well.
        var overflow = exitCode === 0 && captured.length > SkinParser.MAX_READ_FILE_BYTES
        var st = (exitCode === 0 && !overflow) ? "ok" : (exitCode === 3 ? "missing" : "error")
        if (callback) callback(st, st === "ok" ? captured : "")
        destroy()
      }

      Timer {
        id: readWatchdog
        interval: 8000
        repeat: false
        onTriggered: {
          if (reader.finished) return
          reader.finished = true
          readProc.running = false
          if (reader.callback) reader.callback("error", "")
          reader.destroy()
        }
      }

      Process {
        id: readProc
        command: reader.command
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: {
            reader.captured = text
            reader.streamDone = true
            reader.maybeFinish()
          }
        }
        onExited: function(code, status) {
          reader.exitCode = code
          reader.procExited = true
          reader.maybeFinish()
        }
      }
    }
  }

  function readTextFile(filePath, done) {
    var job = freshReadProc.createObject(store, {
      command: ["sh", "-c", SkinParser.READ_FILE_SCRIPT, "sh", String(filePath || "")],
      callback: done
    })
    if (!job) {
      if (done) done("error", "")
      return
    }
    job.start()
  }

  // Read-modify-write for a file other programs edit too. Reads it fresh,
  // lets `change(current, missing)` return the new text (or null to leave it),
  // and writes only if nobody saved the file in between; retries up to 3x.
  function editSharedFile(filePath, change, done, attempt) {
    var tries = attempt || 0
    readTextFile(filePath, function(status, text) {
      if (status === "error") {
        if (done) done(false)
        return
      }
      var missing = status === "missing"
      var current = missing ? "" : text
      var next = change(current, missing)
      if (next === null || next === undefined || next === current) {
        if (done) done(true)
        return
      }
      store.writeFile(filePath, next, function(ok, code) {
        if (code === 3 && tries < 2) {
          store.editSharedFile(filePath, change, done, tries + 1)
          return
        }
        if (code === 3) console.warn("Barcraft: " + filePath + " kept changing while Barcraft updated it; left it as it is")
        if (done) done(ok)
      }, { expect: missing ? "missing" : Qt.md5(current) })
    })
  }

  // ---- Scanning & live directory watching ----------------------------------

  property bool _scanAgain: false

  function rescan() {
    if (scanProc.running) {
      _scanAgain = true
      return
    }
    _scanAgain = false
    _scanStartGen = _hashGen
    scanProc.running = true
  }

  property real _skinWatchStartedAt: 0
  property int _skinWatchQuickExits: 0
  property bool _skinWatchRewatch: false
  property bool _skinWatchDisabled: false

  function startWatcher() {
    if (!isPrimary || _skinWatchDisabled || skinWatcher.running) return
    _skinWatchRewatch = false
    skinWatcher.running = true
  }

  function requestRewatch() {
    if (!isPrimary || _skinWatchDisabled) return
    skinRescanDebounce.restart()
    _skinWatchRewatch = true
    if (skinWatcher.running) {
      skinWatcher.running = false
    } else {
      skinWatchRestart.interval = 100
      skinWatchRestart.restart()
    }
  }

  Timer {
    id: skinRescanDebounce
    interval: 150
    repeat: false
    onTriggered: store.rescan()
  }

  Timer {
    id: skinWatchRestart
    interval: 1000
    repeat: false
    onTriggered: store.startWatcher()
  }

  Timer {
    id: skinWatchRecovered
    interval: 1000
    repeat: false
    onTriggered: {
      store._skinWatchQuickExits = 0
      store.rescan()
    }
  }

  Process {
    id: skinWatcher
    command: ["bash", "-c",
      "command -v inotifywait >/dev/null 2>&1 || exit 127; " +
      "dirs=(); for d in \"$1\" \"$2\" \"$3\" \"$4\"; do [ -n \"$d\" ] && [ -d \"$d\" ] && dirs+=(\"$d\"); done; " +
      "[ \"${#dirs[@]}\" -gt 0 ] || exit 1; " +
      "exec inotifywait -m -q -e close_write,create,delete,delete_self,move,move_self --format '%w|%e|%f' -- \"${dirs[@]}\"",
      "barcraft-skins-watch", store.userSkinsDir, store.legacySkinsDir, store.configDir + "/bar", store.configDir]
    onRunningChanged: {
      if (!running) return
      store._skinWatchStartedAt = Date.now()
      if (store._skinWatchQuickExits > 0) skinWatchRecovered.restart()
    }
    stdout: SplitParser {
      onRead: function(line) {
        var action = SkinParser.classifySkinWatchEvent(line, store.userSkinsDir, store.legacySkinsDir, store.configDir)
        if (action === "rewatch") store.requestRewatch()
        else if (action === "rescan") skinRescanDebounce.restart()
      }
    }
    onExited: function(code, status) {
      skinWatchRecovered.stop()
      if (!store.isPrimary) return
      if (code === 127) {
        store._skinWatchDisabled = true
        return
      }
      if (store._skinWatchRewatch) {
        store._skinWatchRewatch = false
        skinWatchRestart.interval = 100
        skinWatchRestart.restart()
        return
      }
      store._skinWatchQuickExits = Date.now() - store._skinWatchStartedAt < 1000 ? store._skinWatchQuickExits + 1 : 0
      skinWatchRestart.interval = Math.min(60000, 1000 * Math.pow(2, Math.max(0, store._skinWatchQuickExits - 4)))
      skinWatchRestart.restart()
    }
  }

  // Saved skins from both folders (the current one first, so it wins a name
  // clash), read with jq like Omarchy's own scripts: no python needed.
  // Pinned slugs (active, per-monitor, draft, and recently saved skins) are
  // scanned first so a large skin pack cannot push them past the 200-file cap.
  Process {
    id: scanProc
    command: ["sh", "-c", SkinParser.SCAN_SKINS_SCRIPT, "sh",
      String(SkinParser.MAX_SCANNED_SKINS), store.userSkinsDir, store.legacySkinsDir]
      .concat(Array.isArray(store.pinnedSlugs) ? store.pinnedSlugs : [])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          // Barcraft wrote or removed a skin while this scan ran, so what it
          // read may be older than what is on disk. Publishing it would pair
          // an old skin with the new file's hash and let a later Save
          // overwrite the newer file. Scan again instead.
          if (store._hashGen > store._scanStartGen) {
            Qt.callLater(store.rescan)
            return
          }
          var parsed = JSON.parse(text || "[]")
          var rows = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.rows) ? parsed.rows : [])
          var truncated = (!Array.isArray(parsed) && parsed && Number(parsed.truncated) > 0)
            ? Math.floor(Number(parsed.truncated)) : 0
          var hashes = {}
          for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            if (r && r.path && typeof r.text === "string") hashes[r.path] = Qt.md5(r.text)
          }
          store.skinHashes = store._mergeScanHashes(hashes)
          store.truncatedSkinCount = truncated
          var res = SkinParser.parseSkinLibraryDetailed(rows, [store.userSkinsDir, store.legacySkinsDir], store.builtinSkins)
          store.lastDiagnostics = res.diagnostics
          store.skinsScanned(res.skins, res.diagnostics, res.renamedIds, truncated)
        } catch (e) {
          console.warn("Barcraft: could not read saved skins: " + e)
        }
      }
    }
    onExited: {
      if (store._scanAgain) {
        store._scanAgain = false
        Qt.callLater(store.rescan)
      }
    }
  }

  Component.onCompleted: {
    rescan()
    startWatcher()
  }

  Component.onDestruction: {
    skinWatchRestart.stop()
    skinWatchRecovered.stop()
    skinRescanDebounce.stop()
    skinWatcher.running = false
  }
}

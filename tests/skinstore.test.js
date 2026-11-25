// Filesystem integration tests for SkinStore.qml + SkinEngine.qml file ops.
// Runs the exact shell scripts from SkinParser.js against a temporary skin
// directory to verify failed delete, concurrent external edit, rename cleanup,
// legacy sibling removal, and slow-save token guards.
// Run: node tests/skinstore.test.js
"use strict"
const assert = require("assert")
const crypto = require("crypto")
const fs = require("fs")
const os = require("os")
const path = require("path")
const vm = require("vm")
const { spawnSync } = require("child_process")
const P = require(path.join(__dirname, "..", "SkinParser.js"))

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (e) {
    console.error("FAIL " + name)
    throw e
  }
}

function md5(text) {
  return crypto.createHash("md5").update(String(text), "utf8").digest("hex")
}

function runWriteFile(dest, content, opts) {
  const o = opts || {}
  const text = String(content)
  const r = spawnSync("sh", [
    "-c", P.WRITE_FILE_SCRIPT, "sh",
    dest, md5(text),
    o.noClobber ? "1" : "0",
    o.chmodExec ? "1" : "0",
    String(o.removeAfter || ""),
    String(o.expect || "")
  ], { input: text, encoding: "utf8" })
  return r.status
}

function runRemoveSkins(paths) {
  const r = spawnSync("sh", ["-c", P.REMOVE_SKIN_FILES_SCRIPT, "sh", ...paths], { encoding: "utf8" })
  return r.status
}

function makeTempEnv() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "barcraft-store-test-"))
  const userDir = path.join(root, "bar", "skins")
  const legacyDir = path.join(root, "bar-skins")
  fs.mkdirSync(userDir, { recursive: true })
  fs.mkdirSync(legacyDir, { recursive: true })
  return { root, userDir, legacyDir }
}

function cleanupDir(dir) {
  // Restore write bits so rmSync always succeeds even after read-only tests.
  function chmodAll(p) {
    let st
    try { st = fs.lstatSync(p) } catch (_) { return }
    if (st.isSymbolicLink()) return
    if (st.isDirectory()) {
      try { fs.chmodSync(p, 0o755) } catch (_) {}
      for (const name of fs.readdirSync(p)) chmodAll(path.join(p, name))
    } else {
      try { fs.chmodSync(p, 0o644) } catch (_) {}
    }
  }
  chmodAll(dir)
  fs.rmSync(dir, { recursive: true, force: true })
}

function loadEngineHarness(userDir, legacyDir, pendingOps) {
  const qml = fs.readFileSync(path.join(__dirname, "..", "SkinEngine.qml"), "utf8")
  function method(name) {
    const re = new RegExp("^  (function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?^  \\})", "m")
    const m = qml.match(re)
    assert.ok(m, "missing method " + name + " in SkinEngine.qml")
    return m[1]
  }
  const notices = []
  const renamedEvents = []
  let rescans = 0
  let persists = 0
  const hashes = {}
  const ctx = vm.createContext({
    SkinParser: P,
    Qt: { md5 },
    console,
    userSkins: [],
    builtinSkins: P.builtinSkins(),
    userSkinsDir: userDir,
    legacySkinsDir: legacyDir,
    revision: 0,
    standard: false,
    followTheme: false,
    themeSkin: null,
    activeSkinId: "floating",
    prefs: P.normalizePrefs({}),
    stateLoaded: true,
    _renamedSkinIds: {},
    studioButtonPlaced: true,
    hasCustomDraft: false,
    draftBaseHash: "",
    customSkin: P.defaultSkin(),
    monitorSkins: {},
    monitorDrafts: {},
    monitorDraftBaseHashes: {},
    pasteUndoSnapshots: {},
    _editTokens: {},
    _tokenEpoch: 0,
    _legacyWaits: 0,
    truncatedSkinCount: 0,
    _recentSavedSlugs: [],
    _lastPinnedRescanKey: "",
    previewSkin: null,
    previewScreen: "",
    strings: {
      t: k => {
        if (k === "status.skippedNote") return "newer format; skipped: %1"
        if (k === "status.newerFormatNote") return "newer format"
        return k
      }
    },
    persistDebounce: { restart: () => {} },
    persistState: () => { persists++ },
    notice: (key, arg, isError) => { notices.push({ key, arg, isError }) },
    skinRenamed: (oldId, newId) => { renamedEvents.push({ oldId, newId }) },
    store: {
      hashForPath: p => hashes[p] || "",
      recordHash: (p, t) => { hashes[p] = md5(t) },
      rescan: () => { rescans++ },
      legacySiblingPath: p => {
        const prefix = userDir + "/"
        if (p.indexOf(prefix) !== 0) return ""
        return path.join(legacyDir, p.slice(prefix.length))
      },
      writeFile: (dest, content, done, opts) => {
        const exec = () => {
          const code = runWriteFile(dest, content, opts)
          if (code === 0) {
            hashes[dest] = md5(content)
            if (opts && opts.removeAfter && opts.removeAfter !== dest) delete hashes[opts.removeAfter]
          }
          if (done) done(code === 0, code)
        }
        if (pendingOps) pendingOps.push(exec)
        else exec()
      },
      removeSkinFiles: (paths, done) => {
        const exec = () => {
          const code = runRemoveSkins(paths)
          if (code === 0) paths.forEach(p => { delete hashes[p] })
          if (done) done(code === 0, code)
        }
        if (pendingOps) pendingOps.push(exec)
        else exec()
      },
      // Mirrors SkinStore.removeLegacySibling.
      removeLegacySibling: p => {
        const sibling = ctx.store.legacySiblingPath(p)
        if (sibling) ctx.store.removeSkinFiles([sibling], ok => { if (!ok) rescans++ })
      }
    }
  })
  Object.defineProperty(ctx, "usingThemeSkin", {
    get() { return ctx.followTheme && ctx.themeSkin !== null && !ctx.hasCustomDraft }
  })
  Object.defineProperty(ctx, "committedSkin", {
    get() {
      if (ctx.hasCustomDraft && ctx.customSkin) return ctx.customSkin
      if (ctx.followTheme && ctx.themeSkin) return ctx.themeSkin
      return ctx.findSkinById(ctx.activeSkinId) || P.defaultSkin()
    }
  })
  Object.defineProperty(ctx, "activeSkin", {
    get() { return (ctx.previewSkin && ctx.previewScreen === "") ? ctx.previewSkin : ctx.committedSkin }
  })
  const fns = [
    "normalizeTarget", "_tokenFor", "_bumpToken", "_setMonitorDraft", "_setPasteUndo",
    "_draftBaseHashFor", "_setDraftBaseHash", "_captureDraftBaseHash",
    "_rememberSavedSlug", "_forgetSavedSlug",
    "findSkinById", "isUserSkin", "monitorSkinFor", "monitorDraftFor", "hasDraftFor", "committedSkinFor",
    "standardFor", "currentName",
    "targetBaseId", "isSkinShared", "clearPreview", "clearPasteUndo",
    "builtinIdTaken", "slugForName", "skinPath", "replaceUserSkin",
    "selectSkin", "selectForScreen", "updateField", "resetTarget", "importText", "undoPaste",
    "saveUserSkin", "renameUserSkin", "deleteUserSkin",
    "stateJson", "applyState", "_migrateRenamedIds"
  ]
  vm.runInContext("var engine = this;\n" + fns.map(method).join("\n"), ctx)
  return { ctx, notices, renamedEvents, hashes, getRescans: () => rescans, getPersists: () => persists }
}

test("failed delete preserves Studio state, monitor assignments, and reports error", () => {
  const env = makeTempEnv()
  try {
    const file = path.join(env.userDir, "neon.toml")
    const content = P.serializeToml(P.normalizeSkin({ id: "neon", name: "Neon", height: 34 }, "neon", "user"))
    fs.writeFileSync(file, content, "utf8")
    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(content, "neon", "user"), { id: "neon", path: file })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "neon"
    h.ctx.monitorSkins = { "DP-2": "neon" }

    // Make skin directory read-only (skip assertion if running as root, since root ignores 0555).
    fs.chmodSync(env.userDir, 0o555)
    if (process.getuid && process.getuid() === 0) return

    h.ctx.deleteUserSkin("neon")
    assert.strictEqual(fs.existsSync(file), true)
    assert.strictEqual(h.ctx.userSkins.length, 1)
    assert.strictEqual(h.ctx.monitorSkins["DP-2"], "neon")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.deleteFailed")
    assert.strictEqual(h.notices[h.notices.length - 1].isError, true)
  } finally {
    cleanupDir(env.root)
  }
})

test("confirmed delete removes both primary and shadowed legacy skin files", () => {
  const env = makeTempEnv()
  try {
    const primary = path.join(env.userDir, "neon.toml")
    const legacy = path.join(env.legacyDir, "neon.toml")
    const content = P.serializeToml(P.normalizeSkin({ id: "neon", name: "Neon", height: 34 }, "neon", "user"))
    fs.writeFileSync(primary, content, "utf8")
    fs.writeFileSync(legacy, content, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(content, "neon", "user"), { id: "neon", path: primary })
    h.ctx.userSkins = [skin]
    h.ctx.monitorSkins = { "DP-2": "neon" }

    h.ctx.deleteUserSkin("neon")
    assert.strictEqual(fs.existsSync(primary), false)
    assert.strictEqual(fs.existsSync(legacy), false)
    assert.strictEqual(h.ctx.userSkins.length, 0)
    assert.strictEqual(h.ctx.monitorSkins["DP-2"], undefined)
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.deleted")
  } finally {
    cleanupDir(env.root)
  }
})

test("concurrent external edit blocks silent overwrite, keeps draft, and lets confirmed overwrite win", () => {
  const env = makeTempEnv()
  try {
    const file = path.join(env.userDir, "studio-skin.toml")
    const initial = P.serializeToml(P.normalizeSkin({ id: "studio-skin", name: "Studio Skin", height: 30 }, "studio-skin", "user"))
    fs.writeFileSync(file, initial, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(initial, "studio-skin", "user"), { id: "studio-skin", path: file })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "studio-skin"
    h.hashes[file] = md5(initial)

    // User edits height in Studio (draft = 40), while an editor externally changes height to 46 on disk.
    h.ctx.updateField("height", 40, "")
    const external = P.serializeToml(P.normalizeSkin({ id: "studio-skin", name: "Studio Skin", height: 46 }, "studio-skin", "user"))
    fs.writeFileSync(file, external, "utf8")

    h.ctx.saveUserSkin("Studio Skin", false, "")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saveChangedExternally")
    assert.strictEqual(h.ctx.hasCustomDraft, true)
    assert.strictEqual(h.ctx.committedSkin.height, 40)
    assert.strictEqual(fs.readFileSync(file, "utf8"), external)
    assert.ok(h.getRescans() >= 1)

    // Confirmed overwrite writes Studio's version cleanly.
    h.ctx.saveUserSkin("Studio Skin", true, "")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saved")
    assert.strictEqual(h.ctx.hasCustomDraft, false)
    assert.strictEqual(P.parseToml(fs.readFileSync(file, "utf8"), "studio-skin", "user").height, 40)
  } finally {
    cleanupDir(env.root)
  }
})

test("slow async save that finishes after switching skins never clobbers the user's newer choice", () => {
  const env = makeTempEnv()
  try {
    const pending = []
    const h = loadEngineHarness(env.userDir, env.legacyDir, pending)
    h.ctx.updateField("height", 44, "")

    const res = h.ctx.saveUserSkin("Late Save", false, "")
    assert.strictEqual(res.ok, true)
    assert.strictEqual(pending.length, 1)

    // Before the disk write finishes, the user switches to Islands.
    h.ctx.selectSkin("islands")
    assert.strictEqual(h.ctx.activeSkinId, "islands")

    // Now the earlier save finishes.
    pending[0]()
    assert.strictEqual(fs.existsSync(path.join(env.userDir, "late-save.toml")), true)
    assert.strictEqual(h.ctx.findSkinById("late-save").height, 44)
    // User's newer choice ("islands") stays active!
    assert.strictEqual(h.ctx.activeSkinId, "islands")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.savedKeptDraft")
  } finally {
    cleanupDir(env.root)
  }
})

test("rename rolls back cleanly if old file cannot be removed instead of leaving duplicates", () => {
  const env = makeTempEnv()
  try {
    const oldFile = path.join(env.legacyDir, "old-skin.toml")
    const content = P.serializeToml(P.normalizeSkin({ id: "old-skin", name: "Old Skin", height: 32 }, "old-skin", "user"))
    fs.writeFileSync(oldFile, content, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(content, "old-skin", "user"), { id: "old-skin", path: oldFile })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "old-skin"

    // Legacy dir is read-only so oldFile cannot be unlinked, while userDir is writable.
    fs.chmodSync(env.legacyDir, 0o555)
    if (process.getuid && process.getuid() === 0) return

    h.ctx.renameUserSkin("old-skin", "New Skin")
    assert.strictEqual(fs.existsSync(oldFile), true)
    assert.strictEqual(fs.existsSync(path.join(env.userDir, "new-skin.toml")), false)
    assert.strictEqual(h.ctx.userSkins[0].id, "old-skin")
    assert.strictEqual(h.renamedEvents.length, 0)
    assert.strictEqual(h.notices[h.notices.length - 1].isError, true)
  } finally {
    cleanupDir(env.root)
  }
})

test("editing a skin shared by two screens prompts before overwriting and Save As assigns only to the selected screen", () => {
  const env = makeTempEnv()
  try {
    const sharedFile = path.join(env.userDir, "shared.toml")
    const content = P.serializeToml(P.normalizeSkin({ id: "shared", name: "Shared", height: 30 }, "shared", "user"))
    fs.writeFileSync(sharedFile, content, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(content, "shared", "user"), { id: "shared", path: sharedFile })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "shared"
    h.ctx.monitorSkins = { "DP-2": "shared" }

    // Edit DP-2 only.
    h.ctx.updateField("height", 44, "DP-2")
    assert.strictEqual(h.ctx.committedSkinFor("DP-2").height, 44)
    assert.strictEqual(h.ctx.committedSkinFor("").height, 30)

    // Saving with the shared name requires confirmation because Main skin also uses it.
    const clash = h.ctx.saveUserSkin("Shared", false, "DP-2")
    assert.strictEqual(clash.needsConfirm, true)

    // Save As under a new name assigns the new skin only to DP-2 and leaves Main on Shared.
    const saved = h.ctx.saveUserSkin("Portrait Tall", false, "DP-2")
    assert.strictEqual(saved.ok, true)
    assert.strictEqual(h.ctx.monitorSkins["DP-2"], "portrait-tall")
    assert.strictEqual(h.ctx.monitorDrafts["DP-2"], undefined)
    assert.strictEqual(h.ctx.activeSkinId, "shared")
    assert.strictEqual(h.ctx.committedSkinFor("").height, 30)
  } finally {
    cleanupDir(env.root)
  }
})

test("delete commits on the skin's own file even when its legacy sibling can't be removed", () => {
  const env = makeTempEnv()
  try {
    const primary = path.join(env.userDir, "neon.toml")
    const elsewhere = path.join(env.root, "elsewhere.toml")
    const legacy = path.join(env.legacyDir, "neon.toml")
    const content = P.serializeToml(P.normalizeSkin({ id: "neon", name: "Neon", height: 34 }, "neon", "user"))
    fs.writeFileSync(primary, content, "utf8")
    fs.writeFileSync(elsewhere, content, "utf8")
    fs.symlinkSync(elsewhere, legacy)

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(content, "neon", "user"), { id: "neon", path: primary })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "neon"

    h.ctx.deleteUserSkin("neon")
    assert.strictEqual(fs.existsSync(primary), false)
    // The symlink is left alone (the scan never loads symlinks anyway).
    assert.strictEqual(fs.lstatSync(legacy).isSymbolicLink(), true)
    assert.strictEqual(fs.existsSync(elsewhere), true)
    assert.strictEqual(h.ctx.userSkins.length, 0)
    // The bar keeps the deleted skin on as an unsaved draft.
    assert.strictEqual(h.ctx.hasCustomDraft, true)
    assert.strictEqual(h.ctx.committedSkin.height, 34)
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.deleted")
  } finally {
    cleanupDir(env.root)
  }
})

test("rename removes the shadowed legacy copy of the old name", () => {
  const env = makeTempEnv()
  try {
    const primary = path.join(env.userDir, "foo.toml")
    const legacy = path.join(env.legacyDir, "foo.toml")
    const content = P.serializeToml(P.normalizeSkin({ id: "foo", name: "Foo", height: 34 }, "foo", "user"))
    fs.writeFileSync(primary, content, "utf8")
    fs.writeFileSync(legacy, content, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(content, "foo", "user"), { id: "foo", path: primary })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "foo"

    assert.strictEqual(h.ctx.renameUserSkin("foo", "Bar"), "bar")
    assert.strictEqual(fs.existsSync(path.join(env.userDir, "bar.toml")), true)
    assert.strictEqual(fs.existsSync(primary), false)
    assert.strictEqual(fs.existsSync(legacy), false)
    assert.strictEqual(h.ctx.activeSkinId, "bar")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.renamed")
  } finally {
    cleanupDir(env.root)
  }
})

test("a 0.6 choice of a saved 'Draft' or 'Standard' skin follows its new id", () => {
  const env = makeTempEnv()
  try {
    const h = loadEngineHarness(env.userDir, env.legacyDir)
    h.ctx.activeSkinId = "draft"
    h.ctx.monitorSkins = { "DP-2": "standard", "HDMI-A-1": "theme", "eDP-1": "islands" }
    h.ctx._renamedSkinIds = { draft: "draft-saved", standard: "standard-saved", theme: "theme-saved" }
    h.ctx._migrateRenamedIds()
    assert.strictEqual(h.ctx.activeSkinId, "draft-saved")
    assert.strictEqual(JSON.stringify(h.ctx.monitorSkins), JSON.stringify({ "DP-2": "standard-saved", "HDMI-A-1": "theme", "eDP-1": "islands" }))
    assert.strictEqual(h.getPersists(), 1)

    // Nothing to move: no write.
    h.ctx._migrateRenamedIds()
    assert.strictEqual(h.getPersists(), 1)
  } finally {
    cleanupDir(env.root)
  }
})

// SkinStore's hash bookkeeping, run from the QML source.
function loadStoreHashes() {
  const qml = fs.readFileSync(path.join(__dirname, "..", "SkinStore.qml"), "utf8")
  function method(name) {
    const re = new RegExp("^  (function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?^  \\})", "m")
    const m = qml.match(re)
    assert.ok(m, "missing method " + name + " in SkinStore.qml")
    return m[1]
  }
  const ctx = vm.createContext({ Qt: { md5 }, skinHashes: {}, _hashGen: 0, _hashGenByPath: {}, _scanStartGen: 0 })
  vm.runInContext(["hashForPath", "recordHash", "clearHash", "_touchHash", "_mergeScanHashes"].map(method).join("\n"), ctx)
  return ctx
}

test("a scan that started before a save never puts back the hash the save replaced", () => {
  const s = loadStoreHashes()
  s.recordHash("/s/foo.toml", "v1")
  s.recordHash("/s/gone.toml", "old")
  // A scan starts and reads v1 / old ...
  s._scanStartGen = s._hashGen
  const scanned = { "/s/foo.toml": md5("v1"), "/s/gone.toml": md5("old"), "/s/other.toml": md5("x") }
  // ... while Barcraft saves foo again and removes gone.
  s.recordHash("/s/foo.toml", "v2")
  s.clearHash("/s/gone.toml")
  s.skinHashes = s._mergeScanHashes(scanned)
  assert.strictEqual(s.hashForPath("/s/foo.toml"), md5("v2"))
  assert.strictEqual(s.hashForPath("/s/gone.toml"), "")
  assert.strictEqual(s.hashForPath("/s/other.toml"), md5("x"))

  // A scan that starts after the save takes what is on disk.
  s._scanStartGen = s._hashGen
  s.skinHashes = s._mergeScanHashes({ "/s/foo.toml": md5("edited elsewhere") })
  assert.strictEqual(s.hashForPath("/s/foo.toml"), md5("edited elsewhere"))
})

test("external edit followed by watcher rescan still blocks silent overwrite on Save", () => {
  const env = makeTempEnv()
  try {
    const file = path.join(env.userDir, "studio-skin.toml")
    const initial = P.serializeToml(P.normalizeSkin({ id: "studio-skin", name: "Studio Skin", height: 30 }, "studio-skin", "user"))
    fs.writeFileSync(file, initial, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(initial, "studio-skin", "user"), { id: "studio-skin", path: file })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "studio-skin"
    h.hashes[file] = md5(initial)

    // User starts editing in Studio (height 30 -> 40); draft captures initial file hash.
    h.ctx.updateField("height", 40, "")
    assert.strictEqual(h.ctx.draftBaseHash, md5(initial))

    // External editor saves height 46 AND the watcher rescans (updating live store hash to external).
    const external = P.serializeToml(P.normalizeSkin({ id: "studio-skin", name: "Studio Skin", height: 46 }, "studio-skin", "user"))
    fs.writeFileSync(file, external, "utf8")
    h.hashes[file] = md5(external)

    // Save must still compare against the draft's starting hash and block silent clobber.
    const res = h.ctx.saveUserSkin("Studio Skin", false, "")
    assert.strictEqual(res.ok, true)
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saveChangedExternally")
    assert.strictEqual(h.ctx.hasCustomDraft, true)
    assert.strictEqual(h.ctx.committedSkin.height, 40)
    assert.strictEqual(fs.readFileSync(file, "utf8"), external)

    // Confirmed overwrite writes Studio's version and clears the draft hash.
    h.ctx.saveUserSkin("Studio Skin", true, "")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saved")
    assert.strictEqual(h.ctx.hasCustomDraft, false)
    assert.strictEqual(h.ctx.draftBaseHash, "")
    assert.strictEqual(P.parseToml(fs.readFileSync(file, "utf8"), "studio-skin", "user").height, 40)
  } finally {
    cleanupDir(env.root)
  }
})

test("persisted draft survives shell restart and still blocks overwriting a newer external edit", () => {
  const env = makeTempEnv()
  try {
    const file = path.join(env.userDir, "persisted.toml")
    const initial = P.serializeToml(P.normalizeSkin({ id: "persisted", name: "Persisted", height: 30 }, "persisted", "user"))
    fs.writeFileSync(file, initial, "utf8")

    // Session 1: edit skin and persist state to shell.json.
    const h1 = loadEngineHarness(env.userDir, env.legacyDir)
    const skin1 = Object.assign(P.parseToml(initial, "persisted", "user"), { id: "persisted", path: file })
    h1.ctx.userSkins = [skin1]
    h1.ctx.activeSkinId = "persisted"
    h1.hashes[file] = md5(initial)
    h1.ctx.updateField("height", 42, "")
    const persistedJson = JSON.parse(h1.ctx.stateJson())
    assert.strictEqual(persistedJson.draftBaseHash, md5(initial))

    // External editor changes file while shell restarts.
    const external = P.serializeToml(P.normalizeSkin({ id: "persisted", name: "Persisted", height: 48 }, "persisted", "user"))
    fs.writeFileSync(file, external, "utf8")

    // Session 2: fresh engine scans the new external file and reloads persisted shell.json state.
    const h2 = loadEngineHarness(env.userDir, env.legacyDir)
    const skin2 = Object.assign(P.parseToml(external, "persisted", "user"), { id: "persisted", path: file })
    h2.ctx.userSkins = [skin2]
    h2.hashes[file] = md5(external)
    h2.ctx.applyState(P.stateFromJson(persistedJson, id => h2.ctx.findSkinById(id)))
    assert.strictEqual(h2.ctx.draftBaseHash, md5(initial))

    // Save is blocked because disk has external (48), not the draft's base (30).
    h2.ctx.saveUserSkin("Persisted", false, "")
    assert.strictEqual(h2.notices[h2.notices.length - 1].key, "status.saveChangedExternally")
    assert.strictEqual(fs.readFileSync(file, "utf8"), external)

    // Saving under a new name preserves both versions cleanly.
    const saveAs = h2.ctx.saveUserSkin("Persisted Copy", false, "")
    assert.strictEqual(saveAs.ok, true)
    assert.strictEqual(fs.readFileSync(file, "utf8"), external)
    assert.strictEqual(P.parseToml(fs.readFileSync(path.join(env.userDir, "persisted-copy.toml"), "utf8"), "persisted-copy", "user").height, 42)
  } finally {
    cleanupDir(env.root)
  }
})

test("draft restored from 0.7.0 state without a recorded base hash asks before overwriting", () => {
  const env = makeTempEnv()
  try {
    const file = path.join(env.userDir, "legacy-draft.toml")
    const onDisk = P.serializeToml(P.normalizeSkin({ id: "legacy-draft", name: "Legacy Draft", height: 46 }, "legacy-draft", "user"))
    fs.writeFileSync(file, onDisk, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(onDisk, "legacy-draft", "user"), { id: "legacy-draft", path: file })
    h.ctx.userSkins = [skin]
    h.hashes[file] = md5(onDisk)
    // 0.7.0 shell.json had no draftBaseHash field.
    const st = P.stateFromJson({
      skin: "legacy-draft",
      draft: { id: "legacy-draft", name: "Legacy Draft", height: 38 }
    }, id => h.ctx.findSkinById(id))
    h.ctx.applyState(st)
    assert.strictEqual(h.ctx.hasCustomDraft, true)
    assert.strictEqual(h.ctx.draftBaseHash, "")

    // Unconfirmed Save must ask first rather than silently overwriting disk.
    const first = h.ctx.saveUserSkin("Legacy Draft", false, "")
    assert.strictEqual(first.ok, false)
    assert.strictEqual(first.needsConfirm, true)
    assert.strictEqual(fs.readFileSync(file, "utf8"), onDisk)

    // Confirmed overwrite writes Studio's draft.
    const confirmed = h.ctx.saveUserSkin("Legacy Draft", true, "")
    assert.strictEqual(confirmed.ok, true)
    assert.strictEqual(P.parseToml(fs.readFileSync(file, "utf8"), "legacy-draft", "user").height, 38)
  } finally {
    cleanupDir(env.root)
  }
})

test("per-monitor draft blocks external overwrite after rescan, and paste+undo preserves base hash", () => {
  const env = makeTempEnv()
  try {
    const file = path.join(env.userDir, "portrait.toml")
    const initial = P.serializeToml(P.normalizeSkin({ id: "portrait", name: "Portrait", height: 32 }, "portrait", "user"))
    fs.writeFileSync(file, initial, "utf8")

    const h = loadEngineHarness(env.userDir, env.legacyDir)
    const skin = Object.assign(P.parseToml(initial, "portrait", "user"), { id: "portrait", path: file })
    h.ctx.userSkins = [skin]
    h.ctx.activeSkinId = "floating"
    h.ctx.monitorSkins = { "DP-2": "portrait" }
    h.hashes[file] = md5(initial)

    // Edit DP-2 (exclusive owner of portrait): captures base hash.
    h.ctx.updateField("height", 44, "DP-2")
    assert.strictEqual(h.ctx.monitorDraftBaseHashes["DP-2"], md5(initial))

    // Paste another skin named "Portrait" onto DP-2: saving it must ask before overwriting on-disk portrait.toml.
    assert.strictEqual(h.ctx.importText("[bar-skin]\nname = \"Portrait\"\nheight = 50\n", "DP-2"), true)
    assert.strictEqual(h.ctx.monitorDraftBaseHashes["DP-2"], undefined)
    const pasteSave = h.ctx.saveUserSkin("Portrait", false, "DP-2")
    assert.strictEqual(pasteSave.ok, false)
    assert.strictEqual(pasteSave.needsConfirm, true)

    // Undo paste restores the earlier draft (height 44) AND its original base hash.
    assert.strictEqual(h.ctx.undoPaste("DP-2"), true)
    assert.strictEqual(h.ctx.committedSkinFor("DP-2").height, 44)
    assert.strictEqual(h.ctx.monitorDraftBaseHashes["DP-2"], md5(initial))

    // External edit + rescan on portrait.toml still blocks DP-2 Save.
    const external = P.serializeToml(P.normalizeSkin({ id: "portrait", name: "Portrait", height: 36 }, "portrait", "user"))
    fs.writeFileSync(file, external, "utf8")
    h.hashes[file] = md5(external)
    h.ctx.saveUserSkin("Portrait", false, "DP-2")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saveChangedExternally")
    assert.strictEqual(fs.readFileSync(file, "utf8"), external)
  } finally {
    cleanupDir(env.root)
  }
})

function seedUserSkin(h, file, fields) {
  const content = P.serializeToml(P.normalizeSkin(Object.assign({ id: "studio-skin", name: "Studio Skin" }, fields), "studio-skin", "user"))
  fs.writeFileSync(file, content, "utf8")
  const skin = Object.assign(P.parseToml(content, "studio-skin", "user"), { id: "studio-skin", path: file, source: "user" })
  h.ctx.userSkins = [skin]
  h.ctx.activeSkinId = "studio-skin"
  h.hashes[file] = md5(content)
  return content
}

test("saving a draft of a legacy-folder skin writes the new folder without a false conflict", () => {
  const env = makeTempEnv()
  try {
    const h = loadEngineHarness(env.userDir, env.legacyDir)
    seedUserSkin(h, path.join(env.legacyDir, "studio-skin.toml"), { height: 30 })
    h.ctx.updateField("height", 40, "")
    h.ctx.saveUserSkin("Studio Skin", false, "")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saved")
    const saved = path.join(env.userDir, "studio-skin.toml")
    assert.strictEqual(P.parseToml(fs.readFileSync(saved, "utf8"), "studio-skin", "user").height, 40)
  } finally {
    cleanupDir(env.root)
  }
})

test("a draft kept through a slow save starts from the file that save wrote", () => {
  const env = makeTempEnv()
  try {
    const pending = []
    const h = loadEngineHarness(env.userDir, env.legacyDir, pending)
    const file = path.join(env.userDir, "studio-skin.toml")
    seedUserSkin(h, file, { height: 30 })
    h.ctx.updateField("height", 40, "")
    h.ctx.saveUserSkin("Studio Skin", false, "")
    h.ctx.updateField("radius", 9, "")
    pending.shift()()
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.savedKeptDraft")
    assert.strictEqual(h.ctx._draftBaseHashFor(""), md5(fs.readFileSync(file, "utf8")))
    h.ctx.saveUserSkin("Studio Skin", false, "")
    pending.shift()()
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saved")
    assert.strictEqual(P.parseToml(fs.readFileSync(file, "utf8"), "studio-skin", "user").radius, 9)
  } finally {
    cleanupDir(env.root)
  }
})

test("renaming the skin a draft started from carries the draft's base to the new file", () => {
  const env = makeTempEnv()
  try {
    const h = loadEngineHarness(env.userDir, env.legacyDir)
    seedUserSkin(h, path.join(env.userDir, "studio-skin.toml"), { height: 30 })
    h.ctx.updateField("height", 40, "")
    const newSlug = h.ctx.renameUserSkin("studio-skin", "Renamed")
    const newFile = path.join(env.userDir, newSlug + ".toml")
    assert.strictEqual(h.ctx._draftBaseHashFor(""), md5(fs.readFileSync(newFile, "utf8")))
    h.ctx.saveUserSkin("Renamed", false, "")
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.saved")
    assert.strictEqual(P.parseToml(fs.readFileSync(newFile, "utf8"), newSlug, "user").height, 40)
  } finally {
    cleanupDir(env.root)
  }
})

test("reloading state from shell.json while a save is in flight keeps the reloaded draft", () => {
  const env = makeTempEnv()
  try {
    const pending = []
    const h = loadEngineHarness(env.userDir, env.legacyDir, pending)
    seedUserSkin(h, path.join(env.userDir, "studio-skin.toml"), { height: 30 })
    h.ctx.updateField("height", 40, "")
    h.ctx.saveUserSkin("Studio Skin", false, "")
    const reloaded = P.normalizeSkin({ id: "studio-skin", name: "Studio Skin", height: 48 }, "studio-skin", "custom")
    h.ctx.applyState({ activeSkinId: "studio-skin", followTheme: false, standard: false, prefs: h.ctx.prefs,
      monitors: {}, monitorDrafts: {}, monitorDraftBaseHashes: {}, draft: reloaded, draftBaseHash: "" })
    pending.shift()()
    assert.strictEqual(h.notices[h.notices.length - 1].key, "status.savedKeptDraft")
    assert.strictEqual(h.ctx.hasCustomDraft, true)
    assert.strictEqual(h.ctx.committedSkin.height, 48)
  } finally {
    cleanupDir(env.root)
  }
})

test("skipped keys appear literally in the paste notice", () => {
  const env = makeTempEnv()
  try {
    const h = loadEngineHarness(env.userDir, env.legacyDir)
    assert.strictEqual(h.ctx.importText("[bar-skin]\nformat = 2\nheight = 34\n\"a$&b\" = 1\n", ""), true)
    assert.ok(h.notices[h.notices.length - 1].arg.indexOf("a$&b") !== -1)
  } finally {
    cleanupDir(env.root)
  }
})

test("large skin pack past the 200-file limit cannot push pinned active, monitor, or saved skins out of the scan", () => {
  const env = makeTempEnv()
  try {
    const body = name => P.serializeToml(P.normalizeSkin({ id: name, name: name, height: 34 }, name, "user"))
    // Drop a 212-file skin pack (pack-001 .. pack-212) plus two late-alphabet user skins.
    for (let i = 1; i <= 212; i++) {
      const slug = "pack-" + String(i).padStart(3, "0")
      fs.writeFileSync(path.join(env.userDir, slug + ".toml"), body(slug), "utf8")
    }
    const mine = path.join(env.userDir, "zzz-mine.toml")
    const mon = path.join(env.legacyDir, "zzz-monitor.toml")
    fs.writeFileSync(mine, body("ZZZ Mine"), "utf8")
    fs.writeFileSync(mon, body("ZZZ Monitor"), "utf8")
    // Symlink and oversized file must be ignored and not counted toward the cap or truncated total.
    fs.symlinkSync(mine, path.join(env.userDir, "aaa-link.toml"))
    fs.writeFileSync(path.join(env.userDir, "aaa-huge.toml"), "x".repeat(40000), "utf8")

    function runScan(limit, pinned) {
      const r = spawnSync(
        "sh",
        ["-c", P.SCAN_SKINS_SCRIPT, "sh", String(limit), env.userDir, env.legacyDir, ...pinned],
        { encoding: "utf8" }
      )
      assert.strictEqual(r.status, 0, r.stderr)
      return JSON.parse(r.stdout)
    }

    // Without pinning, 200 files load, 14 are truncated, and zzz-* skins fall past the cap.
    const unpinned = runScan(P.MAX_SCANNED_SKINS, [])
    assert.strictEqual(unpinned.rows.length, P.MAX_SCANNED_SKINS)
    assert.strictEqual(unpinned.truncated, 14)
    assert.strictEqual(unpinned.rows.some(r => r.path === mine), false)
    assert.strictEqual(unpinned.rows.some(r => r.path === mon), false)

    // With pinned slugs (active main + monitor skin), both zzz-* skins load first, with no duplicates.
    const pinnedSlugs = P.pinnedScanSlugs("zzz-mine", { "DP-2": "zzz-monitor" }, null, {}, [], P.builtinSkins(), [])
    const pinned = runScan(P.MAX_SCANNED_SKINS, pinnedSlugs)
    assert.strictEqual(pinned.rows.length, P.MAX_SCANNED_SKINS)
    assert.strictEqual(pinned.truncated, 14)
    assert.strictEqual(pinned.rows.filter(r => r.path === mine).length, 1)
    assert.strictEqual(pinned.rows.filter(r => r.path === mon).length, 1)
    assert.strictEqual(pinned.rows.some(r => r.path.endsWith("aaa-link.toml")), false)
    assert.strictEqual(pinned.rows.some(r => r.path.endsWith("aaa-huge.toml")), false)
  } finally {
    cleanupDir(env.root)
  }
})

console.log("SkinStore: " + passed + " tests passed")

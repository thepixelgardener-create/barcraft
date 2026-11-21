// Regression tests for SkinParser.js. Run: node tests/skinparser.test.js
"use strict"
const assert = require("assert")
const path = require("path")
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

function roundtrip(fields) {
  const skin = P.normalizeSkin(Object.assign({ id: "t" }, fields), "t", "user")
  return P.parseToml(P.serializeToml(skin), "t", "user")
}

test("names with apostrophes, quotes and backslashes survive a save", () => {
  for (const name of ["Bob's Neon", "Say \"hi\"", "back\\slash", "it's \"both\""]) {
    assert.strictEqual(roundtrip({ name }).name, name)
  }
})

test("markup-shaped names stay plain text and are kept verbatim", () => {
  const name = "<img src=x>"
  assert.strictEqual(roundtrip({ name }).name, name)
})

test("control characters are stripped from labels", () => {
  assert.strictEqual(P.normalizeSkin({ name: "a\u0007b\nc" }, "t").name, "ab c")
})

test("single-quoted literal strings parse", () => {
  const s = P.parseToml("[bar-skin]\nname = 'Bob\"s'\nmode = 'islands'\n", "x", "user")
  assert.strictEqual(s.name, "Bob\"s")
  assert.strictEqual(s.mode, "islands")
})

test("color refs: hex, theme tokens, aliases, junk", () => {
  assert.strictEqual(P.normalizeColorRef("#AABBCC"), "#aabbcc")
  assert.strictEqual(P.normalizeColorRef("theme.blue"), "theme.blue")
  assert.strictEqual(P.normalizeColorRef("accent"), "theme.accent")
  assert.strictEqual(P.normalizeColorRef("red; rm -rf"), "")
  assert.strictEqual(P.normalizeColorRef("theme.Bad Key"), "")
})

test("theme color tokens round-trip through TOML", () => {
  const s = roundtrip({ customBackground: "theme.blue", gradientTo: "theme.magenta", fill: "gradient" })
  assert.strictEqual(s.customBackground, "theme.blue")
  assert.strictEqual(s.gradientTo, "theme.magenta")
  assert.strictEqual(s.fill, "gradient")
})

test("new fields round-trip", () => {
  const s = roundtrip({ shadow: true, shadowStrength: 0.8, widgetStyle: "chips", iconScale: 1.25, surfaceTone: 0.7, contrast: 1.3 })
  assert.strictEqual(s.shadow, true)
  assert.strictEqual(s.shadowStrength, 0.8)
  assert.strictEqual(s.widgetStyle, "chips")
  assert.strictEqual(s.iconScale, 1.25)
  assert.strictEqual(s.surfaceTone, 0.7)
  assert.strictEqual(s.contrast, 1.3)
})

test("old skins: one contrast drives the surface too", () => {
  const s = P.parseToml("[bar-skin]\nname = \"Old\"\ncontrast = 1.4\n", "old", "user")
  assert.strictEqual(s.surfaceTone, 1.4)
})

test("warcraft loads as runeforge", () => {
  assert.strictEqual(P.normalizeSkin({ art: "warcraft" }, "w").art, "runeforge")
  assert.strictEqual(P.canonicalSkinId("warcraft"), "runeforge")
  assert.ok(P.builtinSkins().some(s => s.id === "runeforge"))
  assert.ok(!P.builtinSkins().some(s => s.id === "warcraft" || /warcraft/i.test(s.name)))
})

test("preset shorthand overrides only what it names", () => {
  const lookup = id => P.builtinSkins().find(s => s.id === id) || null
  const s = P.parseFromShellValues({ "bar-skin.preset": "islands", "bar-skin.radius": "20" }, lookup)
  assert.strictEqual(s.mode, "islands")
  assert.strictEqual(s.radius, 20)
  assert.strictEqual(s.name, "Islands")
  assert.strictEqual(s.id, "theme-skin")
})

test("no [bar-skin] in shell values means no theme skin", () => {
  assert.strictEqual(P.parseFromShellValues({ "bar.background": "x" }), null)
})

test("state file: prefs, monitors and draft round-trip", () => {
  const draft = P.normalizeSkin({ id: "d", name: "Draft's" }, "d", "custom")
  const text = P.serializeStateToml("islands", false, draft,
    { autohideDelay: 900, autohideWhen: "windows", revealOnWorkspace: true },
    { "HDMI-A-1": "frosted", "eDP-1": "theme", "bad name!": "x" })
  const st = P.parseStateToml(text)
  assert.strictEqual(st.activeSkinId, "islands")
  assert.strictEqual(st.followTheme, false)
  assert.deepStrictEqual(st.prefs, { autohideDelay: 900, autohideWhen: "windows", revealOnWorkspace: true, omarchyMenu: false, updateCheck: false })
  assert.deepStrictEqual(st.monitors, { "HDMI-A-1": "frosted", "eDP-1": "theme" })
  assert.strictEqual(P.parseToml(text, "islands", "custom").name, "Draft's")
})

test("state file without a draft has no skin in it", () => {
  const text = P.serializeStateToml("floating", true, null, null, null)
  assert.strictEqual(P.parseToml(text, "floating", "custom"), null)
})

test("prefs are clamped and validated", () => {
  const p = P.normalizePrefs({ autohideWhen: "warp", autohideDelay: 99999 })
  assert.strictEqual(p.autohideWhen, "always")
  assert.strictEqual(p.autohideDelay, 3000)
})

test("icon overrides: added to an existing file, user keys win, removed at 1.0", () => {
  const user = "[font]\nbase-size = 12\n"
  const scaled = P.applyBarIconOverrides(user, 1.25)
  assert.ok(scaled.startsWith("[font]\nbase-size = 12\n"))
  assert.ok(/\[bar\] # barcraft/.test(scaled))
  assert.ok(/icon-size = 15 # barcraft/.test(scaled))
  assert.strictEqual(P.applyBarIconOverrides(scaled, 1.0), user)

  const handSet = "[bar]\nicon-size = 20\n"
  const mixed = P.applyBarIconOverrides(handSet, 1.5)
  assert.ok(/^icon-size = 20$/m.test(mixed))
  assert.ok(!/icon-size = 18 # barcraft/.test(mixed))
  assert.ok(/icon-font = 20 # barcraft/.test(mixed))
  assert.strictEqual(P.applyBarIconOverrides(mixed, 1.0), handSet)
})

test("icon overrides on a missing file", () => {
  assert.strictEqual(P.applyBarIconOverrides("", 1.0), "")
  const created = P.applyBarIconOverrides("", 0.8)
  assert.ok(created.startsWith("[bar] # barcraft\n"))
  assert.strictEqual(P.applyBarIconOverrides(created, 1.0), "")
})

test("icon overrides keep [bar] header when user added keys under Barcraft's [bar] section", () => {
  const withUserKey =
    "[font]\nbase-size = 12\n\n" +
    "[bar] # barcraft\n" +
    "icon-slot = 34 # barcraft\n" +
    "icon-canvas = 20 # barcraft\n" +
    "icon-font = 16 # barcraft\n" +
    "icon-size = 15 # barcraft\n" +
    "size-horizontal = 36\n"
  const reset = P.applyBarIconOverrides(withUserKey, 1.0)
  assert.strictEqual(reset, "[font]\nbase-size = 12\n\n[bar]\nsize-horizontal = 36\n")

  const rescaled = P.applyBarIconOverrides(withUserKey, 1.5)
  assert.ok(/^\[bar\]$/m.test(rescaled))
  assert.ok(/^size-horizontal = 36$/m.test(rescaled))
  assert.ok(/icon-size = 18 # barcraft/.test(rescaled))

  const betweenSections =
    "[font]\nbase-size = 12\n\n" +
    "[bar] # barcraft\n" +
    "icon-size = 15 # barcraft\n\n" +
    "[osd]\nheight = 40\n"
  assert.strictEqual(
    P.applyBarIconOverrides(betweenSections, 1.0),
    "[font]\nbase-size = 12\n\n[osd]\nheight = 40\n"
  )
})

test("isPristineUpdateHook accepts only an unedited Barcraft hook", () => {
  const md5 = text => require("crypto").createHash("md5").update(text, "utf8").digest("hex")
  const body = "plugin='/p'\nomarchy-notification-send -g '󰍜' Barcraft 'Grüße'\n"
  const hook = P.stampUpdateHook(body, md5)
  assert.ok(hook.startsWith("#!/bin/bash\n" + P.HOOK_OWNED_MARKER + "\n# barcraft-digest: "))
  assert.strictEqual(P.isPristineUpdateHook(hook, md5, []), true)

  // Edited after Barcraft wrote it, header kept: no longer Barcraft's.
  assert.strictEqual(P.isPristineUpdateHook(hook + "echo mine\n", md5, []), false)
  assert.strictEqual(P.isPristineUpdateHook(hook.replace("Grüße", "Hallo"), md5, []), false)
  // A header copied into someone else's script proves nothing.
  const copied = "#!/bin/bash\n" + P.HOOK_OWNED_MARKER + "\n# barcraft-digest: " + "0".repeat(32) + "\necho custom\n"
  assert.strictEqual(P.isPristineUpdateHook(copied, md5, []), false)
  assert.strictEqual(P.isPristineUpdateHook("#!/bin/bash\n" + P.HOOK_OWNED_MARKER + "\necho hi\n", md5, []), false)

  // Hooks from 0.5.0/0.5.1 have no digest: only an exact match counts.
  const legacy = "#!/bin/bash\n" + P.HOOK_OWNED_MARKER + "\n# Turn it off to remove.\n" + body
  assert.strictEqual(P.isPristineUpdateHook(legacy, md5, [legacy]), true)
  assert.strictEqual(P.isPristineUpdateHook(legacy + "echo mine\n", md5, [legacy]), false)
  assert.strictEqual(P.isPristineUpdateHook("", md5, [""]), false)
  assert.strictEqual(P.isPristineUpdateHook("#!/bin/bash\necho custom\n", md5, []), false)
})

test("an untouched 0.5.0 hook stays Barcraft's after the language changes", () => {
  const md5 = text => require("crypto").createHash("md5").update(text, "utf8").digest("hex")
  const dir = "/home/me/.config/omarchy/plugins/thepixelgardener.barcraft"
  // Byte for byte what 0.5.0 wrote with Omarchy set to German.
  const german050 = [
    "#!/bin/bash",
    "# Added by Barcraft (thepixelgardener.barcraft). Turn \"Check after Omarchy",
    "# updates\" off in Barcraft Studio to remove this file.",
    "plugin='" + dir + "'",
    "[[ -f $plugin/scripts/sync-upstream.sh ]] || exit 0",
    "if ! bash \"$plugin/scripts/sync-upstream.sh\" --check >/dev/null 2>&1; then",
    "  omarchy-notification-send -g '󰍜' Barcraft 'Omarchy hat seine Leiste aktualisiert. Führe scripts/sync-upstream.sh im Barcraft-Ordner aus, um das Update zu übernehmen.'",
    "fi",
    ""
  ].join("\n")
  const legacy = P.legacyUpdateHookScripts(dir)
  assert.strictEqual(P.isPristineUpdateHook(german050, md5, legacy), true)
  assert.strictEqual(P.isPristineUpdateHook(german050.replace("Führe", "Starte"), md5, legacy), false)
  assert.strictEqual(P.isPristineUpdateHook(german050, md5, P.legacyUpdateHookScripts("/elsewhere")), false)

  // Today's hook in English is pristine; the language it was written in doesn't matter.
  const current = P.updateHookScript(dir, "Omarchy updated its bar.", md5)
  assert.strictEqual(P.isPristineUpdateHook(current, md5, legacy), true)
})

test("resolveSaveTarget prevents silent overwrite on slug collisions and prompts on name clash", () => {
  const existing = [
    { id: "my-skin", name: "My Skin" },
    { id: "my-skin-2", name: "My Skin?" }
  ]
  const builtinTaken = slug => slug === "islands" || slug === "statusline"

  // Distinct display name whose slug collides with "my-skin" and "my-skin-2":
  // must allocate a fresh slug instead of overwriting either existing skin.
  const distinct = P.resolveSaveTarget("my skin!", existing, "floating", builtinTaken, false)
  assert.deepStrictEqual(distinct, { slug: "my-skin-3", overwrite: false, needsConfirm: false, conflictName: "" })

  // Exact same display name as the currently active skin updates in place.
  const activeUpdate = P.resolveSaveTarget("My Skin", existing, "my-skin", builtinTaken, false)
  assert.deepStrictEqual(activeUpdate, { slug: "my-skin", overwrite: true, needsConfirm: false, conflictName: "" })

  // Exact same display name as a different existing skin requires confirmation first.
  const clash = P.resolveSaveTarget("My Skin", existing, "floating", builtinTaken, false)
  assert.deepStrictEqual(clash, { slug: "my-skin", overwrite: false, needsConfirm: true, conflictName: "My Skin" })

  // Confirmed overwrite targets the matched skin explicitly.
  const confirmed = P.resolveSaveTarget("My Skin", existing, "floating", builtinTaken, true)
  assert.deepStrictEqual(confirmed, { slug: "my-skin", overwrite: true, needsConfirm: false, conflictName: "" })

  // Built-in name collision gets -custom suffix without overwriting built-ins.
  const builtinClash = P.resolveSaveTarget("Islands", existing, "floating", builtinTaken, false)
  assert.deepStrictEqual(builtinClash, { slug: "islands-custom", overwrite: false, needsConfirm: false, conflictName: "" })
})

test("theme colors parse with every key mapped", () => {
  const text = "accent = \"#7aa2f7\"\nblue = \"#7aa2f7\"\nbackground = '1a1b26'\n"
  assert.deepStrictEqual(Object.assign({}, P.themeColorMap(text)), { accent: "#7aa2f7", blue: "#7aa2f7", background: "#1a1b26" })
  assert.strictEqual(P.parseThemeColorsToml(text).length, 2)
})

test("old motion prefs in a state file are ignored", () => {
  const st = P.parseStateToml("[barcraft]\nart-motion = \"always\"\npause-on-battery = true\n")
  assert.deepStrictEqual(Object.keys(st.prefs).sort(), ["autohideDelay", "autohideWhen", "omarchyMenu", "revealOnWorkspace", "updateCheck"])
  assert.ok(!/art-motion|pause-on-battery/.test(P.serializeStateToml("floating", true, null, st.prefs, null)))
})

test("built-in skins promise no motion", () => {
  for (const s of P.builtinSkins()) assert.ok(!/rotat|live|animat/i.test(s.name + " " + s.description), s.id)
})

test("standard mode round-trips and defaults off", () => {
  assert.strictEqual(P.parseStateToml("[barcraft]\nactive-skin = \"islands\"\n").standard, false)
  const st = P.parseStateToml(P.serializeStateToml("islands", false, null, null, null, true))
  assert.strictEqual(st.standard, true)
  assert.strictEqual(st.activeSkinId, "islands")
  const s = P.standardSkin()
  assert.strictEqual(s.mode, "edge")
  assert.strictEqual(s.border, "none")
  assert.strictEqual(s.radius + s.edgeMargin + s.sideMargin, 0)
})

test("auto values: parsed, kept, serialized, and the default", () => {
  const s = P.parseToml("[bar-skin]\nradius = auto\nheight = \"auto\"\nedge-margin = 4\nbackground-alpha = \"AUTO\"\n", "a", "user")
  assert.strictEqual(s.radius, "auto")
  assert.strictEqual(s.height, "auto")
  assert.strictEqual(s.edgeMargin, 4)
  assert.strictEqual(s.backgroundAlpha, "auto")
  const back = P.parseToml(P.serializeToml(s), "a", "user")
  assert.strictEqual(back.radius, "auto")
  assert.strictEqual(back.edgeMargin, 4)
  assert.strictEqual(P.defaultSkin().radius, "auto")
  assert.strictEqual(P.normalizeSkin({ radius: "round" }, "x").radius, "auto")
})

test("classic presets follow Omarchy; art presets keep their own geometry", () => {
  const byId = Object.fromEntries(P.builtinSkins().map(s => [s.id, s]))
  for (const id of ["floating", "islands", "frosted"]) {
    assert.strictEqual(byId[id].radius, "auto", id)
    assert.strictEqual(byId[id].sideMargin, "auto", id)
    assert.strictEqual(byId[id].height, "auto", id)
  }
  assert.strictEqual(byId.capsule.radius, 16)
  assert.strictEqual(byId.matrix.height, 30)
  assert.strictEqual(byId.runeforge.height, 32)
  assert.ok(!byId.rocket && !byId.barber)
})

test("preset #8 statusline is a compact high-contrast developer preset", () => {
  const list = P.builtinSkins()
  assert.strictEqual(list.length, 8)
  const dev = list[7]
  assert.strictEqual(dev.id, "statusline")
  assert.strictEqual(dev.name, "Statusline")
  assert.strictEqual(dev.category, "classic")
  assert.strictEqual(dev.mode, "edge")
  assert.strictEqual(dev.height, 26)
  assert.strictEqual(dev.radius, 0)
  assert.strictEqual(dev.widgetStyle, "chips")
  assert.strictEqual(dev.border, "subtle")
  assert.strictEqual(dev.iconScale, 1.0)
  assert.strictEqual(dev.art, "none")

  const lookup = id => list.find(s => s.id === id) || null
  const custom = P.parseToml("[bar-skin]\npreset = \"statusline\"\ncontrast = 1.25\n", "dev", "user", lookup)
  assert.strictEqual(custom.mode, "edge")
  assert.strictEqual(custom.widgetStyle, "chips")
  assert.strictEqual(custom.height, 26)
  assert.strictEqual(custom.contrast, 1.25)
})

test("width is a clamped percentage and opacity may reach zero", () => {
  assert.strictEqual(P.normalizeSkin({ width: 10 }, "w").width, 30)
  assert.strictEqual(P.normalizeSkin({ width: 80 }, "w").width, 80)
  assert.strictEqual(P.normalizeSkin({ backgroundAlpha: 0 }, "w").backgroundAlpha, 0)
})

test("shell.json state round-trips, including the draft and integration switches", () => {
  const draft = P.normalizeSkin({ id: "d", name: "Bob's", radius: "auto", width: 70 }, "d", "custom")
  const json = P.stateToJson("islands", false, draft,
    { autohideDelay: 800, omarchyMenu: true, updateCheck: true }, { "HDMI-A-1": "editorial", "../x": "y" }, true)
  const st = P.stateFromJson(JSON.parse(JSON.stringify(json)))
  assert.strictEqual(st.activeSkinId, "islands")
  assert.strictEqual(st.followTheme, false)
  assert.strictEqual(st.standard, true)
  assert.strictEqual(st.prefs.autohideDelay, 800)
  assert.strictEqual(st.prefs.omarchyMenu, true)
  assert.strictEqual(st.prefs.updateCheck, true)
  assert.deepStrictEqual(st.monitors, { "HDMI-A-1": "editorial" })
  assert.strictEqual(st.draft.name, "Bob's")
  assert.strictEqual(st.draft.radius, "auto")
  assert.strictEqual(st.draft.width, 70)
  assert.ok(!("source" in json.draft) && !("category" in json.draft))
})

test("shell.json state tolerates junk", () => {
  for (const junk of [null, 42, "x", [], { skin: { evil: 1 }, draft: [1], monitors: 5 }]) {
    const st = P.stateFromJson(junk)
    assert.strictEqual(typeof st.activeSkinId, "string")
    assert.strictEqual(st.draft, null)
  }
})

function parseJsonc(t) {
  let o = "", i = 0
  while (i < t.length) {
    const c = t[i]
    if (c === "\"") { let j = i + 1; while (j < t.length && t[j] !== "\"") { if (t[j] === "\\") j++; j++ } o += t.slice(i, j + 1); i = j + 1; continue }
    if (c === "/" && t[i + 1] === "/") { while (i < t.length && t[i] !== "\n") i++; continue }
    if (c === "/" && t[i + 1] === "*") { i = t.indexOf("*/", i + 2) + 2; continue }
    o += c; i++
  }
  return JSON.parse(o.replace(/,(\s*[}\]])/g, "$1"))
}

test("Omarchy menu block: valid JSONC in, same file out", () => {
  const entries = [["appearance.top-bar.barcraft", { label: "Barcraft" }], ["appearance.top-bar.barcraft.studio", { label: "Studio", action: "omarchy-shell shell toggle thepixelgardener.barcraft" }]]
  const cases = [
    "{\n  // header\n  \"a\": {\"action\":\"xdg-open https://x.org//y\"} // note\n}\n",
    "{\n  \"a\": 1 /* c } */\n}",
    "{\n  \"a\": 1,\n}\n",
    "{}",
    ""
  ]
  for (const t of cases) {
    const added = P.applyMenuBlock(t, entries)
    const obj = parseJsonc(added)
    assert.ok(obj["appearance.top-bar.barcraft.studio"], t)
    assert.strictEqual(P.applyMenuBlock(added, entries), added, "idempotent")
    const removed = P.applyMenuBlock(added, null)
    assert.deepStrictEqual(t.trim() ? parseJsonc(removed) : {}, t.trim() ? parseJsonc(t) : {})
  }
  assert.strictEqual(P.applyMenuBlock("not json at all", entries), "not json at all")
})

test("prototype pollution and prototype-chain keys are blocked in TOML and JSON", () => {
  const nasty = "[__proto__]\npolluted = \"yes\"\n[constructor]\npolluted2 = \"yes\"\n[bar-skin]\nname = \"Safe\"\n__proto__ = \"bad\"\ntoString = \"bad\"\n"
  const s = P.parseToml(nasty, "x", "user")
  assert.strictEqual(({}).polluted, undefined)
  assert.strictEqual(({}).polluted2, undefined)
  assert.strictEqual(s.name, "Safe")

  assert.strictEqual(P.normalizeColorRef("constructor"), "")
  assert.strictEqual(P.normalizeColorRef("toString"), "")
  assert.strictEqual(P.normalizeColorRef("__proto__"), "")
  assert.strictEqual(P.canonicalSkinId("toString"), "tostring")
  assert.strictEqual(P.canonicalSkinId("constructor"), "constructor")

  const st = P.parseStateToml("[barcraft-monitors]\n__proto__ = \"floating\"\nconstructor = \"islands\"\nHDMI-A-1 = \"frosted\"\n")
  assert.strictEqual(({}).polluted, undefined)
  assert.deepStrictEqual(st.monitors, { "HDMI-A-1": "frosted" })

  const colors = P.themeColorMap("__proto__ = \"#112233\"\nconstructor = \"#445566\"\naccent = \"#7aa2f7\"\n")
  assert.strictEqual(Object.getPrototypeOf(colors), null)
  assert.strictEqual(colors.accent, "#7aa2f7")
  assert.strictEqual(colors["__proto__"], undefined)
})

test("background field rejects TOML injection and serializes safely", () => {
  const s = P.parseToml("[bar-skin]\nname = \"Ok\"\nbackground = \"x\\\"\\n[injected]\\nevil = true\"\n", "x", "user")
  assert.strictEqual(s.background, "bar.background")
  const serialized = P.serializeToml(s)
  assert.ok(!/\[injected\]/.test(serialized))
  assert.ok(/background\s*=\s*"bar\.background"/.test(serialized))

  const validRef = P.normalizeSkin({ background: "theme.blue" }, "x")
  assert.strictEqual(validRef.background, "theme.blue")
})

test("unclosed or malformed menu markers never truncate omarchy-menu.jsonc", () => {
  const unclosed = "{\n  \"keep\": 1,\n  // barcraft:begin\n  \"user_entry\": 2\n}\n"
  assert.strictEqual(P.applyMenuBlock(unclosed, null), unclosed)
  assert.strictEqual(P.applyMenuBlock(unclosed, [["a", { label: "A" }]]), unclosed)

  const strayEnd = "{\n  \"keep\": 1,\n  // barcraft:end\n  \"user_entry\": 2\n}\n"
  assert.strictEqual(P.applyMenuBlock(strayEnd, null), strayEnd)
})

test("isSafeSkinPath confines paths to allowed skin directories", () => {
  const dirs = ["/home/u/.config/omarchy/bar/skins", "/home/u/.config/omarchy/bar-skins"]
  assert.strictEqual(P.isSafeSkinPath("/home/u/.config/omarchy/bar/skins/my-skin.toml", dirs), true)
  assert.strictEqual(P.isSafeSkinPath("/home/u/.config/omarchy/bar-skins/old_1.toml", dirs), true)
  assert.strictEqual(P.isSafeSkinPath("/home/u/.config/omarchy/bar/skins/../shell.json", dirs), false)
  assert.strictEqual(P.isSafeSkinPath("/home/u/.config/omarchy/bar/skins/sub/a.toml", dirs), false)
  assert.strictEqual(P.isSafeSkinPath("/etc/passwd", dirs), false)
  assert.strictEqual(P.isSafeSkinPath("/home/u/.config/omarchy/bar/skins/.hidden.toml", dirs), false)
  assert.strictEqual(P.isSafeSkinPath("/home/u/.config/omarchy/bar/skins/evil.sh", dirs), false)
})

test("neutralizeMarkup breaks markup-shaped input for shared tooltip/OSD sinks", () => {
  const tracker = "<img src=\"https://example.invalid/tracker\"><b>hi</b>"
  const safe = P.neutralizeMarkup(tracker)
  assert.ok(!/<img\b/i.test(safe))
  assert.ok(!/<b>/i.test(safe))
  assert.strictEqual(safe.replace(/\u200b/g, ""), tracker)
})

test("parseSkinLibrary resolves custom preset inheritance in one pass regardless of file order", () => {
  const dirs = ["/demo/skins", "/demo/legacy-skins"]
  const rows = [
    { path: "/demo/skins/a-grandchild.toml", text: "[bar-skin]\nname = \"Grandchild\"\npreset = \"b-child\"\nradius = 20\n" },
    { path: "/demo/skins/b-child.toml", text: "[bar-skin]\nname = \"Child\"\npreset = \"z-parent\"\nwidget-style = \"pills\"\n" },
    { path: "/demo/skins/z-parent.toml", text: "[bar-skin]\nname = \"Parent\"\npreset = \"islands\"\nheight = 48\n" },
    { path: "/demo/legacy-skins/z-parent.toml", text: "[bar-skin]\nname = \"Stale Legacy\"\nheight = 24\n" },
    { path: "/demo/skins/../escape.toml", text: "[bar-skin]\nname = \"Evil\"\nheight = 50\n" }
  ]
  const skins = P.parseSkinLibrary(rows, dirs, P.builtinSkins())
  assert.strictEqual(skins.length, 3)
  const byId = Object.fromEntries(skins.map(s => [s.id, s]))
  assert.strictEqual(byId["z-parent"].name, "Parent")
  assert.strictEqual(byId["z-parent"].mode, "islands")
  assert.strictEqual(byId["z-parent"].height, 48)
  assert.strictEqual(byId["b-child"].height, 48)
  assert.strictEqual(byId["b-child"].mode, "islands")
  assert.strictEqual(byId["b-child"].widgetStyle, "pills")
  assert.strictEqual(byId["a-grandchild"].height, 48)
  assert.strictEqual(byId["a-grandchild"].mode, "islands")
  assert.strictEqual(byId["a-grandchild"].widgetStyle, "pills")
  assert.strictEqual(byId["a-grandchild"].radius, 20)
})

test("parseSkinLibrary breaks preset cycles and lets a user file inherit from a same-named built-in", () => {
  const dirs = ["/demo/skins"]
  const rows = [
    { path: "/demo/skins/loop-a.toml", text: "[bar-skin]\nname = \"Loop A\"\npreset = \"loop-b\"\nheight = 36\n" },
    { path: "/demo/skins/loop-b.toml", text: "[bar-skin]\nname = \"Loop B\"\npreset = \"loop-a\"\nradius = 14\n" },
    { path: "/demo/skins/islands.toml", text: "[bar-skin]\nname = \"My Islands\"\npreset = \"islands\"\nheight = 42\n" }
  ]
  const skins = P.parseSkinLibrary(rows, dirs, P.builtinSkins())
  const byId = Object.fromEntries(skins.map(s => [s.id, s]))
  assert.strictEqual(byId["loop-a"].height, 36)
  assert.strictEqual(byId["loop-b"].radius, 14)
  assert.strictEqual(byId["islands"].mode, "islands")
  assert.strictEqual(byId["islands"].height, 42)
  assert.strictEqual(byId["islands"].blur, true)
})

test("classifySkinWatchEvent handles edits, renames, temp files, and created/removed skin dirs", () => {
  const userDir = "/home/u/.config/omarchy/bar/skins"
  const legacyDir = "/home/u/.config/omarchy/bar-skins"
  const cfgDir = "/home/u/.config/omarchy"

  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|CLOSE_WRITE,CLOSE|neon.toml", userDir, legacyDir, cfgDir), "rescan")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|MOVED_TO|shared.toml", userDir, legacyDir, cfgDir), "rescan")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|MOVED_FROM|old.toml", userDir, legacyDir, cfgDir), "rescan")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|DELETE|old.toml", userDir, legacyDir, cfgDir), "rescan")
  assert.strictEqual(P.classifySkinWatchEvent(legacyDir + "/|CREATE|legacy.toml", userDir, legacyDir, cfgDir), "rescan")

  // Temp files and unrelated config changes never trigger rescans.
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|CLOSE_WRITE,CLOSE|.barcraft.abc123", userDir, legacyDir, cfgDir), "ignore")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|CREATE|.neon.toml.swp", userDir, legacyDir, cfgDir), "ignore")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|CLOSE_WRITE,CLOSE|notes.txt", userDir, legacyDir, cfgDir), "ignore")
  assert.strictEqual(P.classifySkinWatchEvent(cfgDir + "/|CLOSE_WRITE,CLOSE|shell.json", userDir, legacyDir, cfgDir), "ignore")

  // Skin folder creation or removal re-attaches the watcher and rescans.
  assert.strictEqual(P.classifySkinWatchEvent(cfgDir + "/|CREATE,ISDIR|bar", userDir, legacyDir, cfgDir), "rewatch")
  assert.strictEqual(P.classifySkinWatchEvent(cfgDir + "/|CREATE,ISDIR|bar-skins", userDir, legacyDir, cfgDir), "rewatch")
  assert.strictEqual(P.classifySkinWatchEvent(cfgDir + "/bar/|CREATE,ISDIR|skins", userDir, legacyDir, cfgDir), "rewatch")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|DELETE_SELF|", userDir, legacyDir, cfgDir), "rewatch")
  assert.strictEqual(P.classifySkinWatchEvent(userDir + "/|MOVE_SELF|", userDir, legacyDir, cfgDir), "rewatch")
})

test("SkinEngine handlers: single-pass scan, per-monitor zone sizing, and one-step paste undo", () => {
  const fs = require("fs")
  const vm = require("vm")
  const qml = fs.readFileSync(path.join(__dirname, "..", "SkinEngine.qml"), "utf8")
  const processText = qml.slice(qml.indexOf("id: scanProc"))
  const scanHandler = processText.match(/onStreamFinished: \{\n([\s\S]*?)\n      \}\n    \}\n/)[1]
  function method(name) {
    const re = new RegExp("^  (function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?^  \\})", "m")
    const m = qml.match(re)
    assert.ok(m, "missing method " + name + " in SkinEngine.qml")
    return m[1]
  }

  const notices = []
  let persists = 0
  const ctx = vm.createContext({
    SkinParser: P,
    console,
    userSkins: [],
    builtinSkins: P.builtinSkins(),
    userSkinsDir: "/demo/skins",
    legacySkinsDir: "/demo/legacy-skins",
    revision: 0,
    standard: false,
    followTheme: false,
    themeSkin: null,
    activeSkinId: "statusline",
    hasCustomDraft: false,
    customSkin: P.defaultSkin(),
    pasteUndoSnapshot: null,
    previewSkin: null,
    previewScreen: "",
    vertical: false,
    monitorSkins: { "DP-2": "child" },
    Style: { bar: { sizeHorizontal: 30, sizeVertical: 28 }, space: x => x, gapsOut: 6 },
    strings: { t: k => k === "label.standard" ? "Omarchy standard" : k },
    persistState: () => { persists++ },
    notice: (key, arg, isError) => { notices.push({ key, arg, isError }) },
    text: JSON.stringify([
      { path: "/demo/skins/child.toml", text: "[bar-skin]\nname = \"Child\"\npreset = \"base\"\n" },
      { path: "/demo/skins/base.toml", text: "[bar-skin]\nname = \"Base\"\nheight = 48\nedge-margin = 8\n" }
    ])
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
  Object.defineProperty(ctx, "standardActive", {
    get() { return ctx.standard && !(ctx.previewSkin && ctx.previewScreen === "") }
  })

  const fns = [
    "findSkinById", "monitorSkinFor", "skinForScreen", "barSizePxOf", "edgePxOf", "zoneFor",
    "clearPreview", "clearPasteUndo", "currentName", "importText", "undoPaste", "selectSkin", "resetToPreset"
  ]
  vm.runInContext("var engine = this;\n" + fns.map(method).join("\n"), ctx)

  // 1) First scan resolves child -> base in one pass even when child precedes base.
  vm.runInContext("(function(){" + scanHandler + "})()", ctx)
  assert.strictEqual(ctx.userSkins.length, 2)
  assert.strictEqual(ctx.findSkinById("child").height, 48)
  assert.strictEqual(ctx.revision, 1)
  // Re-scanning identical files does not bump revision.
  vm.runInContext("(function(){" + scanHandler + "})()", ctx)
  assert.strictEqual(ctx.revision, 1)

  // 2) Secondary monitor zone uses that monitor's committed skin size, and hovering a preview leaves it alone.
  assert.strictEqual(ctx.zoneFor("DP-1").sizePx, 26)
  assert.strictEqual(ctx.zoneFor("DP-2").sizePx, 48)
  assert.strictEqual(ctx.zoneFor("DP-2").edgePx, 8)
  ctx.previewScreen = "DP-2"
  ctx.previewSkin = P.normalizeSkin({ id: "prev", name: "Prev", height: 34 }, "prev", "custom")
  assert.strictEqual(ctx.skinForScreen("DP-2").height, 34)
  assert.strictEqual(ctx.zoneFor("DP-2").sizePx, 48)

  // 3) Paste saves previous draft and Undo paste restores it verbatim.
  ctx.customSkin = P.normalizeSkin({ id: "floating", name: "Tuned Draft", height: 40, radius: 18 }, "floating", "custom")
  ctx.hasCustomDraft = true
  ctx.importText("[bar-skin]\nname = \"Shared\"\nheight = 24\nradius = 2\n")
  assert.strictEqual(ctx.committedSkin.name, "Shared")
  assert.strictEqual(ctx.committedSkin.height, 24)
  assert.ok(ctx.pasteUndoSnapshot !== null)

  // Invalid paste leaves undo snapshot intact.
  ctx.importText("not a skin")
  assert.strictEqual(ctx.committedSkin.name, "Shared")
  assert.ok(ctx.pasteUndoSnapshot !== null)

  // Undo paste restores the tuned draft.
  assert.strictEqual(ctx.undoPaste(), true)
  assert.strictEqual(ctx.hasCustomDraft, true)
  assert.strictEqual(ctx.committedSkin.name, "Tuned Draft")
  assert.strictEqual(ctx.committedSkin.height, 40)
  assert.strictEqual(ctx.committedSkin.radius, 18)
  assert.strictEqual(ctx.pasteUndoSnapshot, null)
  assert.strictEqual(notices[notices.length - 1].key, "status.pasteUndone")
  assert.strictEqual(notices[notices.length - 1].arg, "Tuned Draft")

  // Selecting another skin clears undo snapshot.
  ctx.importText("[bar-skin]\nname = \"Shared 2\"\nheight = 28\n")
  assert.ok(ctx.pasteUndoSnapshot !== null)
  ctx.selectSkin("islands")
  assert.strictEqual(ctx.pasteUndoSnapshot, null)
  assert.ok(persists > 0)
})

console.log("SkinParser: " + passed + " tests passed")

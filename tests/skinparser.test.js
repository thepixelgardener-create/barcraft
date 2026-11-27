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
  assert.strictEqual(list.length, 9)
  const dev = list.find(s => s.id === "statusline")
  assert.ok(dev)
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

  const amiga = list.find(s => s.id === "amiga")
  assert.ok(amiga)
  assert.strictEqual(amiga.category, "wild")
  assert.strictEqual(amiga.art, "amiga")
  assert.strictEqual(amiga.customForeground, "#ffffff")
  // A custom accent or background switches Wild Craft art to the theme
  // palette; the preset keeps Workbench blue and orange in the art itself.
  assert.strictEqual(amiga.customAccent, "")
  assert.strictEqual(amiga.customBackground, "")
  assert.strictEqual(amiga.themeTint, false)
  const rt = roundtrip({ art: "amiga", name: "Amiga" })
  assert.strictEqual(rt.art, "amiga")
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

test("SkinEngine handlers: single-pass scan, per-monitor editing/zones, diagnostics, and per-target undo", () => {
  const fs = require("fs")
  const vm = require("vm")
  const qml = fs.readFileSync(path.join(__dirname, "..", "SkinEngine.qml"), "utf8")
  const storeQml = fs.readFileSync(path.join(__dirname, "..", "SkinStore.qml"), "utf8")
  const processText = storeQml.slice(storeQml.indexOf("id: scanProc"))
  const scanHandler = processText.match(/onStreamFinished: \{\n([\s\S]*?)\n      \}\n    \}\n/)[1]
  function method(name) {
    const re = new RegExp("^  (function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?^  \\})", "m")
    const m = qml.match(re)
    assert.ok(m, "missing method " + name + " in SkinEngine.qml")
    return m[1]
  }

  const notices = []
  let persists = 0
  let debounces = 0
  const crypto = require("crypto")
  const md5 = s => crypto.createHash("md5").update(String(s), "utf8").digest("hex")
  const ctx = vm.createContext({
    SkinParser: P,
    Qt: { md5 },
    console,
    userSkins: [],
    skinDiagnostics: [],
    builtinSkins: P.builtinSkins(),
    userSkinsDir: "/demo/skins",
    legacySkinsDir: "/demo/legacy-skins",
    revision: 0,
    standard: false,
    followTheme: false,
    themeSkin: null,
    activeSkinId: "statusline",
    hasCustomDraft: false,
    draftBaseHash: "",
    studioButtonPlaced: true,
    customSkin: P.defaultSkin(),
    monitorSkins: { "DP-2": "child" },
    monitorDrafts: {},
    monitorDraftBaseHashes: {},
    pasteUndoSnapshots: {},
    _editTokens: {},
    _tokenEpoch: 0,
    _legacyWaits: 0,
    previewSkin: null,
    previewScreen: "",
    vertical: false,
    Style: { bar: { sizeHorizontal: 30, sizeVertical: 28 }, space: x => x, gapsOut: 6 },
    strings: {
      t: k => {
        if (k === "label.standard") return "Omarchy standard"
        if (k === "status.skippedNote") return "newer format; skipped: %1"
        if (k === "status.newerFormatNote") return "newer format"
        return k
      }
    },
    persistDebounce: { restart: () => { debounces++ } },
    persistState: () => { persists++ },
    notice: (key, arg, isError) => { notices.push({ key, arg, isError }) },
    text: JSON.stringify([
      { path: "/demo/skins/child.toml", text: "[bar-skin]\nname = \"Child\"\npreset = \"base\"\n" },
      { path: "/demo/skins/base.toml", text: "[bar-skin]\nname = \"Base\"\nheight = 48\nedge-margin = 8\n" }
    ])
  })
  ctx.store = {
    userSkinsDir: ctx.userSkinsDir,
    legacySkinsDir: ctx.legacySkinsDir,
    builtinSkins: ctx.builtinSkins,
    skinHashes: {},
    truncatedSkinCount: 0,
    hashForPath: p => (ctx.store.skinHashes && ctx.store.skinHashes[p]) || "",
    lastDiagnostics: [],
    _mergeScanHashes: h => h,
    skinsScanned: (skins, diags, renamedIds, truncatedCount) => {
      ctx.skinDiagnostics = diags || []
      ctx.truncatedSkinCount = truncatedCount || 0
      if (JSON.stringify(skins) !== JSON.stringify(ctx.userSkins)) {
        ctx.userSkins = skins
        ctx.revision++
      }
    }
  }
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
    "normalizeTarget", "_tokenFor", "_bumpToken", "_setMonitorDraft", "_setPasteUndo", "canUndoPasteFor",
    "_draftBaseHashFor", "_setDraftBaseHash", "_captureDraftBaseHash",
    "findSkinById", "monitorSkinFor", "monitorDraftFor", "hasMonitorSkin", "hasDraftFor",
    "committedSkinFor", "skinForScreen", "standardFor", "targetBaseId", "isSkinShared",
    "barSizePxOf", "edgePxOf", "zoneFor", "chosenIdFor",
    "clearPreview", "clearPasteUndo", "currentName", "updateField",
    "exportToml", "importText", "undoPaste", "selectSkin", "selectForScreen", "resetTarget", "resetToPreset"
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

  // 3) Editing a secondary monitor creates a per-screen draft and leaves Main skin untouched.
  ctx.updateField("height", 36, "DP-2")
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)
  assert.strictEqual(ctx.zoneFor("DP-2").sizePx, 36)
  assert.strictEqual(ctx.committedSkinFor("").height, 26)
  assert.strictEqual(ctx.hasDraftFor("DP-2"), true)
  assert.strictEqual(ctx.hasDraftFor(""), false)
  assert.ok(/height\s*=\s*36/.test(ctx.exportToml("DP-2")))
  assert.ok(/height\s*=\s*26/.test(ctx.exportToml("")))
  assert.ok(debounces > 0)

  // 4) Per-screen paste + undo only affect that monitor.
  assert.strictEqual(ctx.importText("[bar-skin]\nname = \"Portrait\"\nheight = 44\n", "DP-2"), true)
  assert.strictEqual(ctx.committedSkinFor("DP-2").name, "Portrait")
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 44)
  assert.strictEqual(ctx.committedSkinFor("").name, "Statusline")
  assert.strictEqual(ctx.canUndoPasteFor("DP-2"), true)
  assert.strictEqual(ctx.canUndoPasteFor(""), false)
  assert.strictEqual(ctx.undoPaste("DP-2"), true)
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)

  // 5) Strict paste: typo or unknown preset alongside valid name preserves current draft and undo history.
  const prevLen = notices.length
  assert.strictEqual(ctx.importText("[bar-skin]\nname = \"Broken\"\npreset = \"missing\"\n", "DP-2"), false)
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)
  assert.strictEqual(ctx.canUndoPasteFor("DP-2"), false)
  assert.strictEqual(notices[prevLen].key, "status.importError")
  assert.ok(/Line 3: unknown preset "missing"/.test(notices[prevLen].arg))

  const typoIdx = notices.length
  assert.strictEqual(ctx.importText("[bar-skin]\nname = \"Typo\"\nheight = 44\nheigth = 34\n", "DP-2"), false)
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)
  assert.strictEqual(notices[typoIdx].key, "status.importError")
  assert.ok(/Line 4/.test(notices[typoIdx].arg) && /heigth/.test(notices[typoIdx].arg) && /height/.test(notices[typoIdx].arg))

  // Metadata-only paste (name + description, no style keys) is rejected cleanly.
  assert.strictEqual(ctx.importText("[bar-skin]\nname = \"Only Name\"\ndescription = \"Nothing\"\n", "DP-2"), false)
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)

  // 5b) Newer format (format = 2) applies known fields, warns with skipped keys, and keeps Undo paste.
  assert.strictEqual(ctx.importText("[bar-skin]\nformat = 2\nname = \"Future\"\nheight = 42\nglow = 0.5\n", "DP-2"), true)
  assert.strictEqual(ctx.committedSkinFor("DP-2").name, "Future")
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 42)
  assert.strictEqual(ctx.canUndoPasteFor("DP-2"), true)
  assert.strictEqual(notices[notices.length - 1].key, "status.importedAdjusted")
  assert.ok(/glow/.test(notices[notices.length - 1].arg))
  // A subsequent broken paste must leave both the Future draft AND its Undo snapshot untouched.
  assert.strictEqual(ctx.importText("[bar-skin]\nname = \"Bad\"\npreset = \"nope\"\n", "DP-2"), false)
  assert.strictEqual(ctx.committedSkinFor("DP-2").name, "Future")
  assert.strictEqual(ctx.canUndoPasteFor("DP-2"), true)
  assert.strictEqual(ctx.undoPaste("DP-2"), true)
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)

  // 6) Clamped value paste applies skin and reports the adjustment.
  assert.strictEqual(ctx.importText("[bar-skin]\nname = \"Tall\"\nheight = 999\n", ""), true)
  assert.strictEqual(ctx.committedSkin.height, 56)
  assert.strictEqual(notices[notices.length - 1].key, "status.importedAdjusted")
  assert.ok(/Line 3: height adjusted to 56/.test(notices[notices.length - 1].arg))

  // 7) Undo on Main skin restores Statusline, leaving DP-2 draft intact.
  assert.strictEqual(ctx.undoPaste(""), true)
  assert.strictEqual(ctx.committedSkin.name, "Statusline")
  assert.strictEqual(ctx.committedSkinFor("DP-2").height, 36)

  // 8) Returning DP-2 to Main skin clears both override and draft.
  ctx.selectForScreen("DP-2", "")
  assert.strictEqual(ctx.hasMonitorSkin("DP-2"), false)
  assert.strictEqual(ctx.committedSkinFor("DP-2").name, "Statusline")
  assert.ok(persists > 0)
})

test("inspectToml distinguishes hard errors from clamped adjustments and suggests fixes", () => {
  const typoOnly = P.inspectToml("[bar-skin]\nheigth = 34\n", "imported", "custom")
  assert.strictEqual(typoOnly.skin, null)
  assert.strictEqual(typoOnly.appliedCount, 0)
  assert.strictEqual(typoOnly.errors.length, 1)
  assert.strictEqual(typoOnly.errors[0].line, 2)
  assert.strictEqual(typoOnly.errors[0].suggestion, "height")
  assert.ok(/Line 2: unknown key "heigth" \(did you mean "height"\?\)/.test(typoOnly.errors[0].message))

  const badPreset = P.inspectToml("[bar-skin]\npreset = \"missing\"\n", "imported", "custom", () => null)
  assert.strictEqual(badPreset.skin, null)
  assert.strictEqual(badPreset.appliedCount, 0)
  assert.ok(/Line 2: unknown preset "missing"/.test(badPreset.errors[0].message))

  const clamped = P.inspectToml("[bar-skin]\nname = \"Big\"\nheight = 999\n", "imported", "custom")
  assert.ok(clamped.skin !== null)
  assert.strictEqual(clamped.skin.height, 56)
  assert.strictEqual(clamped.errors.length, 0)
  assert.strictEqual(clamped.adjustments.length, 1)
  assert.strictEqual(clamped.adjustments[0].line, 3)
  assert.strictEqual(clamped.adjustments[0].applied, 56)
})

test("inspectShellValues reports theme [bar-skin] typos and clamps", () => {
  const res = P.inspectShellValues({ "bar-skin.heigth": "34", "bar-skin.height": "99" }, () => null)
  assert.ok(res.skin !== null)
  assert.strictEqual(res.skin.height, 56)
  assert.strictEqual(res.errors.length, 1)
  assert.ok(/heigth/.test(res.errors[0].message))
  assert.strictEqual(res.adjustments.length, 1)
  assert.strictEqual(res.adjustments[0].applied, 56)
})

test("reserved IDs (standard, draft, theme) never collide on save or disk load", () => {
  assert.strictEqual(P.isReservedSkinId("standard"), true)
  assert.strictEqual(P.isReservedSkinId("draft"), true)
  assert.strictEqual(P.isReservedSkinId("theme"), true)
  assert.strictEqual(P.isReservedSkinId("islands"), true)
  assert.strictEqual(P.isReservedSkinId("my-custom"), false)

  const target = P.resolveSaveTarget("Standard", [], "floating", slug => P.isReservedSkinId(slug), false)
  assert.strictEqual(target.slug, "standard-custom")

  const lib = P.parseSkinLibraryDetailed([
    { path: "/demo/skins/standard.toml", text: "[bar-skin]\nname = \"Standard\"\nheight = 38\n" },
    { path: "/demo/skins/draft.toml", text: "[bar-skin]\nname = \"Draft\"\nheight = 34\n" },
    { path: "/demo/skins/broken.toml", text: "[bar-skin]\nheigth = 34\n" }
  ], ["/demo/skins"], P.builtinSkins())
  assert.strictEqual(lib.skins.length, 2)
  assert.strictEqual(lib.skins[0].id, "standard-saved")
  assert.strictEqual(lib.skins[0].path, "/demo/skins/standard.toml")
  assert.strictEqual(lib.skins[1].id, "draft-saved")
  assert.strictEqual(lib.diagnostics.length, 1)
  assert.strictEqual(lib.diagnostics[0].path, "/demo/skins/broken.toml")
  assert.strictEqual(JSON.stringify(lib.renamedIds), JSON.stringify({ standard: "standard-saved", draft: "draft-saved" }))
})

test("skin library: renamed reserved slugs never duplicate, and presets naming the old id still resolve", () => {
  const lib = P.parseSkinLibraryDetailed([
    { path: "/demo/skins/standard.toml", text: "[bar-skin]\nname = \"Standard\"\nheight = 38\n" },
    { path: "/demo/skins/child.toml", text: "[bar-skin]\nname = \"Child\"\npreset = \"standard\"\n" },
    { path: "/demo/legacy/standard-saved.toml", text: "[bar-skin]\nname = \"Other\"\nheight = 44\n" }
  ], ["/demo/skins", "/demo/legacy"], P.builtinSkins())
  const ids = lib.skins.map(s => s.id)
  assert.strictEqual(JSON.stringify(ids), JSON.stringify(["standard-saved", "child"]))
  assert.strictEqual(lib.skins[0].path, "/demo/skins/standard.toml")
  assert.strictEqual(lib.skins[1].height, 38)
  assert.strictEqual(lib.diagnostics.length, 0)
})

test("skin library: a broken or empty file never hides a working one in the other folder", () => {
  const lib = P.parseSkinLibraryDetailed([
    { path: "/demo/skins/foo.toml", text: "# not a skin yet\n" },
    { path: "/demo/skins/new.toml", text: "  \n" },
    { path: "/demo/legacy/foo.toml", text: "[bar-skin]\nname = \"Foo\"\nheight = 40\n" }
  ], ["/demo/skins", "/demo/legacy"], P.builtinSkins())
  assert.strictEqual(lib.skins.length, 1)
  assert.strictEqual(lib.skins[0].id, "foo")
  assert.strictEqual(lib.skins[0].path, "/demo/legacy/foo.toml")
  const byPath = {}
  lib.diagnostics.forEach(d => { byPath[d.path] = d.errors[0].message })
  assert.strictEqual(byPath["/demo/skins/foo.toml"], "No [bar-skin] section found")
  assert.strictEqual(byPath["/demo/skins/new.toml"], "File is empty")
})

test("serializeToml: Copy TOML omits inactive sub-keys, skin files keep them", () => {
  const plain = P.serializeToml(P.defaultSkin(), { compact: true })
  assert.ok(/shell\.bar-skin\.toml/.test(plain))
  assert.ok(!/shadow-strength/.test(plain))
  assert.ok(!/bezel-strength/.test(plain))
  assert.ok(!/theme-tint/.test(plain))
  assert.ok(!/hover-edge-px/.test(plain))

  const rich = P.serializeToml(P.normalizeSkin({
    art: "matrix", themeTint: true, bezel: "raised", shadow: true, visibility: "autohide"
  }, "rich", "user"))
  assert.ok(/theme-tint\s*=\s*true/.test(rich))
  assert.ok(/bezel-strength\s*=/.test(rich))
  assert.ok(/shadow-strength\s*=/.test(rich))
  assert.ok(/hover-edge-px\s*=/.test(rich))

  // Saved to disk, values for a switched-off feature survive a round trip.
  const off = P.normalizeSkin({ visibility: "always", hoverEdgePx: 10, accentHairline: false, shadow: false, shadowStrength: 0.4 }, "off", "user")
  const full = P.serializeToml(off)
  assert.ok(/hover-edge-px\s*=\s*10/.test(full))
  assert.ok(/accent-hairline\s*=\s*false/.test(full))
  const back = P.parseToml(full, "off", "user")
  assert.strictEqual(back.hoverEdgePx, 10)
  assert.strictEqual(back.accentHairline, false)
  assert.strictEqual(back.shadowStrength, 0.4)
  assert.ok(!/hover-edge-px/.test(P.serializeToml(off, { compact: true })))
})

test("shell.json state round-trips per-screen monitorDrafts cleanly", () => {
  const mDraft = P.normalizeSkin({ id: "islands", name: "DP-2 Custom", height: 42, radius: 18 }, "islands", "custom")
  const json = P.stateToJson("floating", true, null, null, { "DP-2": "islands" }, false, { "DP-2": mDraft, "../bad": mDraft })
  const st = P.stateFromJson(JSON.parse(JSON.stringify(json)))
  assert.deepStrictEqual(Object.keys(st.monitorDrafts), ["DP-2"])
  assert.strictEqual(st.monitorDrafts["DP-2"].height, 42)
  assert.strictEqual(st.monitorDrafts["DP-2"].name, "DP-2 Custom")
})

test("semver comparison and remote manifest version validation", () => {
  assert.deepStrictEqual(P.parseSemver("0.7.0"), [0, 7, 0])
  assert.deepStrictEqual(P.parseSemver("v1.2.10"), [1, 2, 10])
  assert.strictEqual(P.parseSemver("0.7.0-beta"), null)
  assert.strictEqual(P.parseSemver("<img src=x>"), null)
  assert.strictEqual(P.compareSemver("0.7.1", "0.7.0"), 1)
  assert.strictEqual(P.compareSemver("0.7.0", "0.7.0"), 0)
  assert.strictEqual(P.compareSemver("0.6.0", "0.7.0"), -1)
  assert.strictEqual(P.compareSemver("0.10.0", "0.7.9"), 1)

  const valid = JSON.stringify({ id: "thepixelgardener.barcraft", version: "0.7.1" })
  assert.strictEqual(P.parseRemoteManifestVersion(valid, "thepixelgardener.barcraft"), "0.7.1")
  const wrongId = JSON.stringify({ id: "someone.else", version: "9.9.9" })
  assert.strictEqual(P.parseRemoteManifestVersion(wrongId, "thepixelgardener.barcraft"), "")
  const badVer = JSON.stringify({ id: "thepixelgardener.barcraft", version: "<b>1.0.0</b>" })
  assert.strictEqual(P.parseRemoteManifestVersion(badVer, "thepixelgardener.barcraft"), "")
  assert.strictEqual(P.parseRemoteManifestVersion("not json", "thepixelgardener.barcraft"), "")
  assert.strictEqual(P.parseRemoteManifestVersion("x".repeat(20000), "thepixelgardener.barcraft"), "")
})

test("format version: format = 1 exports round-trip, unversioned 0.7 skins paste, and format > 1 skips unknown keys", () => {
  const exported = P.serializeToml(P.normalizeSkin({ id: "fmt", name: "Fmt", height: 34 }, "fmt", "user"), { compact: true })
  assert.ok(/^format\s*=\s*1$/m.test(exported))
  const rt = P.inspectToml(exported, "imported", "custom")
  assert.strictEqual(rt.errors.length, 0)
  assert.strictEqual(rt.formatVersion, 1)
  assert.strictEqual(rt.newerFormat, false)
  assert.strictEqual(rt.skin.height, 34)

  // Unversioned 0.7 export still pastes with zero errors.
  const legacy = P.inspectToml("[bar-skin]\nname = \"Old 0.7\"\nmode = \"islands\"\nheight = 32\n", "imported", "custom")
  assert.strictEqual(legacy.errors.length, 0)
  assert.strictEqual(legacy.formatVersion, 1)
  assert.strictEqual(legacy.skin.mode, "islands")

  // Name + description alone does not count as applied.
  const metaOnly = P.inspectToml("[bar-skin]\nformat = 1\nname = \"Empty\"\ndescription = \"Desc\"\n", "imported", "custom")
  // Loads as a file (as in 0.7), but carries no style key, so paste refuses it.
  assert.ok(metaOnly.skin)
  assert.strictEqual(metaOnly.styleCount, 0)

  // Invalid format is a hard error.
  const badFmt = P.inspectToml("[bar-skin]\nformat = 0\nheight = 34\n", "imported", "custom")
  assert.strictEqual(badFmt.errors.length, 1)
  assert.strictEqual(badFmt.errors[0].key, "format")

  // Newer format skips unknown keys and unknown enum values while applying known fields.
  const future = P.inspectToml(
    "[bar-skin]\nformat = 2\nname = \"Future\"\nheight = 40\nbezel = \"hologram\"\nglow = 0.8\n",
    "imported", "custom"
  )
  assert.strictEqual(future.errors.length, 0)
  assert.strictEqual(future.newerFormat, true)
  assert.strictEqual(future.formatVersion, 2)
  assert.strictEqual(future.skin.height, 40)
  assert.deepStrictEqual(future.skippedKeys.sort(), ["bezel", "glow"])
})

test("shell.json state round-trips studioButtonPlaced and draft base hashes", () => {
  const h1 = "0123456789abcdef0123456789abcdef"
  const h2 = "fedcba9876543210fedcba9876543210"
  const draft = P.normalizeSkin({ id: "my-skin", name: "My Skin", height: 40 }, "my-skin", "custom")
  const mDraft = P.normalizeSkin({ id: "dp2", name: "DP2", height: 44 }, "dp2", "custom")
  const json = P.stateToJson("my-skin", false, draft, null, { "DP-2": "dp2" }, false, { "DP-2": mDraft }, {
    studioButtonPlaced: true,
    draftBaseHash: h1,
    monitorDraftBaseHashes: { "DP-2": h2, "DP-3": h1, "DP-4": "not-an-md5" }
  })
  assert.strictEqual(json.studioButtonPlaced, true)
  assert.strictEqual(json.draftBaseHash, h1)
  assert.deepStrictEqual(json.monitorDraftBaseHashes, { "DP-2": h2 })

  const st = P.stateFromJson(JSON.parse(JSON.stringify(json)))
  assert.strictEqual(st.studioButtonPlaced, true)
  assert.strictEqual(st.draftBaseHash, h1)
  assert.deepStrictEqual(st.monitorDraftBaseHashes, { "DP-2": h2 })

  // 0.7.0 state without draftBaseHash or studioButtonPlaced loads cleanly with empty hash / false flag.
  const legacy = P.stateFromJson({ skin: "my-skin", draft: { name: "My Skin", height: 40 } })
  assert.strictEqual(legacy.studioButtonPlaced, false)
  assert.strictEqual(legacy.draftBaseHash, "")
})

test("StudioContent resets screenTarget when edited monitor disconnects without dropping saved monitor state", () => {
  const fs = require("fs")
  const vm = require("vm")
  const qml = fs.readFileSync(path.join(__dirname, "..", "StudioContent.qml"), "utf8")
  const m = qml.match(/^  (function resetDisconnectedTarget\(\) \{[\s\S]*?^  \})/m)
  assert.ok(m, "missing resetDisconnectedTarget in StudioContent.qml")
  let previewCleared = 0
  let timerStopped = 0
  const ctx = vm.createContext({
    screenTarget: "DP-2",
    screenNames: ["eDP-1", "DP-2"],
    confirmOverwriteName: "My Skin",
    pendingPreview: "islands",
    previewTimer: { stop: () => { timerStopped++ } },
    engine: {
      monitorSkins: { "DP-2": "islands" },
      monitorDrafts: { "DP-2": { height: 42 } },
      clearPreview: () => { previewCleared++ }
    }
  })
  vm.runInContext(m[1], ctx)

  // Still connected: stays on DP-2.
  ctx.resetDisconnectedTarget()
  assert.strictEqual(ctx.screenTarget, "DP-2")
  assert.strictEqual(previewCleared, 0)

  // Unplug DP-2: falls back to main skin and clears transient Studio state, keeping DP-2's saved skin & draft.
  ctx.screenNames = ["eDP-1"]
  ctx.resetDisconnectedTarget()
  assert.strictEqual(ctx.screenTarget, "")
  assert.strictEqual(ctx.confirmOverwriteName, "")
  assert.strictEqual(ctx.pendingPreview, "")
  assert.strictEqual(previewCleared, 1)
  assert.strictEqual(timerStopped, 1)
  assert.strictEqual(ctx.engine.monitorSkins["DP-2"], "islands")
  assert.strictEqual(ctx.engine.monitorDrafts["DP-2"].height, 42)
})

test("strict paste input: duplicate keys and flat near-miss keys are errors", () => {
  const dup = P.inspectToml("[bar-skin]\nheight = 42\nheight = 30\n", "imported", "custom")
  assert.ok(dup.errors.some(e => /duplicate key "height"/.test(e.message)))
  assert.strictEqual(dup.skin.height, 42)

  const flat = P.inspectToml("height = 42\nheigth = 41\n", "imported", "custom")
  assert.ok(flat.errors.some(e => e.key === "heigth" && e.suggestion === "height"))

  // Without [bar-skin], unrelated top-level keys (a pasted shell.toml) stay ignored.
  const shellish = P.inspectToml("height = 42\nfont-family = \"x\"\n", "imported", "custom")
  assert.strictEqual(shellish.errors.length, 0)
})

test("newer format skips values and lines this version cannot read", () => {
  const res = P.inspectToml("[bar-skin]\nformat = 2\nheight = 42\nfuture = [1, 2]\n", "imported", "custom")
  assert.strictEqual(res.errors.length, 0)
  assert.strictEqual(res.skin.height, 42)
  assert.deepStrictEqual(res.skippedKeys, ["future"])
  assert.ok(res.adjustments.some(a => /skipped: future/.test(a.message)))
})

test("errors are capped and sanitized so a hostile skin can't flood diagnostics", () => {
  let text = "[bar-skin]\nheight = 30\n"
  for (let i = 0; i < 300; i++) text += "junk" + i + " = 1\n"
  text += "\"evil‮$&\" = 1\n"
  const res = P.inspectToml(text, "imported", "custom")
  assert.strictEqual(res.errors.length, 21)
  assert.ok(/…and 281 more/.test(res.errors[20].message))
  for (const e of res.errors) assert.ok(e.message.length <= 160)

  const future = P.inspectToml("[bar-skin]\nformat = 2\nheight = 30\n\"a‮b\" = 1\n", "imported", "custom")
  assert.deepStrictEqual(future.skippedKeys, ["ab"])
})

test("U+2028/U+2029 in a name survive Copy and Save", () => {
  const parsed = P.inspectToml("[bar-skin]\nname = \"x\\u2028y\"\nheight = 30\n", "imported", "custom")
  const out = P.serializeToml(parsed.skin)
  const back = P.inspectToml(out, "imported", "custom")
  assert.strictEqual(back.errors.length, 0)
  assert.ok(back.skin.height === 30)
  assert.strictEqual(P.sanitizeLabel("a b‮c"), "a bc")
})

test("files on disk: a name-only skin still loads, newer-format skips reach diagnostics", () => {
  const dir = "/tmp/barcraft-lib-test"
  const res = P.parseSkinLibraryDetailed([
    { path: dir + "/baseline.toml", text: "[bar-skin]\nname = \"Baseline\"\n" },
    { path: dir + "/future.toml", text: "[bar-skin]\nformat = 3\nheight = 30\nglow = 1\n" }
  ], [dir])
  assert.ok(res.skins.some(s => s.id === "baseline"))
  const diag = res.diagnostics.find(d => d.path === dir + "/future.toml")
  assert.ok(diag && diag.adjustments.some(a => /skipped: glow/.test(a.message)))
})

test("StudioContent only honours an overwrite confirmation on the target it was armed for", () => {
  const fs = require("fs")
  const vm = require("vm")
  const qml = fs.readFileSync(path.join(__dirname, "..", "StudioContent.qml"), "utf8")
  const m = qml.match(/^  (function saveSkin\(\) \{[\s\S]*?^  \})/m)
  assert.ok(m, "missing saveSkin in StudioContent.qml")
  const calls = []
  const ctx = vm.createContext({
    screenTarget: "",
    confirmOverwriteName: "Neon",
    confirmOverwriteTarget: "DP-2",
    lastSaveName: "",
    lastSaveTarget: "",
    nameField: { text: "Neon" },
    overwriteTimer: { restart() {}, stop() {} },
    showStatus() {},
    formatNotice: (t, a) => String(t).replace("%1", () => String(a || "")),
    tr: k => k,
    engine: {
      committedSkinFor: () => ({ name: "Neon" }),
      saveUserSkin: (name, force, target) => { calls.push({ name, force, target }); return { ok: true } }
    }
  })
  vm.runInContext(m[1], ctx)
  ctx.saveSkin()
  assert.deepStrictEqual(calls[0], { name: "Neon", force: false, target: "" })
  ctx.screenTarget = "DP-2"
  ctx.confirmOverwriteName = "Neon"
  ctx.confirmOverwriteTarget = "DP-2"
  ctx.saveSkin()
  assert.deepStrictEqual(calls[1], { name: "Neon", force: true, target: "DP-2" })
})

test("pinnedScanSlugs collects active, monitor, draft, renamed-reserved, and recent slugs safely", () => {
  const slugs = P.pinnedScanSlugs(
    "zzz-main",
    { "DP-2": "standard-saved", "HDMI-A-1": "theme", "eDP-1": "../evil" },
    { id: "zzz-draft" },
    { "DP-2": { id: "zzz-dp2-draft" } },
    [{ id: "custom-alias", path: "/demo/skins/real-file.toml" }],
    P.builtinSkins(),
    ["custom-alias", "zzz-main", "bad/slug", "__proto__"]
  )
  assert.deepStrictEqual(slugs, [
    "zzz-main",
    "standard",
    "standard-saved",
    "zzz-draft",
    "zzz-dp2-draft",
    "real-file"
  ])
})

test("format=2 with thousands of unknown keys stays O(N) and bounds skippedKeys and adjustments", () => {
  let text = "[bar-skin]\nformat = 2\nheight = 999\n"
  for (let i = 0; i < 1500; i++) text += "future_key_" + i + " = 1\n"
  const t0 = Date.now()
  const res = P.inspectToml(text, "imported", "custom")
  const elapsed = Date.now() - t0
  assert.ok(elapsed < 500, "inspectToml took too long: " + elapsed + "ms")
  assert.strictEqual(res.errors.length, 0)
  assert.strictEqual(res.skippedKeys.length, 8)
  assert.strictEqual(res.skippedCount, 1500)
  assert.ok(/\+1492$/.test(res.skippedSummary))
  assert.ok(res.adjustments.length <= 21)
  for (const a of res.adjustments) assert.ok(a.message.length <= 160)
})

test("StudioContent formatNotice handles 0-arg strings and literal $&/%1 safely", () => {
  const fs = require("fs")
  const vm = require("vm")
  const qml = fs.readFileSync(path.join(__dirname, "..", "StudioContent.qml"), "utf8")
  const m = qml.match(/^  (function formatNotice\([\s\S]*?^  \})/m)
  assert.ok(m, "missing formatNotice in StudioContent.qml")
  const ctx = vm.createContext({})
  vm.runInContext(m[1], ctx)
  assert.strictEqual(ctx.formatNotice("Copied to clipboard", ""), "Copied to clipboard")
  assert.strictEqual(ctx.formatNotice("Pasted %1", "A $& %2 skin"), "Pasted A $& %2 skin")
})

test("malformed skin packs and oversized theme bar-skin maps stay bounded during accumulation", () => {
  const dir = "/tmp/barcraft-hostile-pack"
  const badBody = "[bar-skin]\n" + "not valid toml line\n".repeat(400)
  const rows = []
  for (let i = 0; i < 200; i++) {
    rows.push({ path: dir + "/bad-" + String(i).padStart(3, "0") + ".toml", text: badBody })
  }
  const t0 = Date.now()
  const lib = P.parseSkinLibraryDetailed(rows, [dir])
  assert.ok(Date.now() - t0 < 500, "hostile 200-file pack took too long")
  assert.strictEqual(lib.diagnostics.length, P.MAX_LIBRARY_DIAGNOSTICS + 1)
  assert.ok(/…and 150 more files/.test(lib.diagnostics[P.MAX_LIBRARY_DIAGNOSTICS].errors[0].message))
  assert.strictEqual(lib.diagnostics[0].errors.length, 21)
  assert.ok(/…and 380 more/.test(lib.diagnostics[0].errors[20].message))

  const hugeTheme = { "bar-skin.height": "34" }
  for (let k = 0; k < 500; k++) hugeTheme["bar-skin.bogus-" + k] = "x".repeat(4000)
  const themeRes = P.inspectShellValues(hugeTheme, () => null)
  assert.ok(themeRes.skin && themeRes.skin.height === 34)
  assert.strictEqual(themeRes.errors.length, 21)
  assert.strictEqual(themeRes.errorCount, 500)
  assert.ok(/…and 480 more/.test(themeRes.errors[20].message))
  for (const e of themeRes.errors) assert.ok(e.message.length <= 160)
})

test("parseSkinLibraryDetailed diagnoses a broken inherited preset only once and skips failed renames", () => {
  const dir = "/tmp/barcraft-broken-parent"
  const rows = [
    { path: dir + "/broken.toml", text: "[bar-skin]\nheight = \"not-a-number\"\n" },
    { path: dir + "/standard.toml", text: "[bar-skin]\nbogus_key = 1\n" }
  ]
  for (let i = 0; i < 6; i++) {
    rows.push({
      path: dir + "/child-" + i + ".toml",
      text: "[bar-skin]\npreset = \"broken\"\nheight = 34\n"
    })
  }
  const lib = P.parseSkinLibraryDetailed(rows, [dir])
  const brokenDiags = lib.diagnostics.filter(d => d.path === dir + "/broken.toml")
  assert.strictEqual(brokenDiags.length, 1, "broken parent should be diagnosed once, got " + brokenDiags.length)
  assert.strictEqual(lib.renamedIds.standard, undefined, "failed reserved-name file must not enter renamedIds")
})

test("hasPersistedState and shellJsonHasBarcraftState reject placement-only stubs and invalid JSON", () => {
  assert.strictEqual(P.hasPersistedState(null), false)
  assert.strictEqual(P.hasPersistedState({}), false)
  assert.strictEqual(P.hasPersistedState({ studioButtonPlaced: true }), false)
  assert.strictEqual(P.hasPersistedState({ skin: "floating" }), true)
  assert.strictEqual(P.hasPersistedState({ studioButtonPlaced: true, skin: "islands" }), true)

  assert.strictEqual(P.shellJsonHasBarcraftState(""), false)
  assert.strictEqual(P.shellJsonHasBarcraftState("{not valid json"), false)
  assert.strictEqual(P.shellJsonHasBarcraftState(JSON.stringify({ version: 1, bar: {} })), false)
  assert.strictEqual(P.shellJsonHasBarcraftState(JSON.stringify({ version: 1, bar: { barcraft: { studioButtonPlaced: true } } })), false)
  assert.strictEqual(P.shellJsonHasBarcraftState(JSON.stringify({ version: 1, bar: { barcraft: { studioButtonPlaced: true, skin: "islands" } } })), true)
})

console.log("SkinParser: " + passed + " tests passed")

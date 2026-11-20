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
  assert.deepStrictEqual(st.prefs, { autohideDelay: 900, autohideWhen: "windows", revealOnWorkspace: true })
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

test("theme colors parse with every key mapped", () => {
  const text = "accent = \"#7aa2f7\"\nblue = \"#7aa2f7\"\nbackground = '1a1b26'\n"
  assert.deepStrictEqual(P.themeColorMap(text), { accent: "#7aa2f7", blue: "#7aa2f7", background: "#1a1b26" })
  assert.strictEqual(P.parseThemeColorsToml(text).length, 2)
})

test("old motion prefs in a state file are ignored", () => {
  const st = P.parseStateToml("[barcraft]\nart-motion = \"always\"\npause-on-battery = true\n")
  assert.deepStrictEqual(Object.keys(st.prefs).sort(), ["autohideDelay", "autohideWhen", "revealOnWorkspace"])
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

console.log("SkinParser: " + passed + " tests passed")

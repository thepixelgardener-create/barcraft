// Pure JS TOML parser, serializer, and validator for Barcraft skins.
// Follows Omarchy's shell.toml conventions: kebab-case keys, *-alpha
// companions, semantic color roles. [bar-skin] is Barcraft's own section; a
// theme's shell.toml or ~/.config/omarchy/shell.toml may carry it.
//
// No QML imports, so the regression tests in tests/ run it under node.

var VALID_MODES = ["edge", "floating", "islands"]
var VALID_ARTS = ["none", "barber", "runeforge", "rocket"]
var VALID_BEZELS = ["none", "raised", "inset", "ridge", "glass"]
var VALID_BORDERS = ["none", "subtle", "accent", "hyprland"]
var VALID_VISIBILITY = ["always", "autohide"]
var VALID_WIDGET_STYLES = ["plain", "pills", "chips"]
var VALID_FILLS = ["solid", "gradient"]
var VALID_AUTOHIDE_WHEN = ["always", "windows"]

// Older names that still load.
var ART_ALIASES = { warcraft: "runeforge" }
var SKIN_ID_ALIASES = { warcraft: "runeforge" }
var COLOR_REF_ALIASES = { accent: "theme.accent", foreground: "theme.foreground", background: "theme.background" }

// Omarchy's own bar icon tokens ([bar] in shell.toml) and their defaults,
// which the skin's icon-scale multiplies.
var ICON_TOKENS = [
  { key: "icon-slot", base: 27 },
  { key: "icon-canvas", base: 16 },
  { key: "icon-font", base: 13 },
  { key: "icon-size", base: 12 }
]
var OWNED_MARKER = "# barcraft"

function normalizeHex(raw) {
  var s = String(raw || "").trim()
  if (/^#[0-9a-fA-F]{6}$/.test(s)) return s.toLowerCase()
  return ""
}

// A color is either a fixed "#rrggbb" or a live reference to the active
// theme's palette ("theme.blue"), which follows theme switches.
function normalizeColorRef(raw) {
  var s = String(raw || "").trim().toLowerCase()
  if (/^#[0-9a-f]{6}$/.test(s)) return s
  if (COLOR_REF_ALIASES[s]) return COLOR_REF_ALIASES[s]
  if (/^theme\.[a-z][a-z0-9_]{0,31}$/.test(s)) return s
  return ""
}

function isThemeRef(ref) {
  return String(ref || "").indexOf("theme.") === 0
}

function themeRefKey(ref) {
  return isThemeRef(ref) ? String(ref).slice(6) : ""
}

function defaultSkin() {
  return {
    id: "floating",
    name: "Floating",
    description: "Detached bar with soft corners and subtle border",
    category: "classic",
    mode: "floating",
    art: "none",
    themeTint: false,
    bezel: "none",
    bezelStrength: 0.75,
    contrast: 1.0,
    surfaceTone: 1.0,
    customBackground: "",
    customForeground: "",
    customAccent: "",
    height: 30,
    edgeMargin: 6,
    sideMargin: 10,
    sectionGap: 8,
    innerPadding: 10,
    radius: 10,
    iconScale: 1.0,
    background: "bar.background",
    backgroundAlpha: 0.92,
    fill: "solid",
    gradientTo: "",
    blur: false,
    border: "subtle",
    borderAlpha: 0.22,
    borderWidth: 1,
    shadow: false,
    shadowStrength: 0.5,
    widgetStyle: "plain",
    visibility: "always",
    hoverEdgePx: 4,
    accentHairline: true,
    source: "builtin"
  }
}

function preset(fields) {
  var s = defaultSkin()
  for (var k in fields) s[k] = fields[k]
  s.source = "builtin"
  return s
}

function builtinSkins() {
  return [
    preset({
      id: "floating", name: "Floating", category: "classic",
      description: "Detached bar with soft corners and subtle border"
    }),
    preset({
      id: "islands", name: "Islands", category: "classic", mode: "islands",
      description: "Separate floating pills for left, center, and right",
      sectionGap: 10, radius: 14, backgroundAlpha: 0.88, blur: true, borderAlpha: 0.24
    }),
    preset({
      id: "frosted", name: "Frosted", category: "classic",
      description: "Translucent glass bar with Hyprland blur behind it",
      radius: 12, backgroundAlpha: 0.42, blur: true, borderAlpha: 0.30
    }),
    preset({
      id: "capsule", name: "Capsule", category: "classic",
      description: "Rounded bar on a soft shadow with pill-shaped widgets",
      radius: 16, height: 32, edgeMargin: 8, sideMargin: 14, backgroundAlpha: 0.94,
      shadow: true, shadowStrength: 0.55, widgetStyle: "pills", border: "none", borderWidth: 0
    }),
    preset({
      id: "editorial", name: "Editorial", category: "classic", mode: "edge",
      description: "Sharp 0px corners with a crisp 1px accent rule",
      height: 28, edgeMargin: 0, sideMargin: 0, sectionGap: 6, innerPadding: 8, radius: 0,
      backgroundAlpha: 1.0, border: "accent", borderAlpha: 0.65
    }),
    preset({
      id: "barber", name: "Barber Pole", category: "wild", art: "barber",
      description: "3D barber pole cylinder with chrome caps",
      height: 32, sideMargin: 12, innerPadding: 12, radius: 16, backgroundAlpha: 0.96,
      border: "none", borderAlpha: 0.0, borderWidth: 0
    }),
    preset({
      id: "runeforge", name: "Runeforge", category: "wild", art: "runeforge",
      description: "Forged obsidian stone, antique gold & glowing runes",
      height: 34, edgeMargin: 5, innerPadding: 14, radius: 4, backgroundAlpha: 0.98,
      border: "none", borderAlpha: 0.0, borderWidth: 0
    }),
    preset({
      id: "rocket", name: "Long Rocket", category: "wild", art: "rocket",
      description: "Full-width spacecraft with thruster & nosecone",
      height: 34, sideMargin: 8, innerPadding: 12, radius: 0, backgroundAlpha: 0.96,
      border: "none", borderAlpha: 0.0, borderWidth: 0
    })
  ]
}

// Omarchy's own bar, as it ships: a flat strip along the edge in the theme's
// bar colors. The bar draws it from Omarchy's tokens (size, background,
// glassy), so this only says "no skin": no gaps, corners, border or art.
function standardSkin() {
  var s = preset({
    id: "standard", name: "Omarchy standard", category: "standard", mode: "edge",
    description: "The bar exactly as Omarchy ships it",
    height: 26, edgeMargin: 0, sideMargin: 0, sectionGap: 4, innerPadding: 8, radius: 0,
    backgroundAlpha: 1.0, border: "none", borderWidth: 0, borderAlpha: 0
  })
  s.category = "standard"
  return s
}

function clamp(val, min, max, fallback) {
  if (val === undefined || val === null || val === "") return fallback
  var n = Number(val)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function parseBool(raw, fallback) {
  if (typeof raw === "boolean") return raw
  var s = String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "yes") return true
  if (s === "false" || s === "0" || s === "no") return false
  return fallback
}

function oneOf(raw, list, fallback) {
  var s = String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase()
  return list.indexOf(s) === -1 ? fallback : s
}

function slugify(text) {
  var s = String(text || "").trim().toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
  return s.slice(0, 40) || "custom-skin"
}

function canonicalSkinId(id) {
  var s = slugify(id)
  return SKIN_ID_ALIASES[s] || s
}

function sanitizeLabel(text, maxLen) {
  var s = String(text || "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .trim()
  return s.slice(0, maxLen || 48)
}

function round2(n) {
  return Math.round(n * 100) / 100
}

function normalizeSkin(raw, fallbackId, source) {
  var base = defaultSkin()
  var obj = raw && typeof raw === "object" ? raw : {}

  var rawMode = String(obj.mode || base.mode).trim().toLowerCase()
  var mode = rawMode === "stealth" ? "floating" : rawMode
  if (VALID_MODES.indexOf(mode) === -1) mode = base.mode

  var art = String(obj.art || base.art).trim().toLowerCase()
  art = ART_ALIASES[art] || art
  if (VALID_ARTS.indexOf(art) === -1) art = "none"

  var border = String(obj.border || base.border).trim().toLowerCase()
  if (border === "hyprland.active-border" || border === "hyprland.active-border-foreground") border = "hyprland"
  if (VALID_BORDERS.indexOf(border) === -1) border = base.border

  var visibility = oneOf(obj.visibility || (rawMode === "stealth" ? "autohide" : base.visibility), VALID_VISIBILITY, base.visibility)

  var id = slugify(obj.id || fallbackId || "custom")
  var name = sanitizeLabel(obj.name || id, 40)
  var description = sanitizeLabel(obj.description || "", 120)
  var contrast = round2(clamp(obj.contrast, 0.5, 1.5, base.contrast))
  // Skins from before the split had one Contrast for text and surface alike.
  var tone = obj.surfaceTone !== undefined && obj.surfaceTone !== null && obj.surfaceTone !== "" ? obj.surfaceTone : contrast

  return {
    id: id,
    name: name,
    description: description,
    category: obj.category === "wild" || obj.category === "classic" ? obj.category : (art !== "none" ? "wild" : "classic"),
    mode: mode,
    art: art,
    themeTint: parseBool(obj.themeTint, false),
    bezel: oneOf(obj.bezel || base.bezel, VALID_BEZELS, "none"),
    bezelStrength: round2(clamp(obj.bezelStrength, 0.15, 1.0, base.bezelStrength)),
    contrast: contrast,
    surfaceTone: round2(clamp(tone, 0.5, 1.5, base.surfaceTone)),
    customBackground: normalizeColorRef(obj.customBackground),
    customForeground: normalizeColorRef(obj.customForeground),
    customAccent: normalizeColorRef(obj.customAccent),
    height: Math.round(clamp(obj.height, 22, 56, base.height)),
    edgeMargin: Math.round(clamp(obj.edgeMargin, 0, 24, base.edgeMargin)),
    sideMargin: Math.round(clamp(obj.sideMargin, 0, 48, base.sideMargin)),
    sectionGap: Math.round(clamp(obj.sectionGap, 0, 32, base.sectionGap)),
    innerPadding: Math.round(clamp(obj.innerPadding, 4, 24, base.innerPadding)),
    radius: Math.round(clamp(obj.radius, 0, 28, base.radius)),
    iconScale: round2(clamp(obj.iconScale, 0.8, 1.5, base.iconScale)),
    background: String(obj.background || base.background).trim() || "bar.background",
    backgroundAlpha: round2(clamp(obj.backgroundAlpha, 0, 1, base.backgroundAlpha)),
    fill: oneOf(obj.fill || base.fill, VALID_FILLS, base.fill),
    gradientTo: normalizeColorRef(obj.gradientTo),
    blur: parseBool(obj.blur, base.blur),
    border: border,
    borderAlpha: round2(clamp(obj.borderAlpha, 0, 1, base.borderAlpha)),
    borderWidth: Math.round(clamp(obj.borderWidth, 0, 4, base.borderWidth)),
    shadow: parseBool(obj.shadow, base.shadow),
    shadowStrength: round2(clamp(obj.shadowStrength, 0.1, 1.0, base.shadowStrength)),
    widgetStyle: oneOf(obj.widgetStyle || base.widgetStyle, VALID_WIDGET_STYLES, base.widgetStyle),
    visibility: visibility,
    hoverEdgePx: Math.round(clamp(obj.hoverEdgePx, 1, 16, base.hoverEdgePx)),
    accentHairline: parseBool(obj.accentHairline, true),
    source: source || obj.source || "user"
  }
}

// ---------------------------------------------------------------------------
// TOML subset: [sections], bare or "quoted" keys, "basic" strings with
// escapes, 'literal' strings, numbers, booleans and bare words. Enough for
// skin files; anything else on a line is skipped rather than guessed at.

function parseTomlString(rest) {
  var quote = rest.charAt(0)
  var out = ""
  var i = 1
  if (quote === "'") {
    var end = rest.indexOf("'", 1)
    if (end < 0) return null
    return { value: rest.slice(1, end), tail: rest.slice(end + 1) }
  }
  while (i < rest.length) {
    var ch = rest.charAt(i)
    if (ch === "\\") {
      var nx = rest.charAt(i + 1)
      if (nx === "n") out += "\n"
      else if (nx === "t") out += "\t"
      else if (nx === "r") out += "\r"
      else if (nx === "\"" || nx === "\\") out += nx
      else if (nx === "u" && /^[0-9a-fA-F]{4}$/.test(rest.substr(i + 2, 4))) {
        out += String.fromCharCode(parseInt(rest.substr(i + 2, 4), 16))
        i += 4
      } else out += nx
      i += 2
      continue
    }
    if (ch === "\"") return { value: out, tail: rest.slice(i + 1) }
    out += ch
    i++
  }
  return null
}

function parseTomlValue(rest) {
  var s = String(rest || "").trim()
  if (!s) return null
  var c = s.charAt(0)
  if (c === "\"" || c === "'") {
    var str = parseTomlString(s)
    if (!str || !/^\s*(#.*)?$/.test(str.tail)) return null
    return str.value
  }
  var num = s.match(/^(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
  if (num) return num[1]
  var bare = s.match(/^([A-Za-z][A-Za-z0-9_.-]*)\s*(#.*)?$/)
  if (bare) return bare[1]
  return null
}

// { "<section>": { key: "raw value" } }, top-level keys under "".
function parseTomlSections(text) {
  var out = { "": {} }
  var section = ""
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    var sec = line.match(/^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$/)
    if (sec) {
      section = sec[1]
      if (!out[section]) out[section] = {}
      continue
    }
    var kv = line.match(/^(?:"([^"\\]{1,64})"|([A-Za-z0-9_-]{1,64}))\s*=\s*(.*)$/)
    if (!kv) continue
    var value = parseTomlValue(kv[3])
    if (value === null) continue
    out[section][kv[1] !== undefined ? kv[1] : kv[2]] = value
  }
  return out
}

function tomlString(text) {
  return "\"" + String(text || "")
    .replace(/\\/g, "\\\\")
    .replace(/"/g, "\\\"")
    .replace(/\n/g, "\\n")
    .replace(/\t/g, "\\t") + "\""
}

var KEY_MAP = {
  "id": "id",
  "name": "name",
  "description": "description",
  "mode": "mode",
  "art": "art",
  "theme-tint": "themeTint",
  "bezel": "bezel",
  "bezel-strength": "bezelStrength",
  "contrast": "contrast",
  "surface-tone": "surfaceTone",
  "custom-background": "customBackground",
  "custom-foreground": "customForeground",
  "custom-accent": "customAccent",
  "height": "height",
  "edge-margin": "edgeMargin",
  "side-margin": "sideMargin",
  "section-gap": "sectionGap",
  "inner-padding": "innerPadding",
  "inner-padding-x": "innerPadding",
  "radius": "radius",
  "icon-scale": "iconScale",
  "background": "background",
  "background-alpha": "backgroundAlpha",
  "fill": "fill",
  "gradient-to": "gradientTo",
  "blur": "blur",
  "border": "border",
  "border-alpha": "borderAlpha",
  "border-width": "borderWidth",
  "shadow": "shadow",
  "shadow-strength": "shadowStrength",
  "widget-style": "widgetStyle",
  "visibility": "visibility",
  "hover-edge-px": "hoverEdgePx",
  "accent-hairline": "accentHairline"
}

function copySkin(skin) {
  var out = {}
  for (var k in skin) out[k] = skin[k]
  return out
}

// `lookup(id)` resolves `preset = "<skin id>"`, so a theme can name a skin
// in one line and override only what it wants on top of it.
function skinFromKvMap(map, fallbackId, source, lookup) {
  var base = null
  if (map["preset"] !== undefined && typeof lookup === "function") base = lookup(String(map["preset"]))
  var merged = base ? copySkin(base) : {}
  var named = false
  for (var key in map) {
    var field = KEY_MAP[key]
    if (!field) continue
    if (key === "inner-padding" && map["inner-padding-x"] !== undefined) continue
    merged[field] = map[key]
    if (field === "name") named = true
  }
  if (!named && !base) merged.name = fallbackId
  if (!merged.id) merged.id = fallbackId
  return normalizeSkin(merged, fallbackId, source)
}

function parseToml(text, fallbackId, source, lookup) {
  var raw = String(text || "")
  if (!raw.trim()) return null
  var sections = parseTomlSections(raw)
  var map = {}
  var found = false
  var top = sections[""] || {}
  var skinSec = sections["bar-skin"] || {}
  var k
  for (k in top) { if (KEY_MAP[k] || k === "preset") { map[k] = top[k]; found = true } }
  for (k in skinSec) { map[k] = skinSec[k]; found = true }
  if (!found) return null
  return skinFromKvMap(map, fallbackId, source, lookup)
}

function parseFromShellValues(shellValues, lookup) {
  if (!shellValues || typeof shellValues !== "object") return null
  var map = {}
  var found = false
  var prefix = "bar-skin."
  for (var k in shellValues) {
    if (k.indexOf(prefix) === 0) {
      map[k.slice(prefix.length)] = shellValues[k]
      found = true
    }
  }
  if (!found) return null
  var skin = skinFromKvMap(map, "theme-skin", "theme", lookup)
  skin.id = "theme-skin"
  return skin
}

function serializeToml(skin) {
  var s = normalizeSkin(skin, skin ? skin.id : "custom", "user")
  var lines = [
    "# Barcraft skin. Works as ~/.config/omarchy/bar-skins/<name>.toml or as the",
    "# [bar-skin] section of a theme's shell.toml.",
    "[bar-skin]",
    "name             = " + tomlString(s.name),
    s.description ? "description      = " + tomlString(s.description) : null,
    "mode             = \"" + s.mode + "\"",
    "art              = \"" + s.art + "\"",
    "theme-tint       = " + (s.themeTint ? "true" : "false"),
    "bezel            = \"" + s.bezel + "\"",
    "bezel-strength   = " + s.bezelStrength.toFixed(2),
    "contrast         = " + s.contrast.toFixed(2),
    "surface-tone     = " + s.surfaceTone.toFixed(2),
    s.customBackground ? "custom-background = \"" + s.customBackground + "\"" : null,
    s.customForeground ? "custom-foreground = \"" + s.customForeground + "\"" : null,
    s.customAccent ? "custom-accent    = \"" + s.customAccent + "\"" : null,
    "",
    "# Geometry",
    "height           = " + s.height,
    "edge-margin      = " + s.edgeMargin,
    "side-margin      = " + s.sideMargin,
    "section-gap      = " + s.sectionGap,
    "inner-padding-x  = " + s.innerPadding,
    "radius           = " + s.radius,
    "icon-scale       = " + s.iconScale.toFixed(2),
    "",
    "# Surface & Border",
    "background       = \"" + s.background + "\"",
    "background-alpha = " + s.backgroundAlpha.toFixed(2),
    "fill             = \"" + s.fill + "\"",
    s.gradientTo ? "gradient-to      = \"" + s.gradientTo + "\"" : null,
    "blur             = " + (s.blur ? "true" : "false"),
    "border           = \"" + s.border + "\"",
    "border-alpha     = " + s.borderAlpha.toFixed(2),
    "border-width     = " + s.borderWidth,
    "shadow           = " + (s.shadow ? "true" : "false"),
    "shadow-strength  = " + s.shadowStrength.toFixed(2),
    "widget-style     = \"" + s.widgetStyle + "\"",
    "",
    "# Behavior",
    "visibility       = \"" + s.visibility + "\"",
    "hover-edge-px    = " + s.hoverEdgePx,
    "accent-hairline  = " + (s.accentHairline ? "true" : "false"),
    ""
  ]
  return lines.filter(function(l) { return l !== null }).join("\n")
}

// ---------------------------------------------------------------------------
// ~/.config/omarchy/barcraft.toml: the chosen skin, preferences that hold for
// every skin, per-monitor skins, and an unsaved draft.

function defaultPrefs() {
  return {
    autohideDelay: 320,
    autohideWhen: "always",
    revealOnWorkspace: false
  }
}

function normalizePrefs(raw) {
  var base = defaultPrefs()
  var p = raw && typeof raw === "object" ? raw : {}
  return {
    autohideDelay: Math.round(clamp(p.autohideDelay, 100, 3000, base.autohideDelay)),
    autohideWhen: oneOf(p.autohideWhen, VALID_AUTOHIDE_WHEN, base.autohideWhen),
    revealOnWorkspace: parseBool(p.revealOnWorkspace, base.revealOnWorkspace)
  }
}

function sanitizeScreenName(name) {
  var s = String(name || "").trim()
  return /^[A-Za-z0-9_.:-]{1,48}$/.test(s) ? s : ""
}

function parseStateToml(text) {
  var sections = parseTomlSections(text)
  var main = sections["barcraft"] || sections[""] || {}
  var mons = sections["barcraft-monitors"] || {}
  var state = {
    activeSkinId: main["active-skin"] !== undefined ? slugify(main["active-skin"]) : "floating",
    followTheme: parseBool(main["follow-theme"], true),
    standard: parseBool(main["standard"], false),
    prefs: normalizePrefs({
      autohideDelay: main["autohide-delay"],
      autohideWhen: main["autohide-when"],
      revealOnWorkspace: main["reveal-on-workspace"]
    }),
    monitors: {}
  }
  for (var screen in mons) {
    var name = sanitizeScreenName(screen)
    var id = String(mons[screen] || "").trim()
    if (!name || !id) continue
    state.monitors[name] = id === "theme" ? "theme" : slugify(id)
  }
  return state
}

function serializeStateToml(activeSkinId, followTheme, draft, prefs, monitors, standard) {
  var p = normalizePrefs(prefs)
  var lines = [
    "# Barcraft configuration",
    "[barcraft]",
    "# true shows Omarchy's own bar; your skins stay for when you switch back",
    "standard            = " + (standard ? "true" : "false"),
    "active-skin         = \"" + slugify(activeSkinId) + "\"",
    "follow-theme        = " + (followTheme ? "true" : "false"),
    "autohide-delay      = " + p.autohideDelay,
    "autohide-when       = \"" + p.autohideWhen + "\"",
    "reveal-on-workspace = " + (p.revealOnWorkspace ? "true" : "false"),
    ""
  ]
  var names = []
  for (var screen in (monitors || {})) {
    if (sanitizeScreenName(screen) && monitors[screen]) names.push(screen)
  }
  if (names.length > 0) {
    names.sort()
    lines.push("# Skins for single screens; the rest use active-skin")
    lines.push("[barcraft-monitors]")
    for (var i = 0; i < names.length; i++) {
      var id = monitors[names[i]] === "theme" ? "theme" : slugify(monitors[names[i]])
      lines.push(tomlString(names[i]) + " = \"" + id + "\"")
    }
    lines.push("")
  }
  var header = lines.join("\n")
  return draft ? header + "\n" + serializeToml(draft) : header
}

// ---------------------------------------------------------------------------
// Parses Omarchy's active theme colors.toml into an ordered, deduplicated
// array of { name, key, hex } entries (surfaces first, then semantic hues).
function parseThemeColorsToml(text) {
  var raw = String(text || "")
  if (!raw.trim()) return []

  var map = {}
  var lines = raw.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#" || line.charAt(0) === "[") continue
    var m = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["'](#?[0-9a-fA-F]{6})["']/)
    if (!m) continue
    var hex = m[2].charAt(0) === "#" ? m[2].toLowerCase() : ("#" + m[2].toLowerCase())
    map[m[1].toLowerCase()] = hex
  }

  var order = [
    "darker_background", "dark_background", "background", "lighter_background",
    "selection", "muted", "dark_foreground", "foreground", "light_foreground", "bright_foreground",
    "accent", "red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"
  ]

  var out = []
  var seen = {}
  for (var j = 0; j < order.length; j++) {
    var key = order[j]
    var val = map[key]
    if (!val || seen[val]) continue
    seen[val] = true
    out.push({ name: key.replace(/_/g, " "), key: key, hex: val })
  }
  return out
}

// key -> "#rrggbb" for every color the theme defines, duplicates included,
// so a "theme.<key>" reference resolves even when its hex repeats another.
function themeColorMap(text) {
  var map = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^([A-Za-z0-9_-]+)\s*=\s*["'](#?[0-9a-fA-F]{6})["']/)
    if (!m) continue
    map[m[1].toLowerCase()] = (m[2].charAt(0) === "#" ? m[2] : "#" + m[2]).toLowerCase()
  }
  return map
}

// ---------------------------------------------------------------------------
// The skin's icon-scale goes to Omarchy's own [bar] icon tokens in
// ~/.config/omarchy/shell.toml, the machine-level override file the shell
// already watches. Barcraft writes only lines it marks "# barcraft" and never
// replaces a token the user set by hand. scale 1 (or null) removes its lines.
function iconTokenValues(scale) {
  var out = {}
  for (var i = 0; i < ICON_TOKENS.length; i++) {
    out[ICON_TOKENS[i].key] = Math.max(1, Math.round(ICON_TOKENS[i].base * scale))
  }
  return out
}

function applyBarIconOverrides(text, scale) {
  var src = String(text || "")
  var lines = src.length ? src.split("\n") : []
  var tokenKeys = ICON_TOKENS.map(function(t) { return t.key })
  var want = scale !== null && scale !== undefined && Math.abs(Number(scale) - 1) > 0.001
  var values = want ? iconTokenValues(Number(scale)) : {}

  var out = []
  var section = ""
  var barHeaderIndex = -1
  var userKeys = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var trimmed = line.trim()
    var sec = trimmed.match(/^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$/)
    if (sec) {
      section = sec[1]
      // A [bar] header Barcraft added goes and comes back below if needed.
      if (section === "bar" && trimmed.indexOf(OWNED_MARKER) !== -1) continue
      out.push(line)
      if (section === "bar" && barHeaderIndex < 0) barHeaderIndex = out.length - 1
      continue
    }
    if (section === "bar") {
      var kv = trimmed.match(/^([A-Za-z0-9_-]+)\s*=/)
      if (kv && tokenKeys.indexOf(kv[1]) !== -1) {
        if (trimmed.indexOf(OWNED_MARKER) !== -1) continue
        userKeys[kv[1]] = true
      }
    }
    out.push(line)
  }

  if (want) {
    var add = []
    for (var t = 0; t < tokenKeys.length; t++) {
      var key = tokenKeys[t]
      if (userKeys[key]) continue
      add.push(key + " = " + values[key] + " " + OWNED_MARKER)
    }
    if (add.length > 0) {
      if (barHeaderIndex >= 0) {
        out.splice.apply(out, [barHeaderIndex + 1, 0].concat(add))
      } else {
        while (out.length > 0 && out[out.length - 1].trim() === "") out.pop()
        if (out.length > 0) out.push("")
        out.push("[bar] " + OWNED_MARKER)
        out = out.concat(add)
      }
    }
  } else if (barHeaderIndex < 0) {
    while (out.length > 0 && out[out.length - 1].trim() === "") out.pop()
  }

  var result = out.join("\n")
  if (result.length > 0 && result.charAt(result.length - 1) !== "\n") result += "\n"
  if (out.length === 0) result = ""
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeColorRef: normalizeColorRef,
    normalizeSkin: normalizeSkin,
    builtinSkins: builtinSkins,
    defaultSkin: defaultSkin,
    standardSkin: standardSkin,
    parseToml: parseToml,
    parseTomlSections: parseTomlSections,
    serializeToml: serializeToml,
    parseFromShellValues: parseFromShellValues,
    parseStateToml: parseStateToml,
    serializeStateToml: serializeStateToml,
    normalizePrefs: normalizePrefs,
    parseThemeColorsToml: parseThemeColorsToml,
    themeColorMap: themeColorMap,
    applyBarIconOverrides: applyBarIconOverrides,
    canonicalSkinId: canonicalSkinId,
    slugify: slugify,
    sanitizeLabel: sanitizeLabel
  }
}

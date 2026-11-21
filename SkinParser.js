// Pure JS TOML parser, serializer, and validator for Barcraft skins.
// Follows Omarchy's shell.toml conventions: kebab-case keys, *-alpha
// companions, semantic color roles. [bar-skin] is Barcraft's own section; a
// theme's shell.toml or ~/.config/omarchy/shell.toml may carry it.
//
// No QML imports, so the regression tests in tests/ run it under node.

var VALID_MODES = ["edge", "floating", "islands"]
var VALID_ARTS = ["none", "matrix", "runeforge"]
var VALID_BEZELS = ["none", "raised", "inset", "ridge", "glass"]
var VALID_BORDERS = ["none", "subtle", "accent", "hyprland"]
var VALID_VISIBILITY = ["always", "autohide"]
var VALID_WIDGET_STYLES = ["plain", "pills", "chips"]
var VALID_FILLS = ["solid", "gradient"]
var VALID_AUTOHIDE_WHEN = ["always", "windows"]

function dict(entries) {
  var o = Object.create(null)
  for (var k in entries) {
    if (Object.prototype.hasOwnProperty.call(entries, k)) o[k] = entries[k]
  }
  return o
}

function hasOwn(obj, key) {
  return !!obj && Object.prototype.hasOwnProperty.call(obj, key)
}

function isUnsafeKey(key) {
  return key === "__proto__" || key === "constructor" || key === "prototype"
}

// Older names that still load.
var ART_ALIASES = dict({ warcraft: "runeforge" })
var SKIN_ID_ALIASES = dict({ warcraft: "runeforge" })
var COLOR_REF_ALIASES = dict({ accent: "theme.accent", foreground: "theme.foreground", background: "theme.background" })

// Omarchy's own bar icon tokens ([bar] in shell.toml) and their defaults,
// which the skin's icon-scale multiplies.
var ICON_TOKENS = [
  { key: "icon-slot", base: 27 },
  { key: "icon-canvas", base: 16 },
  { key: "icon-font", base: 13 },
  { key: "icon-size", base: 12 }
]
var OWNED_MARKER = "# barcraft"
var HOOK_OWNED_MARKER = "# Added by Barcraft (thepixelgardener.barcraft)."
var HOOK_DIGEST_PREFIX = "# barcraft-digest: "
var HOOK_HEAD = "#!/bin/bash\n" + HOOK_OWNED_MARKER + "\n" + HOOK_DIGEST_PREFIX

// The post-update hook Barcraft writes: a fixed header, then a digest line
// holding the MD5 of everything after it. `md5` is Qt.md5 in the shell (a
// stand-in in the tests): the hex MD5 of the text's UTF-8 bytes.
function stampUpdateHook(body, md5) {
  var rest = String(body === undefined || body === null ? "" : body)
  return HOOK_HEAD + md5(rest) + "\n" + rest
}

// True only for a hook Barcraft wrote and nobody has changed since. The header
// alone proves nothing (an edited copy keeps it), so the digest has to match
// the rest of the file. Hooks from 0.5.0 and 0.5.1 carry no digest: they count
// only when they equal one of `legacy` exactly, which is what those versions
// would have written in this place.
function isPristineUpdateHook(text, md5, legacy) {
  var s = String(text === undefined || text === null ? "" : text)
  if (s.indexOf(HOOK_HEAD) === 0) {
    var rest = s.slice(HOOK_HEAD.length)
    var digest = rest.slice(0, 32)
    return /^[0-9a-f]{32}$/.test(digest) && rest.charAt(32) === "\n" && md5(rest.slice(33)) === digest
  }
  return Array.isArray(legacy) && s !== "" && legacy.indexOf(s) !== -1
}

// Picks a target filename slug when saving a user skin:
// - If an existing user skin has the exact same displayed name:
//   * updating the currently active skin (or an explicit confirmed overwrite)
//     keeps that skin's slug in place;
//   * otherwise returns needsConfirm: true so the UI prompts before overwriting.
// - If no user skin has the same displayed name, never silently collides with
//   another skin whose name happens to slugify to the same filename: allocates
//   a unique slug instead.
function resolveSaveTarget(cleanName, userSkins, activeSkinId, builtinTakenFn, forceOverwrite) {
  var list = Array.isArray(userSkins) ? userSkins : []
  var byId = Object.create(null)
  var exactMatch = null
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (!s || !s.id) continue
    byId[s.id] = s
    if (!exactMatch && s.name === cleanName) exactMatch = s
  }

  if (exactMatch) {
    if (exactMatch.id === activeSkinId || forceOverwrite) {
      return { slug: exactMatch.id, overwrite: true, needsConfirm: false, conflictName: "" }
    }
    return { slug: exactMatch.id, overwrite: false, needsConfirm: true, conflictName: exactMatch.name }
  }

  var base = slugify(cleanName)
  if (typeof builtinTakenFn === "function" && builtinTakenFn(base)) base = (base + "-custom").slice(0, 40)
  var candidate = base
  var n = 2
  while (hasOwn(byId, candidate) || (typeof builtinTakenFn === "function" && builtinTakenFn(candidate))) {
    var suffix = "-" + n
    candidate = base.slice(0, Math.max(1, 40 - suffix.length)) + suffix
    n++
  }
  return { slug: candidate, overwrite: false, needsConfirm: false, conflictName: "" }
}

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
  if (hasOwn(COLOR_REF_ALIASES, s)) return COLOR_REF_ALIASES[s]
  if (/^theme\.[a-z][a-z0-9_]{0,31}$/.test(s)) return s
  return ""
}

function normalizeBackground(raw) {
  var s = String(raw || "").trim().toLowerCase()
  if (s === "bar.background") return "bar.background"
  var ref = normalizeColorRef(s)
  return ref || "bar.background"
}

// Neutralizes markup-shaped text before passing dynamic strings into shared
// Omarchy-owned sinks (tooltips, OSD) whose Text format this plugin doesn't own.
function neutralizeMarkup(text) {
  return String(text === undefined || text === null ? "" : text).replace(/</g, "<\u200b")
}

// Verifies a skin file path sits directly inside one of the allowed skin
// directories with a safe `.toml` filename and no traversal segments.
function isSafeSkinPath(filePath, allowedDirs) {
  var p = String(filePath || "")
  if (!p || p.indexOf("\0") >= 0) return false
  var dirs = Array.isArray(allowedDirs) ? allowedDirs : []
  for (var i = 0; i < dirs.length; i++) {
    var dir = String(dirs[i] || "").replace(/\/+$/, "")
    if (!dir) continue
    var prefix = dir + "/"
    if (p.indexOf(prefix) !== 0) continue
    var name = p.slice(prefix.length)
    if (name.indexOf("/") >= 0 || name === ".." || name === ".") continue
    if (/^[a-z0-9][a-z0-9_-]{0,63}\.toml$/i.test(name)) return true
  }
  return false
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
    description: "Detached bar that lines up with your windows",
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
    // "auto" follows Omarchy: the theme's bar size, Omarchy's panel gap,
    // Hyprland's gaps_out (so the bar lines up with windows), Hyprland's
    // rounding, and the theme's bar background alpha.
    height: "auto",
    edgeMargin: "auto",
    sideMargin: "auto",
    width: 100,
    sectionGap: 8,
    innerPadding: 10,
    radius: "auto",
    iconScale: 1.0,
    background: "bar.background",
    backgroundAlpha: "auto",
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
      description: "Detached bar that lines up with your windows"
    }),
    preset({
      id: "islands", name: "Islands", category: "classic", mode: "islands",
      description: "Separate floating pills for left, center, and right",
      sectionGap: 10, backgroundAlpha: 0.88, blur: true, borderAlpha: 0.24
    }),
    preset({
      id: "frosted", name: "Frosted", category: "classic",
      description: "Translucent glass bar with Hyprland blur behind it",
      backgroundAlpha: 0.42, blur: true, borderAlpha: 0.30
    }),
    preset({
      id: "capsule", name: "Capsule", category: "classic",
      description: "Rounded bar on a soft shadow with pill-shaped widgets",
      radius: 16, backgroundAlpha: 0.94,
      shadow: true, shadowStrength: 0.55, widgetStyle: "pills", border: "none", borderWidth: 0
    }),
    preset({
      id: "editorial", name: "Editorial", category: "classic", mode: "edge",
      description: "Sharp 0px corners with a crisp 1px accent rule",
      edgeMargin: 0, sideMargin: 0, sectionGap: 6, innerPadding: 8, radius: 0,
      border: "accent", borderAlpha: 0.65
    }),
    preset({
      id: "matrix", name: "Matrix", category: "wild", art: "matrix",
      description: "CRT phosphor terminal with digital rain & corner brackets",
      height: 30, edgeMargin: 6, sideMargin: 10, innerPadding: 12, radius: 2,
      backgroundAlpha: 0.98, customForeground: "#7dffb0",
      border: "none", borderAlpha: 0.0, borderWidth: 0
    }),
    preset({
      id: "runeforge", name: "Runeforge", category: "wild", art: "runeforge",
      description: "Chamfered obsidian basalt & hairline etched antique brass",
      height: 32, edgeMargin: 6, sideMargin: 10, innerPadding: 14, radius: 0,
      backgroundAlpha: 0.98,
      border: "none", borderAlpha: 0.0, borderWidth: 0
    }),
    preset({
      id: "statusline", name: "Statusline", category: "classic", mode: "edge",
      description: "Compact high-contrast developer statusline with outlined widget chips",
      height: 26, edgeMargin: 0, sideMargin: 0, sectionGap: 6, innerPadding: 6, radius: 0,
      backgroundAlpha: 0.98, surfaceTone: 1.15, contrast: 1.18,
      border: "subtle", borderAlpha: 0.28, borderWidth: 1,
      widgetStyle: "chips"
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
    height: "auto", edgeMargin: 0, sideMargin: 0, sectionGap: 4, innerPadding: 8, radius: 0,
    backgroundAlpha: "auto", border: "none", borderWidth: 0, borderAlpha: 0
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
  return hasOwn(SKIN_ID_ALIASES, s) ? SKIN_ID_ALIASES[s] : s
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

function isAuto(raw) {
  return String(raw === undefined || raw === null ? "" : raw).trim().toLowerCase() === "auto"
}

// A number in range, or "auto" (follow Omarchy). A missing value falls back,
// and the fallback may itself be "auto".
function autoOr(raw, min, max, fallback, whole) {
  if (isAuto(raw)) return "auto"
  var v = clamp(raw, min, max, fallback)
  if (v === "auto") return "auto"
  return whole ? Math.round(v) : round2(v)
}

function normalizeSkin(raw, fallbackId, source) {
  var base = defaultSkin()
  var obj = raw && typeof raw === "object" ? raw : {}

  var rawMode = String(obj.mode || base.mode).trim().toLowerCase()
  var mode = rawMode === "stealth" ? "floating" : rawMode
  if (VALID_MODES.indexOf(mode) === -1) mode = base.mode

  var art = String(obj.art || base.art).trim().toLowerCase()
  art = hasOwn(ART_ALIASES, art) ? ART_ALIASES[art] : art
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
    height: autoOr(obj.height, 22, 56, base.height, true),
    edgeMargin: autoOr(obj.edgeMargin, 0, 24, base.edgeMargin, true),
    sideMargin: autoOr(obj.sideMargin, 0, 48, base.sideMargin, true),
    width: Math.round(clamp(obj.width, 30, 100, base.width)),
    sectionGap: Math.round(clamp(obj.sectionGap, 0, 32, base.sectionGap)),
    innerPadding: Math.round(clamp(obj.innerPadding, 4, 24, base.innerPadding)),
    radius: autoOr(obj.radius, 0, 28, base.radius, true),
    iconScale: round2(clamp(obj.iconScale, 0.8, 1.5, base.iconScale)),
    background: normalizeBackground(obj.background),
    backgroundAlpha: autoOr(obj.backgroundAlpha, 0, 1, base.backgroundAlpha, false),
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
// Uses null-prototype maps and drops prototype-chain keys to prevent
// Object.prototype pollution from untrusted TOML input.
function parseTomlSections(text) {
  var out = Object.create(null)
  out[""] = Object.create(null)
  var section = ""
  var ignoreSection = false
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#") continue
    var sec = line.match(/^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$/)
    if (sec) {
      if (isUnsafeKey(sec[1])) {
        ignoreSection = true
        continue
      }
      ignoreSection = false
      section = sec[1]
      if (!out[section]) out[section] = Object.create(null)
      continue
    }
    if (ignoreSection) continue
    var kv = line.match(/^(?:"([^"\\]{1,64})"|([A-Za-z0-9_-]{1,64}))\s*=\s*(.*)$/)
    if (!kv) continue
    var key = kv[1] !== undefined ? kv[1] : kv[2]
    if (isUnsafeKey(key)) continue
    var value = parseTomlValue(kv[3])
    if (value === null) continue
    out[section][key] = value
  }
  return out
}

function tomlString(text) {
  return "\"" + String(text || "")
    .replace(/\\/g, "\\\\")
    .replace(/"/g, "\\\"")
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")
    .replace(/\t/g, "\\t") + "\""
}

var KEY_MAP = dict({
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
  "width": "width",
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
})

function copySkin(skin) {
  var out = {}
  for (var k in skin) {
    if (hasOwn(skin, k) && !isUnsafeKey(k)) out[k] = skin[k]
  }
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
    if (!hasOwn(map, key) || isUnsafeKey(key)) continue
    var field = hasOwn(KEY_MAP, key) ? KEY_MAP[key] : ""
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
  var map = Object.create(null)
  var found = false
  var top = sections[""] || Object.create(null)
  var skinSec = sections["bar-skin"] || Object.create(null)
  var k
  for (k in top) { if (hasOwn(KEY_MAP, k) || k === "preset") { map[k] = top[k]; found = true } }
  for (k in skinSec) { if (!isUnsafeKey(k)) { map[k] = skinSec[k]; found = true } }
  if (!found) return null
  return skinFromKvMap(map, fallbackId, source, lookup)
}

function parseFromShellValues(shellValues, lookup) {
  if (!shellValues || typeof shellValues !== "object") return null
  var map = Object.create(null)
  var found = false
  var prefix = "bar-skin."
  for (var k in shellValues) {
    if (!hasOwn(shellValues, k)) continue
    if (k.indexOf(prefix) === 0) {
      var sub = k.slice(prefix.length)
      if (!isUnsafeKey(sub)) {
        map[sub] = shellValues[k]
        found = true
      }
    }
  }
  if (!found) return null
  var skin = skinFromKvMap(map, "theme-skin", "theme", lookup)
  skin.id = "theme-skin"
  return skin
}

function tomlNumberOrAuto(value, fixed) {
  if (value === "auto") return "\"auto\""
  return fixed ? Number(value).toFixed(2) : String(value)
}

function serializeToml(skin) {
  var s = normalizeSkin(skin, skin ? skin.id : "custom", "user")
  var lines = [
    "# Barcraft skin. Works as ~/.config/omarchy/bar/skins/<name>.toml or as the",
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
    "# Geometry (\"auto\" follows Omarchy and Hyprland)",
    "height           = " + tomlNumberOrAuto(s.height),
    "edge-margin      = " + tomlNumberOrAuto(s.edgeMargin),
    "side-margin      = " + tomlNumberOrAuto(s.sideMargin),
    "width            = " + s.width,
    "section-gap      = " + s.sectionGap,
    "inner-padding-x  = " + s.innerPadding,
    "radius           = " + tomlNumberOrAuto(s.radius),
    "icon-scale       = " + s.iconScale.toFixed(2),
    "",
    "# Surface & Border",
    "background       = " + tomlString(s.background),
    "background-alpha = " + tomlNumberOrAuto(s.backgroundAlpha, true),
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
    revealOnWorkspace: false,
    omarchyMenu: false,
    updateCheck: false
  }
}

function normalizePrefs(raw) {
  var base = defaultPrefs()
  var p = raw && typeof raw === "object" ? raw : {}
  return {
    autohideDelay: Math.round(clamp(p.autohideDelay, 100, 3000, base.autohideDelay)),
    autohideWhen: oneOf(p.autohideWhen, VALID_AUTOHIDE_WHEN, base.autohideWhen),
    revealOnWorkspace: parseBool(p.revealOnWorkspace, base.revealOnWorkspace),
    omarchyMenu: parseBool(p.omarchyMenu, base.omarchyMenu),
    updateCheck: parseBool(p.updateCheck, base.updateCheck)
  }
}

function sanitizeScreenName(name) {
  var s = String(name || "").trim()
  if (isUnsafeKey(s)) return ""
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

  var map = Object.create(null)
  var lines = raw.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#" || line.charAt(0) === "[") continue
    var m = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["'](#?[0-9a-fA-F]{6})["']/)
    if (!m) continue
    var key = m[1].toLowerCase()
    if (isUnsafeKey(key)) continue
    var hex = m[2].charAt(0) === "#" ? m[2].toLowerCase() : ("#" + m[2].toLowerCase())
    map[key] = hex
  }

  var order = [
    "darker_background", "dark_background", "background", "lighter_background",
    "selection", "muted", "dark_foreground", "foreground", "light_foreground", "bright_foreground",
    "accent", "red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"
  ]

  var out = []
  var seen = Object.create(null)
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
  var map = Object.create(null)
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^([A-Za-z0-9_-]+)\s*=\s*["'](#?[0-9a-fA-F]{6})["']/)
    if (!m) continue
    var key = m[1].toLowerCase()
    if (isUnsafeKey(key)) continue
    map[key] = (m[2].charAt(0) === "#" ? m[2] : "#" + m[2]).toLowerCase()
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

  function ownedBarSectionHasUserLines(startIdx) {
    for (var j = startIdx + 1; j < lines.length; j++) {
      var t = lines[j].trim()
      if (!t) continue
      if (/^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$/.test(t)) break
      var m = t.match(/^([A-Za-z0-9_-]+)\s*=/)
      if (m && tokenKeys.indexOf(m[1]) !== -1 && t.indexOf(OWNED_MARKER) !== -1) continue
      return true
    }
    return false
  }

  var out = []
  var section = ""
  var barHeaderIndex = -1
  var userKeys = {}
  var droppedOwnedBar = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var trimmed = line.trim()
    var sec = trimmed.match(/^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$/)
    if (sec) {
      section = sec[1]
      droppedOwnedBar = false
      if (section === "bar" && trimmed.indexOf(OWNED_MARKER) !== -1) {
        // Keep a plain [bar] header if the user added their own keys under
        // Barcraft's section, so resetting icon-scale never orphans those keys
        // into whatever section appeared above it.
        if (ownedBarSectionHasUserLines(i)) {
          out.push("[bar]")
          if (barHeaderIndex < 0) barHeaderIndex = out.length - 1
        } else {
          droppedOwnedBar = true
        }
        continue
      }
      out.push(line)
      if (section === "bar" && barHeaderIndex < 0) barHeaderIndex = out.length - 1
      continue
    }
    if (section === "bar") {
      if (droppedOwnedBar && trimmed === "") continue
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

// ---------------------------------------------------------------------------
// shell.json: Barcraft's state lives in the `bar.barcraft` object, beside
// Omarchy's own bar settings, and the host writes it like every other
// setting (shell.mutateShellConfig). Plain JSON, camelCase like shell.json.

var SKIN_JSON_FIELDS = [
  "name", "description", "mode", "art", "themeTint", "bezel", "bezelStrength",
  "contrast", "surfaceTone", "customBackground", "customForeground", "customAccent",
  "height", "edgeMargin", "sideMargin", "width", "sectionGap", "innerPadding", "radius",
  "iconScale", "backgroundAlpha", "fill", "gradientTo", "blur", "border", "borderAlpha",
  "borderWidth", "shadow", "shadowStrength", "widgetStyle", "visibility", "hoverEdgePx",
  "accentHairline"
]

function skinToJson(skin) {
  var s = normalizeSkin(skin, skin ? skin.id : "custom", "custom")
  var out = { id: s.id }
  for (var i = 0; i < SKIN_JSON_FIELDS.length; i++) {
    var key = SKIN_JSON_FIELDS[i]
    if (s[key] === "" && (key === "description" || key.indexOf("custom") === 0 || key === "gradientTo")) continue
    out[key] = s[key]
  }
  return out
}

function stateToJson(activeSkinId, followTheme, draft, prefs, monitors, standard) {
  var p = normalizePrefs(prefs)
  var out = {
    standard: !!standard,
    skin: slugify(activeSkinId),
    followTheme: !!followTheme,
    autohideDelay: p.autohideDelay,
    autohideWhen: p.autohideWhen,
    revealOnWorkspace: p.revealOnWorkspace,
    omarchyMenu: p.omarchyMenu,
    updateCheck: p.updateCheck
  }
  var mons = {}
  var any = false
  for (var screen in (monitors || {})) {
    var name = sanitizeScreenName(screen)
    var id = monitors[screen]
    if (!name || !id) continue
    mons[name] = id === "theme" ? "theme" : slugify(id)
    any = true
  }
  if (any) out.monitors = mons
  if (draft) out.draft = skinToJson(draft)
  return out
}

function stateFromJson(obj, lookup) {
  var o = obj && typeof obj === "object" && !Array.isArray(obj) ? obj : {}
  var state = {
    activeSkinId: o.skin !== undefined ? slugify(o.skin) : "floating",
    followTheme: parseBool(o.followTheme, true),
    standard: parseBool(o.standard, false),
    prefs: normalizePrefs(o),
    monitors: {},
    draft: null
  }
  var mons = o.monitors && typeof o.monitors === "object" ? o.monitors : {}
  for (var screen in mons) {
    var name = sanitizeScreenName(screen)
    var id = String(mons[screen] || "").trim()
    if (!name || !id) continue
    state.monitors[name] = id === "theme" ? "theme" : slugify(id)
  }
  if (o.draft && typeof o.draft === "object" && !Array.isArray(o.draft)) {
    var base = null
    if (o.draft.preset !== undefined && typeof lookup === "function") base = lookup(String(o.draft.preset))
    var merged = base ? copySkin(base) : {}
    for (var k in o.draft) {
      if (hasOwn(o.draft, k) && !isUnsafeKey(k)) merged[k] = o.draft[k]
    }
    state.draft = normalizeSkin(merged, state.activeSkinId, "custom")
  }
  return state
}

// ---------------------------------------------------------------------------
// Omarchy's menu takes user entries from ~/.config/omarchy/extensions/
// omarchy-menu.jsonc. Barcraft's live between two marker comments, so they
// can be replaced or removed without touching anything else in the file.
// `entries` is a list of [id, object] pairs, or null to remove the block.

var MENU_BEGIN = "// barcraft:begin"
var MENU_END = "// barcraft:end"

// Index of every significant JSONC character (not whitespace, not inside a
// comment). Strings count from quote to quote, so "//" in a URL stays text.
function jsoncSignificant(text) {
  var out = []
  var i = 0
  var n = text.length
  while (i < n) {
    var c = text.charAt(i)
    if (c === "\"") {
      out.push(i)
      i++
      while (i < n && text.charAt(i) !== "\"") {
        if (text.charAt(i) === "\\") i++
        i++
      }
      if (i < n) out.push(i)
      i++
      continue
    }
    if (c === "/" && text.charAt(i + 1) === "/") {
      while (i < n && text.charAt(i) !== "\n") i++
      continue
    }
    if (c === "/" && text.charAt(i + 1) === "*") {
      var endComment = text.indexOf("*/", i + 2)
      i = endComment < 0 ? n : endComment + 2
      continue
    }
    if (!/\s/.test(c)) out.push(i)
    i++
  }
  return out
}

function applyMenuBlock(text, entries) {
  var src = String(text || "")
  var lines = src.length ? src.split("\n") : []
  var kept = []
  var inside = false
  for (var i = 0; i < lines.length; i++) {
    var t = lines[i].trim()
    if (t.indexOf(MENU_BEGIN) === 0) {
      if (inside) return src // nested/malformed markers: leave the file untouched
      inside = true
      continue
    }
    if (t.indexOf(MENU_END) === 0) {
      if (!inside) return src // stray end marker: leave the file untouched
      inside = false
      continue
    }
    if (!inside) kept.push(lines[i])
  }
  // Unclosed barcraft:begin marker: refuse to strip the rest of the file.
  if (inside) return src
  var body = kept.join("\n")
  if (!entries || entries.length === 0) return body
  if (!body.trim()) body = "{\n}\n"

  var sig = jsoncSignificant(body)
  if (sig.length === 0) return src
  var close = sig[sig.length - 1]
  // Not a JSONC object we understand: leave the file alone.
  if (body.charAt(close) !== "}" || body.charAt(sig[0]) !== "{") return src
  var prev = sig.length > 1 ? sig[sig.length - 2] : -1
  var head = body.slice(0, close)
  // The entry before ours needs a comma right after it; JSONC allows a
  // trailing comma after ours.
  if (prev >= 0 && body.charAt(prev) !== "{" && body.charAt(prev) !== ",") {
    head = body.slice(0, prev + 1) + "," + body.slice(prev + 1, close)
  }
  head = head.replace(/[ \t]*$/, "")
  if (head.charAt(head.length - 1) !== "\n") head += "\n"
  var block = ["  " + MENU_BEGIN + " (added by Barcraft; turn \"Show in Omarchy menu\" off in Barcraft Studio to remove)"]
  for (var e = 0; e < entries.length; e++) {
    block.push("  " + JSON.stringify(String(entries[e][0])) + ": " + JSON.stringify(entries[e][1]) + ",")
  }
  block.push("  " + MENU_END)
  return head + block.join("\n") + "\n" + body.slice(close)
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
    skinToJson: skinToJson,
    stateToJson: stateToJson,
    stateFromJson: stateFromJson,
    applyMenuBlock: applyMenuBlock,
    slugify: slugify,
    sanitizeLabel: sanitizeLabel,
    neutralizeMarkup: neutralizeMarkup,
    isSafeSkinPath: isSafeSkinPath,
    stampUpdateHook: stampUpdateHook,
    isPristineUpdateHook: isPristineUpdateHook,
    resolveSaveTarget: resolveSaveTarget,
    HOOK_OWNED_MARKER: HOOK_OWNED_MARKER
  }
}

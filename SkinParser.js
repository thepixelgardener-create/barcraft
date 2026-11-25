// Pure JS TOML parser, serializer, and validator for Barcraft skins.
// Follows Omarchy's shell.toml conventions: kebab-case keys, *-alpha
// companions, semantic color roles. [bar-skin] is Barcraft's own section; a
// theme's shell.toml or ~/.config/omarchy/shell.toml may carry it.
//
// No QML imports, so the regression tests in tests/ run it under node.

var VALID_MODES = ["edge", "floating", "islands"]
var VALID_ARTS = ["none", "matrix", "runeforge", "amiga"]
var VALID_BEZELS = ["none", "raised", "inset", "ridge", "glass"]
var VALID_BORDERS = ["none", "subtle", "accent", "hyprland"]
var VALID_VISIBILITY = ["always", "autohide"]
var VALID_WIDGET_STYLES = ["plain", "pills", "chips"]
var VALID_FILLS = ["solid", "gradient"]
var VALID_AUTOHIDE_WHEN = ["always", "windows"]
var RESERVED_SKIN_IDS = ["standard", "draft", "theme", "theme-skin"]
var SKIN_FORMAT_VERSION = 1

function sanitizeMd5(raw) {
  var s = String(raw || "").trim().toLowerCase()
  return /^[0-9a-f]{32}$/.test(s) ? s : ""
}

function isReservedSkinId(slug, builtinList) {
  var s = String(slug || "").trim().toLowerCase()
  if (!s) return true
  if (RESERVED_SKIN_IDS.indexOf(s) !== -1) return true
  if (canonicalSkinId(s) !== s) return true
  var list = Array.isArray(builtinList) ? builtinList : builtinSkins()
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].id === s) return true
  }
  return false
}

// Verified atomic file I/O shell scripts shared by SkinStore.qml and tests.
// Exit codes for WRITE_FILE_SCRIPT:
//   0 written (and old removed if requested)
//   1 failed (or rolled back when old could not be removed)
//   2 target already exists (noClobber)
//   3 target changed on disk since it was read (expect mismatch)
//   4 target written, old file could not be removed and rollback failed
var WRITE_FILE_SCRIPT =
  "dest=$1; want=$2; noclobber=$3; mkexec=$4; old=$5; expect=$6; " +
  "md5() { md5sum | cut -d' ' -f1; }; " +
  "[ -n \"$dest\" ] && [ ! -L \"$dest\" ] || exit 1; " +
  "if [ \"$noclobber\" = 1 ] && [ -e \"$dest\" ]; then exit 2; fi; " +
  "dir=$(dirname -- \"$dest\"); " +
  "mkdir -p -- \"$dir\" || exit 1; " +
  "tmp=$(mktemp \"$dir/.barcraft.XXXXXX\") || exit 1; " +
  "trap 'rm -f -- \"$tmp\"' EXIT; " +
  "cat > \"$tmp\" || exit 1; " +
  "[ \"$(md5 < \"$tmp\")\" = \"$want\" ] || exit 1; " +
  "if [ -f \"$dest\" ]; then chmod --reference=\"$dest\" -- \"$tmp\" || exit 1; " +
  "else m=$(umask); chmod \"$(printf '%o' $(( 0666 & ~m )))\" -- \"$tmp\" || exit 1; fi; " +
  "if [ \"$mkexec\" = 1 ]; then chmod 0755 -- \"$tmp\" || exit 1; fi; " +
  "if [ \"$expect\" = missing ]; then ln -- \"$tmp\" \"$dest\" 2>/dev/null || exit 3; " +
  "elif [ \"$noclobber\" = 1 ]; then ln -- \"$tmp\" \"$dest\" 2>/dev/null || exit 2; " +
  "else " +
  "  if [ -n \"$expect\" ]; then " +
  "    [ ! -L \"$dest\" ] && [ -f \"$dest\" ] && [ \"$(md5 < \"$dest\")\" = \"$expect\" ] || exit 3; " +
  "  fi; " +
  "  mv -fT -- \"$tmp\" \"$dest\" || exit 1; " +
  "fi; " +
  "rm -f -- \"$tmp\"; trap - EXIT; " +
  "[ ! -L \"$dest\" ] && [ -f \"$dest\" ] && [ \"$(md5 < \"$dest\")\" = \"$want\" ] || exit 1; " +
  "if [ -n \"$old\" ] && [ \"$old\" != \"$dest\" ]; then " +
  "  if [ -L \"$old\" ] || { [ -e \"$old\" ] && [ ! -f \"$old\" ]; }; then " +
  "    if [ \"$noclobber\" = 1 ]; then rm -f -- \"$dest\" 2>/dev/null; [ ! -e \"$dest\" ] && exit 1 || exit 4; fi; " +
  "    exit 4; " +
  "  fi; " +
  "  if [ -f \"$old\" ]; then " +
  "    rm -- \"$old\" 2>/dev/null; " +
  "    if [ -e \"$old\" ]; then " +
  "      if [ \"$noclobber\" = 1 ]; then rm -f -- \"$dest\" 2>/dev/null; [ ! -e \"$dest\" ] && exit 1 || exit 4; fi; " +
  "      exit 4; " +
  "    fi; " +
  "  fi; " +
  "fi"

// Removes one or more regular non-symlink skin files and verifies none remain.
// Exit codes: 0 removed (or already absent), 1 failed to remove / symlink.
var REMOVE_SKIN_FILES_SCRIPT =
  "rc=0; " +
  "for p in \"$@\"; do " +
  "  [ -n \"$p\" ] || continue; " +
  "  if [ -L \"$p\" ]; then rc=1; continue; fi; " +
  "  if [ ! -e \"$p\" ]; then continue; fi; " +
  "  if [ ! -f \"$p\" ]; then rc=1; continue; fi; " +
  "  rm -- \"$p\" 2>/dev/null; " +
  "  if [ -e \"$p\" ]; then rc=1; fi; " +
  "done; " +
  "exit \"$rc\""

// Removes a regular file only while it still has the expected MD5.
// Exit codes: 0 removed, 3 missing or changed, 1 failed.
var REMOVE_IF_UNCHANGED_SCRIPT =
  "p=$1; h=$2; " +
  "[ ! -L \"$p\" ] && [ -f \"$p\" ] && [ \"$(md5sum < \"$p\" | cut -d' ' -f1)\" = \"$h\" ] || exit 3; " +
  "rm -- \"$p\" 2>/dev/null && [ ! -e \"$p\" ] || exit 1"

// Fresh uncached read of a regular non-symlink file.
// Exit codes: 0 ok (content on stdout), 3 missing, 4 unreadable/symlink/error.
var READ_FILE_SCRIPT =
  "p=$1; " +
  "[ -n \"$p\" ] || exit 4; " +
  "if [ ! -e \"$p\" ] && [ ! -L \"$p\" ]; then exit 3; fi; " +
  "[ ! -L \"$p\" ] && [ -f \"$p\" ] && [ -r \"$p\" ] || exit 4; " +
  "cat -- \"$p\""

var MAX_SCANNED_SKINS = 200

// Scans up to `limit` regular non-symlink `.toml` files (<= 32 KiB) from
// userdir then legacydir, checking any pinned slugs first so active,
// per-monitor, draft, and recently saved skins are never pushed past the limit
// by a large skin pack. Outputs `{rows: [{path, text}...], truncated: N}` with
// skipped counting capped at 1000 so huge folders stay fast.
var SCAN_SKINS_SCRIPT =
  "limit=$1; userdir=${2%/}; legacydir=${3%/}; shift 3; " +
  "nl=$(printf '\\n_'); nl=${nl%_}; " +
  "{ " +
  "  n=0; skipped=0; seen=\"$nl\"; " +
  "  emit() { " +
  "    f=$1; " +
  "    [ ! -L \"$f\" ] && [ -f \"$f\" ] && [ -r \"$f\" ] || return 0; " +
  "    case \"$seen\" in *\"$nl$f$nl\"*) return 0 ;; esac; " +
  "    seen=\"$seen$f$nl\"; " +
  "    size=$(stat -c %s \"$f\" 2>/dev/null || echo 999999); " +
  "    [ \"$size\" -le 32768 ] || return 0; " +
  "    if [ \"$n\" -ge \"$limit\" ]; then " +
  "      skipped=$((skipped + 1)); " +
  "      return 0; " +
  "    fi; " +
  "    jq -Rs --arg path \"$f\" '{path: $path, text: .}' \"$f\"; " +
  "    n=$((n + 1)); " +
  "  }; " +
  "  for slug in \"$@\"; do " +
  "    [ -n \"$slug\" ] || continue; " +
  "    [ -n \"$userdir\" ] && emit \"$userdir/$slug.toml\"; " +
  "    [ -n \"$legacydir\" ] && emit \"$legacydir/$slug.toml\"; " +
  "  done; " +
  "  for d in \"$userdir\" \"$legacydir\"; do " +
  "    [ -n \"$d\" ] && [ -d \"$d\" ] || continue; " +
  "    for f in \"$d\"/*.toml; do " +
  "      emit \"$f\"; " +
  "      [ \"$skipped\" -ge 1000 ] && break 2; " +
  "    done; " +
  "  done; " +
  "  printf '{\"__meta\":true,\"truncated\":%d}\\n' \"$skipped\"; " +
  "} | jq -s '{rows: map(select(.__meta | not)), truncated: ((map(select(.__meta)) | last | .truncated) // 0)}'"

// Collects safe filename slugs that must be scanned before the alphabetical
// pass so active, per-monitor, draft, and recently saved skins can never be
// pushed past MAX_SCANNED_SKINS by a large skin pack.
function pinnedScanSlugs(activeSkinId, monitorSkins, draft, monitorDrafts, userSkins, builtinList, extraSlugs) {
  var out = []
  var seen = Object.create(null)
  var fileById = Object.create(null)
  var list = Array.isArray(userSkins) ? userSkins : []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (!s || !s.id || !s.path) continue
    var stem = String(s.path).replace(/^.*\//, "").replace(/\.toml$/i, "")
    if (/^[a-z0-9][a-z0-9_-]{0,63}$/i.test(stem)) fileById[s.id] = stem
  }

  function pushRaw(slug) {
    var clean = String(slug || "").trim()
    if (!clean || !/^[a-z0-9][a-z0-9_-]{0,63}$/i.test(clean)) return
    if (isUnsafeKey(clean) || hasOwn(seen, clean) || out.length >= 32) return
    seen[clean] = true
    out.push(clean)
  }

  function addId(rawId) {
    var id = String(rawId || "").trim()
    if (!id || id === "theme" || id === "theme-skin") return
    if (hasOwn(fileById, id)) {
      pushRaw(fileById[id])
      return
    }
    var m = id.match(/^(standard|draft|theme|theme-skin)-saved(?:-\d+)?$/)
    if (m) pushRaw(m[1])
    if (id !== "standard" && id !== "draft") pushRaw(id)
  }

  addId(activeSkinId)
  if (monitorSkins && typeof monitorSkins === "object") {
    for (var screen in monitorSkins) {
      if (hasOwn(monitorSkins, screen)) addId(monitorSkins[screen])
    }
  }
  if (draft && typeof draft === "object") addId(draft.id)
  if (monitorDrafts && typeof monitorDrafts === "object") {
    for (var ds in monitorDrafts) {
      if (hasOwn(monitorDrafts, ds) && monitorDrafts[ds]) addId(monitorDrafts[ds].id)
    }
  }
  if (Array.isArray(extraSlugs)) {
    for (var e = 0; e < extraSlugs.length; e++) addId(extraSlugs[e])
  }
  return out
}

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

// The notification text 0.5.0 and 0.5.1 put in the hook, in every language
// they shipped. Frozen on purpose: an untouched old hook holds one of these,
// whatever the language is today.
var LEGACY_HOOK_MESSAGES = [
  "Omarchy updated its bar. Run scripts/sync-upstream.sh in the Barcraft folder to carry the update over.",
  "Omarchy hat seine Leiste aktualisiert. Führe scripts/sync-upstream.sh im Barcraft-Ordner aus, um das Update zu übernehmen."
]
var LEGACY_HOOK_HEADERS = [
  // 0.5.0
  ["#!/bin/bash",
   "# Added by Barcraft (thepixelgardener.barcraft). Turn \"Check after Omarchy",
   "# updates\" off in Barcraft Studio to remove this file."],
  // 0.5.1
  ["#!/bin/bash",
   HOOK_OWNED_MARKER,
   "# Turn \"Check after Omarchy updates\" off in Barcraft Studio to remove this file."]
]

function shellQuoteSingle(text) {
  return "'" + String(text).replace(/\0/g, "").replace(/'/g, "'\\''") + "'"
}

// The hook's commands: notify when Omarchy's bar moved under Barcraft's copy.
function updateHookCommands(pluginDir, message) {
  return [
    "plugin=" + shellQuoteSingle(pluginDir),
    "[[ -f $plugin/scripts/sync-upstream.sh ]] || exit 0",
    "if ! bash \"$plugin/scripts/sync-upstream.sh\" --check >/dev/null 2>&1; then",
    "  omarchy-notification-send -g " + shellQuoteSingle("󰍜") + " Barcraft " + shellQuoteSingle(message),
    "fi",
    ""
  ]
}

function updateHookScript(pluginDir, message, md5) {
  var body = ["# Turn \"Check after Omarchy updates\" off in Barcraft Studio to remove this file."]
    .concat(updateHookCommands(pluginDir, message)).join("\n")
  return stampUpdateHook(body, md5)
}

// Every hook 0.5.0 or 0.5.1 could have written for this plugin folder.
function legacyUpdateHookScripts(pluginDir) {
  var out = []
  for (var m = 0; m < LEGACY_HOOK_MESSAGES.length; m++) {
    var commands = updateHookCommands(pluginDir, LEGACY_HOOK_MESSAGES[m])
    for (var h = 0; h < LEGACY_HOOK_HEADERS.length; h++) out.push(LEGACY_HOOK_HEADERS[h].concat(commands).join("\n"))
  }
  return out
}

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
      description: "CRT phosphor construct with layered digital rain, PCB traces & bloom brackets",
      height: 30, edgeMargin: 6, sideMargin: 10, innerPadding: 12, radius: 2,
      backgroundAlpha: 0.98, customForeground: "#7dffb0",
      border: "none", borderAlpha: 0.0, borderWidth: 0
    }),
    preset({
      id: "runeforge", name: "Runeforge", category: "wild", art: "runeforge",
      description: "Hammered obsidian basalt, riveted antique brass & molten Elder Futhark runes",
      height: 32, edgeMargin: 6, sideMargin: 10, innerPadding: 14, radius: 0,
      backgroundAlpha: 0.98,
      border: "none", borderAlpha: 0.0, borderWidth: 0
    }),
    preset({
      id: "amiga", name: "Amiga", category: "wild", art: "amiga",
      description: "Workbench blue pixel bevels, copper sheen, Boing Ball & depth gadget",
      height: 30, edgeMargin: 4, sideMargin: 8, innerPadding: 12, radius: 0,
      backgroundAlpha: 0.98, customForeground: "#ffffff",
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
    .replace(/[\r\n\t\u2028\u2029]+/g, " ")
    .replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]/g, "")
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
function parseTomlSectionsWithLines(text) {
  var out = Object.create(null)
  var linesMap = Object.create(null)
  out[""] = Object.create(null)
  linesMap[""] = Object.create(null)
  var section = ""
  var ignoreSection = false
  var syntaxErrors = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var lineNo = i + 1
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
      if (!out[section]) {
        out[section] = Object.create(null)
        linesMap[section] = Object.create(null)
      }
      continue
    }
    if (ignoreSection) continue
    var kv = line.match(/^(?:"([^"\\]{1,64})"|([A-Za-z0-9_-]{1,64}))\s*=\s*(.*)$/)
    if (!kv) {
      if (section === "bar-skin" || section === "") {
        syntaxErrors.push({ line: lineNo, key: "", message: "Line " + lineNo + ": invalid TOML syntax" })
      }
      continue
    }
    var key = kv[1] !== undefined ? kv[1] : kv[2]
    if (isUnsafeKey(key)) continue
    if ((section === "bar-skin" || section === "") && hasOwn(out[section], key)) {
      syntaxErrors.push({ line: lineNo, key: key, duplicate: true, message: "Line " + lineNo + ": duplicate key \"" + sanitizeLabel(key, 40) + "\"" })
      continue
    }
    var value = parseTomlValue(kv[3])
    if (value === null) {
      if (section === "bar-skin" || section === "") {
        syntaxErrors.push({ line: lineNo, key: key, message: "Line " + lineNo + ": invalid value for \"" + sanitizeLabel(key, 40) + "\"" })
      }
      continue
    }
    out[section][key] = value
    linesMap[section][key] = lineNo
  }
  return { sections: out, lines: linesMap, syntaxErrors: syntaxErrors }
}

function parseTomlSections(text) {
  return parseTomlSectionsWithLines(text).sections
}

// Damerau-Levenshtein <= 2 so single transpositions like "heigth" -> "height" match with distance 1.
function closestKeySuggestion(badKey) {
  var target = String(badKey || "").toLowerCase()
  if (!target || target.length > 40) return ""
  var best = ""
  var bestDist = 3
  var candidates = ["format", "preset"]
  for (var k in KEY_MAP) if (hasOwn(KEY_MAP, k)) candidates.push(k)
  for (var i = 0; i < candidates.length; i++) {
    var c = candidates[i]
    if (Math.abs(c.length - target.length) > 2) continue
    var m = target.length
    var n = c.length
    var d = []
    for (var a = 0; a <= m; a++) {
      d[a] = [a]
    }
    for (var b = 0; b <= n; b++) d[0][b] = b
    for (var r = 1; r <= m; r++) {
      for (var col = 1; col <= n; col++) {
        var cost = target.charAt(r - 1) === c.charAt(col - 1) ? 0 : 1
        var v = Math.min(d[r - 1][col] + 1, d[r][col - 1] + 1, d[r - 1][col - 1] + cost)
        if (r > 1 && col > 1 && target.charAt(r - 1) === c.charAt(col - 2) && target.charAt(r - 2) === c.charAt(col - 1)) {
          v = Math.min(v, d[r - 2][col - 2] + 1)
        }
        d[r][col] = v
      }
    }
    if (d[m][n] < bestDist) {
      bestDist = d[m][n]
      best = c
    }
  }
  return bestDist <= 2 ? best : ""
}

function formatLinePrefix(lineNo) {
  return lineNo > 0 ? ("Line " + lineNo + ": ") : ""
}

var NUMERIC_SPECS = dict({
  "bezel-strength": { min: 0.15, max: 1.0, allowAuto: false, whole: false },
  "contrast": { min: 0.5, max: 1.5, allowAuto: false, whole: false },
  "surface-tone": { min: 0.5, max: 1.5, allowAuto: false, whole: false },
  "height": { min: 22, max: 56, allowAuto: true, whole: true },
  "edge-margin": { min: 0, max: 24, allowAuto: true, whole: true },
  "side-margin": { min: 0, max: 48, allowAuto: true, whole: true },
  "width": { min: 30, max: 100, allowAuto: false, whole: true },
  "section-gap": { min: 0, max: 32, allowAuto: false, whole: true },
  "inner-padding": { min: 4, max: 24, allowAuto: false, whole: true },
  "inner-padding-x": { min: 4, max: 24, allowAuto: false, whole: true },
  "radius": { min: 0, max: 28, allowAuto: true, whole: true },
  "icon-scale": { min: 0.8, max: 1.5, allowAuto: false, whole: false },
  "background-alpha": { min: 0, max: 1.0, allowAuto: true, whole: false },
  "border-alpha": { min: 0, max: 1.0, allowAuto: false, whole: false },
  "border-width": { min: 0, max: 4, allowAuto: false, whole: true },
  "shadow-strength": { min: 0.1, max: 1.0, allowAuto: false, whole: false },
  "hover-edge-px": { min: 1, max: 16, allowAuto: false, whole: true }
})

var BOOL_KEYS = dict({
  "theme-tint": true,
  "blur": true,
  "shadow": true,
  "accent-hairline": true
})

var COLOR_REF_KEYS = dict({
  "custom-background": true,
  "custom-foreground": true,
  "custom-accent": true,
  "gradient-to": true
})

function validateRawEntry(key, rawVal, lineNo, errors, adjustments) {
  var prefix = formatLinePrefix(lineNo)
  var str = String(rawVal === undefined || rawVal === null ? "" : rawVal).trim()
  var low = str.toLowerCase()

  if (key === "name" || key === "description" || key === "id") {
    return true
  }
  if (key === "mode") {
    if (low === "stealth" || VALID_MODES.indexOf(low) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid mode \"" + str + "\"" })
    return false
  }
  if (key === "art") {
    var artVal = hasOwn(ART_ALIASES, low) ? ART_ALIASES[low] : low
    if (VALID_ARTS.indexOf(artVal) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid art \"" + str + "\"" })
    return false
  }
  if (key === "bezel") {
    if (VALID_BEZELS.indexOf(low) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid bezel \"" + str + "\"" })
    return false
  }
  if (key === "border") {
    var bVal = (low === "hyprland.active-border" || low === "hyprland.active-border-foreground") ? "hyprland" : low
    if (VALID_BORDERS.indexOf(bVal) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid border \"" + str + "\"" })
    return false
  }
  if (key === "fill") {
    if (VALID_FILLS.indexOf(low) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid fill \"" + str + "\"" })
    return false
  }
  if (key === "widget-style") {
    if (VALID_WIDGET_STYLES.indexOf(low) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid widget-style \"" + str + "\"" })
    return false
  }
  if (key === "visibility") {
    if (VALID_VISIBILITY.indexOf(low) !== -1) return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid visibility \"" + str + "\"" })
    return false
  }
  if (key === "background") {
    if (low === "bar.background" || normalizeColorRef(str) !== "") return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid background color \"" + str + "\"" })
    return false
  }
  if (hasOwn(COLOR_REF_KEYS, key)) {
    if (str === "" || normalizeColorRef(str) !== "") return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid color \"" + str + "\" for " + key })
    return false
  }
  if (hasOwn(BOOL_KEYS, key)) {
    if (typeof rawVal === "boolean" || low === "true" || low === "false" || low === "1" || low === "0" || low === "yes" || low === "no") return true
    errors.push({ line: lineNo, key: key, message: prefix + "invalid boolean \"" + str + "\" for " + key })
    return false
  }
  if (hasOwn(NUMERIC_SPECS, key)) {
    var spec = NUMERIC_SPECS[key]
    if (spec.allowAuto && low === "auto") return true
    var num = Number(str)
    if (str === "" || !isFinite(num)) {
      errors.push({ line: lineNo, key: key, message: prefix + "invalid number \"" + str + "\" for " + key })
      return false
    }
    var clamped = Math.max(spec.min, Math.min(spec.max, num))
    var applied = spec.whole ? Math.round(clamped) : round2(clamped)
    if (num < spec.min || num > spec.max) {
      adjustments.push({
        line: lineNo,
        key: key,
        applied: applied,
        message: prefix + key + " adjusted to " + applied
      })
    }
    return true
  }
  return false
}

function tomlString(text) {
  return "\"" + String(text || "")
    .replace(/\\/g, "\\\\")
    .replace(/"/g, "\\\"")
    .replace(/\r/g, "\\r")
    .replace(/\n/g, "\\n")
    .replace(/\t/g, "\\t")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029") + "\""
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
var MAX_REPORTED_ERRORS = 20
var MAX_KEY_SUGGESTIONS = 5
var MAX_REPORTED_SKIPPED = 8

// Keeps a hostile file or paste from producing thousands of diagnostics, and
// keeps every message short and free of control characters.
function capErrors(errors) {
  var out = []
  for (var i = 0; i < errors.length && i < MAX_REPORTED_ERRORS; i++) {
    var e = errors[i]
    out.push({
      line: e.line || 0,
      key: sanitizeLabel(e.key, 40),
      suggestion: e.suggestion || "",
      message: sanitizeLabel(e.message, 160)
    })
  }
  if (errors.length > MAX_REPORTED_ERRORS) {
    out.push({ line: 0, key: "", message: "…and " + (errors.length - MAX_REPORTED_ERRORS) + " more" })
  }
  return out
}

function skippedSummary(keys) {
  var shown = keys.slice(0, MAX_REPORTED_SKIPPED).join(", ")
  return keys.length > MAX_REPORTED_SKIPPED ? shown + " +" + (keys.length - MAX_REPORTED_SKIPPED) : shown
}

function inspectKvMap(map, lineMap, fallbackId, source, lookup, extraErrors) {
  var tokenErrors = Array.isArray(extraErrors) ? extraErrors : []
  var errors = []
  var adjustments = []
  var skippedKeys = []
  var appliedCount = 0
  var styleCount = 0
  var suggestions = 0
  var formatVersion = SKIN_FORMAT_VERSION
  function skip(key) {
    var label = sanitizeLabel(key, 32)
    if (label && skippedKeys.indexOf(label) === -1) skippedKeys.push(label)
  }
  if (map["format"] !== undefined) {
    var rawFmt = String(map["format"] || "").trim()
    var fmtLine = lineMap && lineMap["format"] ? lineMap["format"] : 0
    if (!/^[1-9]\d{0,5}$/.test(rawFmt)) {
      errors.push({
        line: fmtLine,
        key: "format",
        message: formatLinePrefix(fmtLine) + "invalid format \"" + sanitizeLabel(rawFmt, 12) + "\""
      })
    } else {
      formatVersion = parseInt(rawFmt, 10)
    }
  }
  var newerFormat = formatVersion > SKIN_FORMAT_VERSION
  // A newer format may use values or syntax this version cannot read: those
  // lines are skipped and reported, everything else still applies.
  for (var t = 0; t < tokenErrors.length; t++) {
    var te = tokenErrors[t]
    if (newerFormat) skip(te.key ? te.key : "line " + te.line)
    else errors.push(te)
  }
  var base = null
  if (map["preset"] !== undefined) {
    var presetName = String(map["preset"] || "").trim()
    var pLine = lineMap && lineMap["preset"] ? lineMap["preset"] : 0
    if (typeof lookup === "function") base = lookup(presetName)
    if (base) {
      appliedCount++
      styleCount++
    } else if (newerFormat) {
      skip("preset")
    } else {
      errors.push({
        line: pLine,
        key: "preset",
        message: formatLinePrefix(pLine) + "unknown preset \"" + sanitizeLabel(presetName, 40) + "\""
      })
    }
  }
  var merged = base ? copySkin(base) : {}
  var named = false
  for (var key in map) {
    if (!hasOwn(map, key) || isUnsafeKey(key) || key === "preset" || key === "format") continue
    var lineNo = lineMap && lineMap[key] ? lineMap[key] : 0
    var field = hasOwn(KEY_MAP, key) ? KEY_MAP[key] : ""
    if (!field) {
      if (newerFormat) {
        skip(key)
        continue
      }
      var sug = suggestions < MAX_KEY_SUGGESTIONS ? closestKeySuggestion(key) : ""
      suggestions++
      errors.push({
        line: lineNo,
        key: key,
        suggestion: sug,
        message: formatLinePrefix(lineNo) + "unknown key \"" + sanitizeLabel(key, 40) + "\"" + (sug ? " (did you mean \"" + sug + "\"?)" : "")
      })
      continue
    }
    if (key === "inner-padding" && map["inner-padding-x"] !== undefined) continue
    if (newerFormat) {
      var entryErrors = []
      if (!validateRawEntry(key, map[key], lineNo, entryErrors, adjustments)) {
        skip(key)
        continue
      }
    } else if (!validateRawEntry(key, map[key], lineNo, errors, adjustments)) {
      continue
    }
    merged[field] = map[key]
    appliedCount++
    if (key !== "name" && key !== "description" && key !== "id") styleCount++
    if (field === "name") named = true
  }
  if (newerFormat && skippedKeys.length > 0) {
    adjustments.push({
      line: 0,
      key: "format",
      message: "format " + formatVersion + " is newer than this Barcraft; skipped: " + skippedSummary(skippedKeys)
    })
  }
  if (!named && !base) merged.name = fallbackId
  if (!merged.id) merged.id = fallbackId
  // Files and theme skins load whenever any key applied, as in 0.7. Paste
  // additionally requires a style key (styleCount); see SkinEngine.importText.
  var skin = appliedCount > 0 ? normalizeSkin(merged, fallbackId, source) : null
  return {
    skin: skin,
    appliedCount: appliedCount,
    styleCount: styleCount,
    formatVersion: formatVersion,
    newerFormat: newerFormat,
    skippedKeys: skippedKeys,
    skippedSummary: skippedSummary(skippedKeys),
    errors: capErrors(errors),
    adjustments: adjustments
  }
}

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

function extractSkinKvMapWithLines(text) {
  var raw = String(text || "")
  if (!raw.trim()) return null
  var parsed = parseTomlSectionsWithLines(raw)
  var sections = parsed.sections
  var lines = parsed.lines
  var map = Object.create(null)
  var lineMap = Object.create(null)
  var found = false
  var top = sections[""] || Object.create(null)
  var topLines = lines[""] || Object.create(null)
  var skinSec = sections["bar-skin"] || Object.create(null)
  var skinLines = lines["bar-skin"] || Object.create(null)
  var hasSkinSection = hasOwn(sections, "bar-skin")
  var k
  var typoChecks = 0
  for (k in top) {
    var known = hasOwn(KEY_MAP, k) || k === "preset" || k === "format"
    // Without a [bar-skin] header, other top-level keys are ignored, except
    // one that is a near-miss of a skin key ("heigth"): that is a typo, and
    // passing it on lets the strict paste report it.
    var typo = !known && !hasSkinSection && typoChecks++ < 50 && closestKeySuggestion(k) !== ""
    if (known || typo) {
      map[k] = top[k]
      lineMap[k] = topLines[k] || 0
      if (known) found = true
    }
  }
  for (k in skinSec) {
    if (!isUnsafeKey(k)) {
      map[k] = skinSec[k]
      lineMap[k] = skinLines[k] || 0
      found = true
    }
  }
  if (!found && !hasSkinSection) {
    return parsed.syntaxErrors.length ? { map: map, lineMap: lineMap, syntaxErrors: parsed.syntaxErrors, hasSection: false } : null
  }
  return { map: map, lineMap: lineMap, syntaxErrors: parsed.syntaxErrors, hasSection: hasSkinSection }
}

function extractSkinKvMap(text) {
  var extracted = extractSkinKvMapWithLines(text)
  if (!extracted) return null
  for (var k in extracted.map) {
    if (hasOwn(extracted.map, k)) return extracted.map
  }
  return null
}

function inspectToml(text, fallbackId, source, lookup) {
  var extracted = extractSkinKvMapWithLines(text)
  if (!extracted) {
    return {
      skin: null,
      appliedCount: 0,
      styleCount: 0,
      formatVersion: SKIN_FORMAT_VERSION,
      newerFormat: false,
      skippedKeys: [],
      skippedSummary: "",
      errors: [],
      adjustments: []
    }
  }
  return inspectKvMap(extracted.map, extracted.lineMap, fallbackId, source, lookup, extracted.syntaxErrors)
}

function parseToml(text, fallbackId, source, lookup) {
  var map = extractSkinKvMap(text)
  if (!map) return null
  return skinFromKvMap(map, fallbackId, source, lookup)
}

// Disambiguates an existing user skin file whose filename slug collides with a
// reserved built-in action id ("standard", "theme", "theme-skin", "draft").
function safeUserSlug(baseSlug, usedMap) {
  var slug = baseSlug
  if (RESERVED_SKIN_IDS.indexOf(slug) === -1) return slug
  var candidate = (slug + "-saved").slice(0, 40)
  var n = 2
  while (hasOwn(usedMap, candidate) || RESERVED_SKIN_IDS.indexOf(candidate) !== -1) {
    var suffix = "-" + n
    candidate = (slug + "-saved").slice(0, Math.max(1, 40 - suffix.length)) + suffix
    n++
  }
  return candidate
}

// Indexes all skin files first, then resolves `preset = "<id>"` inheritance
// across the whole library in one pass (handling arbitrary file order,
// multi-level chains, and cycles cleanly). Earlier rows win a slug clash.
function parseSkinLibraryDetailed(rows, allowedDirs, builtinList) {
  var list = Array.isArray(rows) ? rows : []
  var builtins = Array.isArray(builtinList) ? builtinList : builtinSkins()
  var builtinById = Object.create(null)
  for (var b = 0; b < builtins.length; b++) {
    if (builtins[b] && builtins[b].id) builtinById[builtins[b].id] = builtins[b]
  }
  function lookupBuiltin(id) {
    var target = String(id || "").trim()
    if (!target) return null
    if (hasOwn(builtinById, target)) return builtinById[target]
    var alias = canonicalSkinId(target)
    if (hasOwn(builtinById, alias)) return builtinById[alias]
    return null
  }

  var order = []
  var rawBySlug = Object.create(null)
  var seenFileSlugs = Object.create(null)
  var renamedIds = Object.create(null)
  var diagnostics = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    if (!row || typeof row !== "object") continue
    var file = String(row.path || "")
    if (!isSafeSkinPath(file, allowedDirs)) continue
    var fileSlug = slugify(file.replace(/^.*\//, "").replace(/\.toml$/, ""))
    if (hasOwn(seenFileSlugs, fileSlug)) continue
    var extracted = extractSkinKvMapWithLines(row.text)
    if (!extracted) {
      var empty = String(row.text || "").trim() === ""
      diagnostics.push({ path: file, errors: [{ line: 0, key: "", message: empty ? "File is empty" : "No [bar-skin] section found" }], adjustments: [] })
      continue
    }
    // Only a file with a [bar-skin] section claims its name, so a broken copy
    // never hides a working one in the other folder.
    seenFileSlugs[fileSlug] = true
    var slug = safeUserSlug(fileSlug, rawBySlug)
    // A reserved name moved aside ("standard" -> "standard-saved") can meet a
    // later file of that very name; the earlier row wins, as for any clash.
    if (hasOwn(rawBySlug, slug)) continue
    if (slug !== fileSlug) renamedIds[fileSlug] = slug
    rawBySlug[slug] = {
      slug: slug,
      fileSlug: fileSlug,
      path: file,
      map: extracted.map,
      lineMap: extracted.lineMap,
      syntaxErrors: extracted.syntaxErrors
    }
    order.push(slug)
  }

  var resolved = Object.create(null)
  var visiting = Object.create(null)

  function resolveSlug(slug) {
    if (hasOwn(resolved, slug)) return resolved[slug]
    if (hasOwn(visiting, slug) || !hasOwn(rawBySlug, slug)) return null
    visiting[slug] = true
    var entry = rawBySlug[slug]
    var inspected = inspectKvMap(entry.map, entry.lineMap, slug, "user", function(parentId) {
      var target = String(parentId || "").trim()
      if (!target) return null
      var targetSlug = slugify(target)
      var parentKey = hasOwn(rawBySlug, target) ? target
        : (hasOwn(rawBySlug, targetSlug) ? targetSlug
        : (hasOwn(renamedIds, targetSlug) ? renamedIds[targetSlug] : ""))
      if (parentKey && !hasOwn(visiting, parentKey)) {
        var fromUser = resolveSlug(parentKey)
        if (fromUser) return fromUser
      }
      return lookupBuiltin(target)
    }, entry.syntaxErrors)
    delete visiting[slug]
    if (inspected.errors.length > 0 || inspected.adjustments.length > 0) {
      diagnostics.push({
        path: entry.path,
        errors: inspected.errors,
        adjustments: inspected.adjustments
      })
    }
    var skin = inspected.skin
    if (!skin) return null
    skin.id = slug
    skin.source = "user"
    skin.path = entry.path
    skin.category = skin.art !== "none" ? "wild" : "classic"
    resolved[slug] = skin
    return skin
  }

  var parsed = []
  for (var j = 0; j < order.length; j++) {
    var s = resolveSlug(order[j])
    if (s) parsed.push(s)
  }
  // old file slug -> id it loads under, for reserved names moved aside.
  var renamed = {}
  for (var oldId in renamedIds) {
    if (hasOwn(resolved, renamedIds[oldId])) renamed[oldId] = renamedIds[oldId]
  }
  return { skins: parsed, diagnostics: diagnostics, renamedIds: renamed }
}

function parseSkinLibrary(rows, allowedDirs, builtinList) {
  return parseSkinLibraryDetailed(rows, allowedDirs, builtinList).skins
}

// Classifies one `inotifywait --format '%w|%e|%f'` line against the skin
// directories and their parents: "rescan", "rewatch", or "ignore".
function classifySkinWatchEvent(line, userSkinsDir, legacySkinsDir, configDir) {
  var raw = String(line || "")
  var first = raw.indexOf("|")
  if (first < 0) return "ignore"
  var second = raw.indexOf("|", first + 1)
  if (second < 0) return "ignore"
  var dir = raw.slice(0, first).replace(/\/+$/, "")
  var events = raw.slice(first + 1, second).split(",")
  var name = raw.slice(second + 1).replace(/[\r\n]+$/, "")

  function hasEvent(ev) { return events.indexOf(ev) !== -1 }

  var userDir = String(userSkinsDir || "").replace(/\/+$/, "")
  var legacyDir = String(legacySkinsDir || "").replace(/\/+$/, "")
  var cfgDir = String(configDir || "").replace(/\/+$/, "")
  var barDir = cfgDir ? (cfgDir + "/bar") : ""

  if (dir === userDir || dir === legacyDir) {
    if (hasEvent("DELETE_SELF") || hasEvent("MOVE_SELF")) return "rewatch"
    if (/^[a-z0-9][a-z0-9_-]{0,63}\.toml$/i.test(name)) return "rescan"
    return "ignore"
  }
  if (barDir && dir === barDir) {
    if (hasEvent("DELETE_SELF") || hasEvent("MOVE_SELF")) return "rewatch"
    if (name === "skins" && (hasEvent("CREATE") || hasEvent("MOVED_TO") || hasEvent("DELETE") || hasEvent("MOVED_FROM"))) {
      return "rewatch"
    }
    return "ignore"
  }
  if (cfgDir && dir === cfgDir) {
    if ((name === "bar" || name === "bar-skins") && (hasEvent("CREATE") || hasEvent("MOVED_TO") || hasEvent("DELETE") || hasEvent("MOVED_FROM"))) {
      return "rewatch"
    }
    return "ignore"
  }
  return "ignore"
}

function inspectShellValues(shellValues, lookup) {
  if (!shellValues || typeof shellValues !== "object") {
    return {
      skin: null,
      appliedCount: 0,
      styleCount: 0,
      formatVersion: SKIN_FORMAT_VERSION,
      newerFormat: false,
      skippedKeys: [],
      skippedSummary: "",
      errors: [],
      adjustments: []
    }
  }
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
  if (!found) {
    return {
      skin: null,
      appliedCount: 0,
      styleCount: 0,
      formatVersion: SKIN_FORMAT_VERSION,
      newerFormat: false,
      skippedKeys: [],
      skippedSummary: "",
      errors: [],
      adjustments: []
    }
  }
  var res = inspectKvMap(map, null, "theme-skin", "theme", lookup, [])
  if (res.skin) res.skin.id = "theme-skin"
  return res
}

function parseFromShellValues(shellValues, lookup) {
  return inspectShellValues(shellValues, lookup).skin
}

function tomlNumberOrAuto(value, fixed) {
  if (value === "auto") return "\"auto\""
  return fixed ? Number(value).toFixed(2) : String(value)
}

// `options.compact` (Copy TOML) leaves out sub-keys whose feature is off.
// Skin files and stored drafts keep them, so switching a feature back on
// brings back the user's values.
function serializeToml(skin, options) {
  var s = normalizeSkin(skin, skin ? skin.id : "custom", "user")
  var full = !(options && options.compact)
  var lines = [
    "# Barcraft skin. Save as ~/.config/omarchy/bar/skins/<name>.toml,",
    "# or ship in a theme as shell.bar-skin.toml (or [bar-skin] in shell.toml).",
    "[bar-skin]",
    "format           = " + SKIN_FORMAT_VERSION,
    "name             = " + tomlString(s.name),
    s.description ? "description      = " + tomlString(s.description) : null,
    "mode             = \"" + s.mode + "\"",
    "art              = \"" + s.art + "\"",
    (full || s.art !== "none") ? ("theme-tint       = " + (s.themeTint ? "true" : "false")) : null,
    "bezel            = \"" + s.bezel + "\"",
    (full || s.bezel !== "none") ? ("bezel-strength   = " + s.bezelStrength.toFixed(2)) : null,
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
    (full || s.border !== "none") ? ("border-alpha     = " + s.borderAlpha.toFixed(2)) : null,
    (full || s.border !== "none") ? ("border-width     = " + s.borderWidth) : null,
    "shadow           = " + (s.shadow ? "true" : "false"),
    (full || s.shadow) ? ("shadow-strength  = " + s.shadowStrength.toFixed(2)) : null,
    "widget-style     = \"" + s.widgetStyle + "\"",
    "",
    "# Behavior",
    "visibility       = \"" + s.visibility + "\"",
    (full || s.visibility === "autohide") ? ("hover-edge-px    = " + s.hoverEdgePx) : null,
    (full || s.visibility === "autohide") ? ("accent-hairline  = " + (s.accentHairline ? "true" : "false")) : null,
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

function stateToJson(activeSkinId, followTheme, draft, prefs, monitors, standard, monitorDrafts, meta) {
  var p = normalizePrefs(prefs)
  var extra = meta && typeof meta === "object" && !Array.isArray(meta) ? meta : {}
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
  if (extra.studioButtonPlaced) out.studioButtonPlaced = true
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
  if (draft) {
    out.draft = skinToJson(draft)
    var mainHash = sanitizeMd5(extra.draftBaseHash)
    if (mainHash) out.draftBaseHash = mainHash
  }
  var mDrafts = {}
  var anyDraft = false
  for (var dScreen in (monitorDrafts || {})) {
    var dName = sanitizeScreenName(dScreen)
    var dSkin = monitorDrafts[dScreen]
    if (!dName || !dSkin || typeof dSkin !== "object") continue
    mDrafts[dName] = skinToJson(dSkin)
    anyDraft = true
  }
  if (anyDraft) {
    out.monitorDrafts = mDrafts
    var rawHashes = extra.monitorDraftBaseHashes && typeof extra.monitorDraftBaseHashes === "object" && !Array.isArray(extra.monitorDraftBaseHashes)
      ? extra.monitorDraftBaseHashes : null
    if (rawHashes) {
      var mHashes = {}
      var anyHash = false
      for (var hScreen in mDrafts) {
        if (!hasOwn(mDrafts, hScreen)) continue
        var hVal = sanitizeMd5(rawHashes[hScreen])
        if (hVal) {
          mHashes[hScreen] = hVal
          anyHash = true
        }
      }
      if (anyHash) out.monitorDraftBaseHashes = mHashes
    }
  }
  return out
}

function parseDraftObject(rawDraft, fallbackId, lookup) {
  if (!rawDraft || typeof rawDraft !== "object" || Array.isArray(rawDraft)) return null
  var base = null
  if (rawDraft.preset !== undefined && typeof lookup === "function") base = lookup(String(rawDraft.preset))
  var merged = base ? copySkin(base) : {}
  for (var k in rawDraft) {
    if (hasOwn(rawDraft, k) && !isUnsafeKey(k)) merged[k] = rawDraft[k]
  }
  return normalizeSkin(merged, fallbackId, "custom")
}

function stateFromJson(obj, lookup) {
  var o = obj && typeof obj === "object" && !Array.isArray(obj) ? obj : {}
  var state = {
    activeSkinId: o.skin !== undefined ? slugify(o.skin) : "floating",
    followTheme: parseBool(o.followTheme, true),
    standard: parseBool(o.standard, false),
    studioButtonPlaced: parseBool(o.studioButtonPlaced, false),
    prefs: normalizePrefs(o),
    monitors: {},
    draft: null,
    draftBaseHash: "",
    monitorDrafts: {},
    monitorDraftBaseHashes: {}
  }
  var mons = o.monitors && typeof o.monitors === "object" && !Array.isArray(o.monitors) ? o.monitors : {}
  for (var screen in mons) {
    var name = sanitizeScreenName(screen)
    var id = String(mons[screen] || "").trim()
    if (!name || !id) continue
    state.monitors[name] = id === "theme" ? "theme" : slugify(id)
  }
  state.draft = parseDraftObject(o.draft, state.activeSkinId, lookup)
  if (state.draft) state.draftBaseHash = sanitizeMd5(o.draftBaseHash)
  var mDrafts = o.monitorDrafts && typeof o.monitorDrafts === "object" && !Array.isArray(o.monitorDrafts) ? o.monitorDrafts : {}
  var mHashes = o.monitorDraftBaseHashes && typeof o.monitorDraftBaseHashes === "object" && !Array.isArray(o.monitorDraftBaseHashes) ? o.monitorDraftBaseHashes : {}
  for (var dScreen in mDrafts) {
    var dName = sanitizeScreenName(dScreen)
    if (!dName) continue
    var fallback = state.monitors[dName] || state.activeSkinId
    var parsedDraft = parseDraftObject(mDrafts[dScreen], fallback, lookup)
    if (parsedDraft) {
      state.monitorDrafts[dName] = parsedDraft
      var dh = sanitizeMd5(mHashes[dScreen])
      if (dh) state.monitorDraftBaseHashes[dName] = dh
    }
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

// Strict semver parser and remote manifest version validator for explicit
// user-initiated Barcraft update checks.
function parseSemver(raw) {
  var m = String(raw || "").trim().match(/^v?(\d{1,5})\.(\d{1,5})\.(\d{1,5})$/)
  if (!m) return null
  return [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)]
}

function compareSemver(a, b) {
  var pa = parseSemver(a)
  var pb = parseSemver(b)
  if (!pa || !pb) return null
  for (var i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] > pb[i] ? 1 : -1
  }
  return 0
}

function parseRemoteManifestVersion(text, expectedId) {
  var raw = String(text || "")
  if (!raw || raw.length > 16384) return ""
  var obj = null
  try { obj = JSON.parse(raw) } catch (e) { return "" }
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return ""
  var wantId = expectedId || "thepixelgardener.barcraft"
  if (String(obj.id || "") !== wantId) return ""
  var parsed = parseSemver(obj.version)
  if (!parsed) return ""
  return parsed[0] + "." + parsed[1] + "." + parsed[2]
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeColorRef: normalizeColorRef,
    normalizeSkin: normalizeSkin,
    builtinSkins: builtinSkins,
    defaultSkin: defaultSkin,
    standardSkin: standardSkin,
    parseToml: parseToml,
    inspectToml: inspectToml,
    parseTomlSections: parseTomlSections,
    parseSkinLibrary: parseSkinLibrary,
    parseSkinLibraryDetailed: parseSkinLibraryDetailed,
    classifySkinWatchEvent: classifySkinWatchEvent,
    copySkin: copySkin,
    serializeToml: serializeToml,
    parseFromShellValues: parseFromShellValues,
    inspectShellValues: inspectShellValues,
    RESERVED_SKIN_IDS: RESERVED_SKIN_IDS,
    SKIN_FORMAT_VERSION: SKIN_FORMAT_VERSION,
    sanitizeMd5: sanitizeMd5,
    isReservedSkinId: isReservedSkinId,
    WRITE_FILE_SCRIPT: WRITE_FILE_SCRIPT,
    REMOVE_SKIN_FILES_SCRIPT: REMOVE_SKIN_FILES_SCRIPT,
    REMOVE_IF_UNCHANGED_SCRIPT: REMOVE_IF_UNCHANGED_SCRIPT,
    READ_FILE_SCRIPT: READ_FILE_SCRIPT,
    MAX_SCANNED_SKINS: MAX_SCANNED_SKINS,
    SCAN_SKINS_SCRIPT: SCAN_SKINS_SCRIPT,
    pinnedScanSlugs: pinnedScanSlugs,
    parseSemver: parseSemver,
    compareSemver: compareSemver,
    parseRemoteManifestVersion: parseRemoteManifestVersion,
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
    updateHookScript: updateHookScript,
    legacyUpdateHookScripts: legacyUpdateHookScripts,
    resolveSaveTarget: resolveSaveTarget,
    HOOK_OWNED_MARKER: HOOK_OWNED_MARKER
  }
}

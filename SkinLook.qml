import QtQuick
import qs.Commons
import qs.Commons as Commons
import "SkinParser.js" as SkinParser

// What a skin looks like right now: its geometry, and its colors resolved
// against the live theme (theme.<key> references included). One per bar
// surface, so each monitor can wear its own skin, plus one per thumbnail.
QtObject {
  id: look

  property var skin: null
  // key -> "#rrggbb" from the active theme's colors.toml.
  property var paletteMap: ({})
  // Omarchy's bar background is "glassy" (Hyprland blurs behind the bar).
  property bool barGlassy: false
  // A surface that shares the main skin's ink (the widgets draw with one
  // foreground for every monitor) sets this and passes it in.
  property bool useSharedForeground: false
  property color sharedForeground: Commons.Color.bar.text

  readonly property var s: skin || SkinParser.defaultSkin()

  function num(v, fallback) {
    if (v === undefined || v === null || v === "") return fallback
    var n = Number(v)
    return isFinite(n) ? n : fallback
  }

  function resolveRef(ref) {
    var r = String(ref || "")
    if (r === "") return ""
    if (r.charAt(0) === "#") return r
    if (r.indexOf("theme.") !== 0) return ""
    var key = r.slice(6)
    var hex = paletteMap ? paletteMap[key] : undefined
    if (hex) return hex
    if (key === "accent") return String(Commons.Color.accent)
    if (key === "foreground") return String(Commons.Color.foreground)
    if (key === "background") return String(Commons.Color.background)
    return ""
  }

  readonly property string mode: s.mode || "floating"
  readonly property string art: s.art || "none"
  readonly property bool hasArt: art !== "" && art !== "none"
  readonly property bool themeTint: !!s.themeTint
  readonly property string bezel: s.bezel || "none"
  readonly property real bezelStrength: num(s.bezelStrength, 0.75)
  readonly property real contrast: num(s.contrast, 1.0)
  readonly property real surfaceTone: num(s.surfaceTone, contrast)
  readonly property string customBackground: s.customBackground || ""
  readonly property string customForeground: s.customForeground || ""
  readonly property string customAccent: s.customAccent || ""
  readonly property string gradientTo: s.gradientTo || ""
  readonly property int skinHeight: num(s.height, 30)
  readonly property int edgeMargin: mode === "edge" ? 0 : num(s.edgeMargin, 6)
  readonly property int sideMargin: mode === "edge" ? 0 : num(s.sideMargin, 10)
  readonly property int sectionGap: num(s.sectionGap, 8)
  readonly property int innerPadding: num(s.innerPadding, 10)
  readonly property int radius: mode === "edge" ? 0 : num(s.radius, 10)
  readonly property real iconScale: num(s.iconScale, 1.0)
  readonly property real backgroundAlpha: num(s.backgroundAlpha, 0.92)
  readonly property string fill: s.fill || "solid"
  readonly property bool gradientActive: fill === "gradient"
  readonly property bool blur: !!s.blur
  readonly property string borderRole: s.border || "subtle"
  readonly property real borderAlpha: num(s.borderAlpha, 0.22)
  readonly property int borderWidth: num(s.borderWidth, 1)
  readonly property bool shadow: !!s.shadow
  readonly property real shadowStrength: num(s.shadowStrength, 0.5)
  readonly property string widgetStyle: s.widgetStyle || "plain"
  readonly property string visibilityMode: s.visibility || "always"
  readonly property bool autoHide: visibilityMode === "autohide"
  readonly property int hoverEdgePx: num(s.hoverEdgePx, 4)
  readonly property bool accentHairline: s.accentHairline !== false

  readonly property string customBackgroundHex: resolveRef(customBackground)
  readonly property string customForegroundHex: resolveRef(customForeground)
  readonly property string customAccentHex: resolveRef(customAccent)
  readonly property string gradientToHex: resolveRef(gradientTo)

  readonly property color resolvedAccent: customAccentHex !== "" ? Qt.color(customAccentHex) : Commons.Color.accent

  // Omarchy's Glassy bar keeps its see-through look when the skin itself
  // doesn't ask for blur. A skin that does stays opaque enough for
  // Hyprland's ignore_alpha (0.3) to still blur behind it.
  readonly property real effectiveAlpha: {
    var a = Math.max(0, Math.min(1, backgroundAlpha))
    if (barGlassy && !blur) return Math.min(a, 0.35)
    if (barGlassy && blur) return Math.max(a, 0.32)
    return a
  }

  // <1.0 softens toward the middle, >1.0 deepens toward black or white.
  function adjustColorContrast(baseColor, contrastVal, isForeground) {
    var delta = contrastVal - 1.0
    if (Math.abs(delta) < 0.01) return baseColor
    var lum = 0.2126 * baseColor.r + 0.7152 * baseColor.g + 0.0722 * baseColor.b
    var target = isForeground ? (lum >= 0.45 ? 1.0 : 0.0) : (lum < 0.5 ? 0.0 : 1.0)
    if (delta > 0) {
      var t = Math.min(0.65, delta * (isForeground ? 0.95 : 0.85))
      return Qt.rgba(baseColor.r + (target - baseColor.r) * t,
        baseColor.g + (target - baseColor.g) * t,
        baseColor.b + (target - baseColor.b) * t, baseColor.a)
    }
    var soften = Math.min(0.55, -delta * (isForeground ? 0.75 : 0.65))
    var mid = isForeground ? 0.48 : (lum < 0.5 ? 0.36 : 0.64)
    return Qt.rgba(baseColor.r + (mid - baseColor.r) * soften,
      baseColor.g + (mid - baseColor.g) * soften,
      baseColor.b + (mid - baseColor.b) * soften, baseColor.a)
  }

  function srgbChannel(c) {
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  }

  function relativeLuminance(col) {
    return 0.2126 * srgbChannel(col.r) + 0.7152 * srgbChannel(col.g) + 0.0722 * srgbChannel(col.b)
  }

  function contrastRatio(c1, c2) {
    var l1 = relativeLuminance(c1)
    var l2 = relativeLuminance(c2)
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)
  }

  function opaque(c) {
    return Qt.rgba(c.r, c.g, c.b, 1)
  }

  readonly property color surfaceColor: {
    var raw = customBackgroundHex !== "" ? Qt.color(customBackgroundHex) : Commons.Color.bar.background
    var adj = adjustColorContrast(raw, surfaceTone, false)
    return Qt.rgba(adj.r, adj.g, adj.b, effectiveAlpha)
  }

  // The far end of a gradient fill: the chosen color, or the accent.
  readonly property color gradientColor: {
    var raw = gradientToHex !== "" ? Qt.color(gradientToHex) : resolvedAccent
    var adj = adjustColorContrast(raw, surfaceTone, false)
    return Qt.rgba(adj.r, adj.g, adj.b, effectiveAlpha)
  }

  // Manual icon/text color if set. Otherwise the theme's bar text, flipped to
  // a crisp dark or light ink when a custom surface or gradient leaves it
  // under WCAG 4.5:1 at either end, then tuned by the Text contrast slider.
  readonly property color ownForeground: {
    if (customForegroundHex !== "") return adjustColorContrast(Qt.color(customForegroundHex), contrast, true)
    var baseFg = Commons.Color.bar.text
    if (!hasArt && (customBackgroundHex !== "" || gradientActive)) {
      var surfaces = [opaque(surfaceColor)]
      if (gradientActive) surfaces.push(opaque(gradientColor))
      var worst = 99
      for (var i = 0; i < surfaces.length; i++) worst = Math.min(worst, contrastRatio(surfaces[i], baseFg))
      if (worst < 4.5) {
        var dark = Qt.color("#111318")
        var light = Qt.color("#f2f5fa")
        var darkWorst = 99
        var lightWorst = 99
        for (var j = 0; j < surfaces.length; j++) {
          darkWorst = Math.min(darkWorst, contrastRatio(surfaces[j], dark))
          lightWorst = Math.min(lightWorst, contrastRatio(surfaces[j], light))
        }
        baseFg = darkWorst >= lightWorst ? dark : light
      }
    }
    return adjustColorContrast(baseFg, contrast, true)
  }

  readonly property color effectiveForeground: useSharedForeground ? sharedForeground : ownForeground

  readonly property var surfaceBorderSpec: {
    if (borderWidth <= 0 || borderRole === "none") return Border.none()
    var effAlpha = Math.max(0, Math.min(1, borderAlpha * Math.pow(contrast, 1.35)))
    if (borderRole === "hyprland") {
      var raw = Border.resolveValueRef("hyprland.active-border")
      var grad = Border.resolvedGradient(raw, resolvedAccent, effAlpha)
      return {
        color: grad.colors.length > 0 ? grad.colors[0] : Qt.rgba(resolvedAccent.r, resolvedAccent.g, resolvedAccent.b, effAlpha),
        widths: mode === "edge"
          ? { top: 0, right: 0, bottom: borderWidth, left: 0 }
          : { top: borderWidth, right: borderWidth, bottom: borderWidth, left: borderWidth },
        gradient: grad
      }
    }
    var c = borderRole === "accent" ? resolvedAccent : effectiveForeground
    var col = Qt.rgba(c.r, c.g, c.b, effAlpha)
    if (mode === "edge") {
      return {
        color: col,
        widths: { top: 0, right: 0, bottom: borderWidth, left: 0 },
        gradient: { colors: [], angle: 0, enabled: false }
      }
    }
    return Border.flat(col, borderWidth)
  }

  // The flat border color, for small previews that draw a plain Rectangle.
  readonly property color borderPreviewColor: {
    if (borderWidth <= 0 || borderRole === "none") return "transparent"
    var c = borderRole === "subtle" ? effectiveForeground : resolvedAccent
    return Qt.rgba(c.r, c.g, c.b, Math.max(0.25, Math.min(1, borderAlpha * Math.pow(contrast, 1.35))))
  }
}

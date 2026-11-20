import QtQuick
import qs.Commons
import qs.Commons as Commons

// Art renderer for crafted bar skins ("matrix", "runeforge"). Still artwork:
// painted once per resize/color change, zero per-frame redraws, keeping strong
// contrast behind every hosted bar widget.
Item {
  id: root

  required property string art
  property bool themeTint: false
  property string customBackground: ""
  property string customAccent: ""
  property real contrast: 1.0
  property bool vertical: false
  property real cornerRadius: Style.space(10)

  readonly property int leftContentInset: !vertical && (art === "runeforge" || art === "matrix") ? Style.space(12) : 0
  readonly property int rightContentInset: !vertical && (art === "runeforge" || art === "matrix") ? Style.space(12) : 0

  readonly property bool useTintedPalette: themeTint || customBackground !== "" || customAccent !== ""
  readonly property color bg: customBackground !== "" ? Qt.color(customBackground) : Commons.Color.bar.background
  readonly property color fg: Commons.Color.bar.text
  readonly property color acc: customAccent !== "" ? Qt.color(customAccent) : Commons.Color.accent

  visible: art !== "" && art !== "none"

  // =========================================================================
  // 1. MATRIX — Phosphor terminal HUD: deep CRT black, subtle glyph rain,
  //    fine scanlines, and razor-sharp phosphor corner targeting brackets.
  // =========================================================================
  Canvas {
    id: matrixCanvas
    visible: root.art === "matrix"
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    readonly property color phos: root.useTintedPalette ? root.acc : "#00ff66"
    readonly property color crtBg: root.useTintedPalette ? Qt.darker(root.bg, 2.2) : "#050b07"
    readonly property color crtGlow: root.useTintedPalette ? root.bg : "#0a1d11"

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    Connections {
      target: root
      function onThemeTintChanged() { matrixCanvas.requestPaint() }
      function onCustomBackgroundChanged() { matrixCanvas.requestPaint() }
      function onCustomAccentChanged() { matrixCanvas.requestPaint() }
      function onContrastChanged() { matrixCanvas.requestPaint() }
      function onCornerRadiusChanged() { matrixCanvas.requestPaint() }
      function onVerticalChanged() { matrixCanvas.requestPaint() }
    }

    Connections {
      target: Commons.Color
      function onBackgroundChanged() { if (matrixCanvas.visible) matrixCanvas.requestPaint() }
      function onAccentChanged() { if (matrixCanvas.visible) matrixCanvas.requestPaint() }
    }

    function rgba(c, a) {
      return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)).toFixed(3) + ")"
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!visible || width < 4 || height < 4) return

      var w = width
      var h = height
      var r = Math.max(0, Math.min(2, root.cornerRadius))
      var c = matrixCanvas.phos
      var punch = Math.max(0.55, Math.min(1.45, root.contrast))

      // Rounded-square clip path
      ctx.save()
      ctx.beginPath()
      ctx.moveTo(r, 0); ctx.lineTo(w - r, 0)
      if (r > 0) ctx.arcTo(w, 0, w, r, r)
      ctx.lineTo(w, h - r)
      if (r > 0) ctx.arcTo(w, h, w - r, h, r)
      ctx.lineTo(r, h)
      if (r > 0) ctx.arcTo(0, h, 0, h - r, r)
      ctx.lineTo(0, r)
      if (r > 0) ctx.arcTo(0, 0, r, 0, r)
      ctx.closePath()
      ctx.clip()

      // Deep CRT phosphor backdrop with subtle center luminescence
      var bgGrad = ctx.createLinearGradient(0, 0, 0, h)
      bgGrad.addColorStop(0.0, rgba(matrixCanvas.crtGlow, 0.97))
      bgGrad.addColorStop(0.5, rgba(matrixCanvas.crtBg, 0.98))
      bgGrad.addColorStop(1.0, rgba(Qt.darker(matrixCanvas.crtBg, 1.3), 0.99))
      ctx.fillStyle = bgGrad
      ctx.fillRect(0, 0, w, h)

      // Subtle atmospheric digital-rain glyph matrix (deterministic hash, zero motion)
      var glyphs = "01アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワ0123456789ABCDEF"
      var compact = h < 20
      var colStep = compact ? 7 : Math.max(10, Math.round(h * 0.38))
      var rowStep = compact ? 5 : Math.max(7, Math.round(h * 0.27))
      var fontSize = compact ? 5 : Math.max(7, Math.round(rowStep * 0.9))
      ctx.font = fontSize + "px monospace"
      ctx.textBaseline = "top"

      var cols = Math.floor(w / colStep)
      var rows = Math.max(1, Math.ceil(h / rowStep))
      for (var col = 0; col < cols; col++) {
        // Deterministic pseudo-random column density & head row
        var seed = (col * 2654435761) >>> 0
        if ((seed % 5) === 0) continue // breathing gaps between rain streams
        var headRow = seed % (rows + 2)
        for (var row = 0; row < rows; row++) {
          var dist = headRow - row
          if (dist < 0) continue
          var cellHash = ((seed ^ (row * 2246822519)) >>> 0)
          var ch = glyphs.charAt(cellHash % glyphs.length)
          var isHead = (dist === 0)
          var alpha = isHead ? (0.24 * punch) : (Math.max(0.03, (0.14 - dist * 0.03)) * punch)
          // Keep widget areas calm while letting subtle phosphor depth show through
          ctx.fillStyle = isHead ? rgba(Qt.lighter(c, 1.45), Math.min(0.32, alpha)) : rgba(c, Math.min(0.20, alpha))
          ctx.fillText(ch, col * colStep + 2, row * rowStep)
        }
      }

      // Fine horizontal CRT scanlines
      ctx.fillStyle = "rgba(0,0,0,0.22)"
      for (var sy = 1; sy < h; sy += 2) {
        ctx.fillRect(0, sy, w, 1)
      }

      // Top & bottom phosphor bloom wash
      var topBloom = ctx.createLinearGradient(0, 0, 0, Math.max(4, h * 0.35))
      topBloom.addColorStop(0.0, rgba(c, Math.min(0.22, 0.14 * punch)))
      topBloom.addColorStop(1.0, rgba(c, 0))
      ctx.fillStyle = topBloom
      ctx.fillRect(0, 0, w, Math.max(4, h * 0.35))

      var botBloom = ctx.createLinearGradient(0, h - Math.max(4, h * 0.3), 0, h)
      botBloom.addColorStop(0.0, rgba(c, 0))
      botBloom.addColorStop(1.0, rgba(c, Math.min(0.18, 0.11 * punch)))
      ctx.fillStyle = botBloom
      ctx.fillRect(0, h - Math.max(4, h * 0.3), w, Math.max(4, h * 0.3))

      // Subtle bus calibration ticks along bottom edge (full bar only)
      if (!compact && w > 180) {
        ctx.fillStyle = rgba(c, Math.min(0.45, 0.28 * punch))
        var tickStep = 24
        for (var tx = 18; tx < w - 18; tx += tickStep) {
          var tall = ((tx / tickStep) % 4 === 0)
          ctx.fillRect(tx, h - (tall ? 4 : 2), 1, tall ? 3 : 1)
        }
      }

      ctx.restore()

      // Crisp 1px outer phosphor trace
      ctx.strokeStyle = rgba(c, Math.min(0.65, 0.42 * punch))
      ctx.lineWidth = 1
      ctx.strokeRect(0.5, 0.5, w - 1, h - 1)

      // Razor-sharp bright corner targeting brackets (┌ ┐ └ ┘)
      var arm = compact ? Math.min(5, Math.floor(h * 0.35)) : Math.min(10, Math.floor(h * 0.36))
      ctx.strokeStyle = rgba(Qt.lighter(c, 1.3), Math.min(1.0, 0.92 * punch))
      ctx.lineWidth = compact ? 1 : 1.5
      ctx.beginPath()
      // Top-left
      ctx.moveTo(0.75, arm); ctx.lineTo(0.75, 0.75); ctx.lineTo(arm, 0.75)
      // Top-right
      ctx.moveTo(w - arm, 0.75); ctx.lineTo(w - 0.75, 0.75); ctx.lineTo(w - 0.75, arm)
      // Bottom-left
      ctx.moveTo(0.75, h - arm); ctx.lineTo(0.75, h - 0.75); ctx.lineTo(arm, h - 0.75)
      // Bottom-right
      ctx.moveTo(w - arm, h - 0.75); ctx.lineTo(w - 0.75, h - 0.75); ctx.lineTo(w - 0.75, h - arm)
      ctx.stroke()
    }
  }

  // =========================================================================
  // 2. RUNEFORGE — Chamfered obsidian basalt & hairline etched antique brass.
  //    Architectural dark-fantasy craft: fine 1px engraved bevels, octagonal
  //    cut corners, subtle brushed metal depth, and delicate end-cap sigils.
  // =========================================================================
  Canvas {
    id: runeCanvas
    visible: root.art === "runeforge"
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    readonly property color brassBright: root.useTintedPalette ? Qt.lighter(root.acc, 1.25) : "#c8ad72"
    readonly property color brassMuted: root.useTintedPalette ? Qt.darker(root.acc, 1.25) : "#7c653a"
    readonly property color brassDark: root.useTintedPalette ? Qt.darker(root.acc, 2.4) : "#3a2e1a"
    readonly property color slateTop: root.useTintedPalette ? Qt.lighter(root.bg, 1.12) : "#1c1a1d"
    readonly property color slateMid: root.useTintedPalette ? root.bg : "#121114"
    readonly property color slateBot: root.useTintedPalette ? Qt.darker(root.bg, 1.35) : "#0a090b"
    readonly property color ember: root.useTintedPalette ? root.acc : "#d9a648"

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    Connections {
      target: root
      function onThemeTintChanged() { runeCanvas.requestPaint() }
      function onCustomBackgroundChanged() { runeCanvas.requestPaint() }
      function onCustomAccentChanged() { runeCanvas.requestPaint() }
      function onContrastChanged() { runeCanvas.requestPaint() }
      function onVerticalChanged() { runeCanvas.requestPaint() }
    }

    Connections {
      target: Commons.Color
      function onBackgroundChanged() { if (runeCanvas.visible) runeCanvas.requestPaint() }
      function onAccentChanged() { if (runeCanvas.visible) runeCanvas.requestPaint() }
    }

    function rgba(c, a) {
      return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)).toFixed(3) + ")"
    }

    function chamferPath(ctx, x, y, w, h, cut) {
      var c = Math.max(0, Math.min(cut, w / 4, h / 2.2))
      ctx.beginPath()
      ctx.moveTo(x + c, y)
      ctx.lineTo(x + w - c, y)
      ctx.lineTo(x + w, y + c)
      ctx.lineTo(x + w, y + h - c)
      ctx.lineTo(x + w - c, y + h)
      ctx.lineTo(x + c, y + h)
      ctx.lineTo(x, y + h - c)
      ctx.lineTo(x, y + c)
      ctx.closePath()
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!visible || width < 6 || height < 6) return

      var w = width
      var h = height
      var compact = h < 20
      var cut = compact ? 3 : Math.min(7, Math.round(h * 0.22))
      var punch = Math.max(0.6, Math.min(1.4, root.contrast))

      // Chamfered obsidian slate fill
      ctx.save()
      chamferPath(ctx, 0.5, 0.5, w - 1, h - 1, cut)
      ctx.clip()

      var bodyGrad = ctx.createLinearGradient(0, 0, 0, h)
      bodyGrad.addColorStop(0.0, String(runeCanvas.slateTop))
      bodyGrad.addColorStop(0.45, String(runeCanvas.slateMid))
      bodyGrad.addColorStop(1.0, String(runeCanvas.slateBot))
      ctx.fillStyle = bodyGrad
      ctx.fillRect(0, 0, w, h)

      // Subtle forged vertical vignette (warmer center depth, darker edges)
      var vig = ctx.createLinearGradient(0, 0, w, 0)
      vig.addColorStop(0.0, "rgba(0,0,0,0.34)")
      vig.addColorStop(0.18, "rgba(0,0,0,0)")
      vig.addColorStop(0.82, "rgba(0,0,0,0)")
      vig.addColorStop(1.0, "rgba(0,0,0,0.34)")
      ctx.fillStyle = vig
      ctx.fillRect(0, 0, w, h)

      // Fine forged top specular lip
      ctx.fillStyle = rgba(runeCanvas.brassBright, Math.min(0.28, 0.16 * punch))
      ctx.fillRect(cut, 1, w - cut * 2, 1)

      // Subtle engraved interior hairline frame (3px inset)
      if (!compact) {
        chamferPath(ctx, 3.5, 3.5, w - 7, h - 7, Math.max(1, cut - 2))
        ctx.strokeStyle = rgba(runeCanvas.brassBright, Math.min(0.32, 0.18 * punch))
        ctx.lineWidth = 1
        ctx.stroke()
      }

      // Delicate etched diamond sigil clasps at left & right ends
      if (!compact && w > 120) {
        var cy = h / 2
        var dr = Math.min(3.5, h * 0.11)
        var centers = [cut + 5, w - cut - 5]
        for (var i = 0; i < centers.length; i++) {
          var cx = centers[i]
          ctx.beginPath()
          ctx.moveTo(cx, cy - dr)
          ctx.lineTo(cx + dr, cy)
          ctx.lineTo(cx, cy + dr)
          ctx.lineTo(cx - dr, cy)
          ctx.closePath()
          ctx.fillStyle = rgba(runeCanvas.ember, Math.min(0.85, 0.55 * punch))
          ctx.fill()
          ctx.strokeStyle = rgba(runeCanvas.brassBright, Math.min(0.95, 0.72 * punch))
          ctx.lineWidth = 1
          ctx.stroke()
        }
      }
      ctx.restore()

      // Outer hairline antique-brass metallic bevel
      var rimGrad = ctx.createLinearGradient(0, 0, 0, h)
      rimGrad.addColorStop(0.0, rgba(runeCanvas.brassBright, Math.min(0.95, 0.72 * punch)))
      rimGrad.addColorStop(0.5, rgba(runeCanvas.brassMuted, Math.min(0.85, 0.60 * punch)))
      rimGrad.addColorStop(1.0, rgba(runeCanvas.brassDark, Math.min(0.95, 0.80 * punch)))
      chamferPath(ctx, 0.5, 0.5, w - 1, h - 1, cut)
      ctx.strokeStyle = rimGrad
      ctx.lineWidth = 1.25
      ctx.stroke()

      // Crisp bright brass corner facets along the 45-degree chamfers
      ctx.strokeStyle = rgba(runeCanvas.brassBright, Math.min(1.0, 0.85 * punch))
      ctx.lineWidth = 1.25
      ctx.beginPath()
      ctx.moveTo(0.5, cut + 0.5); ctx.lineTo(cut + 0.5, 0.5)
      ctx.moveTo(w - cut - 0.5, 0.5); ctx.lineTo(w - 0.5, cut + 0.5)
      ctx.stroke()
    }
  }
}

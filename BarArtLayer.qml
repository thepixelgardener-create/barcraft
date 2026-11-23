import QtQuick
import qs.Commons
import qs.Commons as Commons

// Art renderer for crafted bar skins ("matrix", "runeforge", "amiga").
// Still artwork: painted once per resize/color change, zero per-frame redraws,
// keeping strong contrast behind every hosted bar widget.
Item {
  id: root

  required property string art
  property bool themeTint: false
  property string customBackground: ""
  property string customAccent: ""
  property real contrast: 1.0
  property bool vertical: false
  property real cornerRadius: Style.space(10)

  readonly property int leftContentInset: !vertical
    ? (art === "amiga" ? Style.space(26) : (art === "runeforge" || art === "matrix" ? Style.space(20) : 0))
    : 0
  readonly property int rightContentInset: !vertical
    ? (art === "amiga" ? Style.space(26) : (art === "runeforge" || art === "matrix" ? Style.space(20) : 0))
    : 0

  readonly property bool useTintedPalette: themeTint || customBackground !== "" || customAccent !== ""
  readonly property color bg: customBackground !== "" ? Qt.color(customBackground) : Commons.Color.bar.background
  readonly property color fg: Commons.Color.bar.text
  readonly property color acc: customAccent !== "" ? Qt.color(customAccent) : Commons.Color.accent

  visible: art !== "" && art !== "none"

  function rgba(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + Math.max(0, Math.min(1, a)).toFixed(3) + ")"
  }

  // =========================================================================
  // 1. MATRIX — Phosphor Construct Terminal: curved CRT vignette, aperture
  //    grille, multi-depth katakana/hex rain with glowing phosphor trails,
  //    PCB traces with nodes, signal telemetry pips, and bloom HUD brackets.
  // =========================================================================
  Canvas {
    id: matrixCanvas
    visible: root.art === "matrix"
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    readonly property color phos: root.useTintedPalette ? root.acc : "#00ff66"
    readonly property color phosHot: root.useTintedPalette ? Qt.lighter(root.acc, 1.55) : "#d6ffe6"
    readonly property color crtBg: root.useTintedPalette ? Qt.darker(root.bg, 2.3) : "#030a06"
    readonly property color crtGlow: root.useTintedPalette ? Qt.darker(root.bg, 1.35) : "#092013"

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

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!visible || width < 4 || height < 4) return

      var w = width
      var h = height
      var r = Math.max(0, Math.min(2, root.cornerRadius))
      var c = matrixCanvas.phos
      var hot = matrixCanvas.phosHot
      var punch = Math.max(0.55, Math.min(1.45, root.contrast))
      var compact = h < 20

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

      // Curved-CRT phosphor backdrop: luminous emerald-black core, dark edges
      var bgGrad = ctx.createLinearGradient(0, 0, 0, h)
      bgGrad.addColorStop(0.0, root.rgba(matrixCanvas.crtGlow, 0.98))
      bgGrad.addColorStop(0.42, root.rgba(matrixCanvas.crtBg, 0.99))
      bgGrad.addColorStop(1.0, root.rgba(Qt.darker(matrixCanvas.crtBg, 1.45), 0.99))
      ctx.fillStyle = bgGrad
      ctx.fillRect(0, 0, w, h)

      // Horizontal CRT tube curvature glow (subtle center & flank lift)
      var hGlow = ctx.createLinearGradient(0, 0, w, 0)
      hGlow.addColorStop(0.0, root.rgba(c, Math.min(0.18, 0.11 * punch)))
      hGlow.addColorStop(0.08, root.rgba(c, 0.02))
      hGlow.addColorStop(0.5, root.rgba(c, Math.min(0.11, 0.06 * punch)))
      hGlow.addColorStop(0.92, root.rgba(c, 0.02))
      hGlow.addColorStop(1.0, root.rgba(c, Math.min(0.18, 0.11 * punch)))
      ctx.fillStyle = hGlow
      ctx.fillRect(0, 0, w, h)

      // Multi-depth digital rain (far micro-plane + glowing mid/hero streams)
      var glyphs = "01アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワ0123456789ABCDEF"
      var colStep = compact ? 6 : Math.max(9, Math.round(h * 0.34))
      var rowStep = compact ? 4 : Math.max(6, Math.round(h * 0.25))
      var fontSize = compact ? 5 : Math.max(7, Math.round(rowStep * 0.92))
      ctx.textBaseline = "top"

      var cols = Math.floor(w / colStep)
      var rows = Math.max(1, Math.ceil(h / rowStep))

      // Subtle vertical phosphor rain trail beams behind bright hero columns
      for (var sc = 0; sc < cols; sc++) {
        var sSeed = (sc * 2654435761) >>> 0
        if ((sSeed % 7) !== 1) continue
        var sx = sc * colStep + 1
        var beam = ctx.createLinearGradient(0, 0, 0, h)
        beam.addColorStop(0.0, root.rgba(c, 0.0))
        beam.addColorStop(0.65, root.rgba(c, Math.min(0.16, 0.09 * punch)))
        beam.addColorStop(1.0, root.rgba(hot, Math.min(0.24, 0.14 * punch)))
        ctx.fillStyle = beam
        ctx.fillRect(sx, 0, Math.max(3, colStep - 3), h)
      }

      // Glyph layers
      ctx.font = fontSize + "px monospace"
      for (var col = 0; col < cols; col++) {
        var seed = (col * 2654435761) >>> 0
        if ((seed % 6) === 0) continue
        var isHeroCol = (seed % 7) === 1
        var headRow = seed % (rows + 2)
        // Slightly calmer in the middle so widgets stay crisp, brighter at edges
        var edgeFrac = Math.min(col, cols - 1 - col) / Math.max(1, cols * 0.15)
        var edgeBoost = edgeFrac < 1 ? (1.28 - 0.28 * edgeFrac) : 1.0
        for (var row = 0; row < rows; row++) {
          var dist = headRow - row
          if (dist < 0) continue
          var cellHash = ((seed ^ (row * 2246822519)) >>> 0)
          var ch = glyphs.charAt(cellHash % glyphs.length)
          var isHead = (dist === 0)
          var xPos = col * colStep + 2
          var yPos = row * rowStep
          if (isHead && isHeroCol && !compact) {
            // Soft phosphor bloom halo behind bright lead glyph
            ctx.fillStyle = root.rgba(c, Math.min(0.32, 0.20 * punch))
            ctx.fillRect(xPos - 1, yPos, fontSize, fontSize)
          }
          var baseAlpha = isHead
            ? ((isHeroCol ? 0.44 : 0.26) * punch * edgeBoost)
            : (Math.max(0.04, (isHeroCol ? 0.22 : 0.14) - dist * 0.032) * punch * edgeBoost)
          ctx.fillStyle = isHead
            ? root.rgba(hot, Math.min(0.58, baseAlpha))
            : root.rgba(c, Math.min(0.28, baseAlpha))
          ctx.fillText(ch, xPos, yPos)
        }
      }

      // Vertical CRT aperture-grille shadow mask + horizontal scanlines
      if (!compact) {
        ctx.fillStyle = "rgba(0,0,0,0.10)"
        for (var gx = 2; gx < w; gx += 3) ctx.fillRect(gx, 0, 1, h)
      }
      ctx.fillStyle = "rgba(0,0,0,0.26)"
      for (var sy = 1; sy < h; sy += 2) ctx.fillRect(0, sy, w, 1)

      // Top & bottom phosphor bloom wash
      var topBloom = ctx.createLinearGradient(0, 0, 0, Math.max(4, h * 0.34))
      topBloom.addColorStop(0.0, root.rgba(c, Math.min(0.26, 0.16 * punch)))
      topBloom.addColorStop(1.0, root.rgba(c, 0))
      ctx.fillStyle = topBloom
      ctx.fillRect(0, 0, w, Math.max(4, h * 0.34))

      var botBloom = ctx.createLinearGradient(0, h - Math.max(4, h * 0.3), 0, h)
      botBloom.addColorStop(0.0, root.rgba(c, 0))
      botBloom.addColorStop(1.0, root.rgba(c, Math.min(0.22, 0.14 * punch)))
      ctx.fillStyle = botBloom
      ctx.fillRect(0, h - Math.max(4, h * 0.3), w, Math.max(4, h * 0.3))

      // Hairline PCB signal rails & calibration ticks (full bar)
      if (!compact && w > 180) {
        ctx.fillStyle = root.rgba(c, Math.min(0.32, 0.20 * punch))
        ctx.fillRect(20, 2, w - 40, 1)
        ctx.fillRect(20, h - 3, w - 40, 1)

        var tickStep = 24
        for (var tx = 24; tx < w - 24; tx += tickStep) {
          var major = ((tx / tickStep) % 4 === 0)
          ctx.fillStyle = major
            ? root.rgba(hot, Math.min(0.62, 0.40 * punch))
            : root.rgba(c, Math.min(0.45, 0.28 * punch))
          ctx.fillRect(tx, h - (major ? 5 : 3), 1, major ? 4 : 2)
          if (major) {
            // Glowing PCB via node on upper rail
            ctx.fillRect(tx, 1, 2, 2)
          }
        }
      }

      // Left & right end-cap signal telemetry pips (safely inside content insets)
      if (!compact && w > 140) {
        var cy = Math.round(h / 2)
        var pipHeights = [3, 5, 7]
        for (var p = 0; p < 3; p++) {
          var ph = Math.min(h - 10, pipHeights[p])
          var alpha = (0.35 + p * 0.22) * punch
          ctx.fillStyle = root.rgba(p === 2 ? hot : c, Math.min(0.9, alpha))
          // Left telemetry bars
          ctx.fillRect(5 + p * 3, cy - Math.floor(ph / 2), 2, ph)
          // Right mirrored telemetry bars
          ctx.fillRect(w - 7 - p * 3, cy - Math.floor(ph / 2), 2, ph)
        }
      }

      ctx.restore()

      // Crisp 1px outer phosphor frame
      ctx.strokeStyle = root.rgba(c, Math.min(0.72, 0.48 * punch))
      ctx.lineWidth = 1
      ctx.strokeRect(0.5, 0.5, w - 1, h - 1)

      // Twin-layer neon HUD corner targeting brackets (bloom + razor core)
      var arm = compact ? Math.min(5, Math.floor(h * 0.38)) : Math.min(11, Math.floor(h * 0.38))
      function traceBrackets() {
        ctx.beginPath()
        ctx.moveTo(1, arm); ctx.lineTo(1, 1); ctx.lineTo(arm, 1)
        ctx.moveTo(w - arm, 1); ctx.lineTo(w - 1, 1); ctx.lineTo(w - 1, arm)
        ctx.moveTo(1, h - arm); ctx.lineTo(1, h - 1); ctx.lineTo(arm, h - 1)
        ctx.moveTo(w - arm, h - 1); ctx.lineTo(w - 1, h - 1); ctx.lineTo(w - 1, h - arm)
      }
      if (!compact) {
        ctx.strokeStyle = root.rgba(c, Math.min(0.40, 0.26 * punch))
        ctx.lineWidth = 3.5
        traceBrackets()
        ctx.stroke()
      }
      ctx.strokeStyle = root.rgba(hot, Math.min(1.0, 0.96 * punch))
      ctx.lineWidth = compact ? 1 : 1.5
      traceBrackets()
      ctx.stroke()
    }
  }

  // =========================================================================
  // 2. RUNEFORGE — Forged Obsidian, Hammered Antique Brass & Molten Runes.
  //    Architectural dark-fantasy craft: double-chamfered basalt slab with
  //    brushed iron sheen, forged rivets, keystone crest, molten ember glow,
  //    and etched geometric Elder Futhark rune medallions at the end-caps.
  // =========================================================================
  Canvas {
    id: runeCanvas
    visible: root.art === "runeforge"
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    readonly property color brassGleam: root.useTintedPalette ? Qt.lighter(root.acc, 1.48) : "#f0d999"
    readonly property color brassBright: root.useTintedPalette ? Qt.lighter(root.acc, 1.18) : "#caa55c"
    readonly property color brassMuted: root.useTintedPalette ? Qt.darker(root.acc, 1.3) : "#7a5e30"
    readonly property color brassDark: root.useTintedPalette ? Qt.darker(root.acc, 2.5) : "#2f2311"
    readonly property color slateTop: root.useTintedPalette ? Qt.lighter(root.bg, 1.16) : "#221f25"
    readonly property color slateMid: root.useTintedPalette ? root.bg : "#141218"
    readonly property color slateBot: root.useTintedPalette ? Qt.darker(root.bg, 1.45) : "#09080c"
    readonly property color emberCore: root.useTintedPalette ? Qt.lighter(root.acc, 1.35) : "#ffbe55"
    readonly property color emberGlow: root.useTintedPalette ? root.acc : "#d4641e"

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

    function drawRivet(ctx, cx, cy, punch) {
      ctx.beginPath()
      ctx.arc(cx, cy, 1.7, 0, Math.PI * 2)
      ctx.fillStyle = "rgba(0,0,0,0.75)"
      ctx.fill()

      ctx.beginPath()
      ctx.arc(cx, cy, 1.25, 0, Math.PI * 2)
      ctx.fillStyle = root.rgba(runeCanvas.brassMuted, Math.min(0.95, 0.85 * punch))
      ctx.fill()

      ctx.beginPath()
      ctx.arc(cx - 0.35, cy - 0.35, 0.55, 0, Math.PI * 2)
      ctx.fillStyle = root.rgba(runeCanvas.brassGleam, Math.min(1.0, 0.95 * punch))
      ctx.fill()
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!visible || width < 6 || height < 6) return

      var w = width
      var h = height
      var compact = h < 20
      var cut = compact ? 3 : Math.min(8, Math.round(h * 0.25))
      var punch = Math.max(0.6, Math.min(1.4, root.contrast))

      // Chamfered obsidian slate slab
      ctx.save()
      chamferPath(ctx, 0.5, 0.5, w - 1, h - 1, cut)
      ctx.clip()

      var bodyGrad = ctx.createLinearGradient(0, 0, 0, h)
      bodyGrad.addColorStop(0.0, String(runeCanvas.slateTop))
      bodyGrad.addColorStop(0.45, String(runeCanvas.slateMid))
      bodyGrad.addColorStop(1.0, String(runeCanvas.slateBot))
      ctx.fillStyle = bodyGrad
      ctx.fillRect(0, 0, w, h)

      // Subtle diagonal hammered-metal sheen bands across the basalt
      if (!compact) {
        var bands = [0.16, 0.50, 0.84]
        for (var b = 0; b < bands.length; b++) {
          var bx = w * bands[b]
          var bandGrad = ctx.createLinearGradient(bx - 36, 0, bx + 36, h)
          bandGrad.addColorStop(0.0, "rgba(255,255,255,0)")
          bandGrad.addColorStop(0.5, root.rgba(runeCanvas.brassGleam, Math.min(0.08, 0.045 * punch)))
          bandGrad.addColorStop(1.0, "rgba(255,255,255,0)")
          ctx.fillStyle = bandGrad
          ctx.fillRect(bx - 42, 0, 84, h)
        }
      }

      // Deep forged edge vignette
      var vig = ctx.createLinearGradient(0, 0, w, 0)
      vig.addColorStop(0.0, "rgba(0,0,0,0.42)")
      vig.addColorStop(0.14, "rgba(0,0,0,0)")
      vig.addColorStop(0.86, "rgba(0,0,0,0)")
      vig.addColorStop(1.0, "rgba(0,0,0,0.42)")
      ctx.fillStyle = vig
      ctx.fillRect(0, 0, w, h)

      // Warm molten forge underglow tucked along the bottom bevel
      var forgeGlow = ctx.createLinearGradient(0, h - Math.max(4, h * 0.28), 0, h)
      forgeGlow.addColorStop(0.0, root.rgba(runeCanvas.emberGlow, 0))
      forgeGlow.addColorStop(1.0, root.rgba(runeCanvas.emberGlow, Math.min(0.24, 0.15 * punch)))
      ctx.fillStyle = forgeGlow
      ctx.fillRect(0, h - Math.max(4, h * 0.28), w, Math.max(4, h * 0.28))

      // Forged top specular lip
      ctx.fillStyle = root.rgba(runeCanvas.brassGleam, Math.min(0.38, 0.24 * punch))
      ctx.fillRect(cut, 1, w - cut * 2, 1)

      // Recessed carved channel groove (dark shadow + etched gold hairline)
      if (!compact) {
        chamferPath(ctx, 2.5, 2.5, w - 5, h - 5, Math.max(1, cut - 1.5))
        ctx.strokeStyle = "rgba(0,0,0,0.72)"
        ctx.lineWidth = 1.25
        ctx.stroke()

        chamferPath(ctx, 4, 4, w - 8, h - 8, Math.max(1, cut - 2.5))
        ctx.strokeStyle = root.rgba(runeCanvas.brassBright, Math.min(0.42, 0.26 * punch))
        ctx.lineWidth = 1
        ctx.stroke()

        // Architectural dwarven fretwork notches along top & bottom rails
        if (w > 220) {
          ctx.fillStyle = root.rgba(runeCanvas.brassBright, Math.min(0.45, 0.28 * punch))
          for (var fx = cut + 28; fx < w - cut - 28; fx += 36) {
            ctx.fillRect(fx, 1, 5, 1)
            ctx.fillRect(fx + 2, 2, 1, 1)
            ctx.fillRect(fx, h - 2, 5, 1)
            ctx.fillRect(fx + 2, h - 3, 1, 1)
          }

          // Subtle top & bottom center keystone diamond crests
          var midX = Math.round(w / 2)
          ctx.fillStyle = root.rgba(runeCanvas.brassGleam, Math.min(0.85, 0.60 * punch))
          ctx.beginPath()
          ctx.moveTo(midX - 5, 1); ctx.lineTo(midX + 5, 1); ctx.lineTo(midX, 4.5); ctx.closePath()
          ctx.fill()
          ctx.beginPath()
          ctx.moveTo(midX - 5, h - 1); ctx.lineTo(midX + 5, h - 1); ctx.lineTo(midX, h - 4.5); ctx.closePath()
          ctx.fill()
        }

        // Four corner forged brass rivets
        if (w > 100 && h >= 24) {
          var rx = cut + 3.5
          drawRivet(ctx, rx, 6.5, punch)
          drawRivet(ctx, rx, h - 6.5, punch)
          drawRivet(ctx, w - rx, 6.5, punch)
          drawRivet(ctx, w - rx, h - 6.5, punch)
        }
      }

      // End-cap molten-ember rune medallions (safely inside content insets)
      if (!compact && w > 120) {
        var cy = h / 2
        var dr = Math.min(6.2, h * 0.21)
        var centers = [cut + 8, w - cut - 8]
        for (var i = 0; i < centers.length; i++) {
          var cx = centers[i]
          // Soft molten ember halo
          var halo = ctx.createRadialGradient(cx, cy, 0.5, cx, cy, dr * 1.9)
          halo.addColorStop(0.0, root.rgba(runeCanvas.emberGlow, Math.min(0.55, 0.36 * punch)))
          halo.addColorStop(1.0, root.rgba(runeCanvas.emberGlow, 0))
          ctx.fillStyle = halo
          ctx.fillRect(cx - dr * 2, cy - dr * 2, dr * 4, dr * 4)

          // Faceted obsidian & brass diamond clasp
          ctx.beginPath()
          ctx.moveTo(cx, cy - dr)
          ctx.lineTo(cx + dr, cy)
          ctx.lineTo(cx, cy + dr)
          ctx.lineTo(cx - dr, cy)
          ctx.closePath()
          ctx.fillStyle = root.rgba(runeCanvas.slateBot, 0.92)
          ctx.fill()
          ctx.strokeStyle = root.rgba(runeCanvas.brassGleam, Math.min(0.95, 0.80 * punch))
          ctx.lineWidth = 1.15
          ctx.stroke()

          // Glowing geometric Elder Futhark rune (Dagaz / Othala vector stroke)
          var rr = dr * 0.52
          ctx.strokeStyle = root.rgba(runeCanvas.emberCore, Math.min(1.0, 0.92 * punch))
          ctx.lineWidth = 1.15
          ctx.beginPath()
          if (i === 0) {
            // Left: Othala-inspired angular rune
            ctx.moveTo(cx - rr * 0.65, cy + rr)
            ctx.lineTo(cx + rr * 0.65, cy - rr * 0.2)
            ctx.lineTo(cx, cy - rr)
            ctx.lineTo(cx - rr * 0.65, cy - rr * 0.2)
            ctx.lineTo(cx + rr * 0.65, cy + rr)
          } else {
            // Right: Dagaz hourglass rune
            ctx.moveTo(cx - rr * 0.7, cy - rr * 0.75)
            ctx.lineTo(cx - rr * 0.7, cy + rr * 0.75)
            ctx.lineTo(cx + rr * 0.7, cy - rr * 0.75)
            ctx.lineTo(cx + rr * 0.7, cy + rr * 0.75)
            ctx.closePath()
          }
          ctx.stroke()
        }
      } else if (compact && w > 40) {
        // Thumbnail molten-gold end diamonds
        var tcy = h / 2
        ctx.fillStyle = root.rgba(runeCanvas.emberCore, 0.9)
        ctx.fillRect(cut + 2, tcy - 1, 2, 2)
        ctx.fillRect(w - cut - 4, tcy - 1, 2, 2)
      }

      ctx.restore()

      // Outer multi-stop metallic antique-brass bevel
      var rimGrad = ctx.createLinearGradient(0, 0, 0, h)
      rimGrad.addColorStop(0.0, root.rgba(runeCanvas.brassGleam, Math.min(1.0, 0.88 * punch)))
      rimGrad.addColorStop(0.35, root.rgba(runeCanvas.brassBright, Math.min(0.95, 0.75 * punch)))
      rimGrad.addColorStop(0.7, root.rgba(runeCanvas.brassMuted, Math.min(0.90, 0.65 * punch)))
      rimGrad.addColorStop(1.0, root.rgba(runeCanvas.brassDark, Math.min(0.98, 0.85 * punch)))
      chamferPath(ctx, 0.6, 0.6, w - 1.2, h - 1.2, cut)
      ctx.strokeStyle = rimGrad
      ctx.lineWidth = compact ? 1.1 : 1.5
      ctx.stroke()

      // Gleaming burnished brass corner facets on the 45° chamfers
      ctx.strokeStyle = root.rgba(runeCanvas.brassGleam, Math.min(1.0, 0.95 * punch))
      ctx.lineWidth = compact ? 1 : 1.75
      ctx.beginPath()
      ctx.moveTo(0.75, cut + 0.75); ctx.lineTo(cut + 0.75, 0.75)
      ctx.moveTo(w - cut - 0.75, 0.75); ctx.lineTo(w - 0.75, cut + 0.75)
      ctx.stroke()
    }
  }

  // =========================================================================
  // 3. AMIGA — Classic Amiga Workbench + Copper-Bar Craft: authentic deep
  //    Workbench Blue with OCS/ECS copper sheen, chiseled 2px white/black
  //    Intuition pixel bevels, Amiga Orange accent hairline, checkered Boing
  //    Ball gadget on the left, and Workbench depth gadget on the right.
  // =========================================================================
  Canvas {
    id: amigaCanvas
    visible: root.art === "amiga"
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    readonly property color wbBlueTop: root.useTintedPalette ? Qt.lighter(root.bg, 1.24) : "#1466bf"
    readonly property color wbBlueMid: root.useTintedPalette ? root.bg : "#0055aa"
    readonly property color wbBlueBot: root.useTintedPalette ? Qt.darker(root.bg, 1.45) : "#003773"
    readonly property color wbWhite: "#ffffff"
    readonly property color wbBlack: "#060910"
    readonly property color wbOrange: root.useTintedPalette ? root.acc : "#ff8800"
    readonly property color boingRed: root.useTintedPalette ? root.acc : "#e82222"

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    Connections {
      target: root
      function onThemeTintChanged() { amigaCanvas.requestPaint() }
      function onCustomBackgroundChanged() { amigaCanvas.requestPaint() }
      function onCustomAccentChanged() { amigaCanvas.requestPaint() }
      function onContrastChanged() { amigaCanvas.requestPaint() }
      function onVerticalChanged() { amigaCanvas.requestPaint() }
    }

    Connections {
      target: Commons.Color
      function onBackgroundChanged() { if (amigaCanvas.visible) amigaCanvas.requestPaint() }
      function onAccentChanged() { if (amigaCanvas.visible) amigaCanvas.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!visible || width < 6 || height < 6) return

      var w = width
      var h = height
      var compact = h < 20
      var punch = Math.max(0.65, Math.min(1.4, root.contrast))

      // Workbench Blue body with classic OCS/ECS copper-bar sheen band
      var copper = ctx.createLinearGradient(0, 0, 0, h)
      copper.addColorStop(0.0, String(amigaCanvas.wbBlueTop))
      copper.addColorStop(0.24, root.rgba(Qt.lighter(amigaCanvas.wbBlueTop, 1.18), 0.99))
      copper.addColorStop(0.45, String(amigaCanvas.wbBlueMid))
      copper.addColorStop(1.0, String(amigaCanvas.wbBlueBot))
      ctx.fillStyle = copper
      ctx.fillRect(0, 0, w, h)

      // Subtle CRT copper raster lines (clean and high-contrast)
      ctx.fillStyle = "rgba(0,0,0,0.09)"
      for (var ry = 2; ry < h - 2; ry += 2) ctx.fillRect(2, ry, w - 4, 1)

      // Classic Workbench titlebar double-pinstripe drag texture along outer flanks
      if (!compact && w > 220) {
        var stripeY1 = Math.round(h * 0.34)
        var stripeY2 = Math.round(h * 0.66)
        var flankW = Math.min(34, Math.floor(w * 0.04))
        var leftStart = h + 4
        var rightEnd = w - h - 4
        ctx.fillStyle = root.rgba(amigaCanvas.wbWhite, Math.min(0.22, 0.14 * punch))
        ctx.fillRect(leftStart, stripeY1, flankW, 1)
        ctx.fillRect(leftStart, stripeY2, flankW, 1)
        ctx.fillRect(rightEnd - flankW, stripeY1, flankW, 1)
        ctx.fillRect(rightEnd - flankW, stripeY2, flankW, 1)
      }

      // Signature Amiga Orange copper hairline tucked above the bottom pixel bevel
      var bev = compact ? 1 : 2
      ctx.fillStyle = root.rgba(amigaCanvas.wbOrange, Math.min(0.95, 0.85 * punch))
      ctx.fillRect(bev, h - bev - 1, w - bev * 2, 1)

      // Iconic Amiga Intuition chiseled 3D pixel bevels (crisp white top/left, hard black bottom/right)
      ctx.fillStyle = root.rgba(amigaCanvas.wbWhite, Math.min(0.95, 0.86 * punch))
      ctx.fillRect(0, 0, w, bev)
      ctx.fillRect(0, 0, bev, h)

      ctx.fillStyle = root.rgba(amigaCanvas.wbBlack, 0.88)
      ctx.fillRect(0, h - bev, w, bev)
      ctx.fillRect(w - bev, 0, bev, h)
      // Pixel-stepped Intuition bevel miters at top-right and bottom-left corners
      if (!compact) {
        ctx.fillStyle = root.rgba(amigaCanvas.wbWhite, 0.86)
        ctx.fillRect(w - 2, 0, 1, 1)
        ctx.fillRect(0, h - 2, 1, 1)
      }

      // Left end-cap: Checkered Boing Ball inside a chiseled Intuition gadget box
      if (!compact && w > 120) {
        var boxW = Math.min(28, h)
        // Vertical Workbench gadget separator (black shadow + white highlight)
        ctx.fillStyle = root.rgba(amigaCanvas.wbBlack, 0.78)
        ctx.fillRect(boxW, bev, 1, h - bev * 2)
        ctx.fillStyle = root.rgba(amigaCanvas.wbWhite, 0.72)
        ctx.fillRect(boxW + 1, bev, 1, h - bev * 2)

        // Subtle recessed gadget well
        ctx.fillStyle = "rgba(0,0,0,0.18)"
        ctx.fillRect(bev, bev, boxW - bev, h - bev * 2 - 1)

        // Iconic Red & White Checkered Boing Ball
        var bcx = Math.round((bev + boxW) / 2)
        var bcy = Math.round(h / 2)
        var br = Math.max(5, Math.min(8.5, Math.floor((h - 10) / 2)))

        // Grounded drop shadow
        ctx.beginPath()
        ctx.arc(bcx + 1.2, bcy + 1.2, br, 0, Math.PI * 2)
        ctx.fillStyle = "rgba(0,0,0,0.45)"
        ctx.fill()

        ctx.save()
        ctx.beginPath()
        ctx.arc(bcx, bcy, br, 0, Math.PI * 2)
        ctx.clip()

        // Base white sphere
        ctx.fillStyle = "#ffffff"
        ctx.fillRect(bcx - br, bcy - br, br * 2, br * 2)

        // Classic tilted Boing Ball checkerboard cells
        var step = Math.max(2.6, br * 0.56)
        ctx.translate(bcx, bcy)
        ctx.rotate(-0.22)
        ctx.fillStyle = String(amigaCanvas.boingRed)
        for (var gy = -3; gy <= 3; gy++) {
          for (var gx = -3; gx <= 3; gx++) {
            if (((gx + gy) & 1) === 0) {
              ctx.fillRect(gx * step - step * 0.5, gy * step - step * 0.5, step, step)
            }
          }
        }
        ctx.restore()

        // Spherical shading + specular highlight + crisp pixel rim
        var sphereShade = ctx.createRadialGradient(bcx - br * 0.32, bcy - br * 0.32, 0.5, bcx, bcy, br)
        sphereShade.addColorStop(0.0, "rgba(255,255,255,0.42)")
        sphereShade.addColorStop(0.55, "rgba(0,0,0,0)")
        sphereShade.addColorStop(1.0, "rgba(0,0,0,0.42)")
        ctx.beginPath()
        ctx.arc(bcx, bcy, br, 0, Math.PI * 2)
        ctx.fillStyle = sphereShade
        ctx.fill()
        ctx.strokeStyle = "rgba(0,0,0,0.65)"
        ctx.lineWidth = 0.85
        ctx.stroke()

        // Right end-cap: Iconic Amiga Workbench Front-to-Back Depth Gadget
        var rSep = w - boxW - 2
        ctx.fillStyle = root.rgba(amigaCanvas.wbBlack, 0.78)
        ctx.fillRect(rSep, bev, 1, h - bev * 2)
        ctx.fillStyle = root.rgba(amigaCanvas.wbWhite, 0.72)
        ctx.fillRect(rSep + 1, bev, 1, h - bev * 2)

        ctx.fillStyle = "rgba(0,0,0,0.18)"
        ctx.fillRect(rSep + 2, bev, w - bev - (rSep + 2), h - bev * 2 - 1)

        var dcx = Math.round((rSep + 2 + w - bev) / 2)
        var dcy = Math.round(h / 2)
        var gw = Math.max(7, Math.min(10, Math.round(h * 0.30)))
        var gh = Math.max(5, Math.min(8, Math.round(h * 0.24)))

        // Back window square (outlined white)
        var bx1 = Math.round(dcx - gw * 0.65)
        var by1 = Math.round(dcy - gh * 0.68)
        ctx.fillStyle = root.rgba(amigaCanvas.wbBlack, 0.85)
        ctx.fillRect(bx1 + 1, by1 + 1, gw, gh)
        ctx.strokeStyle = root.rgba(amigaCanvas.wbWhite, 0.92)
        ctx.lineWidth = 1.2
        ctx.strokeRect(bx1 + 0.5, by1 + 0.5, gw - 1, gh - 1)

        // Front window square (crisp white fill with Amiga Orange title strip)
        var fx1 = Math.round(dcx - gw * 0.22)
        var fy1 = Math.round(dcy - gh * 0.18)
        ctx.fillStyle = root.rgba(amigaCanvas.wbBlack, 0.85)
        ctx.fillRect(fx1 + 1, fy1 + 1, gw, gh)
        ctx.fillStyle = root.rgba(amigaCanvas.wbWhite, 0.96)
        ctx.fillRect(fx1, fy1, gw, gh)
        ctx.fillStyle = String(amigaCanvas.wbOrange)
        ctx.fillRect(fx1 + 1, fy1 + 1, gw - 2, 2)
      } else if (compact && w > 36) {
        // Compact thumbnail signature: tiny Boing Ball dot on left + depth squares on right
        var tcy = Math.round(h / 2)
        ctx.fillStyle = "#ffffff"
        ctx.beginPath()
        ctx.arc(6, tcy, 3, 0, Math.PI * 2)
        ctx.fill()
        ctx.fillStyle = String(amigaCanvas.boingRed)
        ctx.fillRect(4, tcy - 2, 2, 2)
        ctx.fillRect(6, tcy, 2, 2)

        ctx.strokeStyle = "rgba(255,255,255,0.85)"
        ctx.lineWidth = 1
        ctx.strokeRect(w - 10.5, tcy - 3.5, 4, 3.5)
        ctx.fillStyle = "#ffffff"
        ctx.fillRect(w - 8, tcy - 1, 4, 3.5)
      }
    }
  }
}

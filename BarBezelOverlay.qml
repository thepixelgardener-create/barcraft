import QtQuick

// Tactile 3D bezel / bevel overlay for bar surfaces and island pills.
// Lazily instantiates a static Canvas only while a bezel style is active,
// zero per-frame overhead and zero Canvas allocation when bezel is "none".
Item {
  id: root

  property string bezelStyle: "none" // none | raised | inset | ridge | glass
  property real strength: 0.75
  property real radius: 0
  property color accentColor: "#ffffff"

  readonly property bool bezelActive: bezelStyle !== "" && bezelStyle !== "none" && width > 2 && height > 2
  readonly property bool canvasLoaded: bezelLoader.item !== null
  visible: bezelActive

  Loader {
    id: bezelLoader
    anchors.fill: parent
    active: root.bezelActive
    sourceComponent: bezelComponent
  }

  Component {
    id: bezelComponent

    Canvas {
      id: bezelCanvas
      anchors.fill: parent
      renderStrategy: Canvas.Cooperative

      Component.onCompleted: if (width > 2 && height > 2) requestPaint()
      onWidthChanged: if (width > 2 && height > 2) requestPaint()
      onHeightChanged: if (width > 2 && height > 2) requestPaint()

      Connections {
        target: root
        function onBezelStyleChanged() { bezelCanvas.requestPaint() }
        function onStrengthChanged() { bezelCanvas.requestPaint() }
        function onRadiusChanged() { bezelCanvas.requestPaint() }
        function onAccentColorChanged() { bezelCanvas.requestPaint() }
      }

      function roundedRectPath(ctx, x, y, w, h, r) {
        var cr = Math.max(0, Math.min(r, w / 2, h / 2))
        ctx.beginPath()
        ctx.moveTo(x + cr, y)
        ctx.lineTo(x + w - cr, y)
        if (cr > 0) ctx.arcTo(x + w, y, x + w, y + cr, cr)
        ctx.lineTo(x + w, y + h - cr)
        if (cr > 0) ctx.arcTo(x + w, y + h, x + w - cr, y + h, cr)
        ctx.lineTo(x + cr, y + h)
        if (cr > 0) ctx.arcTo(x, y + h, x, y + h - cr, cr)
        ctx.lineTo(x, y + cr)
        if (cr > 0) ctx.arcTo(x, y, x + cr, y, cr)
        ctx.closePath()
      }

      onPaint: {
        if (!root.bezelActive || width <= 2 || height <= 2) return
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

      var w = width
      var h = height
      var r = Math.max(0, Math.min(root.radius, h / 2, w / 2))
      var s = Math.max(0.1, Math.min(1.0, root.strength))
      var style = root.bezelStyle

      ctx.save()
      roundedRectPath(ctx, 0, 0, w, h, r)
      ctx.clip()

      if (style === "raised" || style === "inset") {
        var raised = (style === "raised")
        var topCol = raised ? ("rgba(255,255,255," + (0.42 * s).toFixed(3) + ")") : ("rgba(0,0,0," + (0.62 * s).toFixed(3) + ")")
        var botCol = raised ? ("rgba(0,0,0," + (0.60 * s).toFixed(3) + ")") : ("rgba(255,255,255," + (0.34 * s).toFixed(3) + ")")

        // Top & left directional bevel glow/shadow
        var topGrad = ctx.createLinearGradient(0, 0, 0, Math.max(4, h * 0.34))
        topGrad.addColorStop(0, topCol)
        topGrad.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = topGrad
        ctx.fillRect(0, 0, w, Math.max(4, h * 0.34))

        // Bottom directional bevel shadow/catch-light
        var botGrad = ctx.createLinearGradient(0, h - Math.max(4, h * 0.36), 0, h)
        botGrad.addColorStop(0, "rgba(0,0,0,0)")
        botGrad.addColorStop(1, botCol)
        ctx.fillStyle = botGrad
        ctx.fillRect(0, h - Math.max(4, h * 0.36), w, Math.max(4, h * 0.36))

        // Crisp 1.5px chamfered top/left & bottom/right rim strokes
        ctx.lineWidth = 2
        ctx.strokeStyle = topCol
        roundedRectPath(ctx, 1, 1, w - 2, h - 2, Math.max(0, r - 1))
        ctx.save()
        ctx.beginPath()
        ctx.moveTo(0, h)
        ctx.lineTo(0, 0)
        ctx.lineTo(w, 0)
        ctx.closePath()
        ctx.clip()
        roundedRectPath(ctx, 1, 1, w - 2, h - 2, Math.max(0, r - 1))
        ctx.stroke()
        ctx.restore()

        ctx.strokeStyle = botCol
        ctx.save()
        ctx.beginPath()
        ctx.moveTo(w, 0)
        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        ctx.clip()
        roundedRectPath(ctx, 1, 1, w - 2, h - 2, Math.max(0, r - 1))
        ctx.stroke()
        ctx.restore()
      } else if (style === "ridge") {
        // Machined double-ring metallic ridge
        ctx.lineWidth = 1.5
        ctx.strokeStyle = "rgba(0,0,0," + (0.62 * s).toFixed(3) + ")"
        roundedRectPath(ctx, 0.75, 0.75, w - 1.5, h - 1.5, Math.max(0, r - 0.75))
        ctx.stroke()

        ctx.lineWidth = 1.25
        var ridgeGrad = ctx.createLinearGradient(0, 0, 0, h)
        ridgeGrad.addColorStop(0, "rgba(255,255,255," + (0.50 * s).toFixed(3) + ")")
        ridgeGrad.addColorStop(0.5, "rgba(255,255,255," + (0.14 * s).toFixed(3) + ")")
        ridgeGrad.addColorStop(1, "rgba(255,255,255," + (0.32 * s).toFixed(3) + ")")
        ctx.strokeStyle = ridgeGrad
        roundedRectPath(ctx, 2.5, 2.5, w - 5, h - 5, Math.max(0, r - 2.5))
        ctx.stroke()
      } else if (style === "glass") {
        // Liquid-glass top specular crescent + luminous bottom rim
        var sheen = ctx.createLinearGradient(0, 0, 0, h * 0.52)
        sheen.addColorStop(0, "rgba(255,255,255," + (0.34 * s).toFixed(3) + ")")
        sheen.addColorStop(0.55, "rgba(255,255,255," + (0.08 * s).toFixed(3) + ")")
        sheen.addColorStop(1, "rgba(255,255,255,0)")
        ctx.fillStyle = sheen
        ctx.fillRect(0, 0, w, h * 0.52)

        var rim = ctx.createLinearGradient(0, 0, 0, h)
        rim.addColorStop(0, "rgba(255,255,255," + (0.48 * s).toFixed(3) + ")")
        rim.addColorStop(0.45, "rgba(255,255,255," + (0.08 * s).toFixed(3) + ")")
        rim.addColorStop(1, "rgba(255,255,255," + (0.24 * s).toFixed(3) + ")")
        ctx.lineWidth = 1.25
        ctx.strokeStyle = rim
        roundedRectPath(ctx, 0.75, 0.75, w - 1.5, h - 1.5, Math.max(0, r - 0.75))
        ctx.stroke()
      }

      ctx.restore()
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Commons as Commons

// Art renderer for Wild Craft skins ("barber", "runeforge", "rocket"). Still
// artwork: nothing here animates, so the bar never redraws on its own. Keeps
// strong text contrast behind all hosted bar widgets.
Item {
  id: root

  required property string art
  property bool themeTint: false
  property string customBackground: ""
  property string customAccent: ""
  property real contrast: 1.0
  property bool vertical: false
  property real cornerRadius: Style.space(10)

  // Extra horizontal insets needed by shaped end-caps (e.g. rocket thruster & nosecone)
  readonly property int leftContentInset: art === "rocket" && !vertical ? Math.round(height * 1.45) : (art === "barber" && !vertical ? Math.round(height * 0.45) : (art === "runeforge" && !vertical ? Style.space(14) : 0))
  readonly property int rightContentInset: art === "rocket" && !vertical ? Math.round(height * 1.25) : (art === "barber" && !vertical ? Math.round(height * 0.45) : (art === "runeforge" && !vertical ? Style.space(14) : 0))

  readonly property bool useTintedPalette: themeTint || customBackground !== "" || customAccent !== ""
  readonly property color bg: customBackground !== "" ? Qt.color(customBackground) : Commons.Color.bar.background
  readonly property color fg: Commons.Color.bar.text
  readonly property color acc: customAccent !== "" ? Qt.color(customAccent) : Commons.Color.accent
  readonly property color urg: customAccent !== "" ? Qt.darker(Qt.color(customAccent), 1.45) : Commons.Color.bar.active

  visible: art !== "" && art !== "none"

  // =========================================================================
  // 1. BARBER POLE — Diagonal helix cylinder + chrome end caps
  // =========================================================================
  Item {
    id: barberRoot
    visible: root.art === "barber"
    anchors.fill: parent

    readonly property int capW: Math.max(8, Math.round(height * 0.36))
    readonly property color stripeA: root.useTintedPalette ? root.acc : "#d9363e"
    readonly property color stripeB: root.useTintedPalette ? Qt.lighter(root.bg, 2.2) : "#eef2f7"
    readonly property color stripeC: root.useTintedPalette ? root.urg : "#2563c9"

    // Main rotating glass tube
    Rectangle {
      id: barberTube
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: barberRoot.capW - 2
      anchors.rightMargin: barberRoot.capW - 2
      radius: Math.min(height / 2, root.cornerRadius)
      color: "#161922"
      clip: true

      // Repeating angled stripes
      Item {
        id: stripeTrack
        readonly property real pitch: Math.max(36, Math.round(barberTube.height * 1.8))

        x: -pitch * 2
        y: -barberTube.height
        width: barberTube.width + pitch * 5
        height: barberTube.height * 3

        Repeater {
          model: Math.ceil((barberTube.width + stripeTrack.pitch * 5) / stripeTrack.pitch) + 2

          Item {
            required property int index
            x: index * stripeTrack.pitch
            y: 0
            width: stripeTrack.pitch
            height: parent.height

            // Red / primary stripe
            Rectangle {
              x: 0
              y: -height * 0.2
              width: stripeTrack.pitch * 0.30
              height: parent.height * 1.4
              color: barberRoot.stripeA
              transform: Rotation { angle: 34 }
            }
            // White / light stripe 1
            Rectangle {
              x: stripeTrack.pitch * 0.30
              y: -height * 0.2
              width: stripeTrack.pitch * 0.20
              height: parent.height * 1.4
              color: barberRoot.stripeB
              transform: Rotation { angle: 34 }
            }
            // Blue / secondary stripe
            Rectangle {
              x: stripeTrack.pitch * 0.50
              y: -height * 0.2
              width: stripeTrack.pitch * 0.30
              height: parent.height * 1.4
              color: barberRoot.stripeC
              transform: Rotation { angle: 34 }
            }
            // White / light stripe 2
            Rectangle {
              x: stripeTrack.pitch * 0.80
              y: -height * 0.2
              width: stripeTrack.pitch * 0.20
              height: parent.height * 1.4
              color: barberRoot.stripeB
              transform: Rotation { angle: 34 }
            }
          }
        }
      }

      // Smoked glass readability scrim + 3D cylindrical shading & top specular
      // Modulated by the Contrast slider so users can dial stripe punch vs legibility.
      Rectangle {
        id: scrim
        anchors.fill: parent
        radius: parent.radius
        readonly property real scrimBias: Math.max(0.45, Math.min(1.25, 1.5 - root.contrast * 0.5))
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Math.min(0.45, 0.28 * root.contrast)) }
          GradientStop { position: 0.16; color: Qt.rgba(0.05, 0.06, 0.09, Math.min(0.85, 0.52 * scrim.scrimBias)) }
          GradientStop { position: 0.55; color: Qt.rgba(0.04, 0.05, 0.08, Math.min(0.90, 0.68 * scrim.scrimBias)) }
          GradientStop { position: 0.88; color: Qt.rgba(0.02, 0.02, 0.04, Math.min(0.92, 0.78 * scrim.scrimBias)) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
        }
      }

      // Thin crisp specular reflection line near top of cylinder
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Math.max(2, Math.round(parent.height * 0.12))
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        height: 1
        color: Qt.rgba(1, 1, 1, 0.35)
      }
    }

    // Left chrome end-cap
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: barberRoot.capW
      topLeftRadius: height / 2
      bottomLeftRadius: height / 2
      topRightRadius: 2
      bottomRightRadius: 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#e8edf5" }
        GradientStop { position: 0.28; color: "#9aa5b5" }
        GradientStop { position: 0.55; color: "#cfd8e3" }
        GradientStop { position: 0.82; color: "#525b68" }
        GradientStop { position: 1.0; color: "#2b3038" }
      }
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.45)
    }

    // Right chrome end-cap
    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: barberRoot.capW
      topRightRadius: height / 2
      bottomRightRadius: height / 2
      topLeftRadius: 2
      bottomLeftRadius: 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#e8edf5" }
        GradientStop { position: 0.28; color: "#9aa5b5" }
        GradientStop { position: 0.55; color: "#cfd8e3" }
        GradientStop { position: 0.82; color: "#525b68" }
        GradientStop { position: 1.0; color: "#2b3038" }
      }
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.45)
    }
  }

  // =========================================================================
  // 2. RUNEFORGE — Forged obsidian stone + antique gold bevel + glowing runes
  // =========================================================================
  Item {
    id: runeRoot
    visible: root.art === "runeforge"
    anchors.fill: parent

    readonly property color goldBright: root.useTintedPalette ? Qt.lighter(root.acc, 1.35) : "#e5bc5b"
    readonly property color goldMid: root.useTintedPalette ? root.acc : "#b28228"
    readonly property color goldDark: root.useTintedPalette ? Qt.darker(root.acc, 2.2) : "#4a330e"
    readonly property color stoneTop: root.useTintedPalette ? Qt.lighter(root.bg, 1.18) : "#26211c"
    readonly property color stoneMid: root.useTintedPalette ? root.bg : "#181411"
    readonly property color stoneBot: root.useTintedPalette ? Qt.darker(root.bg, 1.4) : "#0e0c0a"
    readonly property color gemColor: root.useTintedPalette ? root.acc : "#3ba4ff"

    // Outer bronze/gold bevel housing
    Rectangle {
      anchors.fill: parent
      radius: Math.min(Style.space(4), root.cornerRadius)
      gradient: Gradient {
        GradientStop { position: 0.0; color: runeRoot.goldBright }
        GradientStop { position: 0.25; color: runeRoot.goldMid }
        GradientStop { position: 0.75; color: runeRoot.goldDark }
        GradientStop { position: 1.0; color: "#231708" }
      }
      border.width: 1
      border.color: "#140d05"

      // Inner dark forged stone body
      Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Math.max(0, parent.radius - 2)
        gradient: Gradient {
          GradientStop { position: 0.0; color: runeRoot.stoneTop }
          GradientStop { position: 0.45; color: runeRoot.stoneMid }
          GradientStop { position: 1.0; color: runeRoot.stoneBot }
        }
        border.width: 1
        border.color: Qt.rgba(runeRoot.goldBright.r, runeRoot.goldBright.g, runeRoot.goldBright.b, 0.35)

        // Subtle engraved top & bottom metallic inner highlight lines
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 1
          height: 1
          color: Qt.rgba(runeRoot.goldBright.r, runeRoot.goldBright.g, runeRoot.goldBright.b, 0.22)
        }

        // Subtle forged vertical plate seams
        Repeater {
          model: 2
          Rectangle {
            required property int index
            x: index === 0 ? Math.round(parent.width * 0.28) : Math.round(parent.width * 0.72)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            width: 2
            color: Qt.rgba(0, 0, 0, 0.45)

            Rectangle {
              anchors.left: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 1
              color: Qt.rgba(runeRoot.goldBright.r, runeRoot.goldBright.g, runeRoot.goldBright.b, 0.22)
            }
          }
        }
      }

      // Corner forged gold clasps + rivets
      Repeater {
        model: [
          { lx: 0, ty: 0 },
          { lx: 1, ty: 0 },
          { lx: 0, ty: 1 },
          { lx: 1, ty: 1 }
        ]
        Rectangle {
          required property var modelData
          x: modelData.lx === 0 ? 3 : parent.width - width - 3
          y: modelData.ty === 0 ? 3 : parent.height - height - 3
          width: 4
          height: 4
          radius: 2
          color: runeRoot.goldBright
          border.width: 1
          border.color: runeRoot.goldDark
        }
      }

      // Left & right glowing mana/rune diamond medallions
      Repeater {
        model: [0, 1]
        Rectangle {
          id: gem
          required property int modelData
          x: modelData === 0 ? Style.space(6) : parent.width - width - Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(6, Math.round(parent.height * 0.26))
          height: width
          rotation: 45
          color: runeRoot.gemColor
          border.width: 1
          border.color: runeRoot.goldBright

        }
      }
    }
  }

  // =========================================================================
  // 3. LONG ROCKET — Full-width horizontal spacecraft with exhaust plume
  // =========================================================================
  Item {
    id: rocketRoot
    visible: root.art === "rocket"
    anchors.fill: parent

    readonly property int flameW: Math.max(18, Math.round(height * 0.95))
    readonly property int nozzleW: Math.max(10, Math.round(height * 0.42))
    readonly property int noseW: Math.max(22, Math.round(height * 1.15))
    readonly property color accentPaint: root.useTintedPalette ? root.acc : "#d93829"
    readonly property color hullTop: root.useTintedPalette ? Qt.lighter(root.bg, 1.45) : "#454c59"
    readonly property color hullMid: root.useTintedPalette ? root.bg : "#1f232b"
    readonly property color hullBot: root.useTintedPalette ? Qt.darker(root.bg, 1.4) : "#13161c"
    readonly property color flameOuter: root.useTintedPalette ? root.acc : "#ff5e1a"
    readonly property color flameMid: root.useTintedPalette ? Qt.lighter(root.acc, 1.35) : "#ffbe2e"

    // Thruster exhaust plume (left end)
    Item {
      id: thrusterPlume
      x: 0
      y: 0
      width: rocketRoot.flameW
      height: parent.height


      // Outer orange/accent flame cone
      Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(6, parent.width)
        height: Math.max(6, parent.height * 0.56)
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.45; color: Qt.rgba(rocketRoot.flameOuter.r, rocketRoot.flameOuter.g, rocketRoot.flameOuter.b, 0.85) }
          GradientStop { position: 1.0; color: rocketRoot.flameMid }
        }
      }

      // Hot inner white-yellow plasma core
      Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(4, parent.width * 0.58)
        height: Math.max(4, parent.height * 0.28)
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.55; color: rocketRoot.flameMid }
          GradientStop { position: 1.0; color: "#ffffff" }
        }
      }
    }

    // Swept stabilizer fins + engine bell nozzle (vector Canvas painted once on resize)
    Canvas {
      id: tailCanvas
      x: rocketRoot.flameW - 2
      y: 0
      width: rocketRoot.nozzleW + 14
      height: parent.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onVisibleChanged: if (visible) requestPaint()
      Connections {
        target: rocketRoot
        function onAccentPaintChanged() { tailCanvas.requestPaint() }
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var nw = rocketRoot.nozzleW

        // Top & bottom swept crimson/accent stabilizer fins
        ctx.fillStyle = String(rocketRoot.accentPaint)
        ctx.beginPath()
        ctx.moveTo(nw - 2, 0)
        ctx.lineTo(width, 0)
        ctx.lineTo(width, height * 0.22)
        ctx.lineTo(nw + 3, height * 0.22)
        ctx.closePath()
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(nw - 2, height)
        ctx.lineTo(width, height)
        ctx.lineTo(width, height * 0.78)
        ctx.lineTo(nw + 3, height * 0.78)
        ctx.closePath()
        ctx.fill()

        // Dark gunmetal thruster bell nozzle
        var ng = ctx.createLinearGradient(0, height * 0.2, 0, height * 0.8)
        ng.addColorStop(0, "#757e8c")
        ng.addColorStop(0.5, "#363b45")
        ng.addColorStop(1, "#181a20")
        ctx.fillStyle = ng
        ctx.beginPath()
        ctx.moveTo(0, height * 0.26)
        ctx.lineTo(nw + 2, height * 0.16)
        ctx.lineTo(nw + 2, height * 0.84)
        ctx.lineTo(0, height * 0.74)
        ctx.closePath()
        ctx.fill()

        ctx.strokeStyle = "rgba(0,0,0,0.6)"
        ctx.lineWidth = 1
        ctx.stroke()
      }
    }

    // Main rocket fuselage body (hosts all bar widgets cleanly)
    Rectangle {
      id: fuselage
      x: rocketRoot.flameW + rocketRoot.nozzleW - 2
      y: Math.max(1, Math.round(parent.height * 0.06))
      width: Math.max(20, parent.width - x - rocketRoot.noseW + 2)
      height: Math.max(16, parent.height - y * 2)
      gradient: Gradient {
        GradientStop { position: 0.0; color: rocketRoot.hullTop }
        GradientStop { position: 0.24; color: rocketRoot.hullMid }
        GradientStop { position: 0.80; color: rocketRoot.hullMid }
        GradientStop { position: 1.0; color: rocketRoot.hullBot }
      }
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.18)

      // Top metallic specular highlight
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 2
        height: 1
        color: Qt.rgba(1, 1, 1, 0.28)
      }

      // Red/accent racing collar stripe near nose & tail
      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        color: rocketRoot.accentPaint
      }

      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 3
        color: rocketRoot.accentPaint
      }

      // Hull stage seam lines with micro rivets
      Repeater {
        model: 3
        Rectangle {
          required property int index
          x: Math.round(parent.width * ((index + 1) / 4))
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 2
          width: 1
          color: Qt.rgba(0, 0, 0, 0.35)
        }
      }
    }

    // Aerodynamic pointed nosecone (right end)
    Canvas {
      id: noseCanvas
      x: fuselage.x + fuselage.width - 1
      y: fuselage.y
      width: rocketRoot.noseW + 1
      height: fuselage.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onVisibleChanged: if (visible) requestPaint()
      Connections {
        target: rocketRoot
        function onAccentPaintChanged() { noseCanvas.requestPaint() }
        function onHullTopChanged() { noseCanvas.requestPaint() }
        function onHullMidChanged() { noseCanvas.requestPaint() }
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        // Smooth ogive nosecone silhouette
        ctx.save()
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.quadraticCurveTo(width * 0.62, 0, width - 1, height / 2)
        ctx.quadraticCurveTo(width * 0.62, height, 0, height)
        ctx.closePath()
        ctx.clip()

        // Base metallic hull gradient
        var g = ctx.createLinearGradient(0, 0, 0, height)
        g.addColorStop(0, String(rocketRoot.hullTop))
        g.addColorStop(0.35, String(rocketRoot.hullMid))
        g.addColorStop(1, String(rocketRoot.hullBot))
        ctx.fillStyle = g
        ctx.fillRect(0, 0, width, height)

        // Painted red/accent nose tip
        ctx.fillStyle = String(rocketRoot.accentPaint)
        ctx.fillRect(width * 0.48, 0, width * 0.55, height)

        // Glossy specular ridge on nosecone
        ctx.fillStyle = "rgba(255,255,255,0.26)"
        ctx.fillRect(0, 2, width * 0.85, 2)
        ctx.restore()

        // Crisp nosecone outline
        ctx.beginPath()
        ctx.moveTo(0, 0.5)
        ctx.quadraticCurveTo(width * 0.62, 0.5, width - 1, height / 2)
        ctx.quadraticCurveTo(width * 0.62, height - 0.5, 0, height - 0.5)
        ctx.strokeStyle = "rgba(255,255,255,0.22)"
        ctx.lineWidth = 1
        ctx.stroke()
      }
    }
  }
}

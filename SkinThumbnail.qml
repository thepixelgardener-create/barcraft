import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// A small drawing of a skin on a strip of desktop, built from the skin's own
// values (mode, margins, corners, opacity, fill, border, shadow, widget
// style) and the live theme, so every card shows what picking it would do.
Item {
  id: thumb

  property var skin: null
  property var paletteMap: ({})
  // Draw Omarchy's own bar (the Omarchy standard tile).
  property bool standard: false
  property bool highlighted: false

  readonly property real k: 0.42

  SkinLook {
    id: tl
    skin: thumb.skin
    paletteMap: thumb.paletteMap
    standard: thumb.standard
  }

  // From the resolved pixels, so "auto" draws with this desktop's own
  // Hyprland rounding and gaps.
  readonly property real barH: Math.max(9, Math.round(tl.barSizePx * k))
  readonly property real topGap: tl.mode === "edge" ? 0 : Math.max(2, Math.round(tl.edgePx * k) + 2)
  readonly property real sideRoom: tl.mode === "edge" ? 0 : Math.max(3, Math.round(tl.sidePx * k) + 3)
  readonly property real sideGap: sideRoom + Math.round((width - sideRoom * 2) * (100 - tl.widthPercent) / 200)
  readonly property real barRadius: Math.min(barH / 2, tl.radiusPx * k)
  readonly property color ink: tl.effectiveForeground

  clip: true

  // The desktop behind the bar: a wash from the theme's background toward its
  // accent, so a see-through skin reads as see-through.
  Rectangle {
    anchors.fill: parent
    radius: Math.max(0, Style.cornerRadius - 2)
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.lighter(Commons.Color.background, 1.5) }
      GradientStop { position: 1.0; color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.45) }
    }
  }

  component MiniSurface: Item {
    id: mini
    property real r: thumb.barRadius

    RectangularShadow {
      anchors.fill: parent
      visible: tl.shadow
      radius: mini.r
      offset: Qt.vector2d(0, 1.5)
      blur: 4 + 4 * tl.shadowStrength
      color: Qt.rgba(0, 0, 0, 0.25 + 0.35 * tl.shadowStrength)
    }

    Rectangle {
      anchors.fill: parent
      radius: mini.r
      color: tl.surfaceColor
      border.width: tl.borderWidth > 0 && tl.borderRole !== "none" && tl.mode !== "edge" ? 1 : 0
      border.color: tl.borderPreviewColor

      Rectangle {
        visible: tl.gradientActive
        anchors.fill: parent
        anchors.margins: parent.border.width
        radius: Math.max(0, parent.radius - parent.border.width)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: tl.surfaceColor }
          GradientStop { position: 1.0; color: tl.gradientColor }
        }
      }
    }

    // Editorial's rule along the bottom edge.
    Rectangle {
      visible: tl.mode === "edge" && tl.borderWidth > 0 && tl.borderRole !== "none"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: tl.borderPreviewColor
    }
  }

  // A widget: a dot, on a pill or chip when the skin draws them.
  component MiniWidget: Item {
    property real w: Math.max(4, Math.round(thumb.barH * 0.34))
    property color dot: Qt.rgba(thumb.ink.r, thumb.ink.g, thumb.ink.b, 0.7)
    width: tl.widgetStyle === "plain" ? w : w + 6
    height: thumb.barH

    Rectangle {
      visible: tl.widgetStyle !== "plain"
      anchors.centerIn: parent
      width: parent.width
      height: Math.max(5, parent.height - 4)
      radius: tl.widgetStyle === "pills" ? height / 2 : 1.5
      color: Qt.rgba(thumb.ink.r, thumb.ink.g, thumb.ink.b, 0.12)
      border.width: tl.widgetStyle === "chips" ? 1 : 0
      border.color: Qt.rgba(thumb.ink.r, thumb.ink.g, thumb.ink.b, 0.2)
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.w
      height: Math.max(2, Math.round(thumb.barH * 0.22))
      radius: height / 2
      color: parent.dot
    }
  }

  Item {
    id: barArea
    x: thumb.sideGap
    y: thumb.topGap
    width: thumb.width - thumb.sideGap * 2
    height: thumb.barH

    // Wild Craft art draws itself (lazy: 0 Canvases allocated for non-art skins).
    BarArtLayer {
      anchors.fill: parent
      art: tl.hasArt ? tl.art : "none"
      themeTint: tl.themeTint
      customBackground: tl.customBackgroundHex
      customAccent: tl.customAccentHex
      contrast: tl.contrast
      cornerRadius: thumb.barRadius
    }

    MiniSurface {
      visible: !tl.hasArt && tl.mode !== "islands"
      anchors.fill: parent
      r: tl.mode === "edge" ? 0 : thumb.barRadius
    }

    MiniSurface {
      visible: !tl.hasArt && tl.mode === "islands"
      x: 0
      width: leftDots.width + 8
      height: parent.height
    }

    MiniSurface {
      visible: !tl.hasArt && tl.mode === "islands"
      x: Math.round((parent.width - width) / 2)
      width: centerDots.width + 10
      height: parent.height
    }

    MiniSurface {
      visible: !tl.hasArt && tl.mode === "islands"
      x: parent.width - width
      width: rightDots.width + 8
      height: parent.height
    }

    Row {
      id: leftDots
      visible: !tl.hasArt
      x: tl.mode === "islands" ? 4 : 5
      spacing: 2
      MiniWidget { dot: tl.resolvedAccent }
      MiniWidget {}
    }

    Row {
      id: centerDots
      visible: !tl.hasArt
      anchors.horizontalCenter: parent.horizontalCenter
      MiniWidget { w: Math.round(thumb.barH * 1.1) }
    }

    Row {
      id: rightDots
      visible: !tl.hasArt
      anchors.right: parent.right
      anchors.rightMargin: tl.mode === "islands" ? 4 : 5
      spacing: 2
      MiniWidget {}
      MiniWidget {}
      MiniWidget {}
    }
  }
}

import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// One skinned bar surface (the whole bar or an island pill): soft shadow,
// solid or gradient fill, border, and 3D bezel, all driven by a SkinLook.
Item {
  id: surface

  property var look: null
  property string position: "top"
  property bool vertical: false
  property bool transparent: false

  readonly property bool clear: transparent || !look
  readonly property real cornerRadius: look ? Math.min(look.radiusPx, Math.min(width, height) / 2) : 0
  readonly property real shadowReach: look ? Style.space(2) + Style.space(3) * look.shadowStrength : 0

  RectangularShadow {
    anchors.fill: parent
    visible: !surface.clear && surface.look.shadow && surface.width > 0 && surface.height > 0
    radius: surface.cornerRadius
    offset: Qt.vector2d(
      surface.position === "left" ? surface.shadowReach : (surface.position === "right" ? -surface.shadowReach : 0),
      surface.position === "top" ? surface.shadowReach : (surface.position === "bottom" ? -surface.shadowReach : 0))
    blur: surface.look ? Style.space(8) + Style.space(10) * surface.look.shadowStrength : 0
    spread: 0
    color: Qt.rgba(0, 0, 0, surface.look ? 0.22 + 0.4 * surface.look.shadowStrength : 0)
  }

  BorderSurface {
    id: surfaceFill
    anchors.fill: parent
    color: surface.clear ? "transparent" : surface.look.surfaceColor
    borderSpec: surface.clear ? Border.none() : surface.look.surfaceBorderSpec
    radius: surface.cornerRadius

    Behavior on color { ColorAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

    Rectangle {
      readonly property real inset: surface.look && surface.look.borderRole !== "none" ? surface.look.borderWidth : 0
      visible: !surface.clear && surface.look.gradientActive
      anchors.fill: parent
      anchors.margins: inset
      radius: Math.max(0, surfaceFill.radius - inset)
      gradient: Gradient {
        orientation: surface.vertical ? Gradient.Vertical : Gradient.Horizontal
        GradientStop { position: 0.0; color: surface.look ? surface.look.surfaceColor : "transparent" }
        GradientStop { position: 1.0; color: surface.look ? surface.look.gradientColor : "transparent" }
      }
    }

    BarBezelOverlay {
      anchors.fill: parent
      bezelStyle: (surface.clear || !surface.visible) ? "none" : surface.look.bezel
      strength: surface.look ? surface.look.bezelStrength : 0.75
      radius: parent.radius
      accentColor: surface.look ? surface.look.resolvedAccent : "white"
    }
  }
}

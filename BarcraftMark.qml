import QtQuick
import qs.Commons
import qs.Commons as Commons

// Barcraft's mark: a little bar, a raised pill with a bezel. Drawn in the
// ink it's given (the bar's foreground), so it follows the theme and the
// skin's contrast the way a glyph would; `lit` tints it while the Studio is
// open. Plain rectangles, nothing animated.
Item {
  id: mark

  property color ink: Commons.Color.bar.text
  property color accent: Commons.Color.accent
  property bool lit: false

  implicitWidth: Math.round(Style.bar.iconCanvas * 1.4)
  implicitHeight: Math.round(implicitWidth * 0.5)

  readonly property real rim: Math.max(1, Math.round(height * 0.11))
  readonly property real inner: Math.max(0, height - rim * 2)

  // Body: the face falls from lit to shade under a solid rim.
  Rectangle {
    anchors.fill: parent
    radius: height / 2
    border.width: mark.rim
    border.color: Qt.rgba(mark.ink.r, mark.ink.g, mark.ink.b, 0.92)
    gradient: Gradient {
      GradientStop { position: 0.0; color: mark.lit ? Qt.rgba(mark.accent.r, mark.accent.g, mark.accent.b, 0.6) : Qt.rgba(mark.ink.r, mark.ink.g, mark.ink.b, 0.48) }
      GradientStop { position: 0.55; color: Qt.rgba(mark.ink.r, mark.ink.g, mark.ink.b, 0.14) }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.18) }
    }
  }

  // Bezel: light along the inside of the top edge, shade along the bottom.
  Rectangle {
    x: Math.round(mark.height * 0.42)
    y: mark.rim
    width: Math.max(0, mark.width - x * 2)
    height: Math.max(1, Math.round(mark.rim * 0.8))
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.5)
  }

  Rectangle {
    x: Math.round(mark.height * 0.42)
    y: mark.height - mark.rim - height
    width: Math.max(0, mark.width - x * 2)
    height: Math.max(1, Math.round(mark.rim * 0.8))
    radius: height / 2
    color: Qt.rgba(0, 0, 0, 0.32)
  }

  // The bar's own widgets, as on the app icon: accent dot, label, status.
  Rectangle {
    readonly property real d: Math.max(2, Math.round(mark.inner * 0.42))
    x: mark.rim + Math.max(1, Math.round(mark.inner * 0.22))
    anchors.verticalCenter: parent.verticalCenter
    width: d
    height: d
    radius: d / 2
    color: mark.accent
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.max(3, Math.round(mark.width * 0.22))
    height: Math.max(1, Math.round(mark.inner * 0.24))
    radius: height / 2
    color: Qt.rgba(mark.ink.r, mark.ink.g, mark.ink.b, 0.85)
  }

  Rectangle {
    readonly property real d: Math.max(2, Math.round(mark.inner * 0.28))
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: mark.rim + Math.max(1, Math.round(mark.inner * 0.22))
    width: d
    height: d
    radius: d / 2
    color: Qt.rgba(mark.ink.r, mark.ink.g, mark.ink.b, 0.75)
  }
}

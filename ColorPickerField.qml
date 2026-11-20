import QtQuick
import QtQuick.Layouts
import "kit/Theme"
import "kit/Theme" as Kit
import "kit/Ui" as O

// The Studio's color chooser, drawn with the Omarchy UI kit: the current
// color in a ColorWell (press it for the picker), the theme's palette and a
// set of fixed colors as SwatchStrips, and a saturation/value square over a
// hue strip. A theme swatch picks a live reference ("theme.blue") that
// follows theme switches; the fixed swatches and the picker pick "#rrggbb";
// "" means automatic.
//
// The kit's own ColorPicker carries a hex TextField, a TextInput, which reads
// the whole clipboard on every clipboard change in Qt 6.12.0 (see
// LineField.qml); a plugin inside the shell keeps those out.
Column {
  id: root

  property color foreground: Kit.Color.popups.text
  property color dimForeground: Kit.Color.textDim
  property string currentValue: ""
  // What currentValue looks like now (resolved by the engine).
  property color resolvedColor: fallbackColor
  property color fallbackColor: Kit.Color.background
  property var themePalette: [] // [{ name, key, hex }] from the active colors.toml
  property string resetLabel: "Theme"
  property var strings: null
  property bool pickerExpanded: false

  signal colorPicked(string value)

  spacing: Style.spacing.sm

  property real hue: 0.58
  property real sat: 0.65
  property real val: 0.82

  function t(key, fallback) {
    return strings ? strings.t(key) : fallback
  }

  readonly property color shownColor: currentValue !== "" ? resolvedColor : fallbackColor
  readonly property bool isThemeRef: currentValue.indexOf("theme.") === 0

  function toHex2(n) {
    var v = Math.max(0, Math.min(255, Math.round(n)))
    var s = v.toString(16)
    return s.length === 1 ? "0" + s : s
  }

  function colorToHex(c) {
    if (!c) return "#101315"
    return "#" + toHex2(c.r * 255) + toHex2(c.g * 255) + toHex2(c.b * 255)
  }

  function hsvToHex(h, s, v) {
    return colorToHex(Qt.hsva(Math.max(0, Math.min(0.9999, h)), Math.max(0, Math.min(1, s)), Math.max(0, Math.min(1, v)), 1))
  }

  function syncHsvFromColor(c) {
    if (!c) return
    var r = c.r, g = c.g, b = c.b
    var max = Math.max(r, g, b)
    var min = Math.min(r, g, b)
    var d = max - min
    var h = hue
    if (d > 0.0001) {
      if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6
      else if (max === g) h = ((b - r) / d + 2) / 6
      else h = ((r - g) / d + 4) / 6
    }
    hue = h
    sat = max > 0.0001 ? d / max : 0
    val = max
  }

  onShownColorChanged: syncHsvFromColor(shownColor)
  Component.onCompleted: syncHsvFromColor(shownColor)

  readonly property var curatedSwatches: [
    "#111318", "#1c1f2b", "#1e1628", "#102421", "#2a1419", "#241d15",
    "#d93829", "#f28b30", "#d4a234", "#34c785", "#2ea8d9", "#4f7cff",
    "#9b6dff", "#e35ca8", "#dce3ec"
  ]

  readonly property var themeSwatches: {
    if (themePalette && themePalette.length > 0) return themePalette
    return [
      { name: "background", key: "background", hex: colorToHex(Kit.Color.background) },
      { name: "accent", key: "accent", hex: colorToHex(Kit.Color.accent) },
      { name: "foreground", key: "foreground", hex: colorToHex(Kit.Color.foreground) }
    ]
  }

  // Left/Right from the keyboard: automatic, then each theme swatch.
  function stepSwatch(direction) {
    var ring = [""]
    for (var i = 0; i < themeSwatches.length; i++) ring.push("theme." + themeSwatches[i].key)
    var idx = ring.indexOf(currentValue)
    var next = idx < 0 ? (direction > 0 ? 1 : ring.length - 1) : (idx + direction + ring.length) % ring.length
    colorPicked(ring[next])
  }

  function valueLabel() {
    if (currentValue === "") return resetLabel
    if (isThemeRef) return t("color.themeRef", "Theme %1").arg(currentValue.slice(6).replace(/_/g, " "))
    return currentValue.toUpperCase()
  }

  // As many swatches to a strip as the width holds.
  readonly property int perStrip: Math.max(4, Math.floor(width / (Style.space(22) + (Style.spacing.xxs + Math.max(1, Style.space(2))) * 2 + Style.spacing.xxs)))

  function chunks(list) {
    var out = []
    for (var i = 0; i < list.length; i += perStrip) out.push({ start: i, items: list.slice(i, i + perStrip) })
    return out
  }

  // The current color, what it is, and the way back to automatic.
  RowLayout {
    width: parent.width
    spacing: Style.spacing.md

    O.ColorWell {
      swatch: root.shownColor
      foreground: root.foreground
      onClicked: root.pickerExpanded = !root.pickerExpanded
    }

    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: root.valueLabel()
      color: root.currentValue !== "" ? root.foreground : root.dimForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }

    O.Button {
      text: root.resetLabel
      fontSize: Style.font.caption
      selected: root.currentValue === ""
      bordered: true
      onClicked: root.colorPicked("")
    }

    O.Button {
      text: root.pickerExpanded ? root.t("color.hide", "Hide") : root.t("color.custom", "Custom")
      iconText: "󰌁"
      fontSize: Style.font.caption
      selected: root.pickerExpanded
      bordered: true
      onClicked: root.pickerExpanded = !root.pickerExpanded
    }
  }

  // The active theme's palette, as live references.
  Text {
    textFormat: Text.PlainText
    text: root.t("color.themePalette", "Theme palette · follows theme switches")
    color: root.dimForeground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.chunks(root.themeSwatches)

    O.SwatchStrip {
      required property var modelData
      colors: modelData.items.map(function(s) { return s.hex })
      // SwatchStrip writes currentIndex on a click. Keep the binding separate
      // so subsequent changes to the active skin still update the selection.
      Binding on currentIndex {
        value: {
          for (var i = 0; i < modelData.items.length; i++)
            if (root.currentValue === "theme." + modelData.items[i].key) return i
          return -1
        }
      }
      foreground: root.foreground
      activeFocusOnTab: false
      onPicked: function(index) { root.colorPicked("theme." + modelData.items[index].key) }
    }
  }

  // Fixed colors, the same under every theme.
  Text {
    textFormat: Text.PlainText
    text: root.t("color.creativePalette", "Fixed colors")
    color: root.dimForeground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.chunks(root.curatedSwatches)

    O.SwatchStrip {
      required property var modelData
      colors: modelData.items
      Binding on currentIndex {
        value: modelData.items.indexOf(root.currentValue)
      }
      foreground: root.foreground
      activeFocusOnTab: false
      onPicked: function(index) { root.colorPicked(modelData.items[index]) }
    }
  }

  // Saturation (x) by value (y), and the hue strip, in the kit's corners and
  // knobs.
  Column {
    visible: root.pickerExpanded
    width: parent.width
    spacing: Style.spacing.sm

    readonly property real smallRadius: Math.min(4, Style.cornerRadius)
    readonly property real knob: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))

    Item {
      id: svPad
      width: parent.width
      height: Style.space(104)

      Rectangle {
        anchors.fill: parent
        radius: parent.parent.smallRadius
        color: Qt.hsva(root.hue, 1, 1, 1)
        clip: true

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#000000" }
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: parent.parent.smallRadius
        color: "transparent"
        border.width: 1
        border.color: Kit.Color.track
      }

      Rectangle {
        x: Math.round(root.sat * svPad.width) - width / 2
        y: Math.round((1 - root.val) * svPad.height) - height / 2
        width: parent.parent.knob
        height: width
        radius: width / 2
        color: root.shownColor
        border.width: Math.max(1, Style.space(2))
        border.color: Kit.Color.popups.background
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        function pickAt(mx, my) {
          root.sat = Math.max(0, Math.min(1, mx / Math.max(1, svPad.width)))
          root.val = Math.max(0, Math.min(1, 1 - my / Math.max(1, svPad.height)))
          root.colorPicked(root.hsvToHex(root.hue, root.sat, root.val))
        }
        onPressed: function(e) { pickAt(e.x, e.y) }
        onPositionChanged: function(e) { if (pressed) pickAt(e.x, e.y) }
      }
    }

    Item {
      id: hueBar
      width: parent.width
      height: Style.space(14)

      Rectangle {
        anchors.fill: parent
        radius: parent.parent.smallRadius
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.00; color: "#ff0000" }
          GradientStop { position: 0.17; color: "#ffff00" }
          GradientStop { position: 0.33; color: "#00ff00" }
          GradientStop { position: 0.50; color: "#00ffff" }
          GradientStop { position: 0.67; color: "#0000ff" }
          GradientStop { position: 0.83; color: "#ff00ff" }
          GradientStop { position: 1.00; color: "#ff0000" }
        }
        border.width: 1
        border.color: Kit.Color.track
      }

      Rectangle {
        x: Math.round(root.hue * (hueBar.width - width))
        anchors.verticalCenter: parent.verticalCenter
        width: parent.parent.knob
        height: width
        radius: width / 2
        color: Qt.hsva(root.hue, 1, 1, 1)
        border.width: Math.max(1, Style.space(2))
        border.color: Kit.Color.popups.background
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function pickHue(mx) {
          root.hue = Math.max(0, Math.min(0.9999, mx / Math.max(1, hueBar.width)))
          root.colorPicked(root.hsvToHex(root.hue, root.sat, root.val))
        }
        onPressed: function(e) { pickHue(e.x) }
        onPositionChanged: function(e) { if (pressed) pickHue(e.x) }
      }
    }
  }
}

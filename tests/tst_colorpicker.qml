import QtQuick
import QtTest
import ".."

TestCase {
  name: "StudioColorPicker"

  ColorPickerField {
    id: picker
    width: 430
    themePalette: [{ key: "accent", hex: "#ff0000" }]
    onColorPicked: value => currentValue = value
  }

  function test_selectionFollowsSkinAfterClick() {
    const strips = picker.children.filter(item => typeof item.pick === "function")
    const theme = strips[0]
    const fixed = strips[1]
    theme.pick(0)
    compare(picker.currentValue, "theme.accent")
    fixed.pick(0)
    compare(theme.currentIndex, -1)
    compare(fixed.currentIndex, 0)
    picker.currentValue = ""
    compare(fixed.currentIndex, -1)
  }

  function test_hsvFollowsResolvedThemeColor() {
    picker.currentValue = "theme.accent"
    picker.resolvedColor = "red"
    compare(picker.hue, 0)
    picker.resolvedColor = "lime"
    fuzzyCompare(picker.hue, 1 / 3, 0.001)
    picker.currentValue = ""
    picker.fallbackColor = "#808080"
    compare(picker.sat, 0)
    fuzzyCompare(picker.val, 128 / 255, 0.001)
  }
}

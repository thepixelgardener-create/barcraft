import QtQuick
import QtTest
import ".."

Item {
  width: 450
  height: 400

  ColorPickerField {
    id: picker
    width: 430
    themePalette: [{ key: "accent", hex: "#ff0000" }]
    onColorPicked: value => currentValue = value
  }

  TestCase {
    name: "StudioColorPicker"
    when: windowShown

    function collectStrips(node, out) {
      for (let i = 0; i < node.children.length; i++) {
        const child = node.children[i]
        if (typeof child.pick === "function") out.push(child)
        else collectStrips(child, out)
      }
      return out
    }

    function test_selectionFollowsSkinAfterClick() {
      const strips = collectStrips(picker, [])
      const theme = strips[0]
      const fixed = strips[1]
      verify(theme.visible)
      // Fixed colors sit inside the Custom drawer until expanded.
      compare(picker.pickerExpanded, false)
      compare(fixed.visible, false)
      picker.pickerExpanded = true
      compare(fixed.visible, true)
      theme.pick(0)
      compare(picker.currentValue, "theme.accent")
      fixed.pick(0)
      compare(theme.currentIndex, -1)
      compare(fixed.currentIndex, 0)
      picker.currentValue = ""
      compare(fixed.currentIndex, -1)
      picker.pickerExpanded = false
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
}

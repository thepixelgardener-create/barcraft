import QtQuick
import "../Theme"
import "../Theme" as Commons

// The harvested PanelSlider with the theme's colors by default. PanelSlider takes its colors
// from the shell's `bar` object and falls back to hard-coded greys without one; here `bar`
// defaults to the foreground on the popups surface, as the Rune Slider draws. Pass a `bar` for
// another surface (its `background` is the knob ring and notch color).
PanelSlider {
  bar: QtObject {
    property color foreground: Commons.Color.foreground
    property color background: Commons.Color.popups.background
  }
}

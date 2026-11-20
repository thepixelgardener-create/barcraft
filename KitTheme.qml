import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "kit/Theme" as Kit

// Feeds the Omarchy UI kit (kit/) the theme the shell is drawing with.
//
// The kit resolves its colors and sizes itself, from the same files the shell
// resolves its own from. A shell plugin cannot load the kit's C++ reader, so
// this hands those files, and the shell's Hyprland and font values, to its
// stand-in (kit/Theme/ThemeSource.qml), all at once, whenever one moves. The
// same bridge thepixelgardener.omarchyform uses.
//
// Every read of the shell's own singletons goes through a guard: they are not
// a versioned API, and a rename upstream should cost a wrong value, not a
// Studio that will not open.
Item {
  id: theme

  visible: false
  width: 0
  height: 0

  function token(read, fallback) {
    try {
      var v = read()
      return v === undefined || v === null ? fallback : v
    } catch (e) {
      return fallback
    }
  }

  function style(path, fallback) {
    return theme.token(function() {
      var v = Commons.Style
      var parts = path.split(".")
      for (var i = 0; i < parts.length; i++) v = v[parts[i]]
      return v
    }, fallback)
  }

  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy"

  readonly property int rounding: theme.style("cornerRadius", 0)
  // The kit halves Hyprland's gaps itself; the shell has already halved them.
  readonly property real gaps: theme.style("gapsOut", 5) * 2
  readonly property bool animations: !theme.style("reduceMotion", false)
  readonly property string font: theme.style("fontFamily", theme.style("font.family", "monospace"))
  readonly property string resolvedFont: theme.style("resolvedFontFamily", theme.font)

  onRoundingChanged: theme.feed()
  onGapsChanged: theme.feed()
  onAnimationsChanged: theme.feed()
  onFontChanged: theme.feed()
  onResolvedFontChanged: theme.feed()

  // The current theme is a symlink, so a switch retargets it rather than
  // editing a watched file. The shell replaces shellValues even when two
  // themes share the same background and accent.
  Connections {
    target: Commons.Color
    function onShellValuesChanged() {
      colorsFile.reload()
      shellFile.reload()
      nameFile.reload()
    }
  }

  function fileText(view) {
    try { return view.loaded ? view.text() : "" } catch (e) { return "" }
  }

  function feed() {
    Kit.ThemeSource.apply({
      colorsText: theme.fileText(colorsFile),
      shellText: theme.fileText(shellFile),
      userShellText: theme.fileText(userShellFile),
      themeName: theme.fileText(nameFile).trim(),
      languageText: theme.fileText(languageFile).trim(),
      themeDir: theme.themeDir,
      rounding: theme.rounding,
      gapsOut: theme.gaps,
      animations: theme.animations,
      fontFamily: theme.font,
      resolvedFontFamily: theme.resolvedFont
    })
  }

  Component.onCompleted: theme.feed()

  FileView {
    id: colorsFile
    path: theme.themeDir + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feed()
    onLoadFailed: theme.feed()
    onFileChanged: reload()
  }

  FileView {
    id: shellFile
    path: theme.themeDir + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feed()
    onLoadFailed: theme.feed()
    onFileChanged: reload()
  }

  FileView {
    id: userShellFile
    path: theme.configDir + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feed()
    onLoadFailed: theme.feed()
    onFileChanged: reload()
  }

  FileView {
    id: nameFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feed()
    onLoadFailed: theme.feed()
    onFileChanged: reload()
  }

  FileView {
    id: languageFile
    path: theme.configDir + "/language"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feed()
    onLoadFailed: theme.feed()
    onFileChanged: reload()
  }
}

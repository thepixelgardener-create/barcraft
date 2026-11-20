import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Barcraft Studio. Skins: pick, preview on hover or under the cursor, give a
// screen its own skin, manage saved skins. Craft: every skin field, the
// preferences that hold for all skins, save and share.
//
// Keyboard: arrows or hjkl move the cursor, Left/Right adjust the row under
// it, Return or Space activates, 1 and 2 switch tabs, R renames and Delete
// removes a saved skin, Esc closes, Tab moves to the next panel on the bar.
Column {
  id: root

  property var bar: null
  property var engine: null
  property var strings: null
  // The card's room for this content, so the body scrolls rather than grows.
  property real maxHeight: Style.space(680)
  property bool panelOpen: true
  // The key catcher, to hand the keyboard back to after editing text.
  property Item keyTarget: null

  property string activeTab: "presets"
  property string colorTarget: "surface"
  property string screenTarget: ""
  property string statusMessage: ""
  property bool statusError: false
  property string saveNameText: ""
  property string renamingId: ""
  property string confirmDeleteId: ""
  property string pendingPreview: ""

  property bool keyboardMode: false
  property var navItems: []
  property Item navCurrent: null
  property point lastPointer: Qt.point(-1, -1)

  readonly property bool textEditing: nameInput.activeFocus || renamingId !== ""
  readonly property color fg: Commons.Color.popups.text
  readonly property color dimFg: Qt.darker(fg, 1.45)
  readonly property var screenNames: {
    var out = []
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) out.push(list[i].name)
    return out
  }
  readonly property var palette: engine ? engine.themeColors : ({})

  spacing: Style.spacing.panelGap

  function tr(key, fallback) {
    return strings ? strings.t(key) : (fallback || key)
  }

  function num(value, decimals) {
    return Commons.I18n.formatNumber(value, decimals || 0)
  }

  function percent(value) {
    return num(Math.round(value * 100)) + "%"
  }

  // A built-in skin's description in the Omarchy language; saved skins keep
  // the words their author wrote.
  function skinDescription(skin) {
    if (!skin) return ""
    if (skin.source !== "builtin") return skin.description || ""
    var key = "skin." + skin.id
    var text = strings ? strings.t(key) : key
    return text && text !== key ? text : (skin.description || "")
  }

  // ---- Status line ---------------------------------------------------------

  Timer {
    id: statusTimer
    interval: 3200
    repeat: false
    onTriggered: root.statusMessage = ""
  }

  function showStatus(msg, isError) {
    statusMessage = msg
    statusError = !!isError
    statusTimer.restart()
  }

  Connections {
    target: root.engine
    function onNotice(key, arg, isError) {
      root.showStatus(root.tr(key).arg(arg), isError)
    }
  }

  onPanelOpenChanged: {
    if (panelOpen) return
    keyboardMode = false
    renamingId = ""
    confirmDeleteId = ""
    pendingPreview = ""
    previewTimer.stop()
    if (engine) engine.clearPreview()
  }

  // ---- Preview -------------------------------------------------------------

  Timer {
    id: previewTimer
    interval: 160
    repeat: false
    onTriggered: {
      if (!root.engine) return
      if (root.pendingPreview !== "" && root.activeTab === "presets") root.engine.previewById(root.pendingPreview, root.screenTarget)
      else root.engine.clearPreview()
    }
  }

  function hoverPreview(id, on) {
    if (on) pendingPreview = id
    else if (pendingPreview === id) pendingPreview = ""
    previewTimer.restart()
  }

  function setTab(tab) {
    if (activeTab === tab) return
    activeTab = tab
    pendingPreview = ""
    previewTimer.restart()
    body.contentY = 0
  }

  // ---- Choosing and managing skins -------------------------------------------

  function pickSkin(id) {
    if (!engine) return
    pendingPreview = ""
    previewTimer.stop()
    if (screenTarget === "") engine.selectSkin(id)
    else engine.selectForScreen(screenTarget, id)
  }

  function chosenId() {
    if (!engine) return ""
    engine.revision
    return engine.chosenIdFor(screenTarget)
  }

  Timer {
    id: confirmTimer
    interval: 3000
    repeat: false
    onTriggered: root.confirmDeleteId = ""
  }

  function requestDelete(id, name) {
    if (!engine) return
    if (confirmDeleteId === id) {
      confirmDeleteId = ""
      engine.deleteUserSkin(id)
      return
    }
    confirmDeleteId = id
    confirmTimer.restart()
    showStatus(tr("status.confirmDelete").arg(name), true)
  }

  function startRename(id) {
    confirmDeleteId = ""
    renamingId = id
  }

  function finishRename(id, text, commit) {
    if (renamingId !== id) return
    renamingId = ""
    if (commit && engine) {
      var slug = engine.renameUserSkin(id, text)
      if (slug) restoreKey = "card:" + slug
      for (var i = 0; i < navItems.length; i++) {
        if (navItems[i].navKey === restoreKey) {
          navCurrent = navItems[i]
          restoreKey = ""
        }
      }
    }
    restoreKeys()
  }

  function restoreKeys() {
    if (keyTarget) Qt.callLater(function() { if (root.keyTarget) root.keyTarget.forceActiveFocus() })
  }

  // ---- Keyboard cursor -------------------------------------------------------

  // A card rebuilt under the cursor (saved skins reload, a rename gives it a
  // new id) takes the cursor back by its key.
  property string restoreKey: ""

  function registerNav(item) {
    if (navItems.indexOf(item) < 0) navItems = navItems.concat([item])
    if (restoreKey !== "" && item.navKey === restoreKey) {
      navCurrent = item
      restoreKey = ""
    }
  }

  function unregisterNav(item) {
    var i = navItems.indexOf(item)
    if (i >= 0) {
      var next = navItems.slice()
      next.splice(i, 1)
      navItems = next
    }
    if (navCurrent === item) {
      navCurrent = null
      if (restoreKey === "") restoreKey = item.navKey
    }
  }

  // Visible rows in reading order, with their centers.
  function visibleNav() {
    var out = []
    for (var i = 0; i < navItems.length; i++) {
      var item = navItems[i]
      if (!item || !item.visible || !item.navEnabled || item.width <= 0 || item.height <= 0) continue
      var p = item.mapToItem(root, item.width / 2, item.height / 2)
      out.push({ item: item, x: p.x, y: p.y })
    }
    out.sort(function(a, b) { return Math.abs(a.y - b.y) > 6 ? a.y - b.y : a.x - b.x })
    return out
  }

  function setCurrent(item) {
    navCurrent = item
    if (!item) return
    ensureVisible(item)
    hoverPreview(item.navPreviewId, item.navPreviewId !== "")
  }

  function navMove(dx, dy) {
    keyboardMode = true
    var list = visibleNav()
    if (list.length === 0) return
    var idx = -1
    for (var i = 0; i < list.length; i++) if (list[i].item === navCurrent) idx = i
    if (idx < 0) {
      setCurrent(list[0].item)
      return
    }
    var cur = list[idx]
    if (dy !== 0) {
      var rowGap = Infinity
      for (var j = 0; j < list.length; j++) {
        var d = (list[j].y - cur.y) * dy
        if (d > 6 && d < rowGap) rowGap = d
      }
      if (rowGap === Infinity) return
      var best = null
      for (var k = 0; k < list.length; k++) {
        var dk = (list[k].y - cur.y) * dy
        if (Math.abs(dk - rowGap) > 6) continue
        if (!best || Math.abs(list[k].x - cur.x) < Math.abs(best.x - cur.x)) best = list[k]
      }
      if (best) setCurrent(best.item)
    } else if (dx !== 0) {
      if (cur.item.navGrid) {
        var n = list[idx + dx]
        if (n) setCurrent(n.item)
      } else {
        cur.item.adjust(dx)
      }
    }
  }

  function navActivate() {
    keyboardMode = true
    if (navCurrent && navCurrent.visible) navCurrent.activate()
    else navMove(0, 1)
  }

  function navDelete() {
    if (navCurrent) navCurrent.remove()
  }

  function navText(t) {
    if (t === "1") { setTab("presets"); return }
    if (t === "2") { setTab("craft"); return }
    if (navCurrent) navCurrent.textKey(t)
  }

  function isInside(item, ancestor) {
    for (var p = item; p; p = p.parent) if (p === ancestor) return true
    return false
  }

  function ensureVisible(item) {
    if (!isInside(item, bodyColumn)) return
    var p = item.mapToItem(bodyColumn, 0, 0)
    var top = p.y - Style.space(8)
    var bottom = p.y + item.height + Style.space(8)
    if (top < body.contentY) body.contentY = Math.max(0, top)
    else if (bottom > body.contentY + body.height) body.contentY = Math.min(Math.max(0, body.contentHeight - body.height), bottom - body.height)
  }

  // The pointer moving takes the keyboard cursor away.
  HoverHandler {
    onPointChanged: {
      var p = point.scenePosition
      if (root.keyboardMode && (Math.abs(p.x - root.lastPointer.x) > 4 || Math.abs(p.y - root.lastPointer.y) > 4)) root.keyboardMode = false
      root.lastPointer = Qt.point(p.x, p.y)
    }
  }

  // ---- Header ----------------------------------------------------------------

  PanelHero {
    id: hero
    width: parent.width
    foreground: root.fg
    title: root.tr("title", "Barcraft")
    meta: {
      if (!root.engine) return ""
      root.engine.revision
      if (root.engine.previewing) return root.tr("meta.preview").arg(root.engine.previewSkin.name)
      var name = root.engine.committedSkin.name
      if (root.engine.usingThemeSkin) return root.tr("meta.theme").arg(name)
      if (root.engine.hasCustomDraft) return root.tr("meta.custom").arg(name)
      return root.tr("meta.preset").arg(name)
    }
    iconComponent: Component {
      Text {
        textFormat: Text.PlainText
        text: "󰇈"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }
    }
    trailingControl: Component {
      NavItem {
        navKey: "tabs"
        implicitWidth: tabGroup.implicitWidth
        implicitHeight: tabGroup.implicitHeight
        width: implicitWidth
        height: implicitHeight
        onAdjust: function(direction) { root.setTab(root.activeTab === "presets" ? "craft" : "presets") }
        onActivate: root.setTab(root.activeTab === "presets" ? "craft" : "presets")

        ButtonGroup {
          id: tabGroup
          focusable: false
          foreground: root.fg
          value: root.activeTab
          options: [
            { value: "presets", label: root.tr("tab.presets", "Skins") },
            { value: "craft", label: root.tr("tab.craft", "Craft") }
          ]
          onChanged: function(v) { root.setTab(v) }
        }
      }
    }
  }

  PanelSeparator {
    id: heroSeparator
    width: parent.width
    foreground: root.fg
  }

  // ---- Body (scrolls) -------------------------------------------------------

  Flickable {
    id: body
    readonly property real chrome: hero.height + heroSeparator.height
      + (footer.visible ? footer.implicitHeight + root.spacing : 0)
      + (statusText.visible ? statusText.implicitHeight + root.spacing : 0)
      + (keysHint.visible ? keysHint.implicitHeight + root.spacing : 0)
      + root.spacing * 2
    width: parent.width
    height: Math.max(Style.space(140), Math.min(bodyColumn.implicitHeight, root.maxHeight - chrome))
    contentWidth: width
    contentHeight: bodyColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: bodyColumn
      width: body.width
      spacing: Style.spacing.panelGap

      // ======================================================================
      // SKINS
      // ======================================================================
      Column {
        width: parent.width
        spacing: Style.spacing.panelGap
        visible: root.activeTab === "presets" && !!root.engine

        // Per-screen skins, when there is more than one screen.
        Column {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.screenNames.length > 1

          ChoiceRow {
            navKey: "screens"
            label: root.tr("label.applyTo", "Apply to")
            value: root.screenTarget === "" ? "*all*" : root.screenTarget
            options: {
              var out = [{ value: "*all*", label: root.tr("screens.all", "All screens") }]
              for (var i = 0; i < root.screenNames.length; i++) out.push({ value: root.screenNames[i], label: root.screenNames[i] })
              return out
            }
            onPicked: function(v) {
              root.screenTarget = v === "*all*" ? "" : v
              root.pendingPreview = ""
              previewTimer.restart()
            }
          }

          RowLayout {
            width: parent.width
            visible: root.screenTarget !== ""
            spacing: Style.spacing.md

            HintText {
              Layout.fillWidth: true
              text: root.tr("hint.screenSkin", "")
            }

            ActionButton {
              navKey: "useMain"
              visible: !!root.engine && (root.engine.revision, root.engine.hasMonitorSkin(root.screenTarget))
              text: root.tr("action.useMain", "Use main skin")
              onTriggered: if (root.engine) root.engine.selectForScreen(root.screenTarget, "")
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader {
            foreground: root.fg
            text: root.tr("section.builtin", "Classic")
          }

          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.md

            SkinCard {
              visible: !!root.engine && root.engine.themeSkin !== null
              width: Math.floor((parent.width - Style.spacing.md) / 2)
              cardId: "theme"
              skinData: root.engine ? root.engine.themeSkin : null
              title: root.tr("card.theme", "Theme skin")
              subtitle: root.engine && root.engine.themeSkin ? root.engine.themeSkin.name : ""
            }

            Repeater {
              model: root.engine ? root.engine.classicSkins : []

              SkinCard {
                required property var modelData
                width: Math.floor((parent.width - Style.spacing.md) / 2)
                cardId: modelData.id
                skinData: modelData
                title: modelData.name
                subtitle: root.skinDescription(modelData)
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        Column {
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader {
            foreground: root.fg
            text: root.tr("section.wild", "Wild Craft")
          }

          Repeater {
            model: root.engine ? root.engine.wildSkins : []

            SkinCard {
              required property var modelData
              width: parent.width
              wide: true
              cardId: modelData.id
              skinData: modelData
              title: modelData.name
              subtitle: root.skinDescription(modelData)
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        // Saved skins (~/.config/omarchy/bar-skins/*.toml)
        Column {
          width: parent.width
          spacing: Style.spacing.md

          RowLayout {
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              Layout.fillWidth: true
              foreground: root.fg
              text: root.tr("section.user", "Your skins")
            }

            ActionButton {
              navKey: "pasteSkins"
              text: root.tr("action.paste", "Paste skin")
              iconText: "󰆒"
              onTriggered: if (root.engine) root.engine.importFromClipboard()
            }
          }

          HintText {
            width: parent.width
            visible: !!root.engine && root.engine.userSkins.length === 0
            text: root.tr("hint.noUserSkins", "")
          }

          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.md
            visible: !!root.engine && root.engine.userSkins.length > 0

            Repeater {
              model: root.engine ? root.engine.userSkins : []

              SkinCard {
                required property var modelData
                width: Math.floor((parent.width - Style.spacing.md) / 2)
                cardId: modelData.id
                skinData: modelData
                title: modelData.name
                subtitle: root.skinDescription(modelData)
                userSkin: true
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.fg
          visible: root.screenTarget === ""
        }

        ToggleRow {
          navKey: "followTheme"
          visible: root.screenTarget === ""
          label: root.tr("label.followTheme", "Follow theme skin")
          hint: root.tr("label.followThemeHint", "")
          checked: root.engine ? root.engine.followTheme : true
          onToggled: if (root.engine) root.engine.setFollowTheme(!root.engine.followTheme)
        }
      }

      // ======================================================================
      // CRAFT
      // ======================================================================
      Column {
        width: parent.width
        spacing: Style.spacing.panelGap
        visible: root.activeTab === "craft" && !!root.engine

        Section {
          separated: false
          title: root.tr("section.mode", "Architecture")

          ChoiceRow {
            navKey: "mode"
            value: root.engine ? root.engine.mode : "floating"
            options: [
              { value: "edge", label: root.tr("mode.edge", "Edge") },
              { value: "floating", label: root.tr("mode.floating", "Floating") },
              { value: "islands", label: root.tr("mode.islands", "Islands") }
            ]
            onPicked: function(v) { root.engine.updateField("mode", v) }
          }
        }

        Section {
          title: root.tr("section.art", "Craft Art")

          ChoiceRow {
            navKey: "art"
            value: root.engine ? root.engine.art : "none"
            options: [
              { value: "none", label: root.tr("art.none", "Clean") },
              { value: "barber", label: root.tr("art.barber", "Barber") },
              { value: "runeforge", label: root.tr("art.runeforge", "Runeforge") },
              { value: "rocket", label: root.tr("art.rocket", "Rocket") }
            ]
            onPicked: function(v) { root.engine.updateField("art", v) }
          }

          ToggleRow {
            navKey: "themeTint"
            visible: !!root.engine && root.engine.hasArt
            label: root.tr("label.themeTint", "Tint art with theme")
            hint: root.tr("label.themeTintHint", "")
            checked: root.engine ? root.engine.themeTint : false
            onToggled: root.engine.updateField("themeTint", !root.engine.themeTint)
          }
        }

        Section {
          title: root.tr("section.color", "Colors")

          ChoiceRow {
            navKey: "fill"
            label: root.tr("label.fill", "Fill")
            value: root.engine ? root.engine.fill : "solid"
            options: [
              { value: "solid", label: root.tr("fill.solid", "Solid") },
              { value: "gradient", label: root.tr("fill.gradient", "Gradient") }
            ]
            onPicked: function(v) {
              root.engine.updateField("fill", v)
              if (v === "gradient") root.colorTarget = "gradient"
              else if (root.colorTarget === "gradient") root.colorTarget = "surface"
            }
          }

          ChoiceRow {
            navKey: "colorTarget"
            label: root.tr("label.colorTarget", "Paint")
            value: root.colorTarget
            options: {
              var out = [
                { value: "surface", label: root.tr("colorTarget.surface", "Surface") },
                { value: "foreground", label: root.tr("colorTarget.foreground", "Icons") },
                { value: "accent", label: root.tr("colorTarget.accent", "Accent") }
              ]
              if (root.engine && root.engine.fill === "gradient") out.push({ value: "gradient", label: root.tr("colorTarget.gradient", "Blend") })
              return out
            }
            onPicked: function(v) { root.colorTarget = v }
          }

          NavItem {
            id: colorNav
            navKey: "color"
            width: parent.width
            implicitHeight: picker.implicitHeight
            height: implicitHeight
            onAdjust: function(direction) { picker.stepSwatch(direction) }
            onActivate: picker.pickerExpanded = !picker.pickerExpanded

            readonly property string field: root.colorTarget === "foreground" ? "customForeground"
              : (root.colorTarget === "accent" ? "customAccent"
                : (root.colorTarget === "gradient" ? "gradientTo" : "customBackground"))
            readonly property string value: !root.engine ? "" : (root.colorTarget === "foreground" ? root.engine.customForeground
              : (root.colorTarget === "accent" ? root.engine.customAccent
                : (root.colorTarget === "gradient" ? root.engine.gradientTo : root.engine.customBackground)))

            ColorPickerField {
              id: picker
              width: parent.width
              strings: root.strings
              foreground: root.fg
              dimForeground: root.dimFg
              themePalette: root.engine ? root.engine.themePalette : []
              resetLabel: root.colorTarget === "foreground" || root.colorTarget === "gradient"
                ? root.tr("color.auto", "Auto") : root.tr("color.theme", "Theme")
              currentValue: colorNav.value
              resolvedColor: {
                if (!root.engine || colorNav.value === "") return fallbackColor
                root.engine.themeColors
                var hex = root.engine.resolveColorRef(colorNav.value)
                return hex !== "" ? Qt.color(hex) : fallbackColor
              }
              fallbackColor: {
                if (!root.engine) return Commons.Color.bar.background
                if (root.colorTarget === "foreground") return root.engine.effectiveForeground
                if (root.colorTarget === "accent" || root.colorTarget === "gradient") return root.engine.resolvedAccent
                return Commons.Color.bar.background
              }
              onColorPicked: function(value) { root.engine.updateField(colorNav.field, value) }
            }
          }
        }

        Section {
          title: root.tr("section.bezel", "Bezel")

          ChoiceRow {
            navKey: "bezel"
            value: root.engine ? root.engine.bezel : "none"
            options: [
              { value: "none", label: root.tr("bezel.none", "Flat") },
              { value: "raised", label: root.tr("bezel.raised", "Raised") },
              { value: "inset", label: root.tr("bezel.inset", "Inset") },
              { value: "ridge", label: root.tr("bezel.ridge", "Ridge") },
              { value: "glass", label: root.tr("bezel.glass", "Glass") }
            ]
            onPicked: function(v) { root.engine.updateField("bezel", v) }
          }

          SliderRow {
            navKey: "bezelStrength"
            visible: !!root.engine && root.engine.bezel !== "none"
            label: root.tr("label.bezelStrength", "Bezel depth")
            valueText: root.percent(root.engine ? root.engine.bezelStrength : 0.75)
            minimum: 0.2
            maximum: 1.0
            step: 0.05
            integer: false
            value: root.engine ? root.engine.bezelStrength : 0.75
            onChangedValue: function(v) { root.engine.updateField("bezelStrength", v) }
          }
        }

        Section {
          title: root.tr("section.geometry", "Geometry")

          SliderRow {
            navKey: "height"
            label: root.tr("label.height", "Height")
            valueText: root.num(root.engine ? root.engine.skinHeight : 30) + " px"
            minimum: 22
            maximum: 48
            step: 1
            value: root.engine ? root.engine.skinHeight : 30
            onChangedValue: function(v) { root.engine.updateField("height", Math.round(v)) }
          }

          SliderRow {
            navKey: "edgeMargin"
            visible: !!root.engine && root.engine.mode !== "edge"
            label: root.tr("label.edgeMargin", "Edge gap")
            valueText: root.num(root.engine ? root.engine.edgeMargin : 6) + " px"
            minimum: 0
            maximum: 20
            step: 1
            value: root.engine ? root.engine.edgeMargin : 6
            onChangedValue: function(v) { root.engine.updateField("edgeMargin", Math.round(v)) }
          }

          SliderRow {
            navKey: "sideMargin"
            visible: !!root.engine && root.engine.mode !== "edge"
            label: root.tr("label.sideMargin", "Side margin")
            valueText: root.num(root.engine ? root.engine.sideMargin : 10) + " px"
            minimum: 0
            maximum: 36
            step: 1
            value: root.engine ? root.engine.sideMargin : 10
            onChangedValue: function(v) { root.engine.updateField("sideMargin", Math.round(v)) }
          }

          SliderRow {
            navKey: "radius"
            visible: !!root.engine && root.engine.mode !== "edge"
            label: root.tr("label.radius", "Corners")
            valueText: root.num(root.engine ? root.engine.radius : 10) + " px"
            minimum: 0
            maximum: 24
            step: 1
            value: root.engine ? root.engine.radius : 10
            onChangedValue: function(v) { root.engine.updateField("radius", Math.round(v)) }
          }

          SliderRow {
            navKey: "iconScale"
            label: root.tr("label.iconScale", "Icon size")
            valueText: root.percent(root.engine ? root.engine.iconScale : 1)
            minimum: 0.8
            maximum: 1.5
            step: 0.05
            integer: false
            value: root.engine ? root.engine.iconScale : 1
            onChangedValue: function(v) { root.engine.updateField("iconScale", v) }
          }
        }

        Section {
          title: root.tr("section.surface", "Surface")

          SliderRow {
            navKey: "opacity"
            label: root.tr("label.opacity", "Opacity")
            valueText: root.percent(root.engine ? root.engine.backgroundAlpha : 0.92)
            minimum: 0.1
            maximum: 1.0
            step: 0.02
            integer: false
            value: root.engine ? root.engine.backgroundAlpha : 0.92
            onChangedValue: function(v) { root.engine.updateField("backgroundAlpha", v) }
          }

          SliderRow {
            navKey: "surfaceTone"
            label: root.tr("label.surfaceTone", "Surface depth")
            valueText: root.percent(root.engine ? root.engine.surfaceTone : 1)
            minimum: 0.5
            maximum: 1.5
            step: 0.05
            integer: false
            value: root.engine ? root.engine.surfaceTone : 1
            onChangedValue: function(v) { root.engine.updateField("surfaceTone", v) }
          }

          SliderRow {
            navKey: "contrast"
            label: root.tr("label.contrast", "Text contrast")
            valueText: root.percent(root.engine ? root.engine.contrast : 1)
            minimum: 0.5
            maximum: 1.5
            step: 0.05
            integer: false
            value: root.engine ? root.engine.contrast : 1
            onChangedValue: function(v) { root.engine.updateField("contrast", v) }
          }

          ChoiceRow {
            navKey: "border"
            label: root.tr("label.borderRole", "Border")
            value: root.engine ? root.engine.borderRole : "subtle"
            options: [
              { value: "none", label: root.tr("border.none", "None") },
              { value: "subtle", label: root.tr("border.subtle", "Subtle") },
              { value: "accent", label: root.tr("border.accent", "Accent") },
              { value: "hyprland", label: root.tr("border.hyprland", "Hyprland") }
            ]
            onPicked: function(v) {
              root.engine.updateField("border", v)
              if (v !== "none" && root.engine.borderWidth === 0) root.engine.updateField("borderWidth", 1)
            }
          }

          ChoiceRow {
            navKey: "widgetStyle"
            label: root.tr("label.widgetStyle", "Widgets")
            value: root.engine ? root.engine.widgetStyle : "plain"
            options: [
              { value: "plain", label: root.tr("widgetStyle.plain", "Plain") },
              { value: "pills", label: root.tr("widgetStyle.pills", "Pills") },
              { value: "chips", label: root.tr("widgetStyle.chips", "Chips") }
            ]
            onPicked: function(v) { root.engine.updateField("widgetStyle", v) }
          }

          ToggleRow {
            navKey: "shadow"
            label: root.tr("label.shadow", "Shadow")
            hint: root.tr("label.shadowHint", "")
            checked: root.engine ? root.engine.shadow : false
            onToggled: root.engine.updateField("shadow", !root.engine.shadow)
          }

          SliderRow {
            navKey: "shadowStrength"
            visible: !!root.engine && root.engine.shadow
            label: root.tr("label.shadowStrength", "Shadow depth")
            valueText: root.percent(root.engine ? root.engine.shadowStrength : 0.5)
            minimum: 0.1
            maximum: 1.0
            step: 0.05
            integer: false
            value: root.engine ? root.engine.shadowStrength : 0.5
            onChangedValue: function(v) { root.engine.updateField("shadowStrength", v) }
          }

          ToggleRow {
            navKey: "blur"
            label: root.tr("label.blur", "Glass blur")
            hint: root.tr("label.blurHint", "")
            checked: root.engine ? root.engine.blurActive : false
            onToggled: root.engine.setBlur(!root.engine.blurActive)
          }
        }

        Section {
          title: root.tr("section.behavior", "Behavior")

          ToggleRow {
            navKey: "autoHide"
            label: root.tr("label.autoHide", "Auto-hide")
            hint: root.tr("label.autoHideHint", "")
            checked: root.engine ? root.engine.autoHide : false
            onToggled: root.engine.toggleAutoHide()
          }

          HintText {
            width: parent.width
            text: root.tr("hint.behavior", "")
          }

          ChoiceRow {
            navKey: "autohideWhen"
            visible: !!root.engine && root.engine.autoHide
            label: root.tr("label.autohideWhen", "Hide")
            value: root.engine ? root.engine.prefs.autohideWhen : "always"
            options: [
              { value: "always", label: root.tr("autohideWhen.always", "Always") },
              { value: "windows", label: root.tr("autohideWhen.windows", "Only with windows") }
            ]
            onPicked: function(v) { root.engine.setPref("autohideWhen", v) }
          }

          SliderRow {
            navKey: "autohideDelay"
            visible: !!root.engine && root.engine.autoHide
            label: root.tr("label.autohideDelay", "Hide after")
            valueText: root.num(root.engine ? root.engine.prefs.autohideDelay : 320) + " ms"
            minimum: 100
            maximum: 2000
            step: 50
            value: root.engine ? root.engine.prefs.autohideDelay : 320
            onChangedValue: function(v) { root.engine.setPref("autohideDelay", Math.round(v)) }
          }

          ToggleRow {
            navKey: "revealOnWorkspace"
            visible: !!root.engine && root.engine.autoHide
            label: root.tr("label.revealOnWorkspace", "Peek on workspace switch")
            hint: root.tr("label.revealOnWorkspaceHint", "")
            checked: root.engine ? root.engine.prefs.revealOnWorkspace : false
            onToggled: root.engine.setPref("revealOnWorkspace", !root.engine.prefs.revealOnWorkspace)
          }
        }
      }
    }
  }

  // ---- Footer: stays put while the Craft body scrolls -------------------------

  Column {
    id: footer
    width: parent.width
    spacing: Style.spacing.md
    visible: root.activeTab === "craft" && !!root.engine

    PanelSeparator {
      width: parent.width
      foreground: root.fg
    }

    RowLayout {
      width: parent.width
      spacing: Style.spacing.md

      NavItem {
        navKey: "skinName"
        Layout.fillWidth: true
        implicitHeight: nameInput.implicitHeight
        Layout.preferredHeight: implicitHeight
        onActivate: nameInput.forceActiveFocus()
        onTextKey: function(t) { nameInput.forceActiveFocus(); nameInput.insert(nameInput.length, t) }

        TextField {
          id: nameInput
          anchors.fill: parent
          placeholderText: root.tr("placeholder.skinName", "Save as skin name…")
          text: root.saveNameText
          maximumLength: 40
          onTextChanged: root.saveNameText = text
          onAccepted: {
            saveButton.save()
            root.restoreKeys()
          }
          Keys.onEscapePressed: function(event) {
            event.accepted = true
            root.restoreKeys()
          }
        }
      }

      ActionButton {
        id: saveButton
        navKey: "save"
        text: root.tr("action.save", "Save")
        selected: root.saveNameText.trim().length > 0
        onTriggered: save()

        function save() {
          if (!root.engine) return
          root.engine.saveUserSkin(root.saveNameText || root.engine.committedSkin.name)
          root.saveNameText = ""
        }
      }
    }

    RowLayout {
      width: parent.width
      spacing: Style.spacing.md

      ActionButton {
        navKey: "copy"
        text: root.tr("action.copyToml", "Copy TOML")
        iconText: "󰆏"
        onTriggered: if (root.engine) root.engine.copyActiveToml()
      }

      ActionButton {
        navKey: "paste"
        text: root.tr("action.paste", "Paste skin")
        iconText: "󰆒"
        onTriggered: if (root.engine) root.engine.importFromClipboard()
      }

      Item { Layout.fillWidth: true }

      ActionButton {
        navKey: "reset"
        text: root.tr("action.reset", "Reset")
        iconText: "󰜉"
        onTriggered: if (root.engine) root.engine.resetToPreset()
      }
    }
  }

  Text {
    id: statusText
    visible: root.statusMessage !== ""
    textFormat: Text.PlainText
    text: root.statusMessage
    color: root.statusError ? Commons.Color.urgent : Commons.Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    width: parent.width
  }

  HintText {
    id: keysHint
    width: parent.width
    visible: root.keyboardMode && root.statusMessage === ""
    text: root.tr("hint.keys", "")
    horizontalAlignment: Text.AlignHCenter
  }

  // ===========================================================================
  // Building blocks
  // ===========================================================================

  // Anything the keyboard cursor can stop on. Rows react to the signals; the
  // cursor draws its ring around whichever one it is on.
  component NavItem: Item {
    id: navItem

    property string navKey: ""
    property bool navEnabled: true
    // Left/Right move between items (cards) rather than adjust this one.
    property bool navGrid: false
    // A skin id to preview on the bar while the cursor rests here.
    property string navPreviewId: ""
    readonly property bool navFocused: root.keyboardMode && root.navCurrent === navItem

    signal adjust(int direction)
    signal activate()
    signal remove()
    signal textKey(string text)

    Component.onCompleted: root.registerNav(navItem)
    Component.onDestruction: root.unregisterNav(navItem)

    Rectangle {
      // Rows as wide as the scrolling body keep the ring inside it, where
      // the body's clip would cut its sides off.
      readonly property real side: navItem.width >= bodyColumn.width - 1 ? 0 : -Style.space(3)
      z: 100
      visible: navItem.navFocused
      anchors.fill: parent
      anchors.topMargin: -Style.space(3)
      anchors.bottomMargin: -Style.space(3)
      anchors.leftMargin: side
      anchors.rightMargin: side
      radius: Style.cornerRadius + Style.space(3)
      color: "transparent"
      border.width: Math.max(1, Style.space(2))
      border.color: Commons.Color.accent
    }
  }

  component Section: Column {
    property string title: ""
    property bool separated: true
    width: parent.width
    spacing: Style.spacing.md

    PanelSeparator {
      visible: parent.separated
      width: parent.width
      foreground: root.fg
    }

    PanelSectionHeader {
      foreground: root.fg
      text: parent.title
    }
  }

  component HintText: Text {
    textFormat: Text.PlainText
    color: root.dimFg
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component ChoiceRow: NavItem {
    id: choice
    property string label: ""
    property string value: ""
    property var options: []
    signal picked(string value)

    width: parent ? parent.width : 0
    implicitHeight: choiceColumn.implicitHeight
    height: implicitHeight

    function indexOfValue() {
      for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
      return -1
    }

    onAdjust: function(direction) {
      if (options.length === 0) return
      var i = indexOfValue()
      var next = i < 0 ? 0 : Math.max(0, Math.min(options.length - 1, i + direction))
      if (next !== i) picked(options[next].value)
    }
    onActivate: {
      if (options.length === 0) return
      picked(options[(indexOfValue() + 1) % options.length].value)
    }

    Column {
      id: choiceColumn
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        visible: choice.label !== ""
        textFormat: Text.PlainText
        text: choice.label
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      ButtonGroup {
        focusable: false
        foreground: root.fg
        value: choice.value
        options: choice.options
        onChanged: function(v) { choice.picked(v) }
      }
    }
  }

  component SliderRow: NavItem {
    id: sRow
    property string label: ""
    property string valueText: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property bool integer: true
    property real value: 0
    signal changedValue(real v)

    width: parent ? parent.width : 0
    implicitHeight: sliderColumn.implicitHeight
    height: implicitHeight

    onAdjust: function(direction) {
      var next = Math.max(minimum, Math.min(maximum, value + step * direction))
      if (integer) next = Math.round(next)
      else next = Math.round(next / step) * step
      if (Math.abs(next - value) > 0.0001) changedValue(next)
    }

    Column {
      id: sliderColumn
      width: parent.width
      spacing: Style.space(2)

      RowLayout {
        width: parent.width
        Text {
          textFormat: Text.PlainText
          text: sRow.label
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          Layout.fillWidth: true
        }
        Text {
          textFormat: Text.PlainText
          text: sRow.valueText
          color: root.dimFg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      PanelSlider {
        width: parent.width
        bar: root.bar
        minimum: sRow.minimum
        maximum: sRow.maximum
        step: sRow.step
        integer: sRow.integer
        value: sRow.value
        onMoved: function(v) { sRow.changedValue(v) }
        onReleased: function(v) { sRow.changedValue(v) }
      }
    }
  }

  component ToggleRow: NavItem {
    id: tRow
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: toggleLayout.implicitHeight
    height: implicitHeight
    onAdjust: function(direction) { if ((direction > 0) !== checked) toggled() }
    onActivate: toggled()

    RowLayout {
      id: toggleLayout
      width: parent.width
      spacing: Style.spacing.md

      Column {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: tRow.label
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: tRow.hint !== ""
          textFormat: Text.PlainText
          text: tRow.hint
          color: root.dimFg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      ToggleSwitch {
        checked: tRow.checked
        foreground: root.fg
        onToggled: tRow.toggled()
      }
    }
  }

  component ActionButton: NavItem {
    id: action
    property string text: ""
    property string iconText: ""
    property bool selected: false
    signal triggered()

    implicitWidth: actionButton.implicitWidth
    implicitHeight: actionButton.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    width: implicitWidth
    height: implicitHeight
    onActivate: triggered()

    Button {
      id: actionButton
      anchors.fill: parent
      text: action.text
      iconText: action.iconText
      selected: action.selected
      bordered: true
      onClicked: action.triggered()
    }
  }

  component SkinCard: NavItem {
    id: card
    property var skinData: null
    property string cardId: ""
    property string title: ""
    property string subtitle: ""
    property bool userSkin: false
    property bool wide: false
    readonly property bool chosen: root.chosenId() === cardId
    readonly property bool hot: cardHover.hovered || navFocused
    readonly property bool renaming: root.renamingId === cardId && userSkin
    readonly property bool confirmingDelete: root.confirmDeleteId === cardId

    navKey: "card:" + cardId
    navGrid: true
    navPreviewId: cardId
    height: wide ? Style.space(62) : Style.space(96)

    onActivate: root.pickSkin(cardId)
    onRemove: if (userSkin) root.requestDelete(cardId, title)
    onTextKey: function(t) { if (userSkin && (t === "r" || t === "R")) root.startRename(cardId) }

    HoverHandler {
      id: cardHover
      cursorShape: Qt.PointingHandCursor
      onHoveredChanged: root.hoverPreview(card.cardId, hovered)
    }

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: card.chosen
        ? Style.selectedFillFor(root.fg, Commons.Color.accent)
        : (card.hot ? Style.hoverFillFor(root.fg, Commons.Color.accent) : Style.normalFillFor(root.fg, Commons.Color.accent))
      borderSpec: Border.controlSpec(card.chosen ? "selected" : (card.hot ? "hover-cursor" : "normal"), root.fg, Commons.Color.accent)

      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: {
        root.keyboardMode = false
        root.navCurrent = card
        root.pickSkin(card.cardId)
      }
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(6)

      SkinThumbnail {
        width: parent.width
        height: card.wide ? Style.space(20) : Style.space(34)
        skin: card.skinData
        paletteMap: root.palette
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        Column {
          Layout.fillWidth: !card.wide
          Layout.preferredWidth: card.wide ? Math.min(titleText.implicitWidth, parent.width * 0.45) : -1
          spacing: Style.space(1)

          Text {
            id: titleText
            visible: !card.renaming
            width: card.wide ? Math.min(implicitWidth, parent.parent.width * 0.45) : parent.width
            textFormat: Text.PlainText
            text: card.title
            color: card.chosen ? Commons.Color.accent : root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          Loader {
            active: card.renaming
            visible: active
            width: parent.width
            sourceComponent: Component {
              TextField {
                text: card.title
                maximumLength: 40
                verticalPadding: Style.space(2)
                Component.onCompleted: {
                  forceActiveFocus()
                  selectAll()
                }
                onAccepted: root.finishRename(card.cardId, text, true)
                onActiveFocusChanged: if (!activeFocus) root.finishRename(card.cardId, text, false)
                Keys.onEscapePressed: function(event) {
                  event.accepted = true
                  root.finishRename(card.cardId, text, false)
                }
              }
            }
          }

          Text {
            visible: !card.wide && !card.renaming
            width: parent.width
            textFormat: Text.PlainText
            text: card.subtitle
            color: root.dimFg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          visible: card.wide
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: card.subtitle
          color: root.dimFg
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        CardIcon {
          visible: card.userSkin && (card.hot || card.confirmingDelete) && !card.renaming
          glyph: "󰏫"
          tip: root.tr("card.rename", "Rename (R)")
          onTriggered: root.startRename(card.cardId)
        }

        CardIcon {
          visible: card.userSkin && (card.hot || card.confirmingDelete) && !card.renaming
          glyph: "󰆴"
          danger: card.confirmingDelete
          tip: root.tr("card.delete", "Delete (Del)")
          onTriggered: root.requestDelete(card.cardId, card.title)
        }
      }
    }
  }

  component CardIcon: Text {
    id: icon
    property string glyph: ""
    property string tip: ""
    property bool danger: false
    signal triggered()

    textFormat: Text.PlainText
    text: glyph
    color: danger ? Commons.Color.urgent : (iconMouse.containsMouse ? Commons.Color.accent : root.dimFg)
    font.family: Style.font.family
    font.pixelSize: Style.font.body

    MouseArea {
      id: iconMouse
      anchors.fill: parent
      anchors.margins: -Style.space(3)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: icon.triggered()
    }

    PanelToolTip {
      visible: iconMouse.containsMouse && icon.tip !== ""
      text: icon.tip
    }
  }
}

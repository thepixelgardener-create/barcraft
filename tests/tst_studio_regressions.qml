import QtQuick
import QtTest
import ".."

Item {
  id: harness
  width: 480
  height: 360

  // Mirrors the real setup: KeyboardPanel loads Studio in a Loader with
  // focus: true, and StudioContent's key catcher is a plain Item with
  // Keys.priority BeforeItem, not a FocusScope. Without restoreKeys(), focus
  // falls back to the Loader and keys never reach the catcher again.
  property bool restoreEnabled: true
  Loader {
    id: contentLoader
    focus: true
    width: 320
    height: 120
    sourceComponent: Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      property int keyHits: 0
      property bool blocked: draftControls.visible && nameField.activeFocus
      property alias draftControls: draftControls
      property alias nameField: nameField
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (blocked) return
        keyHits++
        event.accepted = true
      }

      function restoreKeys() {
        if (harness.restoreEnabled) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }

      Column {
        id: draftControls
        width: parent.width
        visible: true
        onVisibleChanged: {
          if (!visible && nameField.activeFocus) {
            nameField.focus = false
            keyCatcher.restoreKeys()
          }
        }

        LineField {
          id: nameField
          maximumLength: 40
        }
      }
    }
  }

  // Mirrors Bar.qml's bottom/right barStrip positioning with animatedEdgeOffset
  // instead of Behavior on x / y.
  Item {
    id: barSurface
    property string position: "bottom"
    property bool vertical: position === "left" || position === "right"
    property int thickness: 30
    property int edgeGap: 8
    property bool effectivelyHidden: false
    property string settle: ""
    property bool resizeDue: false
    width: 1920
    height: 56

    Item {
      id: barStrip
      property real animatedEdgeOffset: barSurface.effectivelyHidden
        ? -(barSurface.thickness + barSurface.edgeGap + 8)
        : barSurface.edgeGap
      Behavior on animatedEdgeOffset {
        enabled: barSurface.settle === "" && !barSurface.resizeDue
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }
      x: barSurface.vertical
        ? (barSurface.position === "right" ? parent.width - barSurface.thickness - animatedEdgeOffset : animatedEdgeOffset)
        : 0
      y: barSurface.vertical
        ? 0
        : (barSurface.position === "bottom" ? parent.height - barSurface.thickness - animatedEdgeOffset : animatedEdgeOffset)
      width: barSurface.vertical ? barSurface.thickness : parent.width
      height: barSurface.vertical ? parent.height : barSurface.thickness
    }
  }

  BarBezelOverlay {
    id: bezelOverlay
    width: 240
    height: 30
    bezelStyle: "none"
    strength: 0.75
    radius: 8
  }

  TestCase {
    name: "StudioRegressions"
    when: windowShown

    function test_bezelOverlayLoadsCanvasLazilyOnlyWhenActive() {
      bezelOverlay.bezelStyle = "none"
      compare(bezelOverlay.visible, false)
      compare(bezelOverlay.canvasLoaded, false)

      bezelOverlay.bezelStyle = "glass"
      compare(bezelOverlay.visible, true)
      compare(bezelOverlay.canvasLoaded, true)

      bezelOverlay.bezelStyle = "raised"
      compare(bezelOverlay.canvasLoaded, true)

      bezelOverlay.bezelStyle = "none"
      compare(bezelOverlay.visible, false)
      compare(bezelOverlay.canvasLoaded, false)
    }

    // Hides the draft controls while the name field holds focus (Save
    // clicked, the async save completing) and counts keys that still arrive.
    function hideDraftWithFieldFocused(restore) {
      harness.restoreEnabled = restore
      const catcher = contentLoader.item
      catcher.draftControls.visible = true
      catcher.nameField.forceActiveFocus()
      tryCompare(catcher.nameField, "activeFocus", true)
      compare(catcher.blocked, true)
      catcher.draftControls.visible = false
      compare(catcher.nameField.activeFocus, false)
      compare(catcher.blocked, false)
      wait(30)
      const before = catcher.keyHits
      keyClick(Qt.Key_Down)
      return catcher.keyHits - before
    }

    function test_hidingDraftFooterReleasesLineFieldFocusBackToKeyCatcher() {
      compare(hideDraftWithFieldFocused(true), 1)
      verify(contentLoader.item.activeFocus)
    }

    // Control: the same steps without restoreKeys() leave the keyboard dead,
    // so the test above fails if the handback ever stops working.
    function test_withoutRestoreKeysTheKeyboardGoesDead() {
      compare(hideDraftWithFieldFocused(false), 0)
      harness.restoreEnabled = true
      contentLoader.item.forceActiveFocus()
    }

    function test_bottomAndRightBarSurfaceExpandDoesNotSlideStripAcrossDesktop() {
      // Bottom bar: expanding surface from strip height (56) to screen height (1080)
      // must anchor barStrip immediately at the bottom edge with zero animation travel.
      barSurface.position = "bottom"
      barSurface.effectivelyHidden = false
      barSurface.width = 1920
      barSurface.height = 56
      compare(barStrip.y, 56 - 30 - 8)

      barSurface.height = 1080
      compare(barStrip.y, 1080 - 30 - 8)

      barSurface.height = 56
      compare(barStrip.y, 56 - 30 - 8)

      // Right bar: expanding surface from strip width (56) to screen width (1920)
      // must anchor barStrip immediately at the right edge with zero travel.
      barSurface.position = "right"
      barSurface.width = 56
      barSurface.height = 1080
      compare(barStrip.x, 56 - 30 - 8)

      barSurface.width = 1920
      compare(barStrip.x, 1920 - 30 - 8)

      // Auto-hide still animates animatedEdgeOffset smoothly off the right edge.
      barSurface.effectivelyHidden = true
      tryCompare(barStrip, "animatedEdgeOffset", -(30 + 8 + 8), 500)
      compare(barStrip.x, 1920 - 30 + (30 + 8 + 8))
    }
  }
}

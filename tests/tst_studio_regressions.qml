import QtQuick
import QtTest
import ".."

Item {
  id: harness
  width: 480
  height: 360

  // Mirrors StudioContent's keyTarget + hidden draftControls focus handback.
  FocusScope {
    id: keyCatcher
    width: 320
    height: 120
    focus: true
    property int keyHits: 0
    property bool blocked: (draftControls.visible && nameField.activeFocus)
    Keys.onPressed: function(event) {
      if (blocked) return
      keyHits++
      event.accepted = true
    }

    function restoreKeys() {
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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

  TestCase {
    name: "StudioRegressions"
    when: windowShown

    function test_hidingDraftFooterReleasesLineFieldFocusBackToKeyCatcher() {
      draftControls.visible = true
      nameField.forceActiveFocus()
      tryCompare(nameField, "activeFocus", true)
      compare(keyCatcher.blocked, true)

      // Simulates clicking Save with mouse and the async save completing so
      // draftControls hides while nameField still held activeFocus.
      draftControls.visible = false
      compare(nameField.activeFocus, false)
      compare(keyCatcher.blocked, false)
      tryCompare(keyCatcher, "activeFocus", true)

      const before = keyCatcher.keyHits
      keyClick(Qt.Key_Down)
      compare(keyCatcher.keyHits, before + 1)
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

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Zenbook Duo control panel: per-screen brightness, bottom screen on/off,
// auto-off while the keyboard is docked, layout presets, keyboard status.
// All work is done by bin/zenbook-duo; this panel only renders its JSON state.
Panel {
  id: root
  moduleName: "zenbook-duo"
  ipcTarget: "zenbook-duo"

  readonly property string cli: String(Qt.resolvedUrl("bin/zenbook-duo")).replace(/^file:\/\//, "")

  property var st: null
  readonly property bool ready: st !== null
  property int topBrightness: 0
  property int bottomBrightness: 0
  property real wheelAccumulator: 0
  // True while a slider is held, so a background refresh doesn't yank it.
  property bool dragging: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function refresh() { if (!stateProc.running) stateProc.running = true }

  property var queued: []
  function run(args) {
    if (actionProc.running) { root.queued = root.queued.concat([args]); return }
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }
  function runAfter(args) { run(args) }

  function setBrightness(which, value) {
    var v = Math.max(1, Math.min(100, Math.round(value)))
    if (root.st && root.st.link) {
      root.topBrightness = v
      root.bottomBrightness = v
      brightProc.command = [root.cli, "brightness", "--both", "--no-osd", v + "%"]
    } else {
      if (which === "top") root.topBrightness = v
      else root.bottomBrightness = v
      var name = which === "top" ? root.st.top.name : root.st.bottom.name
      brightProc.command = [root.cli, "brightness", "--monitor", name, "--no-osd", v + "%"]
    }
    if (!brightProc.running) brightProc.running = true
  }

  // Where a screen dropped at logical (x, y) should land: touching the nearest
  // other screen edge-to-edge, aligned to its edges or centre when close, and
  // never overlapping. Returns null when there is no valid spot.
  function snapPosition(mon, x, y, mons) {
    var w = mon.w, h = mon.h
    var others = []
    for (var i = 0; i < mons.length; i++)
      if (mons[i].name !== mon.name && mons[i].enabled) others.push(mons[i])
    if (others.length === 0) return { x: Math.round(x), y: Math.round(y) }

    function overlaps(cx, cy) {
      for (var j = 0; j < others.length; j++) {
        var o = others[j]
        if (cx < o.x + o.w && cx + w > o.x && cy < o.y + o.h && cy + h > o.y) return true
      }
      return false
    }
    // Slide along the edge shared with o (staying in contact), then snap to the
    // nearest edge or centre line of ANY other screen within a threshold.
    function along(pos, size, oPos, oSize, horizontal) {
      var lo = oPos - size + 1, hi = oPos + oSize - 1
      var v = Math.max(lo, Math.min(pos, hi))
      var threshold = 0.12 * size
      var bestT = v, bestDist = threshold
      for (var q = 0; q < others.length; q++) {
        var s = horizontal ? others[q].x : others[q].y
        var e = s + (horizontal ? others[q].w : others[q].h)
        var targets = [s, e - size, s + (e - s - size) / 2, e, s - size]
        for (var t = 0; t < targets.length; t++) {
          var tv = targets[t]
          if (tv < lo || tv > hi) continue  // would lose contact with o
          var dist = Math.abs(tv - v)
          if (dist < bestDist) { bestDist = dist; bestT = tv }
        }
      }
      return bestT
    }

    var best = null, bestD = Infinity
    function consider(cx, cy) {
      cx = Math.round(cx); cy = Math.round(cy)
      if (overlaps(cx, cy)) return
      var d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
      if (d < bestD) { bestD = d; best = { x: cx, y: cy } }
    }
    for (var n = 0; n < others.length; n++) {
      var o = others[n]
      var ay = along(y, h, o.y, o.h, false), ax = along(x, w, o.x, o.w, true)
      consider(o.x + o.w, ay)  // right of o
      consider(o.x - w, ay)    // left of o
      consider(ax, o.y + o.h)  // below o
      consider(ax, o.y - h)    // above o
    }
    return best
  }

  function keyboardStatus() {
    if (!ready) return ""
    var kb = st.keyboard
    if (kb.docked) return strings.t("keyboard.docked")
    if (kb.connected) {
      return kb.battery !== null && kb.battery !== undefined
        ? strings.t("keyboard.bluetoothBattery").arg(Commons.I18n.formatNumber(kb.battery))
        : strings.t("keyboard.bluetooth")
    }
    if (!kb.paired) return strings.t("keyboard.notPaired")
    return strings.t("keyboard.disconnected")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: [root.cli, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || ""))
          root.st = parsed
          if (!root.dragging && parsed.top.brightness !== null) root.topBrightness = parsed.top.brightness
          if (!root.dragging && parsed.bottom.brightness !== null) root.bottomBrightness = parsed.bottom.brightness
        } catch (e) {
          console.warn("zenbook-duo: bad state output")
        }
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      if (root.queued.length > 0) {
        var next = root.queued[0]
        root.queued = root.queued.slice(1)
        root.run(next)
        return
      }
      root.refresh()
    }
  }

  Process {
    id: brightProc
    stdout: StdioCollector { waitForEnd: true }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍺"
    tooltipText: strings.t("title")
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var step = Math.abs(wheel.steps * 5) + "%"
      Quickshell.execDetached([root.cli, "brightness", wheel.steps > 0 ? "+" + step : step + "-"])
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      implicitHeight: col.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        // Only scroll when the content is taller than the panel, so dragging a
        // screen in the arrangement view is not taken over by the flickable.
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: col.implicitHeight > scrollArea.height && !root.dragging
        }

        Column {
          id: col
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰍺"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroText
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: strings.t("title")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                width: parent.width
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                text: root.keyboardStatus().toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                width: parent.width
                elide: Text.ElideRight
              }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator { foreground: root.bar.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(brightHeader.implicitHeight, linkRow.implicitHeight)

            PanelSectionHeader {
              id: brightHeader
              text: strings.t("brightness")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: linkRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: strings.t("linkBoth")
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                trackHeight: 18
                cursorRing: false
                checked: root.ready && root.st.link
                foreground: root.bar.foreground
                anchors.verticalCenter: parent.verticalCenter
                onToggled: root.run(["link", checked ? "off" : "on"])
              }
            }
          }

          BrightnessRow {
            id: topRow
            label: strings.t("topScreen")
            value: root.topBrightness
            sliderEnabled: root.ready && root.st.top.brightness !== null
            onChanged: function(v) { root.setBrightness("top", v) }
          }

          BrightnessRow {
            id: bottomRow
            label: strings.t("bottomScreen")
            value: root.bottomBrightness
            sliderEnabled: root.ready && root.st.bottom.enabled && root.st.bottom.brightness !== null
            onChanged: function(v) { root.setBrightness("bottom", v) }
          }

          // ---------- Bottom screen ----------
          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: strings.t("bottomScreen")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            label: strings.t("bottomOn")
            description: root.ready && !root.st.bottom.enabled && root.st.keyboard.docked && root.st.auto
              ? strings.t("bottomOffDocked") : ""
            checked: root.ready && root.st.bottom.enabled
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.run(["bottom", checked ? "off" : "on"])
          }

          Toggle {
            width: parent.width
            label: strings.t("autoOff")
            description: strings.t("autoOffDescription")
            checked: root.ready && root.st.auto
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.run(["auto", checked ? "off" : "on"])
          }

          // ---------- Layout ----------
          PanelSeparator { foreground: root.bar.foreground }

          Item {
            width: parent.width
            implicitHeight: layoutHeader.implicitHeight

            PanelSectionHeader {
              id: layoutHeader
              text: strings.t("layout")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
            }

            Text {
              textFormat: Text.PlainText
              visible: root.ready && root.st.layout === "custom"
              text: strings.t("layoutCustom").toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: layoutHeader.verticalCenter
            }
          }

          Grid {
            id: layoutGrid
            width: parent.width
            columns: 3
            spacing: Style.spacing.xs
            readonly property real cellWidth: (width - spacing * 2) / 3

            Repeater {
              model: [
                { id: "stacked", icon: "󰍺", key: "layoutStacked" },
                { id: "side", icon: "󰍹", key: "layoutSide" },
                { id: "top-only", icon: "󰹑", key: "layoutTopOnly" }
              ]

              Button {
                required property var modelData
                width: layoutGrid.cellWidth
                text: strings.t(modelData.key)
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.sm
                bordered: true
                active: root.ready && root.st.layout === modelData.id
                onClicked: root.run(["layout", modelData.id])
              }
            }
          }

          // ---------- External monitor side (used by the presets) ----------
          Item {
            width: parent.width
            implicitHeight: extLabel.implicitHeight
            visible: extGrid.visible

            Text {
              id: extLabel
              textFormat: Text.PlainText
              text: strings.t("externalSide")
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
            }
          }

          Grid {
            id: extGrid
            width: parent.width
            columns: 4
            spacing: Style.spacing.xs
            visible: root.ready && root.st.monitors && root.st.monitors.some(function(m) { return !m.internal })
            readonly property real cellWidth: (width - spacing * 3) / 4

            Repeater {
              model: [
                { id: "above", key: "sideAbove" },
                { id: "left", key: "sideLeft" },
                { id: "right", key: "sideRight" },
                { id: "below", key: "sideBelow" }
              ]

              Button {
                required property var modelData
                width: extGrid.cellWidth
                text: strings.t(modelData.key)
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.xs
                bordered: true
                active: root.ready && root.st.layout !== "custom" && root.st.external === modelData.id
                onClicked: {
                  // Picking a side means "use the preset", so leave a custom layout.
                  if (root.st.layout === "custom") root.run(["layout", "stacked"])
                  root.runAfter(["external", modelData.id])
                }
              }
            }
          }

          // ---------- Arrangement (drag screens, like Windows display settings) ----------
          Text {
            textFormat: Text.PlainText
            visible: arrangeView.visible
            text: strings.t("arrangeHint")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Item {
            id: arrangeView
            width: parent.width
            height: Style.space(180)
            visible: mons.length > 1

            readonly property var mons: root.ready && root.st.monitors ? root.st.monitors : []
            // Bounding box of all screens, in Hyprland logical pixels.
            readonly property var box: {
              if (mons.length === 0) return { x: 0, y: 0, w: 1, h: 1 }
              var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
              for (var i = 0; i < mons.length; i++) {
                var m = mons[i]
                x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y)
                x1 = Math.max(x1, m.x + m.w); y1 = Math.max(y1, m.y + m.h)
              }
              return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
            }
            // Leave room around the box so a screen can be dragged past the edge.
            readonly property real k: Math.min(width / (box.w * 1.6), height / (box.h * 1.6))
            readonly property real ox: (width - box.w * k) / 2
            readonly property real oy: (height - box.h * k) / 2

            Rectangle {
              anchors.fill: parent
              color: "transparent"
              radius: Style.cornerRadius
              border.width: 1
              border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.2)
            }

            Repeater {
              model: arrangeView.mons

              Rectangle {
                id: tile
                required property var modelData
                readonly property bool isTop: modelData.name === (root.st ? root.st.top.name : "")
                readonly property bool isBottom: modelData.name === (root.st ? root.st.bottom.name : "")
                readonly property bool isFocused: root.ready && root.st.focused === modelData.name

                x: arrangeView.ox + (modelData.x - arrangeView.box.x) * arrangeView.k
                y: arrangeView.oy + (modelData.y - arrangeView.box.y) * arrangeView.k
                width: modelData.w * arrangeView.k
                height: modelData.h * arrangeView.k
                z: drag.active ? 2 : 1
                radius: Math.min(Style.cornerRadius, 4)
                opacity: modelData.enabled ? 1 : 0.4
                color: drag.active || dragHover.hovered
                  ? Style.selectedFillFor(root.bar.foreground, Commons.Color.accent)
                  : Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
                border.width: isFocused ? 2 : 1
                border.color: isFocused ? Commons.Color.accent : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.5)

                Column {
                  anchors.centerIn: parent
                  width: parent.width - 4
                  spacing: 0

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: tile.isTop ? strings.t("topScreen") : tile.isBottom ? strings.t("bottomScreen") : tile.modelData.name
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: tile.height > Style.space(36)
                    text: tile.modelData.enabled ? tile.modelData.w + "×" + tile.modelData.h : strings.t("off")
                    color: Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                HoverHandler { id: dragHover; cursorShape: tile.modelData.enabled ? Qt.OpenHandCursor : Qt.ArrowCursor }

                DragHandler {
                  id: drag
                  enabled: tile.modelData.enabled
                  cursorShape: Qt.ClosedHandCursor
                  dragThreshold: 2
                  grabPermissions: PointerHandler.CanTakeOverFromAnything
                  // Keep the tile inside the arrangement box.
                  xAxis.minimum: 0
                  xAxis.maximum: arrangeView.width - tile.width
                  yAxis.minimum: 0
                  yAxis.maximum: arrangeView.height - tile.height
                  onActiveChanged: {
                    if (active) { root.dragging = true; return }
                    root.dragging = false
                    var k = arrangeView.k
                    var lx = (tile.x - arrangeView.ox) / k + arrangeView.box.x
                    var ly = (tile.y - arrangeView.oy) / k + arrangeView.box.y
                    var p = root.snapPosition(tile.modelData, lx, ly, arrangeView.mons)
                    if (p) root.run(["arrange", tile.modelData.name, String(p.x), String(p.y)])
                    else root.refresh()  // no valid spot: snap back
                  }
                }
              }
            }
          }

          // ---------- Keyboard ----------
          PanelSeparator { foreground: root.bar.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(kbHeader.implicitHeight, reconnect.implicitHeight)

            Column {
              id: kbHeader
              anchors.left: parent.left
              anchors.right: reconnect.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelSectionHeader {
                text: strings.t("keyboard")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Text {
                textFormat: Text.PlainText
                text: root.keyboardStatus()
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: parent.width
                elide: Text.ElideRight
              }
            }

            Button {
              id: reconnect
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.ready && !root.st.keyboard.docked && root.st.keyboard.paired && !root.st.keyboard.connected
              text: strings.t("reconnect")
              fontSize: Style.font.caption
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.run(["keyboard", "connect"])
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }

  component BrightnessRow: Column {
    id: row
    property string label: ""
    property int value: 0
    property bool sliderEnabled: true
    signal changed(real v)

    width: parent ? parent.width : 0
    spacing: Style.space(4)
    opacity: sliderEnabled ? 1 : 0.45

    Item {
      width: parent.width
      implicitHeight: rowLabel.implicitHeight

      Text {
        id: rowLabel
        textFormat: Text.PlainText
        text: row.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
      }

      Text {
        textFormat: Text.PlainText
        text: Commons.I18n.formatNumber(Math.round(slider.dragging ? slider.liveValue : row.value)) + "%"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: rowLabel.verticalCenter
      }
    }

    PanelSlider {
      id: slider
      bar: root.bar
      enabled: row.sliderEnabled
      x: Style.space(6)
      width: parent.width - Style.space(12)
      minimum: 1
      maximum: 100
      step: 1
      integer: true
      value: row.value
      onMoved: function(v) { root.dragging = true; debounce.pending = v; debounce.restart() }
      onReleased: function(v) { debounce.stop(); root.dragging = false; row.changed(v) }
    }

    Timer {
      id: debounce
      property real pending: 0
      interval: 120
      onTriggered: row.changed(pending)
    }
  }
}

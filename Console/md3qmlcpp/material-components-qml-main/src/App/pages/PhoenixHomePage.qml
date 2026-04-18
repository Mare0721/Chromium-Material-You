import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import md3.Core

Item {
    id: root
    anchors.fill: parent

    property var selectedIds: []
    property bool showImportPanel: false
    property int contextRowId: -1
    property var proxyEditorTargetIds: []
    property int contextAutoSelectedId: -1
    property real contextMenuTargetX: 0
    property real contextMenuTargetY: 0
    property real contextMenuPivotX: 0
    property real contextMenuPivotY: 0
    property real contextMenuEnterFromX: 0
    property real contextMenuEnterFromY: 0
    property real contextMenuExitToX: 0
    property real contextMenuExitToY: 0
    property real contextMenuEnterScale: 0.86
    property real contextMenuExitScale: 0.9
    property bool contextMenuHoverReady: false
    property color contextMenuItemBaseColor: Theme.color.surfaceContainerHigh
    property color contextMenuItemHoverColor: Theme.color.secondaryContainer
    property color contextMenuItemBorderColor: Theme.color.outlineVariant

    function normalizeId(value) {
        var n = Number(value)
        if (isNaN(n)) {
            return -1
        }
        return Math.floor(n)
    }

    function currentIds() {
        var total = PhoenixBackend.profileCount || 0
        var out = []
        for (var i = 0; i < total; i++) {
            var pid = PhoenixBackend.profileIdAt(i)
            if (pid >= 0) {
                out.push(pid)
            }
        }
        return out
    }

    function isSelected(idValue) {
        return idValue >= 0 && selectedIds.indexOf(idValue) !== -1
    }

    function toggleSelected(idValue) {
        if (idValue < 0) {
            return
        }
        var idx = selectedIds.indexOf(idValue)
        if (idx === -1) {
            selectedIds = selectedIds.concat([idValue])
        } else {
            var next = selectedIds.slice()
            next.splice(idx, 1)
            selectedIds = next
        }
    }

    function removeSelected(idValue) {
        if (idValue < 0) {
            return
        }
        var idx = selectedIds.indexOf(idValue)
        if (idx === -1) {
            return
        }
        var next = selectedIds.slice()
        next.splice(idx, 1)
        selectedIds = next
    }

    function ensureSelected(idValue) {
        if (idValue < 0) {
            return
        }
        if (selectedIds.indexOf(idValue) === -1) {
            selectedIds = selectedIds.concat([idValue])
        }
    }

    function clearSelection() {
        selectedIds = []
    }

    function selectAll() {
        selectedIds = currentIds().slice()
    }

    function isRunning(idValue) {
        return idValue >= 0 && PhoenixBackend.runningIds.indexOf(idValue) !== -1
    }

    function statusText(idValue) {
        return isRunning(idValue) ? "运行中" : "已停止"
    }

    function statusColor(idValue) {
        return isRunning(idValue) ? "#1b8f4b" : Theme.color.onSurfaceVariantColor
    }

    function proxyToText(proxy) {
        if (!proxy) {
            return "未设置"
        }
        var scheme = proxy.scheme || "socks5"
        var ip = proxy.ip || ""
        var port = proxy.port || ""
        var user = proxy.user || ""
        if (user.length > 0) {
            return scheme + "://" + ip + ":" + port + ":" + user + ":***"
        }
        return scheme + "://" + ip + ":" + port
    }

    function refreshProfiles() {
        var ids = currentIds()
        var allowed = {}
        for (var i = 0; i < ids.length; i++) {
            allowed[ids[i]] = true
        }

        var next = []
        for (var j = 0; j < selectedIds.length; j++) {
            var pid = normalizeId(selectedIds[j])
            if (pid >= 0 && allowed[pid]) {
                next.push(pid)
            }
        }
        selectedIds = next
    }

    function openContextMenuAt(delegateItem, mouseX, mouseY) {
        var p = delegateItem.mapToItem(root, mouseX, mouseY)
        var margin = 8
        var menuW = contextMenu.width > 0 ? contextMenu.width : (contextMenu.implicitWidth > 0 ? contextMenu.implicitWidth : 224)
        var menuH = contextMenu.implicitHeight > 0 ? contextMenu.implicitHeight : 252
        root.contextMenuTargetX = Math.max(margin, Math.min(root.width - menuW - margin, Math.floor(p.x)))
        root.contextMenuTargetY = Math.max(margin, Math.min(root.height - menuH - margin, Math.floor(p.y)))

        root.contextMenuPivotX = Math.max(root.contextMenuTargetX, Math.min(root.contextMenuTargetX + menuW, p.x))
        root.contextMenuPivotY = Math.max(root.contextMenuTargetY, Math.min(root.contextMenuTargetY + menuH, p.y))

        root.contextMenuEnterFromX = root.contextMenuPivotX - (root.contextMenuPivotX - root.contextMenuTargetX) * root.contextMenuEnterScale
        root.contextMenuEnterFromY = root.contextMenuPivotY - (root.contextMenuPivotY - root.contextMenuTargetY) * root.contextMenuEnterScale
        root.contextMenuExitToX = root.contextMenuPivotX - (root.contextMenuPivotX - root.contextMenuTargetX) * root.contextMenuExitScale
        root.contextMenuExitToY = root.contextMenuPivotY - (root.contextMenuPivotY - root.contextMenuTargetY) * root.contextMenuExitScale

        contextMenu.x = root.contextMenuTargetX
        contextMenu.y = root.contextMenuTargetY
        contextMenuHoverReady = false
        contextMenu.open()
    }

    function openProxyEditor(ids) {
        var normalized = []
        var source = ids || []
        for (var i = 0; i < source.length; i++) {
            var pid = normalizeId(source[i])
            if (pid >= 0) {
                normalized.push(pid)
            }
        }
        if (normalized.length === 0) {
            return
        }

        proxyEditorTargetIds = normalized
        if (normalized.length === 1) {
            proxyEditorInput.text = PhoenixBackend.profileProxyRawText(normalized[0])
        } else {
            proxyEditorInput.text = ""
        }
        proxyEditorPopup.open()
    }

    function applyProxyEdit() {
        if (!proxyEditorTargetIds || proxyEditorTargetIds.length === 0) {
            return
        }
        PhoenixBackend.setProfilesProxy(proxyEditorTargetIds, proxyEditorInput.text)
        proxyEditorPopup.close()
    }

    component ContextMenuActionRow: Rectangle {
        id: actionRow
        property string label: ""
        property string icon: ""
        property bool enabledState: true
        property bool destructive: false
        property string cornerRole: "middle"
        signal triggered()

        radius: 0
        topLeftRadius: cornerRole === "top" ? 14 : 4
        topRightRadius: cornerRole === "top" ? 14 : 4
        bottomLeftRadius: cornerRole === "bottom" ? 14 : 4
        bottomRightRadius: cornerRole === "bottom" ? 14 : 4
        implicitHeight: 40
        color: (rowMouse.containsMouse && root.contextMenuHoverReady && enabledState)
               ? root.contextMenuItemHoverColor
               : root.contextMenuItemBaseColor
        opacity: enabledState ? 1 : 0.78
        scale: enabledState && rowMouse.pressed ? 0.985 : 1
        border.width: 1
        border.color: root.contextMenuItemBorderColor

        Behavior on scale {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: actionRow.icon
                font.family: Theme.iconFont.name
                font.pixelSize: 18
                color: actionRow.enabledState
                      ? (actionRow.destructive
                         ? Theme.color.error
                                                 : Theme.color.onSurfaceVariantColor)
                       : Theme.color.onSurfaceVariantColor
                opacity: actionRow.enabledState ? 1 : 0.7
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: actionRow.label
                color: actionRow.enabledState
                      ? (actionRow.destructive
                         ? Theme.color.error
                                                 : Theme.color.onSurfaceColor)
                       : Theme.color.onSurfaceVariantColor
                font.pixelSize: 14
                font.family: Theme.typography.bodyMedium.family
                font.weight: Font.DemiBold
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            enabled: true
            hoverEnabled: true
            preventStealing: true
            onPositionChanged: root.contextMenuHoverReady = true
            onClicked: {
                if (actionRow.enabledState) {
                    actionRow.triggered()
                }
            }
        }
    }

    Connections {
        target: PhoenixBackend

        function onProfilesChanged() {
            root.refreshProfiles()
        }

        function onRunningIdsChanged() {
            profilesList.forceLayout()
        }
    }

    Component.onCompleted: {
        root.refreshProfiles()
        PhoenixBackend.reloadProfiles()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.bottomMargin: 28
        anchors.topMargin: 42
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Text {
                text: "首页"
                font.pixelSize: Theme.typography.displaySmall.size
                font.family: Theme.typography.displaySmall.family
                font.weight: Font.Bold
                color: Theme.color.onSurfaceColor
            }

            Text {
                text: "环境 " + PhoenixBackend.profileCount + "  运行中 " + PhoenixBackend.runningCount + "  已选中 " + root.selectedIds.length
                font.pixelSize: Theme.typography.bodyLarge.size
                font.family: Theme.typography.bodyLarge.family
                font.weight: Font.Bold
                color: Theme.color.onSurfaceVariantColor
            }

            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(actionFlow.implicitHeight, refreshButton.implicitHeight)
            Layout.topMargin: 6

            RowLayout {
                anchors.fill: parent
                spacing: 10

                Flow {
                    id: actionFlow
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        text: root.showImportPanel ? "收起导入" : "批量导入代理"
                        type: "filledTonal"
                        onClicked: root.showImportPanel = !root.showImportPanel
                    }

                    Button {
                        text: "启动选中"
                        type: "filled"
                        enabled: root.selectedIds.length > 0
                        onClicked: PhoenixBackend.startProfiles(root.selectedIds)
                    }

                    Button {
                        text: "停止选中"
                        type: "outlined"
                        enabled: root.selectedIds.length > 0
                        onClicked: PhoenixBackend.stopProfiles(root.selectedIds)
                    }

                    Button {
                        text: "删除选中"
                        type: "outlined"
                        enabled: root.selectedIds.length > 0
                        onClicked: {
                            PhoenixBackend.deleteProfiles(root.selectedIds)
                            root.clearSelection()
                        }
                    }

                    Button {
                        text: "复制选中代理"
                        type: "text"
                        enabled: root.selectedIds.length > 0
                        onClicked: PhoenixBackend.copyProxiesToClipboard(root.selectedIds)
                    }

                    Button {
                        text: "全选"
                        type: "text"
                        enabled: PhoenixBackend.profileCount > 0
                        onClicked: root.selectAll()
                    }

                    Button {
                        text: "清空选择"
                        type: "text"
                        enabled: root.selectedIds.length > 0
                        onClicked: root.clearSelection()
                    }
                }

                Button {
                    id: refreshButton
                    text: "刷新"
                    type: "text"
                    onClicked: PhoenixBackend.reloadProfiles()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.showImportPanel ? 320 : 0
            opacity: root.showImportPanel ? 1 : 0
            clip: true

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
            }

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
            }

            Card {
                anchors.fill: parent
                padding: 16
                type: "filled"
                color: Theme.color.surfaceContainerLow

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    Text {
                        text: "批量导入"
                        font.pixelSize: Theme.typography.titleMedium.size
                        font.family: Theme.typography.titleMedium.family
                        font.weight: Font.Bold
                        color: Theme.color.onSurfaceColor
                    }

                    Text {
                        text: "每行一个代理，格式：socks5://ip:port:user:pass"
                        font.pixelSize: Theme.typography.bodySmall.size
                        font.family: Theme.typography.bodySmall.family
                        font.weight: Font.Bold
                        color: Theme.color.onSurfaceVariantColor
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 130
                        radius: 16
                        color: Theme.color.surfaceContainerHighest
                        border.width: 0

                        Flickable {
                            id: proxyFlick
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 20
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            clip: true
                            contentWidth: width
                            contentHeight: Math.max(height, proxyInput.contentHeight + 8)

                            TextEdit {
                                id: proxyInput
                                width: proxyFlick.width
                                text: ""
                                color: Theme.color.onSurfaceColor
                                wrapMode: TextEdit.WrapAnywhere
                                selectByMouse: true
                                font.pixelSize: 16
                                font.family: Theme.typography.bodyLarge.family
                                font.weight: Font.Medium

                                Text {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    visible: proxyInput.text.length === 0
                                    text: "例如：socks5://127.0.0.1:1080:user:pass"
                                    color: Theme.color.onSurfaceVariantColor
                                    font.pixelSize: 15
                                    font.family: Theme.typography.bodyLarge.family
                                }
                            }
                        }

                        ScrollBar {
                            target: proxyFlick
                            orientation: Qt.Vertical
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 6
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Layout.topMargin: 12

                        TextField {
                            id: quantityInput
                            Layout.preferredWidth: 196
                            label: "导入数量"
                            text: ""
                            type: "outlined"
                            labelBackgroundColor: Theme.color.surfaceContainerLow
                        }

                        Button {
                            text: "导入"
                            type: "filled"
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: {
                                var qty = root.normalizeId(quantityInput.text)
                                if (qty < 0) {
                                    qty = 0
                                }
                                var added = PhoenixBackend.importProxies(proxyInput.text, qty)
                                if (added > 0) {
                                    proxyInput.text = ""
                                    quantityInput.text = ""
                                    root.showImportPanel = false
                                    root.clearSelection()
                                }
                            }
                        }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 12
            type: "filled"
            color: Theme.color.surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Text {
                    text: "环境列表"
                    font.pixelSize: Theme.typography.titleMedium.size
                    font.family: Theme.typography.titleMedium.family
                    font.weight: Font.Bold
                    color: Theme.color.onSurfaceColor
                }

                Text {
                    visible: !PhoenixBackend.ready
                    text: "后端桥接不可用：" + PhoenixBackend.bridgeError
                    color: Theme.color.error
                    font.pixelSize: Theme.typography.bodySmall.size
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 18
                    color: Theme.color.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Item { Layout.preferredWidth: 22 }
                        Text { text: "ID"; color: Theme.color.onSurfaceColor; font.pixelSize: 14; font.weight: Font.Bold; Layout.preferredWidth: 140 }
                        Text { text: "状态"; color: Theme.color.onSurfaceColor; font.pixelSize: 14; font.weight: Font.Bold; Layout.preferredWidth: 120 }
                        Text { text: "代理"; color: Theme.color.onSurfaceColor; font.pixelSize: 14; font.weight: Font.Bold; Layout.fillWidth: true }
                        Text { text: "操作"; color: Theme.color.onSurfaceColor; font.pixelSize: 14; font.weight: Font.Bold; Layout.preferredWidth: 112; horizontalAlignment: Text.AlignHCenter }
                    }
                }

                ListView {
                    id: profilesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: PhoenixBackend.profileCount

                    delegate: Card {
                        id: delegateCard
                        property int rowId: -1
                        property string rowProxy: "未设置"
                        property bool selectedState: root.isSelected(rowId)
                        property real rowInset: selectedState ? 6 : 0

                        Component.onCompleted: {
                            rowId = PhoenixBackend.profileIdAt(index)
                            rowProxy = PhoenixBackend.profileProxyText(rowId)
                        }

                        Connections {
                            target: PhoenixBackend
                            function onProfilesChanged() {
                                rowId = PhoenixBackend.profileIdAt(index)
                                rowProxy = PhoenixBackend.profileProxyText(rowId)
                            }
                        }

                        x: 0
                        width: Math.max(0, profilesList.width - 2)
                        height: 80
                        radius: 16
                        padding: 0
                        type: "filled"
                        color: selectedState
                               ? Theme.color.primaryContainer
                               : Theme.color.surfaceContainer

                        Behavior on rowInset {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }

                        Behavior on color {
                            ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }

                        property bool rowRunning: root.isRunning(rowId)

                        RowLayout {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            anchors.leftMargin: 12 + delegateCard.rowInset
                            anchors.rightMargin: 12 + delegateCard.rowInset
                            spacing: 12
                            z: 2

                            Item {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: "transparent"
                                    border.width: 1.4
                                    border.color: Theme.color.primary
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Theme.color.primary
                                    opacity: delegateCard.selectedState ? 1 : 0
                                    scale: delegateCard.selectedState ? 1 : 0.2

                                    Behavior on opacity {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }

                                    Behavior on scale {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                                    }
                                }
                            }

                            Text {
                                text: delegateCard.rowId >= 0 ? ("ID " + delegateCard.rowId) : "ID -"
                                font.pixelSize: Theme.typography.titleSmall.size
                                font.family: Theme.typography.titleSmall.family
                                font.weight: Font.Bold
                                color: Theme.color.onSurfaceColor
                                Layout.preferredWidth: 140
                                horizontalAlignment: Text.AlignLeft
                            }

                            Text {
                                text: root.statusText(delegateCard.rowId)
                                color: root.statusColor(delegateCard.rowId)
                                font.pixelSize: Theme.typography.bodyMedium.size
                                font.family: Theme.typography.bodyMedium.family
                                font.weight: Font.Bold
                                Layout.preferredWidth: 120
                                horizontalAlignment: Text.AlignLeft
                            }

                            Text {
                                text: delegateCard.rowProxy
                                color: Theme.color.onSurfaceVariantColor
                                font.pixelSize: Theme.typography.bodyMedium.size
                                font.family: Theme.typography.bodyMedium.family
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Button {
                                text: delegateCard.rowRunning ? "停止" : "启动"
                                type: delegateCard.rowRunning ? "outlined" : "filled"
                                Layout.preferredWidth: 112
                                onClicked: {
                                    var rid = delegateCard.rowId
                                    if (rid < 0) return
                                    if (delegateCard.rowRunning) {
                                        PhoenixBackend.stopSingleProfile(rid)
                                    } else {
                                        PhoenixBackend.startSingleProfile(rid)
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            z: 1
                            // 让鼠标事件向上传播，使子控件(Button)能正常响应点击
                            propagateComposedEvents: true
                            onClicked: function(mouse) {
                                if (delegateCard.rowId < 0) {
                                    return
                                }
                                if (mouse.button === Qt.LeftButton) {
                                    root.toggleSelected(delegateCard.rowId)
                                    mouse.accepted = false
                                }
                                if (mouse.button === Qt.RightButton) {
                                    if (contextMenu.visible && root.contextRowId === delegateCard.rowId) {
                                        contextMenu.close()
                                        if (root.contextAutoSelectedId === delegateCard.rowId) {
                                            root.removeSelected(delegateCard.rowId)
                                            root.contextAutoSelectedId = -1
                                        }
                                    } else {
                                        root.contextRowId = delegateCard.rowId
                                        if (!root.isSelected(delegateCard.rowId)) {
                                            root.ensureSelected(delegateCard.rowId)
                                            root.contextAutoSelectedId = delegateCard.rowId
                                        } else {
                                            root.contextAutoSelectedId = -1
                                        }
                                        root.openContextMenuAt(delegateCard, mouse.x, mouse.y)
                                    }
                                    mouse.accepted = true
                                }
                            }
                            onDoubleClicked: {
                                if (delegateCard.rowId < 0) {
                                    return
                                }
                                if (delegateCard.rowRunning) {
                                    PhoenixBackend.stopSingleProfile(delegateCard.rowId)
                                } else {
                                    PhoenixBackend.startSingleProfile(delegateCard.rowId)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: profilesList.count === 0
                        text: "暂无环境数据"
                        color: Theme.color.onSurfaceVariantColor
                        font.pixelSize: Theme.typography.bodyLarge.size
                        font.family: Theme.typography.bodyLarge.family
                        font.weight: Font.Medium
                    }
                }

                Rectangle {
                    id: contextMenuBackdrop
                    parent: root
                    anchors.fill: parent
                    visible: contextMenu.visible
                    color: "transparent"
                    z: 1200

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        hoverEnabled: true
                        preventStealing: true
                        onPressed: function(mouse) {
                            contextMenu.close()
                            if (root.contextAutoSelectedId >= 0) {
                                root.removeSelected(root.contextAutoSelectedId)
                                root.contextAutoSelectedId = -1
                            }
                            mouse.accepted = true
                        }
                    }
                }

                QQC2.Popup {
                    id: contextMenu
                    parent: root
                    modal: false
                    focus: true
                    closePolicy: QQC2.Popup.CloseOnEscape
                    padding: 0
                    width: 244
                    z: 1201
                    scale: 1

                    onClosed: {
                        root.contextRowId = -1
                        root.contextMenuHoverReady = false
                    }

                    enter: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: root.contextMenuEnterScale; to: 1; duration: 180; easing.type: Easing.OutBack }
                            NumberAnimation { property: "x"; from: root.contextMenuEnterFromX; to: root.contextMenuTargetX; duration: 180; easing.type: Easing.OutBack }
                            NumberAnimation { property: "y"; from: root.contextMenuEnterFromY; to: root.contextMenuTargetY; duration: 180; easing.type: Easing.OutBack }
                        }
                    }

                    exit: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 100; easing.type: Easing.InCubic }
                            NumberAnimation { property: "scale"; from: 1; to: root.contextMenuExitScale; duration: 120; easing.type: Easing.InCubic }
                            NumberAnimation { property: "x"; from: root.contextMenuTargetX; to: root.contextMenuExitToX; duration: 120; easing.type: Easing.InCubic }
                            NumberAnimation { property: "y"; from: root.contextMenuTargetY; to: root.contextMenuExitToY; duration: 120; easing.type: Easing.InCubic }
                        }
                    }

                    background: Item { }

                    contentItem: ColumnLayout {
                        anchors.fill: parent
                        spacing: 2

                        ContextMenuActionRow {
                            Layout.fillWidth: true
                            label: "启动此环境"
                            icon: "play_arrow"
                            cornerRole: "top"
                            enabledState: root.contextRowId >= 0 && !root.isRunning(root.contextRowId)
                            onTriggered: {
                                contextMenu.close()
                                PhoenixBackend.startSingleProfile(root.contextRowId)
                            }
                        }

                        ContextMenuActionRow {
                            Layout.fillWidth: true
                            label: "停止此环境"
                            icon: "stop"
                            cornerRole: "middle"
                            enabledState: root.contextRowId >= 0 && root.isRunning(root.contextRowId)
                            onTriggered: {
                                contextMenu.close()
                                PhoenixBackend.stopSingleProfile(root.contextRowId)
                            }
                        }

                        ContextMenuActionRow {
                            Layout.fillWidth: true
                            label: "复制此 ID"
                            icon: "content_copy"
                            cornerRole: "middle"
                            enabledState: root.contextRowId >= 0
                            onTriggered: {
                                contextMenu.close()
                                PhoenixBackend.copyIdsToClipboard([root.contextRowId])
                            }
                        }

                        ContextMenuActionRow {
                            Layout.fillWidth: true
                            label: "复制此代理"
                            icon: "dns"
                            cornerRole: "middle"
                            enabledState: root.contextRowId >= 0
                            onTriggered: {
                                contextMenu.close()
                                PhoenixBackend.copyProxiesToClipboard([root.contextRowId])
                            }
                        }

                        ContextMenuActionRow {
                            Layout.fillWidth: true
                            label: "修改此环境代理"
                            icon: "edit"
                            cornerRole: "middle"
                            enabledState: root.contextRowId >= 0
                            onTriggered: {
                                contextMenu.close()
                                root.openProxyEditor([root.contextRowId])
                            }
                        }

                        ContextMenuActionRow {
                            Layout.fillWidth: true
                            label: "删除此环境"
                            icon: "delete"
                            cornerRole: "bottom"
                            enabledState: root.contextRowId >= 0
                            destructive: true
                            onTriggered: {
                                contextMenu.close()
                                PhoenixBackend.deleteProfiles([root.contextRowId])
                            }
                        }
                    }
                }

                QQC2.Popup {
                    id: proxyEditorPopup
                    parent: QQC2.Overlay.overlay
                    modal: true
                    focus: true
                    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
                    padding: 16
                    width: Math.max(420, Math.min((parent ? parent.width : root.width) - 56, 680))
                    implicitHeight: proxyEditorContent.implicitHeight + topPadding + bottomPadding
                    x: Math.round(((parent ? parent.width : root.width) - width) / 2)
                    y: Math.round(((parent ? parent.height : root.height) - implicitHeight) / 2)

                    QQC2.Overlay.modal: Rectangle {
                        color: Qt.rgba(0, 0, 0, 0.18)
                    }

                    enter: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 190; easing.type: Easing.OutBack }
                        }
                    }

                    exit: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 110; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; to: 0.98; duration: 110; easing.type: Easing.OutCubic }
                        }
                    }

                    background: Rectangle {
                        radius: 18
                        color: Theme.color.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.color.outlineVariant
                    }

                    contentItem: Column {
                        id: proxyEditorContent
                        width: proxyEditorPopup.availableWidth
                        spacing: 12

                        Text {
                            text: proxyEditorTargetIds.length > 1
                                  ? ("修改选中代理（" + proxyEditorTargetIds.length + " 个）")
                                  : "修改环境代理"
                            color: Theme.color.onSurfaceColor
                            font.pixelSize: Theme.typography.titleMedium.size
                            font.family: Theme.typography.titleMedium.family
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "留空并保存可清空代理；示例：socks5://127.0.0.1:1080:user:pass"
                            color: Theme.color.onSurfaceVariantColor
                            font.pixelSize: Theme.typography.bodySmall.size
                            font.family: Theme.typography.bodySmall.family
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }

                        TextField {
                            id: proxyEditorInput
                            width: parent.width
                            label: "代理地址"
                            text: ""
                            type: "outlined"
                            labelBackgroundColor: Theme.color.surfaceContainerLow
                        }

                        RowLayout {
                            width: parent.width
                            spacing: 10

                            Item { Layout.fillWidth: true }

                            Button {
                                text: "取消"
                                type: "text"
                                onClicked: proxyEditorPopup.close()
                            }

                            Button {
                                text: "保存"
                                type: "filled"
                                enabled: proxyEditorTargetIds.length > 0
                                onClicked: root.applyProxyEdit()
                            }
                        }
                    }
                }
            }
        }
    }
}

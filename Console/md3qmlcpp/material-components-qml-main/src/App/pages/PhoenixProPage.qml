import QtQuick
import QtQuick.Layouts
import md3.Core

Item {
    id: root
    anchors.fill: parent

    function parseIdList(text) {
        var tokens = text.replace(/\n/g, ",").split(",")
        var out = []
        var seen = {}
        for (var i = 0; i < tokens.length; i++) {
            var raw = tokens[i].trim()
            if (raw.length === 0) {
                continue
            }
            var n = parseInt(raw)
            if (isNaN(n)) {
                continue
            }
            if (!seen[n]) {
                out.push(n)
                seen[n] = true
            }
        }
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "批处理中心"
                font.pixelSize: Theme.typography.displaySmall.size
                font.family: Theme.typography.displaySmall.family
                font.weight: Font.Bold
                color: Theme.color.onSurfaceColor
            }

            Item { Layout.fillWidth: true }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            padding: 16
            type: "filled"
            color: Theme.color.surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                Text {
                    text: "按 ID 批量操作"
                    color: Theme.color.onSurfaceColor
                    font.pixelSize: Theme.typography.titleMedium.size
                    font.family: Theme.typography.titleMedium.family
                    font.weight: Font.Bold
                }

                Text {
                    text: "输入多个 ID，支持逗号或换行分隔，例如：1,2,3"
                    color: Theme.color.onSurfaceVariantColor
                    font.pixelSize: Theme.typography.bodySmall.size
                    font.family: Theme.typography.bodySmall.family
                    font.weight: Font.Bold
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    radius: 16
                    color: Theme.color.surfaceContainerHighest
                    border.width: 0

                    Flickable {
                        id: idFlick
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 20
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        clip: true
                        contentWidth: width
                        contentHeight: Math.max(height, idInput.contentHeight + 8)

                        TextEdit {
                            id: idInput
                            width: idFlick.width
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
                                visible: idInput.text.length === 0
                                text: "1,2,3"
                                color: Theme.color.onSurfaceVariantColor
                                font.pixelSize: 15
                                font.family: Theme.typography.bodyLarge.family
                            }
                        }
                    }

                    ScrollBar {
                        target: idFlick
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
                    spacing: 10

                    Button {
                        text: "批量启动"
                        type: "filled"
                        onClicked: {
                            var ids = root.parseIdList(idInput.text)
                            PhoenixBackend.startProfiles(ids)
                        }
                    }

                    Button {
                        text: "批量停止"
                        type: "outlined"
                        onClicked: {
                            var ids = root.parseIdList(idInput.text)
                            PhoenixBackend.stopProfiles(ids)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "复制这些 ID"
                        type: "text"
                        onClicked: {
                            var ids = root.parseIdList(idInput.text)
                            PhoenixBackend.copyIdsToClipboard(ids)
                        }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            padding: 16
            type: "filled"
            color: Theme.color.surfaceContainerLow

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                Text {
                    text: "代理批量导入"
                    color: Theme.color.onSurfaceColor
                    font.pixelSize: Theme.typography.titleMedium.size
                    font.family: Theme.typography.titleMedium.family
                    font.weight: Font.Bold
                }

                Text {
                    text: "每行一个代理，可选导入数量（0 表示按行数）"
                    color: Theme.color.onSurfaceVariantColor
                    font.pixelSize: Theme.typography.bodySmall.size
                    font.family: Theme.typography.bodySmall.family
                    font.weight: Font.Bold
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
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
                                text: "socks5://127.0.0.1:1080:user:pass"
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
                    Layout.topMargin: -6
                    Layout.leftMargin: 0
                    Layout.rightMargin: 20

                    TextField {
                        id: qtyInput
                        Layout.preferredWidth: 196
                        label: "导入数量"
                        text: ""
                        type: "outlined"
                        labelBackgroundColor: Theme.color.surfaceContainerLow
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "导入"
                        type: "filled"
                        Layout.preferredWidth: 96
                        Layout.rightMargin: 0
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: {
                            var qty = parseInt(qtyInput.text)
                            if (isNaN(qty)) {
                                qty = 0
                            }
                            var added = PhoenixBackend.importProxies(proxyInput.text, qty)
                            if (added > 0) {
                                proxyInput.text = ""
                                qtyInput.text = ""
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}

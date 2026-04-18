import QtQuick
import QtQuick.Layouts
import md3.Core

Item {
    id: root
    anchors.fill: parent

    property var currentItem: navItems[0]

    property var navItems: [
        { type: "item", text: "首页", icon: "home", page: "pages/PhoenixHomePage.qml" },
        { 
            type: "group", 
            text: "组件", 
            icon: "widgets",
            children: [
                { type: "item", text: "运行日志", icon: "terminal", page: "pages/PhoenixLogsPage.qml" },
                { type: "item", text: "状态组件", icon: "widgets", page: "pages/PhoenixWidgetsPage.qml" },
                { type: "item", text: "批处理中心", icon: "workspace_premium", page: "pages/PhoenixProPage.qml" }
            ]
        },
        { type: "divider" },
        { type: "item", text: "设置", icon: "settings", page: "pages/PhoenixSettingsPage.qml" },
        { type: "item", text: "关于", icon: "info", page: "pages/PhoenixAboutPage.qml" }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        NavigationDrawer {
            id: navDrawer
            modal: false
            drawerWidth: 260
            title: ""
            model: root.navItems
            currentItem: root.currentItem
            onItemClicked: (itemData) => root.currentItem = itemData
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.color.background
            clip: true

            Item {
                anchors.fill: parent

                Loader {
                    anchors.fill: parent
                    sourceComponent: prodPageLoader
                }

                Component {
                    id: prodPageLoader

                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        opacity: 1
                        source: root.currentItem ? root.currentItem.page : ""
                        transform: Translate {
                            id: pageEnterTranslate
                            y: 0
                        }

                        onLoaded: {
                            if (item) {
                                enterAnim.stop()
                                animOpacity.target = pageLoader
                                animY.target = pageEnterTranslate
                                pageLoader.opacity = 0
                                pageEnterTranslate.y = 50
                                enterAnim.start()
                            }
                        }
                    }
                }

                Component {
                    id: devPageLoader

                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        opacity: 1
                        source: ProjectSourceDir + "/src/App/" + (root.currentItem ? root.currentItem.page : "")
                        transform: Translate {
                            id: pageEnterTranslate
                            y: 0
                        }

                        onLoaded: {
                            if (item) {
                                enterAnim.stop()
                                animOpacity.target = pageLoader
                                animY.target = pageEnterTranslate
                                pageLoader.opacity = 0
                                pageEnterTranslate.y = 50
                                enterAnim.start()
                            }
                        }
                    }
                }
            }

            ParallelAnimation {
                id: enterAnim
                NumberAnimation { id: animOpacity; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { id: animY; property: "y"; to: 0; duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

}

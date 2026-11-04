/*
 * Copyright (C) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Forms 1.0

/*
 * The libraries to pick from, as tabs under the header the way the other
 * webOS apps switch views (Phone): this device first, then each video server
 * of the accounts, each its account's icon over its short label; the page
 * header carries the full name. Shown only when there is a
 * server. The tabs share the width; past what fits they scroll sideways, as
 * the platform TabBar does.
 *
 * The bar is light, as the page under it, rather than the platform's dark
 * grey; the selected tab keeps the platform's blue. Captions are all one
 * size, on up to two lines: "Free TV – Netherlands" as "Free TV" over
 * "Netherlands".
 */
TabBar {
    id: bar
    objectName: "sourceBar"

    // [{sourceId, name, label, icon}]
    property var sources: []
    property string current: ""
    signal picked(string sourceId)

    readonly property var tabs: [{ sourceId: "", name: "This Device", icon: Qt.resolvedUrl("../images/device-dark.svg"),
                                   selectedIcon: Qt.resolvedUrl("../images/device.svg") }]
                                .concat(sources)
    readonly property real tabWidth: Math.max(width / Math.max(1, tabs.length), Units.gu(11))

    implicitHeight: Units.gu(7)
    visible: sources.length > 0

    // A label's "Kind – name" (a Free TV list) breaks at the dash.
    function captionOf(t) {
        return String(t.label || t.name || "").replace(" – ", "\n");
    }

    background: Rectangle {
        objectName: "sourceBarBackground"
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.ruleLight }
            GradientStop { position: 1.0; color: Colors.pageBackground }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Colors.ruleDark
        }
    }

    // A tap moves the bar's index itself, which would leave the tab lit when
    // the app shows another library for its own reasons (a server gone);
    // the bar follows `current` instead.
    function follow() {
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i].sourceId === current) {
                currentIndex = i;
                return;
            }
        }
        currentIndex = 0;
    }
    onCurrentChanged: follow()
    onTabsChanged: Qt.callLater(follow)
    Component.onCompleted: follow()

    Repeater {
        model: bar.tabs

        TabButton {
            id: tab
            required property var modelData
            objectName: "source:" + tab.modelData.sourceId
            width: bar.tabWidth
            // The bar gives its tabs its height; one set here comes out
            // shifted up by half the difference to the implicit height.
            implicitHeight: bar.availableHeight
            focusPolicy: Qt.NoFocus

            // The platform's own content wants a two-frame sprite; account
            // icons are plain pictures, so the icon and caption are drawn here,
            // and the tab is the bar's light grey unless it is selected.
            background: Rectangle {
                color: tab.checked ? "#4585b8" : tab.down ? "#20000000" : "transparent"
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Units.gu(1)
                    anchors.bottomMargin: Units.gu(1)
                    width: 1
                    color: Colors.ruleDark
                    visible: !tab.checked
                }
            }
            contentItem: Item {
                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Units.gu(0.3)
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Units.gu(2.6)
                        height: width
                        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                        fillMode: Image.PreserveAspectFit
                        source: {
                            var icon = String(tab.checked && tab.modelData.selectedIcon ? tab.modelData.selectedIcon
                                                                                       : tab.modelData.icon || "");
                            return icon.charAt(0) === "/" ? "file://" + icon : icon;
                        }
                    }
                    Label {
                        objectName: "tabCaption"
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        // The icon shows the kind of server; the label is the
                        // name without it ("Home", not "Jellyfin – Home").
                        // Names as they are written, not in capitals, every
                        // tab at the same size: a long one goes on to a
                        // second line, then is cut short.
                        text: bar.captionOf(tab.modelData)
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        lineHeight: 0.9
                        color: tab.checked ? "#ffffff" : Colors.text
                        opacity: tab.down ? 0.7 : 1
                        font.pixelSize: FontUtils.sizeToPixels("x-small")
                        font.weight: tab.checked ? Font.Bold : Font.Normal
                    }
                }
            }
            onClicked: bar.picked(tab.modelData.sourceId)
        }
    }
}

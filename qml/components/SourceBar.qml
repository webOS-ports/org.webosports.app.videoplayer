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
 * of the accounts, each an icon over its caption. Shown only when there is a
 * server. The tabs share the width; past what fits they scroll sideways, as
 * the platform TabBar does.
 */
TabBar {
    id: bar
    objectName: "sourceBar"

    // [{sourceId, name, icon}]
    property var sources: []
    property string current: ""
    signal picked(string sourceId)

    readonly property var tabs: [{ sourceId: "", name: "This Device", icon: Qt.resolvedUrl("../images/device.svg") }]
                                .concat(sources)
    readonly property real tabWidth: Math.max(width / Math.max(1, tabs.length), Units.gu(11))

    implicitHeight: Units.gu(6)
    visible: sources.length > 0

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
            // icons are plain pictures, so the icon and caption are drawn here
            // and the platform's background (the selected blue) stays.
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
                            var icon = String(tab.modelData.icon || "");
                            return icon.charAt(0) === "/" ? "file://" + icon : icon;
                        }
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tab.modelData.name
                        color: "#ffffff"
                        opacity: tab.down ? 0.7 : 1
                        font.pixelSize: FontUtils.sizeToPixels("x-small")
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                        font.weight: tab.checked ? Font.Bold : Font.Normal
                    }
                }
            }
            onClicked: bar.picked(tab.modelData.sourceId)
        }
    }
}

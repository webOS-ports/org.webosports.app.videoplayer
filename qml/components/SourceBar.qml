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
 * The bar wears the page header's own background, so the two are one
 * grey; the captions are dark and the selected tab is Messaging's blue (its
 * palm-chrome.less, sampled from the Mojo app).
 * Captions are all one size, on up to two lines under an icon that stays
 * in one place: "Free TV – Netherlands" as "Free TV" over "Netherlands".
 *
 * The library page and a server's page each have a bar. They share how far
 * the row is scrolled (scrollX, scrolled()), so picking a tab far along does
 * not show the next page's bar back at the start; the selected tab is kept
 * in view.
 *
 * A flick runs as far as the finger sends it: the platform bar snaps to a
 * tab, and a snapping ListView stops a hard flick about a screen along.
 */
TabBar {
    id: bar
    objectName: "sourceBar"

    // [{sourceId, name, label, icon}]
    property var sources: []
    property string current: ""
    signal picked(string sourceId)
    // How far the row is scrolled, shared between the pages' bars: from the
    // row's start (originX), which a ListView moves as it makes its tabs.
    property real scrollX: 0
    signal scrolled(real x)

    readonly property var tabs: [{ sourceId: "", name: "This Device", icon: Qt.resolvedUrl("../images/device-dark.svg"),
                                   selectedIcon: Qt.resolvedUrl("../images/device.svg") }]
                                .concat(sources)
    readonly property real tabWidth: Math.max(width / Math.max(1, tabs.length), Units.gu(11))

    // Tall enough for the icon and two lines of caption, from the caption
    // font's own line height (the tab's padding is the platform's 6 px).
    FontMetrics {
        id: captionMetrics
        font.pixelSize: FontUtils.sizeToPixels("x-small")
    }
    readonly property real tabPadding: 6
    implicitHeight: Math.ceil(2 * tabPadding + Units.gu(0.4) + Units.gu(2.6) + Units.gu(0.3)
                              + 2 * captionMetrics.height + Units.gu(0.4))
    visible: sources.length > 0

    // A label's "Kind – name" (a Free TV list) breaks at the dash.
    function captionOf(t) {
        return String(t.label || t.name || "").replace(" – ", "\n");
    }

    // Messaging's colours (org.webosports.messaging, app/css/palm-chrome.less).
    readonly property color selectedTop: "#306ba3"
    readonly property color selectedBottom: "#6ca6ce"
    readonly property color captionColor: "#333333"

    // The header's own picture, edges and all, not a grey picked to match.
    background: AppHeader {
        objectName: "sourceBarBackground"
        enabled: false
    }

    // The platform bar's row, without its snapping and with the flick speed
    // of the app's other lists (in widths, not Qt's 2500 px/s).
    contentItem: ListView {
        implicitWidth: contentWidth
        implicitHeight: 40
        model: bar.contentModel
        currentIndex: bar.currentIndex
        spacing: bar.spacing
        orientation: ListView.Horizontal
        boundsBehavior: Flickable.StopAtBounds
        snapMode: ListView.NoSnap
        maximumFlickVelocity: Math.max(width, 1) * 8
        flickDeceleration: Math.max(width, 1) * 1.5
    }

    // A tap moves the bar's index itself, which would leave the tab lit when
    // the app shows another library for its own reasons (a server gone);
    // the bar follows `current` instead.
    function follow() {
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i].sourceId === current) {
                currentIndex = i;
                Qt.callLater(reveal);
                return;
            }
        }
        currentIndex = 0;
        Qt.callLater(reveal);
    }
    // Scrolled as the other bar was, and the selected tab in view.
    function reveal() {
        var v = contentItem;
        if (!v || !visible || v.contentWidth <= 0)
            return;
        v.contentX = v.originX + Math.max(0, Math.min(scrollX, v.contentWidth - v.width));
        v.positionViewAtIndex(currentIndex, ListView.Contain);
        scrolled(v.contentX - v.originX);
    }
    onVisibleChanged: if (visible) Qt.callLater(reveal)
    Connections {
        target: bar.contentItem
        function onMovementEnded() { bar.scrolled(bar.contentItem.contentX - bar.contentItem.originX); }
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
            // icons are plain pictures, so the icon and caption are drawn here.
            // A tab's base is see-through (a pressed one shaded); the blue is
            // a layer of its own, as "gradient: null" paints a Rectangle black.
            background: Rectangle {
                objectName: "tabBackground"
                color: tab.down && !tab.checked ? "#20000000" : "transparent"
                Rectangle {
                    objectName: "tabSelected"
                    anchors.fill: parent
                    visible: tab.checked
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: bar.selectedTop }
                        GradientStop { position: 1.0; color: bar.selectedBottom }
                    }
                }
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
            // The icon at one height on every tab, the caption hanging under
            // it, so a second line of caption does not push the icon up.
            contentItem: Item {
                Column {
                    anchors.top: parent.top
                    anchors.topMargin: Units.gu(0.4)
                    width: parent.width
                    spacing: Units.gu(0.3)
                    Image {
                        objectName: "tabIcon"
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
                        color: tab.checked ? "#ffffff" : bar.captionColor
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

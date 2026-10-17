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

import QtQuick
import QtQuick.Controls

import LunaNext.Common 0.1

/*
 * A short list to pick from, over the player: the audio tracks, the
 * subtitles, the speed. Drawn inside the player (not as a popup window
 * layer), so it turns with the picture when the player is turned.
 *
 * choices: [{label, checked, header (a heading, not a choice), key}].
 */
Item {
    id: sheet

    property string title
    property var choices: []
    readonly property bool shown: visible

    signal chosen(var choice)

    visible: false
    anchors.fill: parent

    readonly property real headerRowHeight: Units.gu(4.5)
    readonly property real rowHeight: Math.max(Units.gu(6), 54)
    readonly property real listHeight: {
        var h = 0;
        for (var i = 0; i < choices.length; i++)
            h += choices[i].header ? headerRowHeight : rowHeight;
        return h;
    }

    function show(newTitle, newChoices) {
        title = newTitle;
        choices = newChoices;
        visible = true;
    }

    function hide() {
        visible = false;
    }

    // A tap outside closes it.
    MouseArea {
        anchors.fill: parent
        onClicked: sheet.hide()
    }

    Rectangle {
        id: panel
        objectName: "sheetPanel"
        anchors.centerIn: parent
        width: Math.min(parent.width - Units.gu(4), Units.gu(44))
        height: Math.min(parent.height - Units.gu(4), heading.height + sheet.listHeight + Units.gu(1))
        radius: Units.gu(1)
        color: "#e6202020"
        border.color: "#555555"

        // Taps on the panel stay on it.
        MouseArea {
            anchors.fill: parent
        }

        Label {
            id: heading
            x: Units.gu(2)
            width: parent.width - Units.gu(4)
            height: Units.gu(5.5)
            verticalAlignment: Text.AlignVCenter
            text: sheet.title
            color: "#cccccc"
            font.pixelSize: FontUtils.sizeToPixels("medium")
            font.bold: true
            elide: Text.ElideRight
        }

        ListView {
            id: list
            objectName: "sheetList"
            anchors.top: heading.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Units.gu(1)
            clip: true
            model: sheet.choices
            boundsBehavior: Flickable.StopAtBounds

            delegate: ItemDelegate {
                id: choice
                objectName: "choice_" + index
                width: list.width
                height: modelData.header ? sheet.headerRowHeight : sheet.rowHeight
                enabled: !modelData.header
                padding: 0
                background: Rectangle {
                    color: choice.pressed ? "#44ffffff" : "transparent"
                }
                contentItem: Item {
                    Label {
                        objectName: "choiceLabel"
                        x: Units.gu(2)
                        width: parent.width - Units.gu(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        elide: Text.ElideRight
                        color: modelData.header ? "#999999" : "white"
                        font.pixelSize: FontUtils.sizeToPixels(modelData.header ? "small" : "medium")
                        font.bold: modelData.header === true
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Units.gu(2)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.checked === true
                        text: "✓"
                        color: "#7fb9ff"
                        font.pixelSize: FontUtils.sizeToPixels("large")
                    }
                }
                onClicked: {
                    sheet.hide();
                    sheet.chosen(modelData);
                }
            }
        }
    }
}

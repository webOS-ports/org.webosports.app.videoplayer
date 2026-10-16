/*
 * Copyright (C) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import QtQuick
import QtQuick.Controls

import LunaNext.Common 0.1

/*
 * A button with a picture from qml/images ("<image>.svg"), drawn at its
 * size, or a short text (the speed). On the player's dark bars; lit while
 * held or checked.
 *
 * At least 54 px across, the legacy guidelines' smallest touch target.
 */
ToolButton {
    id: button

    property string image
    property string label
    // The picture's share of the button.
    property real iconSize: Units.gu(3)
    property color labelColor: "white"

    implicitWidth: Math.max(Units.gu(6), 54)
    implicitHeight: Math.max(Units.gu(5.5), 54)
    padding: 0
    focusPolicy: Qt.NoFocus

    contentItem: Item {
        Image {
            anchors.centerIn: parent
            width: button.iconSize
            height: button.iconSize
            visible: button.image !== ""
            source: button.image !== "" ? Qt.resolvedUrl("../images/" + button.image + ".svg") : ""
            sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
            opacity: button.enabled ? 1.0 : 0.35
        }
        Text {
            anchors.centerIn: parent
            visible: button.image === ""
            text: button.label
            color: button.labelColor
            opacity: button.enabled ? 1.0 : 0.35
            font.pixelSize: FontUtils.sizeToPixels("medium")
            font.bold: true
        }
    }

    background: Rectangle {
        radius: Units.gu(0.6)
        color: button.pressed ? "#55ffffff" : (button.checked ? "#33ffffff" : "transparent")
    }
}

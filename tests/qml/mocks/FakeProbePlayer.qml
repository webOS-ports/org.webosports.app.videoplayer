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

/*
 * A stand-in for qml/ProbePlayer.qml: answers with a length of 30 s after a
 * moment, fails for a "broken" file and never answers for a "hang" one.
 * sources lists what it was asked.
 */
Item {
    property url source
    property int duration: 0
    property bool done: false
    property bool failed: false
    property var sources: []

    onSourceChanged: {
        done = false;
        failed = false;
        duration = 0;
        var s = sources.slice();
        s.push(String(source));
        sources = s;
        answer.restart();
    }

    Timer {
        id: answer
        interval: 30
        onTriggered: {
            var name = String(parent.source).split("/").pop();
            if (name.indexOf("hang") >= 0)
                return;
            if (name.indexOf("broken") >= 0) {
                parent.failed = true;
            } else {
                parent.duration = 30000;
            }
            parent.done = true;
        }
    }
}

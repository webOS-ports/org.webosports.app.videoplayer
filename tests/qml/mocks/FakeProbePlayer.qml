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

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

import LuneOS.Components 1.0 as LC
import "js/Library.js" as Library

/*
 * Reads the length of the videos the library does not know yet, one at a
 * time, with a player that only loads (ProbePlayer: Qt reads the
 * container on a thread, nothing is decoded). It runs only while asked to
 * (the library on screen, nothing playing).
 *
 * A file that gives no answer in timeoutMs is marked as failed, and the
 * probe stops for the rest of the run: whatever held it up may hold up the
 * next one too. Its player is set aside, not destroyed (destroying waits
 * for the pipeline).
 */
Item {
    id: probe

    // The player type; the tests give a stand-in.
    property url playerSource: Qt.resolvedUrl("ProbePlayer.qml")
    property bool active: true
    property int timeoutMs: 10000
    readonly property bool broken: _broken
    readonly property bool busy: _current !== null

    // A file's length was read (0: it has none, a stream), or not.
    signal measured(string key, int durationMs)
    signal failed(string key)
    // About to load path, and done with it: for the crash guard.
    signal starting(string path)
    signal finished(string path)

    property var _pending: []
    property var _current: null
    property var _player: null
    property var _setAside: []
    property bool _broken: false

    // files: [{path, size, modified}] to measure, replacing what was asked.
    function request(files) {
        var busyWith = _current ? _current.path : "";
        _pending = files.filter(function(f) { return f.path !== busyWith; });
        _next();
    }

    onActiveChanged: _next()

    function _makePlayer() {
        var component = Qt.createComponent(playerSource);
        if (component.status !== Component.Ready) {
            console.warn("DurationProbe: " + component.errorString());
            _broken = true;
            return null;
        }
        return component.createObject(probe);
    }

    function _next() {
        if (!active || _broken || _current !== null || _pending.length === 0)
            return;
        if (!_player)
            _player = _makePlayer();
        if (!_player)
            return;
        _current = _pending.shift();
        starting(_current.path);
        timer.restart();
        var url = LC.FileLists.fileUrl(_current.path);
        // The same file again (it changed on disk): a new source to load.
        if (String(_player.source) === url)
            _player.source = "";
        _player.source = url;
    }

    function _settle(ok) {
        if (_current === null)
            return;
        var key = Library.cacheKey(_current);
        var duration = _player.duration;
        var path = _current.path;
        _current = null;
        finished(path);
        timer.stop();
        if (ok)
            measured(key, duration > 0 ? duration : 0);
        else
            failed(key);
        Qt.callLater(_next);
    }

    Connections {
        target: probe._player
        function onDoneChanged() {
            if (probe._player.done && probe._current !== null)
                probe._settle(!probe._player.failed);
        }
        function onDurationChanged() {
            if (probe._player.duration > 0 && probe._current !== null)
                probe._settle(true);
        }
    }

    Timer {
        id: timer
        interval: probe.timeoutMs
        onTriggered: {
            if (probe._current === null)
                return;
            console.warn("DurationProbe: no answer for " + probe._current.path + " in " + interval + " ms; stopping");
            var key = Library.cacheKey(probe._current);
            probe._current = null;
            probe._setAside.push(probe._player);
            probe._player = null;
            probe._broken = true;
            probe.failed(key);
        }
    }
}

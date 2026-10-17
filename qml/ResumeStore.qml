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
import QtCore
import LuneOS.Components 1.0

import "js/Playback.js" as Playback

/*
 * Where each video was left - position, length, the audio and subtitle
 * tracks chosen - for picking up there and for "Continue Watching". One
 * JSON value in the app's settings file; Playback.js has its rules.
 */
Settings {
    id: store

    // In the app's own file, as every QML app has (LuneOS.Components' AppFiles).
    location: AppFiles.preferencesFile("org.webosports.app.videoplayer")
    category: "resume"

    property string videos: "{}"
    // Bumped on every change, for the library's bindings.
    property int revision: 0

    function entry(path) {
        var e = Playback.parseStore(videos)[path];
        return e ? e : null;
    }

    function positionOf(path) {
        return Playback.resumePosition(Playback.parseStore(videos), path);
    }

    function remember(path, state) {
        videos = JSON.stringify(Playback.remember(Playback.parseStore(videos), path, state));
        revision++;
    }

    function forget(path) {
        videos = JSON.stringify(Playback.forget(Playback.parseStore(videos), path));
        revision++;
    }

    function continueWatching(exists, limit) {
        return Playback.continueWatching(Playback.parseStore(videos), exists, limit);
    }
}

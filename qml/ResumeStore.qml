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

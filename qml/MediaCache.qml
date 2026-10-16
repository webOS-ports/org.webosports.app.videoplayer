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

/*
 * What the app has learnt about each file, kept between runs: its length
 * (from the probe or from playing it) and whether there is a picture of
 * it. Keyed by Library.cacheKey(), so a file replaced under the same name
 * is looked at again.
 *
 * The file lives in the pictures' folder: writing it makes the folder, so
 * the pictures can be saved there (an image is saved only into a folder
 * that exists).
 */
Settings {
    id: cache

    // A path (StandardPaths gives a file: URL).
    readonly property string folder: decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation))
                                                        .replace(/^file:\/\//, ""))
                                     + "/org.webosports.app.videoplayer/thumbnails"
    location: "file://" + folder + "/index.ini"
    category: "media"

    // {key: {duration: ms, thumb: "file name" or "", failed: true}}
    property string facts: "{}"
    property int revision: 0
    readonly property int maxEntries: 1000

    function all() {
        try {
            var v = JSON.parse(facts);
            return v && typeof v === "object" ? v : {};
        } catch (e) {
            return {};
        }
    }

    function factsFor(key) {
        return all()[key] || null;
    }

    function update(key, changes) {
        var v = all();
        var e = v[key] || {};
        for (var k in changes)
            e[k] = changes[k];
        e.at = Date.now();
        v[key] = e;
        // The oldest go once there are too many (pictures are left on disk;
        // a later one under the same name replaces them).
        var keys = Object.keys(v);
        if (keys.length > maxEntries) {
            keys.sort(function(a, b) { return (v[b].at || 0) - (v[a].at || 0); });
            for (var i = maxEntries; i < keys.length; i++)
                delete v[keys[i]];
        }
        facts = JSON.stringify(v);
        revision++;
    }

    // The folder made on disk, before a picture is saved into it: settings
    // are written a moment after they change, so this is done when the app
    // starts, long before the first picture is taken.
    function ensureFolder() {
        if (!all()[""])
            update("", { created: true });
    }

    Component.onCompleted: ensureFolder()

    function thumbnailUrl(key) {
        var e = factsFor(key);
        return e && e.thumb ? "file://" + folder + "/" + e.thumb : "";
    }
}

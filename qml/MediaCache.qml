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

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

.pragma library

/*
 * The library's rules: what is a video, which folders are looked in, the
 * order and search of the list, and paths.
 */

// What the scan lists: appinfo.json's mimeTypes, and .ts, which is left out
// there not to take TypeScript files from the editors.
var videoExtensions = ["3g2", "3gp", "asf", "avi", "flv", "m2ts", "m4v", "mkv", "mov",
                       "mp4", "mpeg", "mpg", "mts", "ogv", "ts", "webm", "wmv"];

// The scan's name filters for FolderListModel.
function nameFilters() {
    return videoExtensions.map(function(e) { return "*." + e; });
}

function extensionOf(name) {
    var base = String(name).split("/").pop();
    var dot = base.lastIndexOf(".");
    return dot > 0 ? base.substr(dot + 1).toLowerCase() : "";
}

function isVideo(name) {
    var base = String(name).split("/").pop();
    if (base.charAt(0) === ".")
        return false;
    return videoExtensions.indexOf(extensionOf(base)) >= 0;
}

// How deep below a root the scan goes, and how many folders it reads at
// most, so a large card cannot keep it busy for minutes.
var maxDepth = 6;
var maxFolders = 400;

// Folders not looked in: hidden ones (.thumbnails, the app store's
// .cryptofs), the app data under a root, and system folders on cards.
var skippedFolders = ["cryptofs", "lost+found", "android", "LOST.DIR", "System Volume Information",
                      "$RECYCLE.BIN"];

function shouldScanFolder(name, depth) {
    var base = String(name);
    if (base === "" || base.charAt(0) === "." || depth > maxDepth)
        return false;
    for (var i = 0; i < skippedFolders.length; i++) {
        if (skippedFolders[i].toLowerCase() === base.toLowerCase())
            return false;
    }
    return true;
}

// The folders to scan: the internal storage, and each card or USB stick
// mounted beside it under /media (the names in mounted, from a listing of
// /media). The system's own folders there are left out.
var mediaSystemFolders = ["internal", "cryptofs", "multimedia"];

function scanRoots(mounted) {
    var roots = ["/media/internal"];
    (mounted || []).forEach(function(name) {
        if (name && name.charAt(0) !== "." && mediaSystemFolders.indexOf(name) < 0)
            roots.push("/media/" + name);
    });
    return roots;
}

// The removable root a path is on, for the library's "SD card" label, or "".
function volumeOf(path, roots) {
    for (var i = 0; i < roots.length; i++) {
        if (roots[i] !== "/media/internal" && String(path).indexOf(roots[i] + "/") === 0)
            return roots[i].split("/").pop();
    }
    return "";
}

// The name shown: the file name without its extension.
function displayName(path) {
    var base = String(path).split("/").pop();
    var dot = base.lastIndexOf(".");
    return dot > 0 ? base.substr(0, dot) : base;
}

// The folder a file is in, relative to its root ("" at the root itself).
function folderOf(path, roots) {
    var dir = String(path).substring(0, String(path).lastIndexOf("/"));
    for (var i = 0; i < roots.length; i++) {
        if (dir === roots[i])
            return "";
        if (dir.indexOf(roots[i] + "/") === 0)
            return dir.substr(roots[i].length + 1);
    }
    return dir;
}

// A launch target ("/path", "file:///path", percent-encoded or not) as a
// local path, or "" for anything that is not a local file.
function localPath(target) {
    var t = String(target === undefined || target === null ? "" : target).trim();
    if (t.indexOf("file://") === 0) {
        t = t.substr(7);
        // file://localhost/path
        if (t.charAt(0) !== "/") {
            var slash = t.indexOf("/");
            if (slash < 0 || t.substring(0, slash) !== "localhost")
                return "";
            t = t.substr(slash);
        }
        try {
            t = decodeURIComponent(t);
        } catch (e) {
            return "";
        }
    }
    if (t.charAt(0) !== "/")
        return "";
    return t;
}

// The file URL of a path, with the characters a URL cannot hold encoded.
function fileUrl(path) {
    return "file://" + String(path).split("/").map(function(part) {
        return encodeURIComponent(part);
    }).join("/");
}

// The SubRip files that go with a video: the same name with .srt, then
// with a language between ("movie.en.srt" goes with "movie.mkv") among
// the names in its folder.
function subtitleCandidates(videoPath, namesInFolder) {
    var dir = String(videoPath).substring(0, String(videoPath).lastIndexOf("/") + 1);
    var base = displayName(videoPath);
    var exact = [];
    var withLanguage = [];
    (namesInFolder || []).forEach(function(name) {
        var lower = name.toLowerCase();
        if (lower.substr(-4) !== ".srt")
            return;
        var stem = name.substr(0, name.length - 4);
        if (stem === base)
            exact.push(dir + name);
        else if (stem.indexOf(base + ".") === 0 && stem.length > base.length + 1)
            withLanguage.push(dir + name);
    });
    withLanguage.sort();
    return exact.concat(withLanguage);
}

// The language part of "movie.en.srt" for the picker ("en"), or "".
function subtitleLabel(videoPath, srtPath) {
    var base = displayName(videoPath);
    var stem = displayName(srtPath);
    return stem.length > base.length + 1 ? stem.substr(base.length + 1) : "";
}

// ---- order and search -------------------------------------------------------

// "Episode 2" before "Episode 10".
function naturalCompare(a, b) {
    var ax = String(a).toLowerCase().match(/(\d+|\D+)/g) || [];
    var bx = String(b).toLowerCase().match(/(\d+|\D+)/g) || [];
    for (var i = 0; i < Math.min(ax.length, bx.length); i++) {
        var x = ax[i], y = bx[i];
        if (x === y)
            continue;
        var nx = /^\d/.test(x), ny = /^\d/.test(y);
        if (nx && ny) {
            var d = parseInt(x, 10) - parseInt(y, 10);
            if (d !== 0)
                return d < 0 ? -1 : 1;
            if (x.length !== y.length)
                return x.length - y.length;
            continue;
        }
        return x.localeCompare(y);
    }
    return ax.length - bx.length;
}

// files: [{path, name, size, modified (ms)}], a new array. "name" A-Z,
// "date" newest first, "size" largest first; ties by name.
function sorted(files, order) {
    var copy = files.slice();
    copy.sort(function(a, b) {
        var c = 0;
        if (order === "date")
            c = (b.modified || 0) - (a.modified || 0);
        else if (order === "size")
            c = (b.size || 0) - (a.size || 0);
        if (c !== 0)
            return c < 0 ? -1 : 1;
        return naturalCompare(displayName(a.name || a.path), displayName(b.name || b.path))
                || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
    });
    return copy;
}

// Folds case and accents, so "cafe" finds "Café".
function fold(s) {
    var t = String(s).toLowerCase();
    if (t.normalize)
        t = t.normalize("NFD").replace(/[̀-ͯ]/g, "");
    return t;
}

// The files whose name or folder has every word of query in it.
function filter(files, query, roots) {
    var words = fold(query).split(/\s+/).filter(function(w) { return w !== ""; });
    if (words.length === 0)
        return files.slice();
    return files.filter(function(f) {
        var hay = fold(displayName(f.path) + " " + folderOf(f.path, roots || []));
        return words.every(function(w) { return hay.indexOf(w) >= 0; });
    });
}

// The key a file's cached facts (length, picture) are kept under: its path
// with its size and time, so a file replaced under the same name is looked
// at again.
function cacheKey(file) {
    return file.path + "|" + (file.size || 0) + "|" + Math.floor((file.modified || 0) / 1000);
}

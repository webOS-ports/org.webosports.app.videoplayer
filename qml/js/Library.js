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

.pragma library
.import LuneOS.Components 1.0 as LC

/*
 * The library's rules: what is a video, which folders are looked in, the
 * order and search of the list, and paths. Names, launch targets, file URLs,
 * the order of names and matching a search are LuneOS.Components' FileLists,
 * as in the other apps.
 */

// What the scan lists: appinfo.json's mimeTypes, and .ts, which is left out
// there not to take TypeScript files from the editors.
var videoExtensions = ["3g2", "3gp", "asf", "avi", "flv", "m2ts", "m4v", "mkv", "mov",
                       "mp4", "mpeg", "mpg", "mts", "ogv", "ts", "webm", "wmv"];

// The scan's name filters for FolderListModel.
function nameFilters() {
    return videoExtensions.map(function(e) { return "*." + e; });
}

function isVideo(name) {
    var base = String(name).split("/").pop();
    if (base.charAt(0) === ".")
        return false;
    return videoExtensions.indexOf(LC.FileLists.extensionOf(base)) >= 0;
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

// The SubRip files that go with a video: the same name with .srt, then
// with a language between ("movie.en.srt" goes with "movie.mkv") among
// the names in its folder.
function subtitleCandidates(videoPath, namesInFolder) {
    var dir = String(videoPath).substring(0, String(videoPath).lastIndexOf("/") + 1);
    var base = LC.FileLists.displayName(videoPath);
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
    var base = LC.FileLists.displayName(videoPath);
    var stem = LC.FileLists.displayName(srtPath);
    return stem.length > base.length + 1 ? stem.substr(base.length + 1) : "";
}

// ---- order and search -------------------------------------------------------

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
        return LC.FileLists.naturalCompare(LC.FileLists.displayName(a.name || a.path), LC.FileLists.displayName(b.name || b.path))
                || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
    });
    return copy;
}

// The files whose name or folder has every word of query in it, case and
// accents aside.
function filter(files, query, roots) {
    return files.filter(function(f) {
        return LC.FileLists.matches(LC.FileLists.displayName(f.path) + " " + folderOf(f.path, roots || []), query);
    });
}

// The key a file's cached facts (length, picture) are kept under: its path
// with its size and time, so a file replaced under the same name is looked
// at again.
function cacheKey(file) {
    return file.path + "|" + (file.size || 0) + "|" + Math.floor((file.modified || 0) / 1000);
}

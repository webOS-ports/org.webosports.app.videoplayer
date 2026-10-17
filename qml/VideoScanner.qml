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
import Qt.labs.folderlistmodel

import LuneOS.Components 1.0 as LC
import "js/Library.js" as Library

/*
 * Finds the videos: every folder under each root, a few folders at a time,
 * through FolderListModel, which reads them on a thread of its own - the
 * screen never waits for the disk. Folders the rules in Library.js leave
 * out (hidden, system) are not entered.
 *
 * roots, if set, are scanned; left empty the scan takes the internal
 * storage and whatever is mounted beside it under /media (memory cards,
 * USB sticks), as the listing of /media shows them at the time.
 */
Item {
    id: scanner

    // Folders to scan instead of /media's (for the tests).
    property var roots: []
    readonly property var activeRoots: _activeRoots
    // [{path, name, size, modified (ms)}], when a scan has finished.
    property var files: []
    readonly property bool running: _running
    // Bumped when a scan finishes.
    property int generation: 0

    property var _activeRoots: []
    property bool _running: false
    property var _queue: []        // [{path, depth}]
    property var _found: []
    property int _busy: 0
    property int _folders: 0
    property bool _again: false
    readonly property int _parallel: 3

    function rescan() {
        if (_running) {
            _again = true;
            return;
        }
        _running = true;
        _found = [];
        _folders = 0;
        if (roots && roots.length > 0) {
            _start(roots);
        } else {
            _waitingForMedia = true;
            mediaGuard.restart();
            mediaListing.folder = "";
            mediaListing.folder = "file:///media";
        }
    }

    function _start(rootList) {
        _activeRoots = rootList;
        _queue = rootList.map(function(r) { return { path: r, depth: 0 }; });
        _pump();
    }

    // /media's folders, once read, give the roots.
    property bool _waitingForMedia: false

    function _mediaRead(names) {
        if (!_waitingForMedia)
            return;
        _waitingForMedia = false;
        mediaGuard.stop();
        _start(Library.scanRoots(names));
    }

    FolderListModel {
        id: mediaListing
        showFiles: false
        showDirs: true
        showHidden: false
        showDotAndDotDot: false
        onStatusChanged: {
            if (status !== FolderListModel.Ready)
                return;
            Qt.callLater(function() {
                var names = [];
                for (var i = 0; i < mediaListing.count; i++)
                    names.push(mediaListing.get(i, "fileName"));
                scanner._mediaRead(names);
            });
        }
    }

    // Without a listing of /media, the internal storage alone.
    Timer {
        id: mediaGuard
        interval: 5000
        onTriggered: scanner._mediaRead([])
    }

    function _pump() {
        while (_busy < _parallel && _queue.length > 0 && _folders < Library.maxFolders) {
            var next = _queue.shift();
            _folders++;
            _busy++;
            folderReader.createObject(scanner, { path: next.path, depth: next.depth });
        }
        if (_busy === 0 && (_queue.length === 0 || _folders >= Library.maxFolders))
            _finish();
    }

    function _finish() {
        files = _found;
        _running = false;
        generation++;
        if (_again) {
            _again = false;
            Qt.callLater(rescan);
        }
    }

    function _read(reader) {
        var model = reader.model;
        for (var i = 0; i < model.count; i++) {
            var name = model.get(i, "fileName");
            var path = model.get(i, "filePath");
            // A folder that is gone is listed as another one (the model
            // falls back): only what is in the folder asked for counts.
            if (path.substring(0, path.lastIndexOf("/")) !== reader.path)
                continue;
            if (model.get(i, "fileIsDir")) {
                if (Library.shouldScanFolder(name, reader.depth + 1))
                    _queue.push({ path: path, depth: reader.depth + 1 });
            } else if (Library.isVideo(name)) {
                var modified = model.get(i, "fileModified");
                _found.push({
                    path: path,
                    name: name,
                    size: model.get(i, "fileSize"),
                    modified: modified ? new Date(modified).getTime() : 0
                });
            }
        }
        _busy--;
        reader.destroy();
        _pump();
    }

    Component {
        id: folderReader

        // One folder: its videos and its folders.
        QtObject {
            id: reader
            property string path
            property int depth
            property bool done: false
            property FolderListModel model: FolderListModel {
                showDirs: true
                showFiles: true
                showHidden: false
                showDotAndDotDot: false
                showOnlyReadable: true
                caseSensitive: false
                nameFilters: Library.nameFilters()
                sortField: FolderListModel.Unsorted
                folder: LC.FileLists.fileUrl(reader.path)
                // Read just after: not from inside the model's own signal,
                // as reading ends with destroying it.
                onStatusChanged: {
                    if (status === FolderListModel.Ready)
                        reader.later.restart();
                }
            }
            property Timer later: Timer {
                interval: 0
                onTriggered: reader.deliver()
            }
            // A folder that cannot be read (gone, no permission) never
            // becomes Ready: give up on it.
            property Timer guard: Timer {
                interval: 5000
                running: true
                onTriggered: reader.deliver()
            }
            function deliver() {
                if (done)
                    return;
                done = true;
                later.stop();
                guard.stop();
                scanner._read(reader);
            }
        }
    }
}

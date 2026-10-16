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
import QtTest

import "../../qml"
import "../../qml/js/Library.js" as Library

/*
 * The scan over tests/data/library, the length probe with a stand-in
 * player, and the cache making its folder.
 */
TestCase {
    id: test
    name: "Scanner"

    readonly property string root: decodeURIComponent(Qt.resolvedUrl("../data/library").toString().replace(/^file:\/\//, ""))

    Component {
        id: scannerComponent
        VideoScanner { }
    }
    Component {
        id: probeComponent
        DurationProbe {
            playerSource: Qt.resolvedUrl("mocks/FakeProbePlayer.qml")
            timeoutMs: 300
        }
    }
    Component {
        id: cacheComponent
        MediaCache { }
    }

    function scan(roots) {
        var s = createTemporaryObject(scannerComponent, test, { roots: roots });
        s.rescan();
        tryVerify(function() { return s.generation > 0; }, 10000, "the scan finishes");
        return s;
    }

    function relative(files) {
        return files.map(function(f) { return f.path.substr(test.root.length + 1); }).sort();
    }

    function test_finds_the_videos() {
        var s = scan([root]);
        compare(relative(s.files), [
            "Café Night 2audio ass.mkv",
            "Movies/Big Buck.mp4",
            "Movies/Episode 10.mkv",
            "Movies/Episode 2.mkv",
            "Movies/Series/Season 1/S01E01.webm",
            "broken.mp4",
            "clip.AVI",
            "deep/1/2/3/4/5/too-deep-not.mp4",
            "hang.mp4",
            "with-srt/movie.mp4"
        ]);
        // Not: notes.txt, .hidden/, cryptofs/, the seventh level down.
        var f = s.files.filter(function(x) { return x.name === "Big Buck.mp4"; })[0];
        compare(f.size, 0);
        verify(f.modified > 0, "a time");
    }

    function test_rescan_while_scanning_scans_again() {
        var s = createTemporaryObject(scannerComponent, test, { roots: [root + "/Movies"] });
        s.rescan();
        s.rescan();
        tryVerify(function() { return s.generation >= 2; }, 10000, "two scans");
        compare(s.files.length, 4);
        verify(!s.running);
    }

    function test_missing_root_is_empty() {
        var s = scan([root + "/no such folder"]);
        compare(s.files.length, 0);
    }

    function test_folder_limit() {
        var old = Library.maxFolders;
        Library.maxFolders = 2;
        var s = scan([root]);
        Library.maxFolders = old;
        verify(s.files.length < 10, "stops after two folders: " + s.files.length);
    }

    function test_probe_measures_and_gives_up() {
        var p = createTemporaryObject(probeComponent, test);
        var measured = {}, failed = [];
        p.measured.connect(function(key, ms) { measured[key] = ms; });
        p.failed.connect(function(key) { failed.push(key); });
        var files = [
            { path: "/v/a.mp4", size: 1, modified: 1000 },
            { path: "/v/broken.mp4", size: 1, modified: 1000 },
            { path: "/v/hang.mp4", size: 1, modified: 1000 },
            { path: "/v/after.mp4", size: 1, modified: 1000 }
        ];
        p.request(files);
        tryVerify(function() { return p.broken; }, 3000, "gives up at the hang");
        compare(measured[Library.cacheKey(files[0])], 30000);
        compare(failed.length, 2);
        verify(failed.indexOf(Library.cacheKey(files[1])) >= 0);
        verify(failed.indexOf(Library.cacheKey(files[2])) >= 0);
        wait(200);
        compare(measured[Library.cacheKey(files[3])], undefined, "nothing after the hang");
        compare(p._setAside.length, 1, "the hung player is kept, not destroyed");
        verify(!p.busy);
    }

    // Asked again while busy (a rescan): the file being read is not asked
    // twice, which would set the same source and get no answer.
    function test_probe_asked_again_while_busy() {
        var p = createTemporaryObject(probeComponent, test);
        var measured = [];
        p.measured.connect(function(key) { measured.push(key); });
        var a = { path: "/v/a.mp4", size: 1, modified: 1 };
        var b = { path: "/v/b.mp4", size: 1, modified: 1 };
        p.request([a, b]);
        verify(p.busy);
        p.request([a, b]);
        tryVerify(function() { return measured.length === 2; }, 2000, "both measured: " + measured);
        verify(!p.broken);
        // Measured again later (changed on disk): it answers again.
        p.request([b]);
        tryVerify(function() { return measured.length === 3; }, 2000);
        verify(!p.broken);
    }

    function test_probe_waits_while_inactive() {
        var p = createTemporaryObject(probeComponent, test, { active: false });
        var count = 0;
        p.measured.connect(function() { count++; });
        p.request([{ path: "/v/a.mp4", size: 1, modified: 1 }]);
        wait(150);
        compare(count, 0);
        p.active = true;
        tryCompare(p, "busy", false, 2000);
        tryVerify(function() { return count === 1; }, 2000);
    }

    function test_cache_makes_its_folder() {
        var c = createTemporaryObject(cacheComponent, test);
        // The index file is written soon after: the folder is there.
        tryVerify(function() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "file://" + c.folder + "/index.ini", false);
            xhr.send();
            return xhr.responseText.indexOf("facts") >= 0;
        }, 3000, "index written in " + c.folder);
        c.update("k", { duration: 5 });
        compare(c.factsFor("k").duration, 5);
        compare(c.thumbnailUrl("k"), "");
        c.update("k", { thumb: "x.jpg" });
        compare(c.thumbnailUrl("k"), "file://" + c.folder + "/x.jpg");
    }
}

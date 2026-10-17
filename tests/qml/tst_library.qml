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

import LuneOS.Components 1.0

import "../../qml/js/Library.js" as Library

/*
 * qml/js/Library.js: what is a video, which folders, order, search, paths;
 * and what the app relies on of LuneOS.Components' FileLists.
 */
TestCase {
    name: "Library"

    function test_videos_by_extension() {
        verify(Library.isVideo("a.mp4"));
        verify(Library.isVideo("/x/B.MKV"), "case does not matter");
        verify(Library.isVideo("c.webm"));
        verify(Library.isVideo("d.avi"));
        verify(!Library.isVideo("notes.txt"));
        verify(!Library.isVideo("song.m4a"), "sound only is not listed");
        verify(!Library.isVideo(".hidden.mp4"));
        verify(!Library.isVideo("mp4"));
    }

    function test_folders_scanned() {
        verify(Library.shouldScanFolder("Movies", 1));
        verify(!Library.shouldScanFolder(".thumbnails", 1));
        verify(!Library.shouldScanFolder(".cryptofs", 1));
        verify(!Library.shouldScanFolder("cryptofs", 1));
        verify(!Library.shouldScanFolder("LOST.DIR", 1));
        verify(Library.shouldScanFolder("deep", Library.maxDepth));
        verify(!Library.shouldScanFolder("deeper", Library.maxDepth + 1));
    }

    function test_scan_roots_take_cards_beside_internal() {
        compare(Library.scanRoots([]), ["/media/internal"]);
        compare(Library.scanRoots(["internal", "cryptofs", "multimedia", ".cache", "SDCARD", "usb1"]),
                ["/media/internal", "/media/SDCARD", "/media/usb1"]);
        compare(Library.volumeOf("/media/SDCARD/a.mp4", ["/media/internal", "/media/SDCARD"]), "SDCARD");
        compare(Library.volumeOf("/media/internal/a.mp4", ["/media/internal", "/media/SDCARD"]), "");
    }

    function test_launch_targets() {
        compare(FileLists.localPath("/media/internal/a.mp4"), "/media/internal/a.mp4");
        compare(FileLists.localPath("file:///media/internal/My%20Film.mkv"), "/media/internal/My Film.mkv");
        compare(FileLists.localPath("file://localhost/media/a.mp4"), "/media/a.mp4");
        compare(FileLists.localPath("file://otherhost/a.mp4"), "");
        compare(FileLists.localPath("http://example.com/a.mp4"), "");
        compare(FileLists.localPath("relative.mp4"), "");
        compare(FileLists.localPath("file:///bad%E0%A4%A.mp4"), "");
        compare(FileLists.localPath(undefined), "");
    }

    function test_file_urls_are_encoded() {
        compare(FileLists.fileUrl("/media/internal/My Film #1.mkv"), "file:///media/internal/My%20Film%20%231.mkv");
        compare(FileLists.localPath(FileLists.fileUrl("/a/Café 50%.mp4")), "/a/Café 50%.mp4");
    }

    function test_names_and_folders() {
        compare(FileLists.displayName("/a/b/My.Film.2024.mkv"), "My.Film.2024");
        compare(FileLists.displayName("/a/noext"), "noext");
        var roots = ["/media/internal", "/media/sd"];
        compare(Library.folderOf("/media/internal/a.mp4", roots), "");
        compare(Library.folderOf("/media/internal/Movies/Series/a.mp4", roots), "Movies/Series");
        compare(Library.folderOf("/media/sd/DCIM/a.mp4", roots), "DCIM");
        compare(Library.folderOf("/elsewhere/a.mp4", roots), "/elsewhere");
    }

    function test_subtitle_files_found_by_name() {
        var names = ["movie.srt", "movie.nl.srt", "movie.en.SRT", "movie2.srt", "other.srt", "movie.mp4"];
        compare(Library.subtitleCandidates("/v/movie.mp4", names),
                ["/v/movie.srt", "/v/movie.en.SRT", "/v/movie.nl.srt"]);
        compare(Library.subtitleCandidates("/v/none.mp4", names), []);
        compare(Library.subtitleLabel("/v/movie.mp4", "/v/movie.en.SRT"), "en");
        compare(Library.subtitleLabel("/v/movie.mp4", "/v/movie.srt"), "");
    }

    function test_natural_order() {
        var names = ["Episode 10", "episode 2", "Episode 1", "Zebra", "apple"];
        verify(FileLists.naturalCompare("Episode 3", "Episode 2") > 0);
        verify(FileLists.naturalCompare("Episode 2", "Episode 10") < 0);
        compare(FileLists.naturalCompare("a 7", "A 7"), 0);
        names.sort(FileLists.naturalCompare);
        compare(names, ["apple", "Episode 1", "episode 2", "Episode 10", "Zebra"]);
    }

    function test_sorting() {
        var files = [
            { path: "/m/b.mp4", name: "b.mp4", size: 300, modified: 1000 },
            { path: "/m/a.mp4", name: "a.mp4", size: 100, modified: 3000 },
            { path: "/m/c.mp4", name: "c.mp4", size: 200, modified: 2000 }
        ];
        var names = function(list) { return list.map(function(f) { return f.name; }); };
        compare(names(Library.sorted(files, "name")), ["a.mp4", "b.mp4", "c.mp4"]);
        compare(names(Library.sorted(files, "date")), ["a.mp4", "c.mp4", "b.mp4"]);
        compare(names(Library.sorted(files, "size")), ["b.mp4", "c.mp4", "a.mp4"]);
        compare(names(files), ["b.mp4", "a.mp4", "c.mp4"], "the input is left as it was");
    }

    function test_search() {
        var files = [
            { path: "/media/internal/Movies/Café Night.mkv" },
            { path: "/media/internal/Holiday/Beach day.mp4" },
            { path: "/media/internal/Night Train.mp4" }
        ];
        var roots = ["/media/internal"];
        compare(Library.filter(files, "", roots).length, 3);
        compare(Library.filter(files, "cafe", roots).length, 1, "accents folded");
        compare(Library.filter(files, "NIGHT", roots).length, 2);
        compare(Library.filter(files, "night movies", roots).length, 1, "every word, folders too");
        compare(Library.filter(files, "holiday", roots)[0].path, "/media/internal/Holiday/Beach day.mp4");
        compare(Library.filter(files, "xyz", roots).length, 0);
    }

    function test_cache_key_changes_with_the_file() {
        var a = { path: "/a.mp4", size: 10, modified: 5000 };
        var b = { path: "/a.mp4", size: 11, modified: 5000 };
        var c = { path: "/a.mp4", size: 10, modified: 9000 };
        verify(Library.cacheKey(a) !== Library.cacheKey(b));
        verify(Library.cacheKey(a) !== Library.cacheKey(c));
        compare(Library.cacheKey(a), Library.cacheKey({ path: "/a.mp4", size: 10, modified: 5400 }),
                "within the same second");
    }
}

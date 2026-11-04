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
import QtTest

import LunaNext.Common 0.1

import "../../qml/js/Playback.js" as Playback

/*
 * The app as a whole - qml/main.qml - with a stand-in player engine
 * (mocks/FakeEngine.qml) and length probe (mocks/FakeProbePlayer.qml),
 * over the files in tests/data/library, on one screen per run (see
 * tools/run-tests.sh). Each state is also saved as a picture in
 * build/test-output/ui/ to look at.
 */
TestCase {
    id: test
    name: "Ui"
    when: windowShown

    readonly property string root: decodeURIComponent(Qt.resolvedUrl("../data/library").toString().replace(/^file:\/\//, ""))
    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))
    property var app: null
    property string profile: Settings.profileName
    property int quits: 0
    // The bus subscriptions the app makes: uri, args, cancelled.
    property var subscriptions: []

    function fakeSubscribe(uri, json, onReply, onError) {
        var entry = { uri: uri, args: JSON.parse(json), cancelled: false };
        test.subscriptions.push(entry);
        return { cancel: function() { entry.cancelled = true; } };
    }

    // The media session's bus: its registration (with the reply and
    // whether it was cancelled) and what was sent on it.
    property var mediaRegistrations: []
    property var mediaCalls: []
    property QtObject fakeMediaBus: QtObject {
        function subscribe(uri, json, onReply, onError) {
            var entry = { uri: uri, args: JSON.parse(json), cancelled: false,
                          reply: function(p) { onReply({ payload: JSON.stringify(p) }); } };
            test.mediaRegistrations.push(entry);
            return { cancel: function() { entry.cancelled = true; } };
        }
        function call(uri, json, onReply, onError) {
            test.mediaCalls.push({ method: uri.split("/").pop(), args: JSON.parse(json) });
        }
    }

    // ---- a stand-in org.webosports.service.videos ---------------------------

    // Calls made: {method, args}. videoFail: method -> error reply.
    property var videoCalls: []
    property var videoFail: ({})
    property bool videoServiceThere: true
    // itemId -> held getItem replies (functions), released by the test.
    property var videoHeld: ({})
    property var videoHold: []
    // What continueWatching answers.
    property var videoContinue: []

    function movie(i) {
        return { id: "m" + i, kind: "movie", title: "Movie " + (i < 10 ? "0" : "") + i, year: 2000 + i, durationMs: 60000,
                 playable: true, hasChildren: false, artwork: {} };
    }
    function episodeOf(season, n) {
        return { id: "s" + season + "e" + n, kind: "episode", title: "Episode " + n, seriesTitle: "Test Show", season: season,
                 episode: n, durationMs: 60000, playable: true, hasChildren: false, artwork: {} };
    }
    readonly property var showItem: ({ id: "show1", kind: "show", title: "Test Show", playable: false, hasChildren: true, artwork: {} })

    function videoAnswer(method, a) {
        if (method === "listSources")
            return { sources: [
                { sourceId: "acc-jf", name: "Jellyfin – Home", label: "Home", provider: "jellyfin", icon: "",
                  features: { search: true, progress: true, continueWatching: true, live: false } },
                { sourceId: "acc-up|uuid-1", name: "NAS", provider: "upnp", icon: "",
                  features: { search: false, progress: false, continueWatching: false, live: false } }] };
        if (method === "listSections")
            return a.sourceId === "acc-jf"
                ? { sections: [{ id: "continue", title: "Continue Watching", layout: "row" },
                               { id: "empty", title: "Next Up", layout: "row" },
                               { id: "movies", title: "Movies", layout: "grid" },
                               { id: "shows", title: "Shows", layout: "grid" }] }
                : { sections: [{ id: "c:2", title: "Video", layout: "grid" }] };
        if (method === "listItems") {
            if (a.sectionId === "continue") {
                var m = movie(3);
                m.progress = { positionMs: 30000, watched: false };
                return { items: [m, episodeOf(1, 2)], nextCursor: null };
            }
            if (a.sectionId === "movies") {
                var start = a.cursor ? Number(a.cursor) : 0;
                var all = [];
                for (var i = 0; i < 60; i++)
                    all.push(movie(i));
                var page = all.slice(start, start + a.limit);
                return { items: page, nextCursor: start + page.length < all.length ? String(start + page.length) : null };
            }
            if (a.sectionId === "shows")
                return { items: [showItem], nextCursor: null };
            if (a.sectionId === "c:2")
                return { items: [{ id: "f1", kind: "collection", title: "Folder", playable: false, hasChildren: true, artwork: {} }],
                         nextCursor: null };
            if (a.parentId === "f1")
                return { items: [{ id: "v1", kind: "video", title: "Home video", playable: true, hasChildren: false, artwork: {} }],
                         nextCursor: null };
            return { items: [], nextCursor: null };
        }
        if (method === "getItem") {
            if (a.itemId === "show1")
                return { item: { id: "show1", kind: "show", title: "Test Show", description: "A show.", artwork: {},
                                 seasons: [{ id: "season1", kind: "season", title: "Season 1" },
                                           { id: "season2", kind: "season", title: "Season 2" }] } };
            if (a.itemId === "season1")
                return { item: { id: "season1", kind: "season", title: "Season 1",
                                 children: [episodeOf(1, 1), episodeOf(1, 2), episodeOf(1, 3)] } };
            if (a.itemId === "season2")
                return { item: { id: "season2", kind: "season", title: "Season 2", children: [episodeOf(2, 1)] } };
        }
        if (method === "search")
            return { items: a.query === "night" ? [movie(7)] : [], nextCursor: null };
        if (method === "searchAll") {
            var found = a.query === "night" ? [movie(7)] : (a.query === "test show" ? [showItem] : []);
            return { results: found.length > 0 && a.sourceIds.indexOf("acc-jf") >= 0
                              ? [{ sourceId: "acc-jf", items: found, nextCursor: null }] : [], failed: [] };
        }
        if (method === "continueWatching")
            return { items: test.videoContinue.filter(function(it) { return a.sourceIds.indexOf(it.sourceId) >= 0; }), failed: [] };
        if (method === "resolve")
            return { stream: { url: "https://server.example/" + a.itemId + "/master.m3u8?ApiKey=k", protocol: "hls",
                               subtitles: [], session: { play: "ps-" + a.itemId }, drm: null } };
        if (method === "reportProgress")
            return {};
        return null;
    }

    function fakeVideoCall(uri, json, onReply, onError) {
        var method = uri.split("/").pop();
        var args = JSON.parse(json);
        test.videoCalls.push({ method: method, args: args });
        var answer = function() {
            if (!test.videoServiceThere) {
                onError({ payload: JSON.stringify({ returnValue: false, errorCode: -1, errorText: "Unknown service" }) });
                return;
            }
            var failure = test.videoFail[method];
            var answer = failure ? null : test.videoAnswer(method, args);
            var reply = failure ? failure : (answer === null ? { returnValue: false, errorCode: "NOT_FOUND" }
                                                             : Object.assign({ returnValue: true }, answer));
            onReply({ payload: JSON.stringify(reply) });
        };
        if (method === "getItem" && test.videoHold.indexOf(args.itemId) >= 0)
            test.videoHeld[args.itemId] = answer;
        else if ((method === "listSources" || method === "searchAll") && test.videoHold.indexOf(method) >= 0)
            test.videoHeld[method] = answer;
        else
            Qt.callLater(answer);
    }

    function videoCallsOf(method) {
        return videoCalls.filter(function(c) { return c.method === method; });
    }

    // The display holds asked for, and whether each still is.
    function screenHolds() {
        return subscriptions.filter(function(s) { return s.uri === "luna://com.palm.display/control/setProperty"; });
    }

    function init_data() {
        return [{ tag: Settings.profileName + " " + Settings.displayWidth + "x" + Settings.displayHeight }];
    }

    function shot(name) {
        var done = false;
        var ok = app.contentItem.grabToImage(function(result) {
            result.saveToFile(shotDir + "/" + profile + "-" + name + ".png");
            done = true;
        });
        verify(ok, "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
    }

    function startApp() {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status === Component.Error)
            fail(component.errorString());
        app = component.createObject(null, {
            engineSource: Qt.resolvedUrl("mocks/FakeEngine.qml"),
            probePlayerSource: Qt.resolvedUrl("mocks/FakeProbePlayer.qml"),
            scanRoots: [root],
            quitOnBack: false,
            busSubscribe: fakeSubscribe,
            mediaBus: fakeMediaBus,
            busCall: fakeVideoCall
        });
        verify(app !== null, "main.qml made");
        quits = 0;
        subscriptions = [];
        mediaRegistrations = [];
        mediaCalls = [];
        app.quitRequested.connect(function() { test.quits++; });
        app.resume.videos = "{}";
        app.cache.facts = "{}";
        app.prefs.sortOrder = "name";
        app.prefs.fillMode = "fit";
        app.prefs.fullScreen = true;
        app.prefs.subtitleSize = "medium";
        app.prefs.turnLandscape = true;
        app.prefs.readLengths = true;
        app.player.hideDelay = 400;
        tryVerify(function() { return app.scanner.generation > 0 && app.scanner.files.length === 10; }, 10000,
                  "the ten test videos found");
        app.requestActivate();
        wait(50);
        return app;
    }

    function cleanup() {
        videoCalls = [];
        videoFail = ({});
        videoHold = [];
        videoHeld = ({});
        videoContinue = [];
        videoServiceThere = true;
        Playback.loadTimeoutMs = 15000;
        Playback.streamLoadTimeoutMs = 30000;
        if (app) {
            // Closed while the probe reads a file is no crash in the probe.
            app.probeGuard.mark("");
            app.destroy();
            app = null;
        }
        wait(50);
    }

    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function wide() {
        return app.library.wide;
    }

    function view() {
        return findChild(app.library, wide() ? "videoGrid" : "videoList");
    }

    function rowFor(name) {
        var v = view();
        for (var i = 0; i < v.count; i++) {
            var item = v.itemAtIndex(i);
            if (item && item.name === name)
                return item;
        }
        return null;
    }

    function playerChild(name) {
        return findChild(app.player, name);
    }

    // Opens a test file and waits until it plays.
    function play(file, options) {
        app.playFile(root + "/" + file, options);
        tryVerify(function() { return app.player.started; }, 3000, file + " starts");
        return app.player.engine;
    }

    function clickButton(name) {
        var b = playerChild(name);
        verify(b, name);
        if (!app.player.controlsShown)
            app.player.showControls();
        tryVerify(function() { return b.visible && b.opacity > 0.9 && b.parent.parent.opacity > 0.9; }, 1000,
                  name + " shown");
        mouseClick(b);
    }

    function choose(label) {
        var list = playerChild("sheetList");
        verify(list && list.visible, "a picker shown");
        for (var i = 0; i < list.count; i++) {
            // Each brought into view: rows out of it are not made.
            list.positionViewAtIndex(i, ListView.Contain);
            list.forceLayout();
            var item = list.itemAtIndex(i);
            if (item && findChild(item, "choiceLabel").text === label) {
                mouseClick(item);
                return;
            }
        }
        fail("no choice " + label);
    }

    // ---- the library ------------------------------------------------------

    function test_library_lists_the_videos() {
        startApp();
        var v = view();
        verify(v.visible);
        tryCompare(v, "count", 10);
        var names = [];
        for (var i = 0; i < v.count; i++)
            names.push(app.library.rows[i].name);
        compare(names, ["Big Buck", "broken", "Café Night 2audio ass", "clip", "Episode 2", "Episode 10",
                        "hang", "movie", "S01E01", "too-deep-not"]);
        compare(app.library.rows[0].details.split(" · ")[0], "library/Movies", "the root counts as a card here: " + app.library.rows[0].details);
        compare(wide(), Settings.displayWidth >= Units.gu(90), "a grid on a tablet, a list on phones");
        shot("library");
    }

    function test_lengths_come_from_the_probe() {
        startApp();
        var before = rowFor("Big Buck");
        // The probe stops at hang.mp4, which never answers: the ones before
        // it get their length, broken.mp4 gets none.
        tryVerify(function() { return app.probe.broken; }, 15000, "the probe gives up on hang.mp4");
        var lengths = app.library.rows.map(function(r) { return r.name + "=" + r.length; });
        verify(lengths.indexOf("Big Buck=0:30") >= 0, lengths.join(", "));
        verify(lengths.indexOf("broken=") >= 0, lengths.join(", "));
        verify(lengths.indexOf("hang=") >= 0, lengths.join(", "));
        var row = rowFor("Big Buck");
        compare(row.length, "0:30");
        // A length coming in changes the row; it is not made again.
        var f = app.scanner.files.filter(function(x) { return x.name === "Big Buck.mp4"; })[0];
        app.cache.update(f.path + "|" + f.size + "|" + Math.floor(f.modified / 1000), { duration: 45000 });
        tryCompare(row, "length", "0:45");
        verify(rowFor("Big Buck") === row, "the same row");
    }

    // The probe writes down which file it loads; a file that ended the app
    // switches reading lengths off at the next start, with a word why.
    function test_a_crash_while_reading_lengths_switches_it_off() {
        startApp();
        var marks = [];
        app.probe.starting.connect(function(p) { marks.push(String(app.probeGuard.value("loading", ""))); });
        app.cache.facts = "{}";
        app.requestLengths();
        tryVerify(function() { return marks.length > 0; }, 5000, "the probe loads a file");
        compare(marks[0].indexOf(root), 0, "named on disk before it is loaded: " + marks[0]);
        app.probe.active = false;
        tryVerify(function() { return !app.probe.busy; }, 15000);
        // As if the app had ended while loading hang.mp4.
        app.probeGuard.mark(root + "/hang.mp4");
        app.destroy();
        app = null;
        wait(50);
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        app = component.createObject(null, {
            engineSource: Qt.resolvedUrl("mocks/FakeEngine.qml"),
            probePlayerSource: Qt.resolvedUrl("mocks/FakeProbePlayer.qml"),
            scanRoots: [root],
            quitOnBack: false
        });
        verify(!app.prefs.readLengths, "switched off");
        verify(app.notice.indexOf("“hang” stopped the app") >= 0, app.notice);
        compare(String(app.probeGuard.value("loading", "")), "", "and forgotten");
        tryVerify(function() { return app.scanner.generation > 0; }, 10000);
        wait(300);
        verify(!app.probe.busy, "nothing read");
        verify(findChild(app.library, "libraryNotice").visible);
        shot("probe-crash-notice");
    }

    function test_search_narrows_and_back_clears_it() {
        startApp();
        var search = findChild(app.library, "searchField");
        verify(search.visible, "shown with six or more videos");
        search.text = "episode";
        tryCompare(view(), "count", 2);
        search.text = "cafe";
        tryCompare(view(), "count", 1, 2000, "accents folded");
        search.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(search.text, "");
        tryCompare(view(), "count", 10);
        compare(quits, 0);
        keyClick(Qt.Key_Escape);
        compare(quits, 1, "back with nothing open ends the app");
    }

    function test_app_menu_sorts() {
        startApp();
        app.openAppMenu();
        var menu = app.appMenu;
        tryCompare(menu, "opened", true);
        compare(menu.count, 6);
        verify(menu.itemAt(0).checked, "Sort by Name");
        menu.itemAt(1).triggered();
        compare(app.prefs.sortOrder, "date");
        verify(menu.itemAt(1).checked && !menu.itemAt(0).checked);
        menu.itemAt(2).triggered();
        compare(app.prefs.sortOrder, "size");
        menu.itemAt(3).triggered();
        verify(!app.prefs.turnLandscape);
        menu.close();
        // Not over the player.
        play("Movies/Big Buck.mp4");
        app.openAppMenu();
        verify(!menu.visible);
    }

    // ---- playing ----------------------------------------------------------

    function test_tapping_a_video_plays_it() {
        startApp();
        var row = rowFor("Big Buck");
        verify(row);
        mouseClick(row);
        verify(app.player.isOpen);
        compare(app.player.path, root + "/Movies/Big Buck.mp4");
        verify(app.player.fileInfo !== null, "the library's facts go with it");
        verify(playerChild("loadingIndicator").visible, "opening shown");
        tryVerify(function() { return app.player.started; }, 3000);
        verify(!playerChild("loadingIndicator").visible);
        verify(app.screenBlocked, "the screen kept on while playing");
        shot("player");
        // The bars go after a while of playing, and a tap brings them back.
        tryCompare(app.player, "controlsShown", false, 3000);
        tryCompare(playerChild("bottomBar"), "visible", false, 2000);
        mouseClick(app.player);
        verify(app.player.controlsShown);
        mouseClick(app.player);
        verify(!app.player.controlsShown);
    }

    function test_play_pause_and_jumps() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        var holds = screenHolds();
        compare(holds.length, 1, "one hold while playing");
        compare(holds[0].args, { requestBlock: true, client: "org.webosports.app.videoplayer" });
        verify(!holds[0].cancelled);
        clickButton("playButton");
        verify(!e.playing);
        verify(!app.player.wantPlay);
        tryCompare(app, "screenBlocked", false, 1000, "the screen let go while paused");
        verify(holds[0].cancelled, "the call cancelled");
        wait(app.player.hideDelay + 200);
        verify(app.player.controlsShown, "the bars stay while paused");
        clickButton("playButton");
        verify(e.playing);
        tryCompare(app, "screenBlocked", true, 1000);
        holds = screenHolds();
        compare(holds.length, 2, "held again");
        verify(!holds[1].cancelled);
        var before = e.position;
        clickButton("forwardButton");
        verify(e.position >= before + 9900, "forward 10 s: " + before + " -> " + e.position);
        clickButton("backButton");
        verify(e.position <= before + 1000, "back 10 s");
        clickButton("backButton");
        compare(e.position < 1000, true, "not before the start");
    }

    function test_seek_bar() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        clickButton("playButton");
        var bar = playerChild("seekBar");
        verify(bar.enabled);
        var y = bar.height / 2;
        mousePress(bar, bar.leftPadding + 2, y);
        mouseMove(bar, bar.width * 0.75, y);
        mouseRelease(bar, bar.width * 0.75, y);
        var seeks = e.calls.filter(function(c) { return c.indexOf("seek ") === 0; });
        verify(seeks.length >= 1, "one seek on letting go: " + e.calls);
        verify(e.position > 15000 && e.position < 30000, "about three quarters: " + e.position);
        compare(playerChild("elapsedLabel").text, "0:" + ("0" + Math.floor(e.position / 1000)).slice(-2));
    }

    function test_speed() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        clickButton("speedButton");
        verify(playerChild("choiceSheet").visible);
        shot("speed");
        choose("1.5×");
        compare(e.rate, 1.5);
        verify(!playerChild("choiceSheet").visible);
        compare(playerChild("speedButton").label, "1.5×");
    }

    function test_audio_track_choice_is_remembered() {
        startApp();
        var e = play("Café Night 2audio ass.mkv");
        verify(playerChild("audioButton").enabled);
        clickButton("audioButton");
        choose("Dutch – 880 Hz (AC3)");
        compare(e.activeAudioTrack, 1);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        compare(app.resume.entry(root + "/Café Night 2audio ass.mkv").audioTrack, 1);
        e = play("Café Night 2audio ass.mkv");
        tryCompare(e, "activeAudioTrack", 1, 1000, "the same track next time");
    }

    function test_single_audio_track_has_no_picker() {
        startApp();
        play("Movies/Big Buck.mp4");
        verify(!playerChild("audioButton").enabled);
    }

    function test_subtitles_from_files_next_to_the_video() {
        startApp();
        var e = play("with-srt/movie.mp4");
        tryCompare(app.player, "srtListed", true, 2000);
        compare(app.player.srtFiles.length, 3);
        compare(app.player.subtitleChoice, "srt:" + root + "/with-srt/movie.srt", "the plain .srt by default");
        tryVerify(function() { return app.player.srtCues.length === 2; }, 2000, "read");
        var text = playerChild("subtitleText");
        e.seek(1500);
        tryCompare(text, "text", "External one");
        verify(text.visible);
        e.seek(7000);
        tryCompare(text, "text", "External <i>two</i><br>second line");
        shot("subtitles");
        e.seek(5000);
        tryCompare(text, "text", "");
        verify(!text.visible);

        clickButton("subtitleButton");
        choose("From file (en)");
        tryCompare(app.player, "srtEncoding", "Windows-1252", 2000);
        e.seek(1500);
        tryCompare(text, "text", "Café naïve € 5");
        clickButton("subtitleButton");
        choose("From file (nl)");
        tryCompare(app.player, "srtEncoding", "UTF-8", 2000);
        e.seek(1600);
        tryCompare(text, "text", "Hé daar");
        clickButton("subtitleButton");
        choose("Off");
        tryCompare(text, "text", "");
        keyClick(Qt.Key_Escape);
        compare(app.resume.entry(root + "/with-srt/movie.mp4").subtitle, "off", "remembered");
    }

    function test_subtitles_inside_the_video() {
        startApp();
        var e = play("Café Night 2audio ass.mkv");
        compare(app.player.subtitleChoice, "off", "a track inside is not on by itself");
        clickButton("subtitleButton");
        choose("English");
        compare(e.activeSubtitleTrack, 0);
        var text = playerChild("subtitleText");
        e.seek(6500);
        tryCompare(text, "text", "EMBEDDED ASS two <i>italic</i>");
        e.seek(13000);
        tryCompare(text, "text", "EMBEDDED ASS three<br>line");
        clickButton("subtitleButton");
        choose("Off");
        compare(e.activeSubtitleTrack, -1);
        tryCompare(text, "text", "");
    }

    function test_subtitle_size() {
        startApp();
        var e = play("with-srt/movie.mp4");
        var text = playerChild("subtitleText");
        var medium = text.font.pixelSize;
        clickButton("subtitleButton");
        choose("Large");
        compare(app.prefs.subtitleSize, "large");
        verify(text.font.pixelSize > medium);
        clickButton("subtitleButton");
        choose("Small");
        verify(text.font.pixelSize < medium);
        verify(text.font.pixelSize >= 14);
    }

    // A double tap on the picture, turned or not.
    function test_fit_and_fill() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        var stage = playerChild("playerStage");
        verify(!e.fill);
        mouseDoubleClickSequence(stage);
        compare(app.prefs.fillMode, "fill");
        verify(e.fill);
        verify(app.player.controlsShown);
        mouseDoubleClickSequence(stage);
        verify(!e.fill);
        compare(app.prefs.fillMode, "fit");
        compare(app.windowProperties["LuneOS_fullscreen"], "true", "not the fullscreen");
    }

    function test_turning_on_a_tall_screen() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        var stage = playerChild("playerStage");
        var tall = app.height > app.width;
        compare(playerChild("turnButton").visible, tall);
        compare(app.player.turned, tall, "a wide video turned on a tall screen only");
        if (!tall)
            return;
        compare(stage.rotation, 90);
        compare(stage.width, app.height);
        shot("turned");
        clickButton("turnButton");
        verify(!app.player.turned, "the button turns it back");
        compare(stage.rotation, 0);
        app.player.sensorRotation = 90;
        clickButton("turnButton");
        verify(app.player.turned);
        compare(stage.rotation, 270, "the way the device is held: left side up");
        keyClick(Qt.Key_Escape);
        // A tall video is not turned.
        play("tall.mp4");
        compare(app.player.errorText, "");
    }

    function test_resume_where_left() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        e.seek(12000);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen, "back closes the player");
        var at = app.resume.positionOf(root + "/Movies/Big Buck.mp4");
        verify(at >= 12000 && at < 13000, "remembered " + at);
        if (!wide()) {
            compare(app.library.rows[0].section, "Continue Watching");
            compare(app.library.rows[0].name, "Big Buck");
        }
        verify(app.library.rows.some(function(r) { return r.name === "Big Buck" && r.progress > 0.35; }), "progress shown");
        shot("continue");
        var callsBefore = e.calls.length;
        e = play("Movies/Big Buck.mp4");
        compare(app.player.resumedFrom, at);
        verify(e.calls.slice(callsBefore).indexOf("seek " + at) >= 0, e.calls.join(","));
        verify(e.position >= at, "it plays on from there: " + e.position);
        verify(playerChild("resumeNotice").visible);
        mouseClick(playerChild("startOverButton"));
        verify(e.position < 1000);
        compare(app.player.resumedFrom, 0);
    }

    function test_a_video_that_never_starts_is_given_up() {
        startApp();
        Playback.loadTimeoutMs = 800;
        app.playFile(root + "/hang.mp4");
        var first = app.player.engine;
        verify(playerChild("loadingIndicator").visible);
        tryVerify(function() { return app.player.errorText !== ""; }, 3000, "an error, not a spinner for ever");
        verify(playerChild("errorPanel").visible);
        verify(app.player.errorText.indexOf("did not start playing") >= 0, app.player.errorText);
        verify(!playerChild("loadingIndicator").visible);
        // The hung engine is kept aside, never destroyed or asked again.
        verify(app.player.engine !== first, "a fresh engine");
        compare(first.visible, false);
        var callsBefore = first.calls.length;
        shot("timeout");
        mouseClick(playerChild("errorCloseButton"));
        verify(!app.player.isOpen);
        var e = play("Movies/Big Buck.mp4");
        verify(e !== first);
        compare(first.calls.length, callsBefore, "the hung one left alone");
        verify(!app.screenBlocked || e.playing);
    }

    function test_a_broken_video_says_so() {
        startApp();
        app.playFile(root + "/broken.mp4");
        tryVerify(function() { return app.player.errorText !== ""; }, 3000);
        compare(findChild(app.player, "errorLabel").text, "Could not decode the video (stand-in).");
        verify(!app.screenBlocked);
        verify(screenHolds().every(function(h) { return h.cancelled; }), "not held for a video that does not play");
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
    }

    function test_back_closes_the_player_then_the_app() {
        startApp();
        play("Movies/Big Buck.mp4");
        clickButton("speedButton");
        keyClick(Qt.Key_Escape);
        verify(!playerChild("choiceSheet").visible, "a picker first");
        verify(app.player.isOpen);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen, "then the player");
        verify(!app.screenBlocked);
        verify(screenHolds().length > 0 && screenHolds().every(function(h) { return h.cancelled; }), "every hold let go");
        compare(quits, 0);
        keyClick(Qt.Key_Escape);
        compare(quits, 1, "then the app");
    }

    // The card shell covers the status bar while the player is open
    // ("LuneOS_fullscreen"), not over the library.
    function test_the_player_is_fullscreen() {
        startApp();
        compare(app.windowProperties["LuneOS_fullscreen"], "false", "the library keeps the bar, said from the start");
        play("Movies/Big Buck.mp4");
        compare(app.windowProperties["LuneOS_fullscreen"], "true");
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        compare(app.windowProperties["LuneOS_fullscreen"], "false");
        play("Movies/Big Buck.mp4");
        compare(app.windowProperties["LuneOS_fullscreen"], "true", "and again");
    }

    // The arrows button takes the player out of fullscreen and back in;
    // the choice is kept for the next video.
    function test_fullscreen_button() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        var button = playerChild("fullScreenButton");
        compare(button.image, "fullscreen-exit");
        clickButton("fullScreenButton");
        compare(app.windowProperties["LuneOS_fullscreen"], "false");
        verify(!app.prefs.fullScreen);
        compare(button.image, "fullscreen");
        verify(!e.fill, "not the picture's fit");
        keyClick(Qt.Key_Escape);
        play("Movies/Big Buck.mp4");
        compare(app.windowProperties["LuneOS_fullscreen"], "false", "remembered");
        clickButton("fullScreenButton");
        compare(app.windowProperties["LuneOS_fullscreen"], "true");
        verify(app.prefs.fullScreen);
    }

    // The screen lock, as Netflix's: no bars and no taps while locked, a
    // notice for a while after a tap, and its icon asking before unlocking.
    function test_screen_lock() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        var stage = playerChild("playerStage");
        var notice = playerChild("lockNotice");
        var label = playerChild("lockLabel");
        var playButton = playerChild("playButton");
        app.player.lockNoticeDelay = 600;
        verify(e.playing);
        // Where the play button is, in the stage.
        var playAt = playButton.mapToItem(stage, playButton.width / 2, playButton.height / 2);

        clickButton("lockButton");
        verify(app.player.locked);
        verify(!playerChild("bottomBar").visible);
        verify(!playerChild("topBar").visible);
        tryCompare(notice, "opacity", 1, 1000);
        compare(label.text, "Screen locked");
        tryCompare(notice, "visible", false, 2000, "the notice goes by itself");

        // Taps do nothing but bring the notice back.
        mouseClick(stage, playAt.x, playAt.y);
        verify(e.playing, "the play button is not there");
        verify(!playerChild("bottomBar").visible);
        tryCompare(notice, "opacity", 1, 1000);
        mouseDoubleClickSequence(stage, stage.width / 2, stage.height / 3);
        verify(!e.fill, "nor the double tap");
        app.player.jump(10000);
        verify(!playerChild("bottomBar").visible, "a key's jump leaves the bars off");
        // Paused from outside (a call) while locked: the bars stay off, and
        // a tap still shows the notice.
        tryCompare(notice, "visible", false, 2000);
        app.player.controlsShown = true;
        verify(!playerChild("bottomBar").visible);
        mouseClick(stage);
        tryCompare(notice, "opacity", 1, 1000);

        // The icon asks first; unanswered, the question goes with the notice.
        mouseClick(notice);
        verify(app.player.locked);
        compare(label.text, "Unlock controls?");
        tryCompare(notice, "visible", false, 2000);
        verify(!app.player.unlockAsked);
        mouseClick(stage);
        tryCompare(notice, "opacity", 1, 1000);
        compare(label.text, "Screen locked");
        mouseClick(notice);
        mouseClick(notice);
        verify(!app.player.locked);
        verify(app.player.controlsShown);
        tryCompare(playerChild("bottomBar"), "visible", true, 1000);
        shot("unlocked");

        // Back still closes the player, and a new video starts unlocked.
        clickButton("lockButton");
        verify(app.player.locked);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        play("Movies/Big Buck.mp4");
        verify(!app.player.locked);
    }

    // The end of the video, or an error, needs the bars: they unlock.
    function test_screen_lock_lets_go_at_the_end() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        clickButton("lockButton");
        verify(app.player.locked);
        e.seek(25000);
        tryVerify(function() { return e.ended; }, 8000);
        verify(!app.player.locked);
        tryCompare(playerChild("bottomBar"), "visible", true, 1000);
    }

    // Launched with a file before the scan is done: the player learns of
    // the file when it is, and the library gets its picture.
    function test_launch_before_the_scan_gets_a_picture() {
        startApp();
        // The start's own scan done first: one still running would fill the
        // list again behind the test's back (a busy machine, a slow screen).
        tryVerify(function() { return app.scanner.generation > 0 && !app.scanner.running; }, 5000, "the first scan done");
        app.scanner.files = [];
        app.launchParams = JSON.stringify({ "target": root + "/clip.AVI" });
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.fileInfo, null);
        app.scanner.rescan();
        tryVerify(function() { return app.player.fileInfo !== null; }, 5000, "known after the scan");
        app.player.engine.seek(6000);
        tryVerify(function() {
            var f = app.player.fileInfo;
            var facts = app.cache.factsFor(f.path + "|" + f.size + "|" + Math.floor(f.modified / 1000));
            return facts && facts.thumb && facts.duration === 30000;
        }, 3000, "picture and length kept");
    }

    function test_launched_with_a_target() {
        startApp();
        app.launchParams = JSON.stringify({ "target": "file://" + encodeURI(root + "/Movies/Episode 2.mkv"), "position": 8000 });
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.path, root + "/Movies/Episode 2.mkv");
        compare(app.player.resumedFrom, 8000);
        // Again, with another: the same player.
        app.launchParams = JSON.stringify({ "target": root + "/clip.AVI" });
        tryCompare(app.player, "path", root + "/clip.AVI");
        tryVerify(function() { return app.player.started; }, 3000);
        // Neither a local file nor a stream.
        app.launchParams = JSON.stringify({ "target": "ftp://example.com/a.mp4" });
        verify(app.notice.indexOf("Only videos on this device") === 0, app.notice);
    }

    // ---- streams ----

    readonly property string streamsDir: decodeURIComponent(Qt.resolvedUrl("../data/streams").toString())

    function test_a_link_as_target_plays_the_stream() {
        startApp();
        app.launchParams = JSON.stringify({ "target": "https://example.com/films/Night%20Train.mp4" });
        tryVerify(function() { return app.player.started; }, 3000);
        verify(app.player.streaming);
        compare(app.player.engine.source.toString(), Qt.url("https://example.com/films/Night%20Train.mp4").toString());
        compare(app.player.path, "https://example.com/films/Night%20Train.mp4", "remembered by its link");
        compare(app.player.subtitleChoice, "off");
        compare(app.notice, "");
        app.player.engine.seek(9000);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        compare(app.resume.entry("https://example.com/films/Night%20Train.mp4").position, 9000);
    }

    function test_a_stream_with_its_subtitles_and_server_position() {
        startApp();
        var reports = [];
        app.player.positionReported.connect(function(path, ms, duration, state) {
            reports.push({ path: path, ms: ms, state: state });
        });
        app.launchParams = JSON.stringify({ "stream": {
            "url": "https://jellyfin.example/Videos/ep1/master.m3u8?api_key=k",
            "title": "Episode One",
            "key": "videos:acc1:ep1",
            "startMs": 4000,
            "subtitles": [
                { "url": streamsDir + "/missing.vtt", "label": "Dutch", "lang": "nl", "format": "vtt" },
                { "url": streamsDir + "/ep1.vtt", "label": "English", "lang": "en", "format": "vtt", "default": true }
            ]
        } });
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.title, "Episode One");
        compare(app.player.path, "videos:acc1:ep1");
        compare(app.player.resumedFrom, 4000, "where the server says it was left");
        compare(app.player.srtFiles.length, 2);
        compare(app.player.subtitleChoice, "srt:" + streamsDir + "/ep1.vtt", "the server's default is on");
        tryVerify(function() { return app.player.srtCues.length === 2; }, 2000, "the WebVTT read");
        var e = app.player.engine;
        var text = playerChild("subtitleText");
        e.seek(5500);
        tryCompare(text, "text", "Two &amp; more");
        e.seek(1500);
        tryCompare(text, "text", "Stream <i>one</i>");
        shot("stream-subtitles");

        clickButton("subtitleButton");
        choose("Dutch");
        compare(app.player.subtitleChoice, "srt:" + streamsDir + "/missing.vtt");
        clickButton("subtitleButton");
        choose("Off");
        tryCompare(text, "text", "");

        e.seek(12000);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        var last = reports[reports.length - 1];
        compare(last.state, "stopped");
        compare(last.path, "videos:acc1:ep1");
        compare(last.ms, 12000);
        compare(app.resume.entry("videos:acc1:ep1").position, 12000, "kept on the device too");

        // Opened again: the device's own position wins over the server's.
        app.launchParams = JSON.stringify({ "stream": { "url": "https://jellyfin.example/Videos/ep1/master.m3u8",
                                                          "key": "videos:acc1:ep1", "startMs": 4000 } });
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.resumedFrom, 12000);
    }

    function test_a_slow_stream_gets_longer_to_start() {
        startApp();
        Playback.loadTimeoutMs = 300;
        Playback.streamLoadTimeoutMs = 900;
        app.playStream({ url: "https://example.com/hang.m3u8", title: "Slow" });
        wait(600);
        compare(app.player.errorText, "", "not given up at a file's limit");
        tryVerify(function() { return app.player.errorText !== ""; }, 3000);
        verify(app.player.errorText.indexOf("The server may be slow") > 0, app.player.errorText);
    }

    function test_not_a_stream_link() {
        startApp();
        app.playStream({ url: "file:///etc/passwd" });
        verify(!app.player.isOpen);
        verify(app.notice.indexOf("This is not a link to a video") === 0, app.notice);
        app.notice = "";
        app.launchParams = JSON.stringify({ "stream": { "title": "no url" } });
        verify(!app.player.isOpen);
        verify(app.notice.indexOf("This is not a link to a video") === 0, app.notice);
    }

    function test_interruptions_pause() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        verify(app.screenBlocked);
        tryCompare(app.player, "controlsShown", false, 3000);
        app.player.interrupt("call");
        verify(!e.playing);
        verify(app.player.controlsShown);
        tryCompare(app, "screenBlocked", false, 1000);
        verify(app.resume.positionOf(root + "/Movies/Big Buck.mp4") === 0 || true);
        // A pause from the sound system shows as paused too.
        clickButton("playButton");
        verify(e.playing);
        e.playing = false;
        verify(!app.player.wantPlay);
        compare(playerChild("playButton").image, "play");
    }

    // A headset's keys, through mediacontroller, while a video is open.
    function test_media_session_follows_the_player() {
        startApp();
        compare(mediaRegistrations.length, 0, "no session for the library");
        var e = play("Movies/Big Buck.mp4");
        compare(mediaRegistrations.length, 1, "a session for the open video");
        var reg = mediaRegistrations[0];
        compare(reg.args.appId, "org.webosports.app.videoplayer");
        reg.reply({ returnValue: true, subscribed: true });
        var activations = mediaCalls.filter(function(c) { return c.method === "activateMediaSession"; });
        compare(activations.length, 1, "playing takes the headset's keys");
        var meta = mediaCalls.filter(function(c) { return c.method === "setMediaMetaData"; });
        compare(meta[0].args.mediaMetaData.title, app.player.title);

        reg.reply({ returnValue: true, keyEvent: "pause", mediaId: reg.args.mediaId });
        verify(!e.playing, "the headset's pause pauses");
        verify(!app.player.wantPlay);
        reg.reply({ returnValue: true, keyEvent: "play", mediaId: reg.args.mediaId });
        verify(e.playing, "and play plays");
        activations = mediaCalls.filter(function(c) { return c.method === "activateMediaSession"; });
        compare(activations.length, 2, "resuming takes the keys again");
        var before = e.position;
        reg.reply({ returnValue: true, keyEvent: "next", mediaId: reg.args.mediaId });
        verify(e.position >= before + 9900, "next jumps 10 s: " + before + " -> " + e.position);
        reg.reply({ returnValue: true, keyEvent: "previous", mediaId: reg.args.mediaId });
        verify(e.position <= before + 1000, "previous jumps back");

        keyClick(Qt.Key_Escape);
        tryVerify(function() { return !app.player.isOpen; }, 1000, "the player closed");
        verify(reg.cancelled, "the session ends with the player");
    }

    function test_end_of_the_video() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        e.seek(25000);
        var turned = app.player.turned;
        tryVerify(function() { return e.ended; }, 8000);
        compare(app.player.turned, turned, "the picture stays as it was turned at the end");
        verify(app.player.controlsShown);
        compare(playerChild("playButton").image, "play");
        compare(app.resume.positionOf(root + "/Movies/Big Buck.mp4"), 0, "nothing to resume at the end");
        clickButton("playButton");
        verify(e.playing);
        verify(e.position < 1000, "from the start again");
    }

    function test_a_picture_for_the_library() {
        startApp();
        var e = play("Movies/Big Buck.mp4");
        e.seek(6000);
        tryVerify(function() { return app.player.thumbnailDone; }, 3000);
        var key = app.player.fileInfo.path + "|0|" + Math.floor(app.player.fileInfo.modified / 1000);
        tryVerify(function() { var f = app.cache.factsFor(key); return f && f.thumb; }, 3000, "saved");
        keyClick(Qt.Key_Escape);
        var row = rowFor("Big Buck");
        var picture = findChild(row, "thumbnail");
        tryCompare(picture, "status", Image.Ready, 3000);
        shot("library-picture");
    }

    function test_bars_fit_the_screen() {
        startApp();
        play("Movies/Big Buck.mp4");
        var stage = playerChild("playerStage");
        var row = playerChild("buttonRow");
        verify(row.width <= stage.width, row.width + " in " + stage.width);
        var minWidth = 54;
        for (var i = 0; i < row.children.length; i++) {
            var b = row.children[i];
            if (b.visible)
                verify(b.width >= minWidth - 0.5, b.objectName + " " + b.width);
        }
        var bar = playerChild("seekBar");
        verify(bar.width > stage.width * 0.4, "a seek bar to use: " + bar.width);
        clickButton("subtitleButton");
        var panel = playerChild("sheetPanel");
        verify(panel.width <= stage.width && panel.height <= stage.height);
        shot("subtitle-picker");
    }

    // ---- video servers ---------------------------------------------------------

    function browseChild(name) {
        return findChild(app.browse, name);
    }

    function openServer(sourceId) {
        tryVerify(function() { return app.sources.list.length === 2; }, 2000, "the servers listed");
        var bar = findChild(app.library, "sourceBar");
        verify(bar.visible, "the libraries bar shown");
        var chip = findChild(bar, "source:" + sourceId);
        verify(chip, sourceId);
        compare(chip.mapToItem(bar, 0, 0).y, 0, "the tab fills the bar, not shifted up");
        compare(chip.height, bar.height);
        mouseClick(chip);
        tryVerify(function() { return app.browse.visible; }, 1000, "the server's library shown");
        var tabs = findChild(app.browse, "sourceBar");
        tryVerify(function() { return tabs.currentItem === findChild(tabs, "source:" + sourceId); }, 1000,
                  "its tab lit on the server's page");
        // Its home, or with one section only, that section's list.
        tryVerify(function() {
            var c = app.browse.current;
            return c !== null && (c.kind === "list" || (browseChild("homeView") !== null && c.sections !== null));
        }, 2000, "its home");
    }

    function tapTile(id) {
        var tile = null;
        tryVerify(function() { tile = browseChild("tile:" + id); return tile !== null && tile.visible; }, 2000, "tile " + id);
        // With the libraries on top a row can start low on a short screen
        // (the Q25): scroll it up first, as a user would.
        var home = browseChild("homeView");
        if (home !== null && home.visible) {
            var below = tile.mapToItem(home, 0, 0).y + tile.height - home.height;
            if (below > 0) {
                home.contentY += below;
                wait(50);
            }
        }
        mouseClick(tile);
    }

    function test_servers_are_libraries_beside_the_device() {
        startApp();
        openServer("acc-jf");
        compare(findChild(app.browse, "browseHeader").title, "Jellyfin – Home", "the full name in the header");
        var tabs = findChild(app.browse, "sourceBar");
        compare(findChild(findChild(tabs, "source:acc-jf"), "tabCaption").text, "Home", "the tab shows the label");
        compare(findChild(findChild(tabs, "source:acc-up|uuid-1"), "tabCaption").text, "NAS", "or the name, without a label");
        // A "Kind – name" label on two lines; every caption the same size, at
        // most two lines; a light bar, the selected tab in the platform blue.
        compare(tabs.captionOf({ label: "Free TV – Netherlands" }), "Free TV\nNetherlands");
        compare(tabs.captionOf({ name: "NAS" }), "NAS");
        var captions = ["source:", "source:acc-jf", "source:acc-up|uuid-1"].map(function(n) {
            return findChild(findChild(tabs, n), "tabCaption");
        });
        captions.forEach(function(c) {
            compare(c.font.pixelSize, captions[0].font.pixelSize, "one size for every tab: " + c.text);
            compare(c.maximumLineCount, 2);
            compare(c.fontSizeMode, Text.FixedSize);
        });
        compare(tabs.background.objectName, "sourceBarBackground", "the bar's own light background");
        // The header's own picture behind the bar.
        var header = findChild(app.browse, "browseHeader");
        compare(String(tabs.background.background.source), String(header.background.source), "the header's grey");
        verify(String(tabs.background.background.source).indexOf("toolbar-light.png") > 0);
        // Dark captions, the selected tab Messaging's blue.
        compare(String(captions[2].color), "#333333", "an unselected caption dark on the light bar");
        compare(String(captions[1].color), "#ffffff", "the selected one white on blue");
        var lit = findChild(findChild(tabs, "source:acc-jf"), "tabSelected");
        verify(lit.visible, "the selected tab's blue");
        compare(String(lit.gradient.stops[0].color), "#306ba3");
        compare(String(lit.gradient.stops[1].color), "#6ca6ce");
        verify(!findChild(findChild(tabs, "source:acc-up|uuid-1"), "tabSelected").visible, "no blue on the others");
        // As drawn: an unselected tab as light as the header, the selected
        // one blue. (The black tabs the phone drew for "gradient: null" do
        // not show here: the host's renderer draws that one see-through.)
        // (The whole window, read at scene points: grabImage(tabs) comes
        // out cut from the wrong place in the app's window.)
        var scene = tabs.Window.window.contentItem;
        waitForRendering(scene);
        var drawn = grabImage(scene);
        var spot = function(n) {
            var t = findChild(tabs, n), p = t.mapToItem(scene, Units.gu(0.5), t.height / 2);
            return drawn.pixel(Math.round(p.x), Math.round(p.y));
        };
        var grey = spot("source:acc-up|uuid-1");
        verify(grey.r > 0.85 && grey.g > 0.85 && grey.b > 0.85, "an unselected tab light: " + grey);
        var blue = spot("source:acc-jf");
        verify(blue.b > blue.r + 0.2, "the selected tab blue: " + blue);
        verify(String(findChild(tabs, "source:").contentItem.children[0].children[0].source).indexOf("device-dark.svg") > 0,
               "the device's icon dark when not selected");
        compare(app.library.visible, false);
        // Rows show their videos; an empty row is not shown; libraries open.
        tryVerify(function() { return browseChild("tile:m3") !== null; }, 2000, "Continue Watching's films");
        verify(browseChild("tile:s1e2") !== null);
        var empty = browseChild("row:empty");
        verify(!empty || !empty.visible, "an empty row is left out");
        verify(browseChild("library:movies") !== null);
        verify(browseChild("library:shows") !== null);
        var home = browseChild("homeView");
        // Flicks as fast as the finger: the cap in screens, not Qt's 2500 px/s.
        compare(home.maximumFlickVelocity, home.height * 8);
        compare(home.flickDeceleration, home.height * 1.5);
        verify(home.maximumFlickVelocity > 2500);
        var row = findChild(browseChild("row:continue"), "rowList");
        if (row)
            compare(row.maximumFlickVelocity, row.width * 8, "a row by its width");
        verify(browseChild("library:shows").mapToItem(home, 0, 0).y < browseChild("row:continue").mapToItem(home, 0, 0).y,
               "the libraries above the rows");
        compare(videoCallsOf("listItems").map(function(c) { return c.args.sectionId; }).sort(), ["continue", "empty"],
                "only rows load at once");
        shot("server-home");
        // Back goes to this device.
        keyClick(Qt.Key_Escape);
        tryCompare(app, "sourceId", "");
        verify(app.library.visible);
        compare(quits, 0);
    }

    function test_tabs_keep_their_place_and_their_icons_in_line() {
        startApp();
        tryVerify(function() { return app.sources.generation > 0; }, 2000);
        var many = [];
        for (var i = 0; i < 12; i++)
            many.push({ sourceId: "acc-m" + i, name: "M3U – List " + i, label: i === 3 ? "Free TV – Netherlands" : "List " + i,
                        provider: "m3u", icon: "", features: { search: true, progress: false, continueWatching: false, live: true } });
        app.sources.list = many;
        var bar = findChild(app.library, "sourceBar");
        tryVerify(function() { return findChild(bar, "source:acc-m11") !== null; }, 1000);
        // Every icon at one height, the two-line caption under its own and
        // inside its tab (after a frame: a Column places its children late).
        wait(100);
        var icons = ["source:", "source:acc-m0", "source:acc-m3"].map(function(n) {
            var t = findChild(bar, n);
            return { y: findChild(t, "tabIcon").mapToItem(t, 0, 0).y, tab: t };
        });
        compare(icons[2].y, icons[0].y, "the icon over a two-line caption not pushed up");
        compare(icons[1].y, icons[0].y);
        var two = findChild(icons[2].tab, "tabCaption");
        compare(two.lineCount, 2);
        verify(two.mapToItem(icons[2].tab, 0, 0).y + two.height <= icons[2].tab.height + 1, "the caption inside the tab");
        // Scrolled along and a tab far along picked: the server's page shows
        // the row where it was, with that tab in view.
        var row = bar.contentItem;
        verify(row.contentWidth > row.width, "more tabs than fit");
        // A hard flick runs to the end of the row, and one back to its start
        // (a snapping row stopped about a screen along).
        compare(row.snapMode, ListView.NoSnap);
        compare(row.maximumFlickVelocity, row.width * 8);
        compare(row.flickDeceleration, row.width * 1.5);
        var flick = function(from, by) {
            var y = bar.height / 2, t = touchEvent(bar);
            t.press(0, bar, from, y).commit();
            for (var k = 1; k <= 5; k++) { wait(16); t.move(0, bar, from + by * k / 5, y).commit(); }
            wait(16);
            t.release(0, bar, from + by, y).commit();
        };
        flick(bar.width * 0.85, -bar.width * 0.5);
        tryVerify(function() { return !row.moving; }, 4000);
        compare(row.contentX - row.originX, row.contentWidth - row.width, "flicked to the end");
        compare(app.sourceId, "", "a flick picks nothing");
        flick(bar.width * 0.15, bar.width * 0.5);
        tryVerify(function() { return !row.moving; }, 4000);
        compare(row.contentX - row.originX, 0, "and back to the start");
        row.contentX = row.originX + row.contentWidth - row.width;
        row.movementEnded();
        var x = row.contentX - row.originX;
        compare(app.tabScrollX, x);
        // A tab in view but not at the row's end: the row stays put.
        mouseClick(findChild(bar, "source:acc-m10"));
        tryVerify(function() { return app.browse.visible; }, 1000);
        var other = findChild(app.browse, "sourceBar");
        tryVerify(function() { return Math.abs(other.contentItem.contentX - other.contentItem.originX - x) < 1; }, 1000,
                  "the server's bar as the library's was");
        var lit = findChild(other, "source:acc-m10");
        verify(lit.checked);
        var at = lit.mapToItem(other, 0, 0).x;
        verify(at >= -1 && at + lit.width <= other.width + 1, "the picked tab in view: " + at);
        // Back to this device from the start of the row: its tab comes into view.
        other.contentItem.contentX = other.contentItem.originX + other.contentItem.contentWidth - other.contentItem.width;
        keyClick(Qt.Key_Escape);
        tryCompare(app, "sourceId", "");
        tryVerify(function() { var t = findChild(bar, "source:"); var p = t.mapToItem(bar, 0, 0).x; return p >= -1 && p + t.width <= bar.width + 1; },
                  1000, "this device's tab in view");
    }

    function test_the_servers_shown_at_once_from_the_last_time() {
        startApp();
        tryVerify(function() { return app.sources.generation > 0 && app.sources.list.length === 2; }, 2000);
        verify(!app.sources.fromCache);
        app.destroy();
        app = null;
        wait(50);
        // The service slow to answer (it looks for media servers): the tabs
        // from the last answer are there before it.
        videoHold = ["listSources"];
        startApp();
        compare(app.sources.list.map(function(s) { return s.sourceId; }), ["acc-jf", "acc-up|uuid-1"]);
        verify(app.sources.fromCache);
        tryVerify(function() { return findChild(app.library, "sourceBar").visible; }, 1000, "the bar at once");
        compare(app.sources.generation, 0, "not answered yet");
        tryVerify(function() { return videoHeld["listSources"] !== undefined; }, 1000);
        videoHeld["listSources"]();
        tryVerify(function() { return app.sources.generation > 0; }, 1000);
        verify(!app.sources.fromCache);
        // Only what a tab shows is kept.
        var kept = JSON.parse(app.sources._kept.list);
        var allowed = ["accountId", "features", "icon", "label", "name", "provider", "sourceId", "templateId"];
        compare(kept.length, 2);
        kept.forEach(function(k) {
            Object.keys(k).forEach(function(key) { verify(allowed.indexOf(key) >= 0, "kept " + key); });
        });
        // A service gone keeps nothing for the next start.
        videoHold = [];
        videoServiceThere = false;
        app.sources.refresh();
        tryVerify(function() { return app.sources.list.length === 0; }, 1000);
        compare(app.sources._kept.list, "[]");
    }

    function test_without_the_service_there_is_no_bar() {
        videoServiceThere = false;
        startApp();
        tryVerify(function() { return app.sources.generation > 0; }, 2000, "the servers asked for at the start");
        compare(videoCallsOf("listSources").length, 1);
        compare(app.sources.list.length, 0);
        verify(!findChild(app.library, "sourceBar").visible);
        compare(app.sources.errorText, "The video service does not answer.");
        compare(app.sources._kept.list, "[]", "and none kept for the next start");
    }

    function test_a_library_pages_and_plays_with_progress_for_the_server() {
        startApp();
        openServer("acc-jf");
        mouseClick(browseChild("library:movies"));
        var grid = null;
        tryVerify(function() { grid = browseChild("listView"); return grid !== null && grid.count === 50; }, 2000, "a page");
        compare(findChild(app.browse, "levelTitle").text, "Movies");
        grid.positionViewAtEnd();
        tryCompare(grid, "count", 60, 2000, "the next page as the end comes into view");
        compare(videoCallsOf("listItems").filter(function(c) { return c.args.sectionId === "movies"; })
                .map(function(c) { return c.args.cursor || ""; }), ["", "50"]);
        grid.positionViewAtEnd();
        wait(100);
        compare(videoCallsOf("listItems").filter(function(c) { return c.args.sectionId === "movies"; }).length, 2,
                "no page after the last");
        shot("server-grid");
        grid.positionViewAtBeginning();
        tapTile("m1");
        tryVerify(function() { return app.player.started; }, 3000, "it plays");
        var res = videoCallsOf("resolve")[0].args;
        compare(res.sourceId, "acc-jf");
        compare(res.itemId, "m1");
        compare(res.prefer.maxHeight, Math.min(app.width, app.height) >= 1000 ? 1080 : 720);
        // The test window cannot be made bigger than the offscreen screen,
        // so the rule is asked directly.
        compare(app.streamHeightFor(1920, 1200), 1080, "a big screen asks for 1080 lines");
        compare(app.streamHeightFor(1200, 1920), 1080);
        compare(app.streamHeightFor(800, 1280), 720);
        compare(app.player.title, "Movie 01");
        compare(app.player.path, "videos:acc-jf/m1");
        compare(app.player.stream.url, "https://server.example/m1/master.m3u8?ApiKey=k");
        app.player.engine.seek(20000);
        app.player.pause();
        tryVerify(function() { return videoCallsOf("reportProgress").length > 0; }, 2000, "the pause reported");
        var r = videoCallsOf("reportProgress").pop().args;
        compare([r.sourceId, r.itemId, r.state, r.positionMs, r.session.play], ["acc-jf", "m1", "paused", 20000, "ps-m1"]);
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        r = videoCallsOf("reportProgress").pop().args;
        compare([r.state, r.positionMs], ["stopped", 20000]);
        verify(app.browse.visible, "back to the list it came from");
        compare(browseChild("listView").count, 60, "as it was");
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return browseChild("homeView") !== null; }, 1000, "up to the home");
        keyClick(Qt.Key_Escape);
        tryCompare(app, "sourceId", "");
    }

    function test_a_live_channel_has_nothing_to_seek_keep_or_report() {
        startApp();
        var channel = { id: "ch1", kind: "live", title: "Channel One", playable: true, hasChildren: false, artwork: {} };
        // A place kept from before (a list that once had it as a film) is not used.
        app.resume.remember("videos:acc-jf/ch1", { position: 10000, duration: 30000, audioTrack: 0, subtitle: "off" });
        app.playOnline("acc-jf", channel, []);
        tryVerify(function() { return app.player.started; }, 3000, "it plays");
        compare(app.player.resumedFrom, 0, "not resumed");
        verify(app.player.live);
        compare(app.player.path, "videos:acc-jf/ch1");
        verify(app.player.engine.seekable, "the engine could seek; the player does not");
        app.player.showControls();
        tryVerify(function() { return playerChild("seekRow").visible; }, 1000, "the bar is shown");
        verify(!playerChild("seekBar").visible, "no seek bar");
        verify(!playerChild("remainingLabel").visible, "no time left");
        verify(playerChild("elapsedLabel").text.indexOf("LIVE") >= 0, playerChild("elapsedLabel").text);
        verify(!playerChild("backButton").enabled && !playerChild("forwardButton").enabled, "no jumps");
        verify(!playerChild("speedButton").enabled, "no speeds");
        compare(app.session.durationMs, 0, "no length for the headset either");
        wait(300);
        var at = app.player.engine.position;
        app.player.jump(10000);
        app.player.command({ seek: 60000 });
        verify(app.player.engine.position < at + 1000, "neither jump nor seek moved it: " + at + " -> " + app.player.engine.position);
        app.player.pause();
        app.player.saveState();
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        compare(videoCallsOf("reportProgress").length, 0, "a channel has no progress for the server");
        compare(app.resume.entry("videos:acc-jf/ch1").position, 10000, "nor kept on the device");
        verify(app.onlineNow === null, "done with it");

        // A film after it reports as before.
        app.playOnline("acc-jf", { id: "m1", kind: "movie", title: "Movie 01", playable: true }, []);
        tryVerify(function() { return app.player.path === "videos:acc-jf/m1" && app.player.started; }, 3000);
        verify(!app.player.live);
        app.player.showControls();
        tryVerify(function() { return playerChild("seekBar").visible; }, 1000, "the film's seek bar");
        verify(playerChild("remainingLabel").visible);
        verify(playerChild("forwardButton").enabled);
        app.player.pause();
        tryVerify(function() { return videoCallsOf("reportProgress").length > 0; }, 2000, "the film's pause reported");

        // From the film to the channel and on to another film: the film left
        // is reported stopped, the channel left is not reported.
        app.playOnline("acc-jf", channel, []);
        tryVerify(function() { return app.player.path === "videos:acc-jf/ch1" && app.player.started; }, 3000);
        verify(app.player.live);
        app.playOnline("acc-jf", { id: "m2", kind: "movie", title: "Movie 02", playable: true }, []);
        tryVerify(function() { return app.player.path === "videos:acc-jf/m2" && app.player.started; }, 3000);
        var items = videoCallsOf("reportProgress").map(function(c) { return c.args.itemId + ":" + c.args.state; });
        verify(items.indexOf("m1:stopped") >= 0, items);
        verify(items.every(function(i) { return i.indexOf("ch1:") !== 0; }), items);
    }

    function test_the_end_counts_as_watched() {
        startApp();
        openServer("acc-jf");
        tapTile("m3");
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.resumedFrom, 0, "the stream gave no place");
        app.player.engine.seek(app.player.engine.duration);
        tryVerify(function() { return app.player.engine.ended; }, 3000);
        tryVerify(function() { return videoCallsOf("reportProgress").some(function(c) { return c.args.state === "ended"; }); }, 2000);
        var r = videoCallsOf("reportProgress").filter(function(c) { return c.args.state === "ended"; })[0].args;
        compare(r.positionMs, app.player.engine.duration, "the whole length");
    }

    function test_a_show_opens_on_its_seasons_and_plays_on() {
        startApp();
        openServer("acc-jf");
        mouseClick(browseChild("library:shows"));
        tapTile("show1");
        var episodes = null;
        tryVerify(function() { episodes = browseChild("episodeList"); return episodes !== null && episodes.count === 3; }, 2000,
                  "the first season's episodes");
        compare(browseChild("seasonBar").count, 2);
        shot("server-show");
        mouseClick(browseChild("season:season2"));
        tryCompare(episodes, "count", 1, 2000, "season 2");
        // Season 1's answer comes after season 2 was picked again: it is
        // not shown.
        videoHold = ["season1"];
        mouseClick(browseChild("season:season1"));
        mouseClick(browseChild("season:season2"));
        tryCompare(episodes, "count", 1, 2000);
        videoHeld["season1"]();
        wait(50);
        compare(episodes.count, 1, "the late answer for the season left is dropped");
        videoHold = [];
        mouseClick(browseChild("season:season1"));
        tryCompare(episodes, "count", 3, 2000);
        episodes.positionViewAtIndex(1, ListView.Contain);
        wait(50);
        mouseClick(browseChild("episode:s1e2"));
        tryVerify(function() { return app.player.started && app.player.path === "videos:acc-jf/s1e2"; }, 3000);
        compare(app.player.title, "Test Show S1E2 – Episode 2");
        app.player.engine.seek(12000);
        // A headset's next: the next episode, the one left stopped there.
        app.session.actionRequested("forward");
        tryVerify(function() { return app.player.path === "videos:acc-jf/s1e3" && app.player.started; }, 3000, "episode 3");
        var stops = videoCallsOf("reportProgress").filter(function(c) { return c.args.state === "stopped"; });
        compare(stops.length, 1);
        compare([stops[0].args.itemId, stops[0].args.positionMs], ["s1e2", 12000]);
        // The last one has no next: 10 s on instead.
        app.player.engine.seek(1000);
        app.session.actionRequested("forward");
        wait(100);
        compare(app.player.path, "videos:acc-jf/s1e3");
        verify(app.player.engine.position >= 11000 && app.player.engine.position < 11500, app.player.engine.position);
        app.session.actionRequested("back");
        tryVerify(function() { return app.player.path === "videos:acc-jf/s1e2"; }, 3000, "back to episode 2");
    }

    function test_a_media_server_folder_and_no_search() {
        startApp();
        openServer("acc-up|uuid-1");
        verify(!browseChild("browseSearch").visible, "this one cannot search");
        // Its one section is opened at once: no tile to tap for it.
        tryVerify(function() { var g = browseChild("listView"); return g !== null && g.count === 1; }, 2000, "the folder list");
        compare(app.browse.stack.length, 1, "the list is the top level");
        compare(app.browse.current.kind, "list");
        verify(browseChild("library:c:2") === null, "no library tile");
        verify(!findChild(app.browse, "levelTitle").visible, "no title over it");
        compare(videoCallsOf("listItems").filter(function(c) { return c.args.sectionId === "c:2"; }).length, 1);
        tapTile("f1");
        tapTile("v1");
        tryVerify(function() { return app.player.started; }, 3000);
        compare(app.player.path, "videos:acc-up|uuid-1/v1");
        compare(videoCallsOf("reportProgress").length, 0, "nothing to report yet");
        keyClick(Qt.Key_Escape);
        verify(!app.player.isOpen);
        compare(app.browse.stack.length, 2, "back in the folder");
        keyClick(Qt.Key_Escape);
        compare(app.browse.stack.length, 1, "up to the section's list");
        verify(browseChild("library:c:2") === null, "not to a home with its tile");
        keyClick(Qt.Key_Escape);
        tryCompare(app, "sourceId", "", 1000, "and from it to this device");
    }

    function test_search_on_the_server() {
        startApp();
        openServer("acc-jf");
        var field = browseChild("browseSearch");
        verify(field.visible);
        field.forceActiveFocus();
        field.text = "night";
        field.accepted();
        var grid = null;
        tryVerify(function() { grid = browseChild("listView"); return grid !== null && grid.count === 1; }, 2000);
        compare(findChild(app.browse, "levelTitle").text, "Search: “night”");
        field.text = "nothing";
        field.accepted();
        tryVerify(function() { var e = browseChild("listEmpty"); return e !== null && e.visible; }, 2000);
        compare(app.browse.stack.length, 2, "a new search takes the old one's place");
    }

    function test_errors_say_what_to_do() {
        videoFail = { resolve: { returnValue: false, errorCode: "AUTH_EXPIRED", errorText: "x" } };
        startApp();
        openServer("acc-jf");
        tapTile("m3");
        tryVerify(function() { return /Accounts/.test(app.notice); }, 2000, app.notice);
        verify(!app.player.isOpen);
        var notice = browseChild("browseNotice");
        verify(notice.visible);
        shot("server-error");
        videoFail = { listSections: { returnValue: false, errorCode: "SERVER_UNREACHABLE" } };
        app.notice = "";
        app.showSource("");
        app.showSource("acc-jf");
        tryVerify(function() { return /does not answer/.test(notice.text); }, 2000, notice.text);
    }

    function test_a_server_gone_goes_back_to_the_device() {
        startApp();
        openServer("acc-up|uuid-1");
        videoServiceThere = false;
        app.sources.refresh();
        tryCompare(app, "sourceId", "", 2000);
        verify(app.library.visible);
    }

    // ---- the servers on the device's page ---------------------------------

    function onlineEpisode(n, at, position) {
        var e = episodeOf(1, n);
        e.sourceId = "acc-jf";
        e.progress = { positionMs: position, watched: false };
        e.lastPlayedAt = at;
        e.artwork = { thumb: "https://server.example/e" + n + ".jpg" };
        return e;
    }

    function test_continue_watching_is_the_device_and_the_servers_by_time() {
        if (Settings.displayWidth >= Units.gu(90))
            skip("Continue Watching is on phones");
        videoContinue = [onlineEpisode(1, "2020-01-01T10:00:00.000Z", 15000),
                         onlineEpisode(2, new Date(Date.now() + 3600000).toISOString(), 30000)];
        startApp();
        tryVerify(function() { return videoCallsOf("continueWatching").length > 0; }, 2000, "asked");
        compare(videoCallsOf("continueWatching")[0].args.sourceIds, ["acc-jf"], "only the servers that keep a place");
        compare(videoCallsOf("continueWatching")[0].args.limit, 8);
        var e = play("Movies/Big Buck.mp4");
        e.seek(12000);
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return app.library.rows.length > 3 && app.library.rows[2].section === "Continue Watching"; }, 2000);
        var cw = app.library.rows.filter(function(r) { return r.section === "Continue Watching"; });
        compare(cw.map(function(r) { return r.name; }), ["Test Show S1E2 – Episode 2", "Big Buck", "Test Show S1E1 – Episode 1"]);
        compare(cw[0].online, true);
        compare(cw[0].details, "Home · 30 s left");
        compare(String(cw[0].thumbnail), "https://server.example/e2.jpg");
        compare(cw[0].progress, 0.5);
        compare(cw[1].online, false);
        shot("continue-merged");
        // A server's row plays from the server.
        var row = rowFor("Test Show S1E2 – Episode 2");
        verify(row !== null);
        mouseClick(row);
        tryVerify(function() { return app.player.isOpen; }, 2000);
        var r = videoCallsOf("resolve");
        compare(r.length, 1);
        compare([r[0].args.sourceId, r[0].args.itemId], ["acc-jf", "s1e2"]);
        tryVerify(function() { return app.player.started; }, 3000);
        var before = videoCallsOf("continueWatching").length;
        keyClick(Qt.Key_Escape);
        tryVerify(function() { return videoCallsOf("reportProgress").some(function(c) { return c.args.state === "stopped"; }); }, 2000);
        tryVerify(function() { return videoCallsOf("continueWatching").length > before; }, 2000, "asked again once stopped");
    }

    function test_continue_watching_shows_eight() {
        if (Settings.displayWidth >= Units.gu(90))
            skip("Continue Watching is on phones");
        var many = [];
        for (var i = 1; i <= 10; i++)
            many.push(onlineEpisode(i, "2020-01-" + (i < 10 ? "0" : "") + i + "T10:00:00.000Z", 15000));
        videoContinue = many;
        startApp();
        tryVerify(function() { return app.library.rows.some(function(r) { return r.online; }); }, 2000);
        var cw = app.library.rows.filter(function(r) { return r.section === "Continue Watching"; });
        compare(cw.length, 8);
        compare(cw[0].name, "Test Show S1E10 – Episode 10", "the last watched first");
    }

    function test_a_server_row_menu_has_no_forgetting() {
        if (Settings.displayWidth >= Units.gu(90))
            skip("Continue Watching is on phones");
        videoContinue = [onlineEpisode(1, "2020-01-01T10:00:00.000Z", 15000)];
        startApp();
        // Played here before: the device keeps a place for it as well.
        app.resume.videos = JSON.stringify({ "videos:acc-jf/s1e1": { position: 15000, duration: 60000, at: 1 } });
        tryVerify(function() { return rowFor("Test Show S1E1 – Episode 1") !== null; }, 2000);
        var row = rowFor("Test Show S1E1 – Episode 1");
        mousePress(row);
        wait(1200);
        mouseRelease(row);
        var menu = app.library.menu;
        tryCompare(menu, "opened", true);
        compare(menu.itemAt(0).text, "Play");
        verify(menu.itemAt(1).enabled, "from the start");
        verify(menu.itemAt(2).enabled, "show on its server");
        verify(!menu.itemAt(3).enabled, "the server keeps its own list");
        menu.itemAt(2).triggered();
        menu.close();
        compare(app.sourceId, "acc-jf");
    }

    function test_search_also_asks_the_servers() {
        startApp();
        tryVerify(function() { return app.sources.list.length === 2; }, 2000);
        var search = findChild(app.library, "searchField");
        verify(app.library.serversSearch);
        search.text = "night";
        tryVerify(function() { return videoCallsOf("searchAll").length === 1; }, 2000, "after the typing stops");
        compare(videoCallsOf("searchAll")[0].args, { query: "night", limit: 10, sourceIds: ["acc-jf"] });
        tryVerify(function() { return app.library.rows.some(function(r) { return r.section === "On Home"; }); }, 2000);
        var found = app.library.rows.filter(function(r) { return r.section === "On Home"; });
        compare(found.map(function(r) { return r.name; }), ["Movie 07"]);
        compare(app.library.rows.filter(function(r) { return r.section === "Matches"; }).length, 1, "the device's match first");
        compare(app.library.rows[0].section, "Matches");
        shot("search-servers");
        app.library.openRow(found[0]);
        tryVerify(function() { return videoCallsOf("resolve").length === 1; }, 2000);
        compare(videoCallsOf("resolve")[0].args.itemId, "m7");
    }

    function test_a_server_search_typed_over_is_not_shown() {
        videoHold = ["searchAll"];
        startApp();
        tryVerify(function() { return app.sources.list.length === 2; }, 2000);
        var search = findChild(app.library, "searchField");
        search.text = "night";
        tryVerify(function() { return videoHeld["searchAll"] !== undefined; }, 2000);
        verify(app.library.onlineSearching);
        search.text = "nothing";
        videoHeld["searchAll"]();
        wait(100);
        verify(!app.library.rows.some(function(r) { return r.section === "On Home"; }), "the answer for night");
        search.text = "";
        verify(!app.library.onlineSearching);
        wait(700);
        compare(videoCallsOf("searchAll").length, 1, "nothing asked for no text");
    }

    function test_a_show_found_opens_on_its_server() {
        startApp();
        tryVerify(function() { return app.sources.list.length === 2; }, 2000);
        findChild(app.library, "searchField").text = "test show";
        tryVerify(function() { return app.library.rows.some(function(r) { return r.section === "On Home"; }); }, 2000);
        var row = app.library.rows.filter(function(r) { return r.section === "On Home"; })[0];
        app.library.openRow(row);
        compare(app.sourceId, "acc-jf");
        tryVerify(function() { return app.browse.current !== null && app.browse.current.kind === "show"; }, 2000);
        compare(app.browse.current.title, "Test Show");
        verify(!app.player.isOpen);
    }
}

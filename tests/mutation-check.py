#!/usr/bin/env python3
"""Breaks the app one way at a time and checks that a test catches it.

Each mutation replaces one piece of text in one file, runs the QML test
file that should notice (tools/run-tests.sh's environment, one screen),
and puts the file back. A mutation that leaves every test passing is a
hole in the tests and makes this script fail.

    python3 -I tests/mutation-check.py [path to luneos-components]

MUTATIONS_MATCHING=<words> runs only the mutations whose description has
those words in it.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "luneos-components")

# (what it breaks, file, text, replacement, test file, profile)
MUTATIONS = [
    # Videos from servers. (The sources are asked for at the start and on
    # coming to the front; a test window comes to the front at once, so
    # dropping either alone is not seen, and is not listed.)
    ('server: ended reported at 0', 'qml/js/Online.js', 'var at = state === "ended" && durationMs > 0 ? durationMs : Math.max(0, Math.round(positionMs));', 'var at = Math.max(0, Math.round(positionMs));', 'online', None),
    ('live: a channel resumes like a film', 'qml/js/Online.js', '    if (item && item.kind === "live")\n        return', '    if (false)\n        return', 'online', None),
    ('live: the seek bar shown', 'qml/PlayerView.qml', '                    visible: !view.live\n                    enabled: view.canSeek', '                    enabled: view.canSeek', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: the time left shown', 'qml/PlayerView.qml', '                    objectName: "remainingLabel"\n                    visible: !view.live\n', '                    objectName: "remainingLabel"\n', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: no LIVE label', 'qml/PlayerView.qml', 'text: view.live ? "\\u25CF LIVE"', 'text: false ? ""', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: jumps and seeks allowed', 'qml/PlayerView.qml', 'engine.seekable && started && !live', 'engine.seekable && started', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: a launch seek allowed', 'qml/PlayerView.qml', 'if (typeof c.seek === "number" && engine && !live)', 'if (typeof c.seek === "number" && engine)', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: speeds allowed', 'qml/PlayerView.qml', '                    enabled: !view.live\n', '', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: remembered on the device', 'qml/PlayerView.qml', 'if (!isOpen || !started || !resume || !engine || live)', 'if (!isOpen || !started || !resume || !engine)', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: reported to the server', 'qml/main.qml', '            if (now.item.kind !== "live")\n                videoSources.report', '            if (true)\n                videoSources.report', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: reported when left for another', 'qml/main.qml', 'if (prev && prev.item.kind !== "live" && playerView.isOpen', 'if (prev && playerView.isOpen', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: a length for the headset', 'qml/main.qml', 'playerView.engine !== null && !playerView.live ? playerView.engine.duration : 0', 'playerView.engine !== null ? playerView.engine.duration : 0', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('live: started at a remembered place', 'qml/PlayerView.qml', 'var at = live ? 0 : opts.position', 'var at = opts.position', 'ui::Ui::test_a_live_channel_has_nothing_to_seek_keep_or_report', None),
    ('server: progress without the session', 'qml/js/Online.js', '        args.session = session;', '', 'online', None),
    ('server: neighbour does not skip folders', 'qml/js/Online.js', '                if (items[j].playable)\n                    return items[j];', '                return items[j];', 'online', None),
    ('server: watched shows no full bar', 'qml/js/Online.js', '    if (p.watched)\n        return 1;', '', 'online', None),
    ('server: bus error codes shown raw', 'qml/js/Online.js', 'if (typeof code !== "string" || code === "")', 'if (!code)', 'online', None),
    ('server: repeats kept when paging', 'qml/js/Online.js', '        if (!seen[add[j].id]) {', '        if (true) {', 'online', None),
    ('server: parseKey splits at the last slash', 'qml/js/Online.js', 'var slash = rest.indexOf("/");', 'var slash = rest.lastIndexOf("/");', 'online', None),
    ('server: libraries left below the rows', 'qml/js/Online.js', 'return all.filter(function(s) { return s.layout === "grid"; })\n              .concat(all.filter(function(s) { return s.layout === "row"; }));', 'return all;', 'online', None),
    ('tabs: the full name in the tab', 'qml/components/SourceBar.qml', 'text: tab.modelData.label || tab.modelData.name', 'text: tab.modelData.name', 'ui::Ui::test_servers_are_libraries_beside_the_device', None),
    ('tabs: no name without a label', 'qml/components/SourceBar.qml', 'text: tab.modelData.label || tab.modelData.name', 'text: tab.modelData.label', 'ui::Ui::test_servers_are_libraries_beside_the_device', None),
    ('tabs: the lit tab does not follow the library', 'qml/components/SourceBar.qml', '    onCurrentChanged: follow()\n', '', 'ui::Ui::test_servers_are_libraries_beside_the_device', None),
    ('tabs: a tab given its height and shifted up', 'qml/components/SourceBar.qml', '            implicitHeight: bar.availableHeight\n', '            height: bar.height\n', 'ui::Ui::test_servers_are_libraries_beside_the_device', None),
    ('server: the list asked twice at the start', 'qml/VideoSources.qml', '        if (loading && Date.now() - _askedAt < 10000)\n            return;\n', '', 'ui::Ui::test_without_the_service_there_is_no_bar', None),
    ('server: a big screen asks for 720 lines', 'qml/main.qml', 'return Math.min(w, h) >= 1000 ? 1080 : 720;', 'return 720;', 'ui::Ui::test_a_library_pages_and_plays_with_progress_for_the_server', None),
    ('server: episode title without the show', 'qml/js/Online.js', 'if (item.kind === "episode" && item.seriesTitle) {', 'if (false) {', 'online', None),
    ('server: libraries load at once', 'qml/BrowsePage.qml', '                if (s.layout === "row")\n                    loadRow(entry, s.id);', '                loadRow(entry, s.id);', 'ui::Ui::test_servers_are_libraries_beside_the_device', 'mindphone'),
    ('server: no next page', 'qml/BrowsePage.qml', '                if (atYEnd && entry)\n                    page.loadMore(entry);', '', 'ui::Ui::test_a_library_pages_and_plays_with_progress_for_the_server', 'mindphone'),
    ('server: pages after the last', 'qml/BrowsePage.qml', '            entry.done = !entry.cursor;', '            entry.done = false;', 'ui::Ui::test_a_library_pages_and_plays_with_progress_for_the_server', 'mindphone'),
    ('server: searches pile up', 'qml/BrowsePage.qml', '                    if (page.current && page.current.kind === "list" && page.current.query !== undefined)\n                        page.pop();', '', 'ui::Ui::test_search_on_the_server', 'mindphone'),
    ('server: back leaves the app from a server', 'qml/BrowsePage.qml', '        if (sourceId !== "") {\n            appWindow.showSource("");\n            return true;\n        }', '', 'ui::Ui::test_servers_are_libraries_beside_the_device', 'mindphone'),
    ('server: a show opens as a list', 'qml/BrowsePage.qml', '        } else if (item.kind === "show") {\n            openShow(item);', '        } else if (false) {', 'ui::Ui::test_a_show_opens_on_its_seasons_and_plays_on', 'mindphone'),
    ('server: the season picked ignored', 'qml/BrowsePage.qml', '            if (entry.season !== season)\n                return;\n            entry.episodes', '            entry.episodes', 'ui::Ui::test_a_show_opens_on_its_seasons_and_plays_on', 'mindphone'),
    ('server: progress not reported', 'qml/main.qml', '            videoSources.report(Online.progressArgs(k.sourceId, k.itemId, positionMs, durationMs, state, now.session));', '', 'ui::Ui::test_a_library_pages_and_plays_with_progress_for_the_server', 'mindphone'),
    ('server: the episode left not stopped', 'qml/main.qml', '            if (prev && playerView.isOpen && playerView.engine && playerView.started)', '            if (false)', 'ui::Ui::test_a_show_opens_on_its_seasons_and_plays_on', 'mindphone'),
    ('server: headset next always jumps', 'qml/main.qml', '                if (!appWindow.playNeighbour(1))', '                if (true)', 'ui::Ui::test_a_show_opens_on_its_seasons_and_plays_on', 'mindphone'),
    ('server: resolve errors not shown', 'qml/main.qml', '            notice = Online.errorText(r);', '', 'ui::Ui::test_errors_say_what_to_do', 'mindphone'),
    ('server: a gone server stays shown', 'qml/main.qml', '            if (appWindow.sourceId !== "" && find(appWindow.sourceId) === null)', '            if (false)', 'ui::Ui::test_a_server_gone_goes_back_to_the_device', 'mindphone'),
    ('server: bar shown with no servers', 'qml/components/SourceBar.qml', '    visible: sources.length > 0', '    visible: true', 'ui::Ui::test_without_the_service_there_is_no_bar', 'mindphone'),
    ("WebVTT voice tags shown", "qml/js/Subtitles.js", "    s = s.replace(/<[^>]*>/g, \"\");\n    s = s.replace(/\\u0001",
     "    s = s.replace(/\\u0001", "subtitles", None),
    ("WebVTT cue times read without hours", "qml/js/Subtitles.js", "var hours = m[1] === undefined ? 0 : parseInt(m[1], 10);",
     "var hours = 0;", "subtitles", None),
    ("WebVTT read as SubRip", "qml/js/Subtitles.js", "? parseVtt(text) : parseSrt(text)", "? parseSrt(text) : parseSrt(text)",
     "subtitles", None),
    ("ftp taken for a stream", "qml/js/Library.js", "return /^https?:\\/\\/", "return /^(?:https?|ftp):\\/\\/", "library", None),
    ("a stream gets a file's time-out", "qml/PlayerView.qml",
     "return streaming ? Playback.streamLoadTimeoutMs : Playback.loadTimeoutMs;", "return Playback.loadTimeoutMs;",
     "ui::Ui::test_a_slow_stream_gets_longer_to_start", "mindphone"),
    ("the server's position ignored", "qml/PlayerView.qml",
     ": (stream && stream.startMs > 0 ? stream.startMs : 0));", ": 0);",
     "ui::Ui::test_a_stream_with_its_subtitles_and_server_position", "mindphone"),
    ("every stream subtitle on by default", "qml/PlayerView.qml",
     "        if (want === \"\" && stream) {", "        if (false) {",
     "ui::Ui::test_a_stream_with_its_subtitles_and_server_position", "mindphone"),
    ("closing not reported", "qml/PlayerView.qml",
     "            positionReported(path, at, length, \"stopped\");", "",
     "ui::Ui::test_a_stream_with_its_subtitles_and_server_position", "mindphone"),
    ("a stream link turned away", "qml/main.qml",
     "        if (Library.isStreamUrl(target)) {", "        if (false) {",
     "ui::Ui::test_a_link_as_target_plays_the_stream", "mindphone"),
    ("a file link taken for a stream", "qml/main.qml",
     "        if (!stream || !Library.isStreamUrl(stream.url)) {", "        if (!stream) {",
     "ui::Ui::test_not_a_stream_link", "mindphone"),
    ("SRT decoded as Latin-1 even when UTF-8", "qml/js/Subtitles.js",
     "    if (utf8 !== null)\n        return { text: utf8, encoding: \"UTF-8\" };", "", "subtitles", None),
    ("Windows-1252 table ignored", "qml/js/Subtitles.js",
     "cp1252[b] !== undefined ? cp1252[b] : b", "b", "subtitles", None),
    ("overlong UTF-8 accepted", "qml/js/Subtitles.js",
     "if (cp < min || cp > 0x10ffff", "if (cp > 0x10ffff", "subtitles", None),
    ("cue end inclusive", "qml/js/Subtitles.js", "if (ms < cues[i].end)", "if (ms <= cues[i].end)", "subtitles", None),
    ("overlapping cues: only the last", "qml/js/Subtitles.js",
     "i >= 0 && i > last - 8", "i >= 0 && i > last - 1", "subtitles", None),
    ("Matroska ASS fields kept", "qml/js/Subtitles.js", "        fields = 8;", "        fields = -1;", "subtitles", None),
    ("ASS override blocks kept", "qml/js/Subtitles.js",
     "            i = close + 1;\n            continue;", "            out += block;\n            i = close + 1;\n            continue;",
     "subtitles", None),
    ("markup not escaped", "qml/js/Subtitles.js", "    s = escapeHtml(s);", "", "subtitles", None),
    ("hidden folders scanned", "qml/js/Library.js", "base.charAt(0) === \".\" || depth > maxDepth",
     "depth > maxDepth", "library", None),
    ("no depth limit", "qml/VideoScanner.qml", "if (Library.shouldScanFolder(name, reader.depth + 1))",
     "if (Library.shouldScanFolder(name, 1))", "scanner", None),
    ("a vanished folder lists another", "qml/VideoScanner.qml",
     "            if (path.substring(0, path.lastIndexOf(\"/\")) !== reader.path)\n                continue;", "",
     "scanner", None),
    # The natural order, accent folding and launch URLs are LuneOS.Components'
    # FileLists now, mutation-checked with luneos-components' tests.
    ("resume at the very end", "qml/js/Playback.js", "&& positionMs <= durationMs - endMarginMs", "", "playback", None),
    ("store not pruned", "qml/js/Playback.js", "if (paths.length > maxRemembered)", "if (false)", "playback", None),
    ("started without a picture", "qml/js/Playback.js", "return hasVideo ? framesShown > 0 : positionMs > 0;",
     "return true;", "playback", None),
    ("probe asks the busy file again", "qml/DurationProbe.qml",
     "_pending = files.filter(function(f) { return f.path !== busyWith; });", "_pending = files.slice();",
     "scanner", None),
    ("hung probe player destroyed", "qml/DurationProbe.qml", "probe._setAside.push(probe._player);",
     "probe._player.destroy();", "scanner", None),
    ("no load time-out", "qml/PlayerView.qml",
     "} else if (view.wantPlay && Playback.loadTimedOut(", "} else if (false && Playback.loadTimedOut(", "ui", "mindphone"),
    ("hung engine reused", "qml/PlayerView.qml", "                engineHost.setAside();", "", "ui", "mindphone"),
    ("screen kept on while paused", "qml/main.qml", "&& playerView.engine.playing && active", "&& active", "ui",
     "mindphone"),
    ("screen held over a second service", "qml/main.qml", "        subscribe: appWindow.busSubscribe\n", "", "ui",
     "mindphone"),
    ("screen held under another name", "qml/main.qml", "clientName: \"org.webosports.app.videoplayer\"",
     "clientName: \"\"", "ui", "mindphone"),
    ("fullscreen button ignored", "qml/main.qml", "        active: appWindow.fullScreen", "        active: playerView.isOpen",
     "ui", "mindphone"),
    ("fullscreen not set on the window", "qml/main.qml", "        window: appWindow\n        active: appWindow.fullScreen",
     "        window: null\n        active: appWindow.fullScreen", "ui", "mindphone"),
    ("resume position not used", "qml/PlayerView.qml", "            e.seek(at);\n", "", "ui", "mindphone"),
    ("SRT not loaded by default", "qml/PlayerView.qml",
     "        if (want === \"\" )\n            want = srtFiles.length > 0 ? \"srt:\" + srtFiles[0] : \"off\";",
     "        if (want === \"\" )\n            want = \"off\";", "ui", "mindphone"),
    ("audio track not remembered", "qml/PlayerView.qml", "            e.activeAudioTrack = audio;", "", "ui", "mindphone"),
    ("not turned on a tall screen", "qml/PlayerView.qml", "(prefs !== null && prefs.turnLandscape && landscapeVideo)",
     "false", "ui", "mindphone"),
    ("turned back at the end", "qml/PlayerView.qml",
     "            if (s.width > 0 && s.height > 0)\n                view.landscapeVideo", "            view.landscapeVideo",
     "ui", "mindphone"),
    ("back does not close the player", "qml/PlayerView.qml", "        if (isOpen) {\n            close();\n            return true;",
     "        if (false) {\n            close();\n            return true;", "ui", "mindphone"),
    ("interruption does not pause", "qml/PlayerView.qml", "        log(\"interrupted\", { reason: reason });\n        pause();",
     "        log(\"interrupted\", { reason: reason });", "ui", "mindphone"),
    ("launched file not learnt after the scan", "qml/main.qml",
     "                playerView.fileInfo = appWindow.fileInfoFor(playerView.path);", "                ;", "ui", "mindphone"),
    ("probe crash not noticed", "qml/main.qml", "            preferences.readLengths = false;\n", "", "ui", "mindphone"),
    ("probe on without being asked", "qml/main.qml", "active: preferences.readLengths && !playerView.isOpen",
     "active: !playerView.isOpen", "ui", "mindphone"),
    ("library rows made again on every change", "qml/LibraryPage.qml", "                rowModel.set(i, r);",
     "                { rowModel.remove(i); rowModel.insert(i, r); }", "ui", "mindphone"),
    ("media session registered for the library", "qml/MediaSession.qml",
     "if (!bus || !appId || !active || _call)", "if (!bus || !appId || _call)", "mediasession", None),
    ("media session kept after the player closed", "qml/MediaSession.qml",
     "onActiveChanged: active ? register() : unregister()", "onActiveChanged: if (active) register()",
     "mediasession", None),
    ("media session activated only once", "qml/MediaSession.qml",
     "if (playing && (all || _sentStatus !== status))", "if (playing && all)", "mediasession", None),
    ("a paused video sent as stopped", "qml/js/MediaSession.js",
     "return open ? \"PLAYSTATE_PAUSED\" : \"PLAYSTATE_STOPPED\";", "return \"PLAYSTATE_STOPPED\";",
     "mediasession", None),
    ("a headset's stop ignored", "qml/js/MediaSession.js", "    case \"pause\":\n    case \"stop\":",
     "    case \"pause\":", "mediasession", None),
    ("a headset's next ignored", "qml/js/MediaSession.js", "    case \"fastForward\":\n        return \"forward\";",
     "    case \"fastForward\":\n        return \"\";", "mediasession", None),
    ("length sent in ms", "qml/js/MediaSession.js", "String(Math.round(durationMs / 1000))", "String(durationMs)",
     "mediasession", None),
    ("another session's keys obeyed", "qml/js/MediaSession.js",
     "if (reply.mediaId !== undefined && reply.mediaId !== mediaId)", "if (false)", "mediasession", None),
    # The app's wiring, against its own test: tst_ui as a whole has a probe
    # test that depends on the test files' times on disk.
    ("media session for the library too", "qml/main.qml", "        active: playerView.isOpen\n",
     "        active: true\n", "ui::Ui::test_media_session_follows_the_player", "mindphone"),
    ("media session never told it plays", "qml/main.qml",
     "        playing: playerView.engine !== null && playerView.engine.playing\n", "        playing: false\n",
     "ui::Ui::test_media_session_follows_the_player", "mindphone"),
    ("headset's next does not jump", "qml/main.qml", "                playerView.jump(Session.JUMP_MS);",
     "                playerView.jump(0);", "ui::Ui::test_media_session_follows_the_player", "mindphone"),
    ("headset's pause ignored", "qml/main.qml", "            else if (action === \"pause\")\n                playerView.pause();",
     "", "ui::Ui::test_media_session_follows_the_player", "mindphone"),
]


def run_test(name, profile, conf):
    env = dict(os.environ, XDG_CONFIG_HOME=os.path.join(conf, "config"), XDG_CACHE_HOME=os.path.join(conf, "cache"),
               QT_QPA_PLATFORM="offscreen", QML_XHR_ALLOW_FILE_READ="1",
               QT_QUICK_CONTROLS_STYLE="QtQuick.Controls.LuneOS")
    shutil.rmtree(os.path.join(conf, "config"), ignore_errors=True)
    shutil.rmtree(os.path.join(conf, "cache"), ignore_errors=True)
    args = [os.environ.get("QMLTESTRUNNER", "/usr/lib/qt6/bin/qmltestrunner"),
            "-import", os.path.join(LC, "modules"), "-import", os.path.join(LC, "test/imports")]
    if profile:
        common = os.path.join(conf, "profile-" + profile, "LunaNext", "Common")
        if not os.path.isdir(common):
            shutil.copytree(os.path.join(LC, "test/imports/LunaNext/Common"), common)
            stub = os.path.join(common, "SettingsStub.js")
            text = open(stub).read().replace('var defaultProfile = "desktop";', 'var defaultProfile = "%s";' % profile)
            open(stub, "w").write(text)
        args[1:1] = ["-import", os.path.join(conf, "profile-" + profile)]
    # "ui::Ui::test_x" runs that one test function only.
    name, _, function = name.partition("::")
    args += ["-input", os.path.join(HERE, "tests/qml/tst_%s.qml" % name)]
    if function:
        args.append(function)
    return subprocess.run(args, cwd=HERE, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=900).returncode


def main():
    holes = 0
    with tempfile.TemporaryDirectory() as conf:
        only = os.environ.get("MUTATIONS_MATCHING", "")
        for what, rel, old, new, test, profile in MUTATIONS:
            if only and only not in what:
                continue
            path = os.path.join(HERE, rel)
            original = open(path, encoding="utf-8").read()
            if original.count(old) != 1:
                print("STALE  %s: the text is not in %s once" % (what, rel))
                holes += 1
                continue
            try:
                open(path, "w", encoding="utf-8").write(original.replace(old, new))
                caught = run_test(test, profile, conf) != 0
            finally:
                open(path, "w", encoding="utf-8").write(original)
            print("%s %s (tst_%s)" % ("caught" if caught else "MISSED", what, test))
            holes += 0 if caught else 1
    total = len([m for m in MUTATIONS if not os.environ.get("MUTATIONS_MATCHING", "") or os.environ["MUTATIONS_MATCHING"] in m[0]])
    print("%d of %d mutations caught" % (total - holes, total))
    return 1 if holes else 0


if __name__ == "__main__":
    sys.exit(main())

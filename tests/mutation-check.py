#!/usr/bin/env python3
"""Breaks the app one way at a time and checks that a test catches it.

Each mutation replaces one piece of text in one file, runs the QML test
file that should notice (tools/run-tests.sh's environment, one screen),
and puts the file back. A mutation that leaves every test passing is a
hole in the tests and makes this script fail.

    python3 -I tests/mutation-check.py [path to luneos-components]
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
        for what, rel, old, new, test, profile in MUTATIONS:
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
    print("%d of %d mutations caught" % (len(MUTATIONS) - holes, len(MUTATIONS)))
    return 1 if holes else 0


if __name__ == "__main__":
    sys.exit(main())

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
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0
import QtCore as Core

import Eos.Window 0.1
import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0

import "js/Library.js" as Library

/*
 * Videos: the videos on the device, and a player for them.
 *
 * Opened with {"target": "<path or file: URL>"} - by Files, Email, the
 * browser's downloads (appinfo.json's mimeTypes) - it plays that video.
 * The back gesture (an Escape key) closes the player, then the app.
 */
WebOSWindow {
    id: appWindow

    title: "Videos"
    width: Settings.displayWidth
    height: Settings.displayHeight
    visible: true
    color: "black"
    windowType: "_WEBOS_WINDOW_TYPE_CARD"

    // The settings apps' header, less of it where the screen has little to
    // spare.
    readonly property real headerHeight: (height < Units.gu(70) || width < Units.gu(50)) ? Units.gu(7.5)
                                                                                     : Units.gu(10)
    readonly property bool compact: width < Units.gu(50)
    readonly property url appIcon: Qt.resolvedUrl("../icon.png")

    // What the tests replace: the player engine, the length probe's player,
    // the folders scanned.
    property url engineSource: Qt.resolvedUrl("VideoEngine.qml")
    property url probePlayerSource: Qt.resolvedUrl("ProbePlayer.qml")
    property var scanRoots: []

    property alias prefs: preferences
    property alias resume: resumeStore
    property alias cache: mediaCache
    property alias scanner: videoScanner
    property alias probe: durationProbe
    property alias player: playerView
    property alias library: libraryPage
    property alias appMenu: appMenu
    property alias probeGuard: probeGuard

    // The back gesture in the library ends the app (not in the tests).
    property bool quitOnBack: true
    signal quitRequested()

    // Says what went wrong, at the top of the library, until dismissed.
    property string notice: ""
    readonly property bool active: Qt.application.state === Qt.ApplicationActive

    PreferencesModel {
        id: preferences
    }

    ResumeStore {
        id: resumeStore
    }

    MediaCache {
        id: mediaCache
    }

    VideoScanner {
        id: videoScanner
        roots: appWindow.scanRoots
        onGenerationChanged: {
            appWindow.requestLengths();
            // Opened from another app before the scan was done: now the
            // player knows the file (for its length and picture).
            if (playerView.isOpen && !playerView.fileInfo)
                playerView.fileInfo = appWindow.fileInfoFor(playerView.path);
        }
    }

    DurationProbe {
        id: durationProbe
        playerSource: appWindow.probePlayerSource
        // Asked for (preferences), and not while a video plays: it would
        // take from its decoding.
        active: preferences.readLengths && !playerView.isOpen
        onStarting: function(path) { probeGuard.mark(path); }
        onFinished: function(path) { probeGuard.mark(""); }
        onMeasured: function(key, durationMs) { mediaCache.update(key, { duration: durationMs }); }
        onFailed: function(key) { mediaCache.update(key, { failed: true }); }
    }

    /*
     * The file the probe is loading, written to disk before it is loaded:
     * a file that ends the app (a crashing decoder) is still named there at
     * the next start, and the probe is switched off then. Written with
     * setValue() and sync(), not a property, which would be saved a moment
     * later - too late in a crash.
     */
    Core.Settings {
        id: probeGuard
        location: preferences.location
        category: "probe"

        function mark(path) {
            setValue("loading", path);
            sync();
        }

        function check() {
            var crashed = String(value("loading", ""));
            if (crashed === "")
                return;
            mark("");
            preferences.readLengths = false;
            appWindow.notice = "Reading the length of “" + Library.displayName(crashed) + "” stopped the app, so "
                    + "reading lengths is switched off. It can be switched on again in the app menu.";
        }
    }

    // The lengths not known yet, newest files first.
    function requestLengths() {
        var facts = mediaCache.all();
        var wanted = Library.sorted(videoScanner.files, "date").filter(function(f) {
            var fact = facts[Library.cacheKey(f)];
            return !fact || (!(fact.duration > 0) && !fact.failed && fact.duration !== 0);
        });
        durationProbe.request(wanted);
    }

    // Videos come and go over USB while the app is in the background: look
    // again on coming back. Going to the background pauses the video.
    onActiveChanged: {
        if (active) {
            videoScanner.rescan();
        } else {
            playerView.interrupt("inactive");
            playerView.saveState();
        }
    }

    function fileInfoFor(path) {
        var files = videoScanner.files;
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === path)
                return files[i];
        }
        return null;
    }

    // Plays a file: from the library, or a launch target.
    function playFile(target, options) {
        var path = Library.localPath(target);
        if (path === "") {
            notice = "Only videos on this device can be played: " + target;
            return;
        }
        playerView.open(path, options);
        playerView.fileInfo = fileInfoFor(path);
    }

    LunaService {
        id: service
        name: "org.webosports.app.videoplayer"
    }

    /*
     * The screen kept on while a video plays: luna-displaymanager's
     * "requestBlock" holds the display as it is (no dimming, no timeout)
     * for as long as the call stays open, and cancelling the call lets go.
     * Needs "display.operation". Paused, ended or in the background, it is
     * let go.
     */
    readonly property bool keepScreenOn: playerView.isOpen && playerView.engine !== null
                                         && playerView.engine.playing && active
    property var screenBlockCall: null
    readonly property bool screenBlocked: screenBlockCall !== null
    onKeepScreenOnChanged: updateScreenBlock(keepScreenOn)

    function updateScreenBlock(on) {
        if (on && !screenBlockCall) {
            // The desktop stand-in for the bus returns no call object.
            screenBlockCall = service.subscribe("luna://com.palm.display/control/setProperty",
                                                JSON.stringify({ "requestBlock": true, "client": "org.webosports.app.videoplayer" }),
                                                function() {},
                                                function(error) { console.warn("Could not keep the screen on: " + error); })
                              || ({});
            playerView.log("screen", { blocked: true });
        } else if (!on && screenBlockCall) {
            if (typeof screenBlockCall.cancel === "function")
                screenBlockCall.cancel();
            screenBlockCall = null;
            playerView.log("screen", { blocked: false });
        }
    }

    /*
     * The player covers the whole screen, the status bar and the gesture
     * area too: the card shell makes the card fullscreen while the window
     * property "LuneOS_fullscreen" is "true" (luna-next-cardshell's
     * CardWindowWrapper); a flick up from the bottom edge still leaves it.
     * The library keeps the bar. A shell without this ignores the property.
     */
    readonly property bool fullScreen: playerView.isOpen
    onFullScreenChanged: {
        setWindowProperty("LuneOS_fullscreen", fullScreen ? "true" : "false");
        playerView.log("fullscreen", { on: fullScreen });
    }

    // A phone call starting pauses the video. Without oFono's QML module
    // (no modem) the loader stays empty.
    Loader {
        id: callWatcher
        source: Qt.resolvedUrl("CallWatcher.qml")
    }
    Connections {
        target: callWatcher.item
        ignoreUnknownSignals: true
        function onCallStarted() { playerView.interrupt("call"); }
    }

    /* {"target": path} plays it; with "position" (ms), "subtitle" ("off",
     * "srt", "track:<n>"), "audioTrack" and "rate" it starts so, and with
     * "report": true it logs what happens. For tools/test-device.sh also
     * {"player": {...}} (PlayerView.command) and {"snapshot": "<png path>"},
     * a picture of the app's window drawn by the app itself, which works
     * with the screen locked ("snapshotDelay": ms, taken that much later). */
    LaunchParams {
        window: appWindow
        onLaunched: function(params) {
            if (params.player && typeof params.player === "object")
                playerView.command(params.player);
            if (typeof params.snapshot === "string" && params.snapshot.charAt(0) === "/") {
                if (typeof params.snapshotDelay === "number") {
                    snapshotTimer.path = params.snapshot;
                    snapshotTimer.interval = params.snapshotDelay;
                    snapshotTimer.restart();
                } else {
                    appWindow.snapshot(params.snapshot);
                }
            }
            if (typeof params.target === "string" && params.target !== "") {
                appWindow.playFile(params.target, {
                    position: typeof params.position === "number" ? params.position : undefined,
                    subtitle: typeof params.subtitle === "string" ? params.subtitle : undefined,
                    audioTrack: typeof params.audioTrack === "number" ? params.audioTrack : undefined,
                    rate: typeof params.rate === "number" ? params.rate : undefined,
                    report: params.report === true
                });
            }
        }
        onAppMenuRequested: appWindow.openAppMenu()
    }

    Timer {
        id: snapshotTimer
        property string path
        onTriggered: appWindow.snapshot(path)
    }

    function snapshot(path) {
        var ok = root.grabToImage(function(result) {
            var saved = result.saveToFile(path);
            console.warn("VIDEOPLAYER " + JSON.stringify({ event: "snapshot", path: path, saved: saved }));
        });
        if (!ok)
            console.warn("VIDEOPLAYER " + JSON.stringify({ event: "snapshot", path: path, saved: false }));
    }

    // The app menu drops from the top of the window, as in every app. Only
    // over the library: the player has its own bars.
    function openAppMenu() {
        if (!playerView.isOpen)
            appMenu.popup(0, 0);
    }

    Menu {
        id: appMenu
        objectName: "appMenu"
        LuneOSMenu.appMenuStyle: true

        MenuItem {
            text: "Sort by Name"
            checkable: true
            checked: preferences.sortOrder === "name"
            onTriggered: preferences.sortOrder = "name"
        }
        MenuItem {
            text: "Sort by Date"
            checkable: true
            checked: preferences.sortOrder === "date"
            onTriggered: preferences.sortOrder = "date"
        }
        MenuItem {
            text: "Sort by Size"
            checkable: true
            checked: preferences.sortOrder === "size"
            onTriggered: preferences.sortOrder = "size"
        }
        MenuItem {
            text: "Turn Wide Videos on Tall Screens"
            checkable: true
            checked: preferences.turnLandscape
            onTriggered: preferences.turnLandscape = !preferences.turnLandscape
        }
        MenuItem {
            text: "Read Video Lengths"
            checkable: true
            checked: preferences.readLengths
            onTriggered: preferences.readLengths = !preferences.readLengths
        }
        MenuItem {
            text: "Refresh"
            onTriggered: videoScanner.rescan()
        }
    }

    FocusScope {
        id: root
        anchors.fill: parent
        focus: true

        LibraryPage {
            id: libraryPage
            anchors.fill: parent
            visible: !playerView.isOpen
        }

        PlayerView {
            id: playerView
            anchors.fill: parent
            engineSource: appWindow.engineSource
            prefs: preferences
            resume: resumeStore
            cache: mediaCache
            onClosed: root.forceActiveFocus()
        }

        // The back gesture arrives as Escape (see LunaNext.Common's
        // EventType): it closes what is open - a picker, the player, the
        // search - and then the app.
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                if (playerView.handleBack())
                    return;
                if (libraryPage.handleBack())
                    return;
                appWindow.quitRequested();
                if (appWindow.quitOnBack)
                    Qt.quit();
            } else if (playerView.isOpen && event.key === Qt.Key_Space) {
                event.accepted = true;
                playerView.togglePlay();
            } else if (playerView.isOpen && event.key === Qt.Key_Left) {
                event.accepted = true;
                playerView.jump(-10000);
            } else if (playerView.isOpen && event.key === Qt.Key_Right) {
                event.accepted = true;
                playerView.jump(10000);
            }
        }
    }

    Component.onCompleted: {
        probeGuard.check();
        videoScanner.rescan();
    }
}

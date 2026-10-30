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

import "../../qml"
import "../../qml/js/MediaSession.js" as Session

/*
 * The media session (js/MediaSession.js, MediaSession.qml) against a fake
 * com.webos.service.mediacontroller: what it registers and when, what it
 * tells the service, what each key asks for, and that a refusal or the
 * service going is retried and the session ends with the player.
 */
Item {
    id: root
    width: 100
    height: 100

    // --- the fake bus ------------------------------------------------------

    property var calls: []       // { method, payload } of every call()
    property var subscription: null
    property int subscribes: 0
    property int cancels: 0

    function method(uri) { return uri.replace(Session.SERVICE, ""); }

    QtObject {
        id: fakeBus
        function subscribe(uri, args, onReply, onError) {
            root.subscribes++;
            var call = {
                method: root.method(uri), payload: JSON.parse(args),
                reply: function(p) { onReply({ payload: JSON.stringify(p) }); },
                fail: function(e) { onError(e); },
                cancel: function() { root.cancels++; root.subscription = null; }
            };
            root.subscription = call;
            return call;
        }
        function call(uri, args, onReply, onError) {
            root.calls.push({ method: root.method(uri), payload: JSON.parse(args) });
            onReply({ payload: "{\"returnValue\":true}" });
        }
    }

    function sent(name) {
        return root.calls.filter(function(c) { return c.method === name; });
    }

    property var actions: []

    Component {
        id: sessionComponent
        MediaSession {
            bus: fakeBus
            appId: "org.webosports.app.videoplayer"
            retryInterval: 20
            onActionRequested: function(action) { root.actions.push(action); }
        }
    }

    TestCase {
        name: "MediaSession"
        when: windowShown

        property var session: null

        function init() {
            root.calls = [];
            root.subscription = null;
            root.subscribes = 0;
            root.cancels = 0;
            root.actions = [];
            session = createTemporaryObject(sessionComponent, root);
            verify(session);
        }

        function opened() {
            session.title = "Big Buck";
            session.active = true;
            verify(root.subscription, "a video open registers the session");
        }

        function registered() {
            opened();
            root.subscription.reply({ returnValue: true, subscribed: true });
            verify(session.registered);
        }

        // --- js/MediaSession.js -------------------------------------------

        function test_keys() {
            compare(Session.actionForKey("play"), "play");
            compare(Session.actionForKey("pause"), "pause");
            compare(Session.actionForKey("stop"), "pause");
            compare(Session.actionForKey("next"), "forward");
            compare(Session.actionForKey("fastForward"), "forward");
            compare(Session.actionForKey("previous"), "back");
            compare(Session.actionForKey("rewind"), "back");
            compare(Session.actionForKey("volumeUp"), "");
            compare(Session.actionForKey(""), "");
        }

        function test_playStatus() {
            compare(Session.playStatus(true, true), "PLAYSTATE_PLAYING");
            compare(Session.playStatus(false, true), "PLAYSTATE_PAUSED");
            compare(Session.playStatus(false, false), "PLAYSTATE_STOPPED");
        }

        function test_metaData() {
            compare(Session.metaData("Big Buck", 596400), { title: "Big Buck", totalDuration: "596" });
            compare(Session.metaData("Big Buck", 0), { title: "Big Buck" });
            compare(Session.metaData("", 0), {});
        }

        function test_replies() {
            compare(Session.parseReply("{\"returnValue\":true,\"subscribed\":true}", "m"), { registered: true });
            compare(Session.parseReply({ returnValue: true, subscribed: true, keyEvent: "pause", mediaId: "m" }, "m"),
                    { keyEvent: "pause" });
            compare(Session.parseReply({ returnValue: true, keyEvent: "pause", mediaId: "other" }, "m"), {});
            compare(Session.parseReply({ returnValue: false, errorText: "Denied" }, "m"), { failed: "Denied" });
            compare(Session.parseReply("not json", "m"), { failed: "not JSON" });
        }

        function test_sessionIdsDifferPerRun() {
            verify(Session.sessionId("a", 1) !== Session.sessionId("a", 2));
            verify(Session.sessionId("a", 1).indexOf("a-") === 0);
        }

        // --- MediaSession.qml ---------------------------------------------

        function test_noSessionWithoutAVideo() {
            compare(root.subscribes, 0, "the library alone registers nothing");
        }

        function test_registersOnceWhileOpen() {
            opened();
            compare(root.subscription.method, "registerMediaSession");
            compare(root.subscription.payload.appId, "org.webosports.app.videoplayer");
            compare(root.subscription.payload.mediaId, session.mediaId);
            compare(root.subscription.payload.subscribe, true);
            session.register();
            compare(root.subscribes, 1);
            compare(root.cancels, 0);
        }

        function test_tellsTheServiceOnceRegistered() {
            session.durationMs = 596400;
            session.playing = true;
            opened();
            compare(root.calls.length, 0, "nothing is sent before the session exists");
            root.subscription.reply({ returnValue: true, subscribed: true });
            compare(root.sent("activateMediaSession").length, 1);
            compare(root.sent("setMediaPlayStatus")[0].payload.playStatus, "PLAYSTATE_PLAYING");
            compare(root.sent("setMediaMetaData")[0].payload.mediaMetaData, { title: "Big Buck", totalDuration: "596" });
            compare(root.sent("setMediaMetaData")[0].payload.mediaId, session.mediaId);
        }

        function test_activatedOnEveryStart() {
            registered();
            compare(root.sent("activateMediaSession").length, 0, "a paused video takes no keys");
            session.playing = true;
            compare(root.sent("activateMediaSession").length, 1);
            session.playing = false;
            compare(root.sent("setMediaPlayStatus").slice(-1)[0].payload.playStatus, "PLAYSTATE_PAUSED");
            compare(root.sent("activateMediaSession").length, 1, "pausing activates nothing");
            session.playing = true;
            compare(root.sent("activateMediaSession").length, 2,
                    "resuming takes the headset's keys back from another player");
            var metas = root.sent("setMediaMetaData").length;
            session.title = "Big Buck";
            compare(root.sent("setMediaMetaData").length, metas, "the same metadata is not sent again");
            session.durationMs = 1000;
            compare(root.sent("setMediaMetaData").slice(-1)[0].payload.mediaMetaData.totalDuration, "1");
        }

        function test_keysAskThePlayer() {
            registered();
            var keys = ["pause", "play", "next", "previous", "stop", "volumeUp", "play", "play"];
            for (var i = 0; i < keys.length; i++)
                root.subscription.reply({ returnValue: true, subscribed: true, keyEvent: keys[i],
                                          mediaId: session.mediaId });
            compare(root.actions, ["pause", "play", "forward", "back", "pause", "play", "play"]);
        }

        function test_endsWhenThePlayerCloses() {
            registered();
            session.active = false;
            compare(root.cancels, 1);
            verify(!session.registered);
            wait(60);
            compare(root.subscribes, 1, "a closed player is not registered again");
            session.active = true;
            compare(root.subscribes, 2, "the next video registers again");
        }

        function test_refusalIsRetried() {
            opened();
            root.subscription.reply({ returnValue: false, errorText: "Denied" });
            verify(!session.registered);
            compare(root.cancels, 1);
            tryVerify(function() { return root.subscription !== null; }, 1000, "registers again");
            root.subscription.reply({ returnValue: true, subscribed: true });
            verify(session.registered);
        }

        function test_noRetryOnceClosed() {
            opened();
            root.subscription.fail("Service disconnected");
            session.active = false;
            wait(60);
            compare(root.subscribes, 1, "nothing to retry for a closed player");
        }

        function test_serviceGoingIsRetried() {
            registered();
            root.subscription.fail("Service disconnected");
            verify(!session.registered);
            tryVerify(function() { return root.subscription !== null; }, 1000);
        }

        function test_endsWithTheApp() {
            registered();
            session.destroy();
            tryCompare(root, "cancels", 1);
        }
    }
}

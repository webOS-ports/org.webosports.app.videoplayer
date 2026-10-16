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

/*
 * The player's rules: where a video resumes, when a load has failed, the
 * speeds, the track names, and where each video was left.
 */

// ---- resume -----------------------------------------------------------------

// A position worth coming back to: some way in and not at the end. Videos
// shorter than this are always played from the start.
var minResumeMs = 3000;
var endMarginMs = 5000;
var maxRemembered = 200;

function worthResuming(positionMs, durationMs) {
    return durationMs > minResumeMs + endMarginMs
            && positionMs >= minResumeMs
            && positionMs <= durationMs - endMarginMs;
}

function parseStore(json) {
    try {
        var v = JSON.parse(json || "{}");
        return v && typeof v === "object" && !Array.isArray(v) ? v : {};
    } catch (e) {
        return {};
    }
}

// The store with what the player knows of path now: position and length,
// when (at, ms), and the chosen audio and subtitle tracks. A position not
// worth resuming from is dropped, the choices are kept. Only the
// maxRemembered most recent files are kept.
function remember(store, path, state) {
    var copy = {};
    for (var k in store)
        copy[k] = store[k];
    var old = copy[path] || {};
    var entry = {
        position: worthResuming(state.position, state.duration) ? Math.floor(state.position) : 0,
        duration: state.duration > 0 ? Math.floor(state.duration) : (old.duration || 0),
        at: state.at || Date.now()
    };
    if (state.audioTrack !== undefined)
        entry.audioTrack = state.audioTrack;
    else if (old.audioTrack !== undefined)
        entry.audioTrack = old.audioTrack;
    if (state.subtitle !== undefined)
        entry.subtitle = state.subtitle;
    else if (old.subtitle !== undefined)
        entry.subtitle = old.subtitle;
    copy[path] = entry;

    var paths = Object.keys(copy);
    if (paths.length > maxRemembered) {
        paths.sort(function(a, b) { return (copy[b].at || 0) - (copy[a].at || 0); });
        for (var i = maxRemembered; i < paths.length; i++)
            delete copy[paths[i]];
    }
    return copy;
}

function forget(store, path) {
    var copy = {};
    for (var k in store) {
        if (k !== path)
            copy[k] = store[k];
    }
    return copy;
}

// Where to start path: the remembered position, or 0.
function resumePosition(store, path) {
    var e = store[path];
    return e && e.position > 0 ? e.position : 0;
}

// The videos to carry on with, most recent first: [{path, position,
// duration, at}], only those exists(path) says are still there.
function continueWatching(store, exists, limit) {
    var out = [];
    for (var path in store) {
        var e = store[path];
        if (e.position > 0 && (!exists || exists(path)))
            out.push({ path: path, position: e.position, duration: e.duration || 0, at: e.at || 0 });
    }
    out.sort(function(a, b) { return b.at - a.at; });
    return limit ? out.slice(0, limit) : out;
}

// ---- starting ---------------------------------------------------------------

// How long a video may take to start before the player gives up on it.
// Some files hang the hardware decoder before the first picture; this
// turns that into an error instead of a spinner for ever.
var loadTimeoutMs = 15000;

// Whether a video has started: it plays and has shown a picture, or, with
// no picture to wait for (audio only), its position has moved.
function hasStarted(playing, framesShown, hasVideo, positionMs) {
    if (!playing)
        return false;
    return hasVideo ? framesShown > 0 : positionMs > 0;
}

// Whether to give up: wanted to play since startedAt, still not started.
function loadTimedOut(startedAt, now, started) {
    return !started && startedAt > 0 && now - startedAt >= loadTimeoutMs;
}

// ---- speed, picture ---------------------------------------------------------

var rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

// The rate after r in rates, round to the first.
function nextRate(r) {
    for (var i = 0; i < rates.length; i++) {
        if (rates[i] > r + 0.001)
            return rates[i];
    }
    return rates[0];
}

// Seek target for a jump of delta from position, kept inside the video
// (not right at its end, which would end it).
function jumpTarget(positionMs, deltaMs, durationMs) {
    var t = positionMs + deltaMs;
    if (durationMs > 0)
        t = Math.min(t, Math.max(0, durationMs - 1000));
    return Math.max(0, Math.round(t));
}

// The rotation that shows a landscape video upright on a portrait screen,
// by which way the device is held (sensorRotation: the orientation
// sensor's 90 for left side up, 270 for right side up, -1 when it does not
// know). Left side up wants the picture's top on the screen's left edge
// (turned by 270); right side up, and not knowing, by 90.
function turnAngle(sensorRotation) {
    return sensorRotation === 90 ? 270 : 90;
}

// ---- tracks -----------------------------------------------------------------

// A track's label from its metadata: "English", "English – 880 Hz",
// "Track 2" when it has neither; codec added in brackets when known.
// GStreamer gives "Default" for a track without a language.
function trackLabel(language, title, codec, index) {
    var lang = language && language !== "Default" && language !== "C" ? language : "";
    var parts = [];
    if (lang)
        parts.push(lang);
    if (title && title !== lang)
        parts.push(title);
    var text = parts.length ? parts.join(" – ") : "Track " + (index + 1);
    if (codec)
        text += " (" + codec + ")";
    return text;
}

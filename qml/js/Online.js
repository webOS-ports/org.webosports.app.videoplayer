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

.pragma library

/*
 * Videos from servers: what the app makes of org.webosports.service.videos'
 * answers (Jellyfin, PeerTube, UPnP/DLNA media servers). The service's
 * shapes are in its contract.js: sources, sections {id, title, layout},
 * items {id, kind, title, subtitle, artwork, durationMs, progress, playable,
 * hasChildren, ...}, streams {url, protocol, subtitles, startMs, session,
 * height, heights}.
 */

var SERVICE = "luna://org.webosports.service.videos/";
var KEY_PREFIX = "videos:";
var PAGE_SIZE = 50;

// What a played item is remembered by (where it was left, the subtitles
// chosen), and what a key says back.
function itemKey(sourceId, itemId) {
    return KEY_PREFIX + sourceId + "/" + itemId;
}

function parseKey(key) {
    var s = String(key);
    if (s.indexOf(KEY_PREFIX) !== 0)
        return null;
    var rest = s.substring(KEY_PREFIX.length);
    // A source id holds no "/" (an account id, or "<account>|<server>").
    var slash = rest.indexOf("/");
    if (slash <= 0 || slash === rest.length - 1)
        return null;
    return { sourceId: rest.substring(0, slash), itemId: rest.substring(slash + 1) };
}

// The title the player shows: an episode with its show.
function titleOf(item) {
    if (!item)
        return "";
    if (item.kind === "episode" && item.seriesTitle) {
        var se = (item.season !== undefined ? "S" + item.season : "") + (item.episode !== undefined ? "E" + item.episode : "");
        return item.seriesTitle + (se ? " " + se : "") + " – " + item.title;
    }
    return item.title || "";
}

// The service's stream as the player's playStream() takes it.
function playStreamFor(sourceId, item, stream) {
    var subs = (stream.subtitles || []).filter(function(s) {
        return s && typeof s.url === "string" && /^https?:/i.test(s.url);
    }).map(function(s) {
        return { url: s.url, label: s.label || s.lang || "", lang: s.lang || "", format: s.format || "vtt", default: s.default === true };
    });
    // A channel (an IPTV list's) has no length, place or end: the player
    // shows it as live, with nothing to seek or resume.
    if (item && item.kind === "live")
        return { url: stream.url, title: titleOf(item), subtitles: subs, startMs: 0, key: itemKey(sourceId, item.id), live: true,
                 height: stream.height > 0 ? stream.height : 0, heights: heightsOf(stream) };
    return {
        url: stream.url,
        height: stream.height > 0 ? stream.height : 0,
        heights: heightsOf(stream),
        title: titleOf(item),
        subtitles: subs,
        startMs: stream.startMs > 0 ? stream.startMs : (item && item.progress && item.progress.positionMs > 0 ? item.progress.positionMs : 0),
        key: itemKey(sourceId, item.id)
    };
}

/*
 * What reportProgress is called with for the player's positionReported.
 * At the end the whole length is reported, so the server counts it as
 * watched (the player itself forgets the place, 0).
 */
function progressArgs(sourceId, itemId, positionMs, durationMs, state, session) {
    var at = state === "ended" && durationMs > 0 ? durationMs : Math.max(0, Math.round(positionMs));
    var args = { sourceId: sourceId, itemId: itemId, positionMs: at, durationMs: Math.max(0, Math.round(durationMs)), state: state };
    if (session && typeof session === "object")
        args.session = session;
    return args;
}

// The next and the previous playable item in a list (the season's
// episodes), or null.
function neighbour(items, itemId, step) {
    if (!items)
        return null;
    for (var i = 0; i < items.length; i++) {
        if (items[i].id === itemId) {
            for (var j = i + step; j >= 0 && j < items.length; j += step) {
                if (items[j].playable)
                    return items[j];
            }
            return null;
        }
    }
    return null;
}

// A line under a tile: the subtitle the service gave, else the year.
function detailsOf(item) {
    if (item.subtitle)
        return item.subtitle;
    if (item.year)
        return String(item.year);
    return "";
}

// 0..1 watched, or -1 for no bar.
function progressOf(item) {
    var p = item.progress;
    if (!p)
        return -1;
    if (p.watched)
        return 1;
    return item.durationMs > 0 && p.positionMs > 0 ? Math.min(1, p.positionMs / item.durationMs) : -1;
}

// The picture for a tile: wide (thumb) or tall (poster).
function pictureOf(item, wide) {
    var a = item.artwork || {};
    return (wide ? (a.thumb || a.backdrop || a.poster) : (a.poster || a.thumb)) || "";
}

// What to tell the user for a service error.
function errorText(reply) {
    var code = reply && reply.errorCode;
    // The bus's own errors (no such service, not allowed) come with numbers.
    if (typeof code !== "string" || code === "")
        return "The video service does not answer.";
    switch (code) {
    case "AUTH_EXPIRED":
        return "The server no longer accepts this account. Remove it in Accounts and add it again.";
    case "SERVER_UNREACHABLE":
        return "The server does not answer. Check the network, and that the server is on.";
    case "NO_SOURCE":
        return "This library is not there any more.";
    case "NOT_FOUND":
        return "The server does not have this any more.";
    case "DRM_REQUIRED":
        return "This video is protected, and Videos cannot play protected videos.";
    case "GEO_BLOCKED":
        return "This video is not offered where this device is.";
    case "NOT_SUPPORTED":
        return "This server cannot do that.";
    case "TIMEOUT":
        return "The server took too long to answer.";
    }
    var t = reply && typeof reply.errorText === "string" && reply.errorText !== "" ? reply.errorText : "";
    if (code === "SERVER_ERROR" && t !== "")
        return t;
    return t !== "" ? t : "Something went wrong (" + code + ").";
}

// A list of items with a page added on, without the ones it already has
// (a server's list can shift while it is paged through).
function appendPage(items, page) {
    var seen = {};
    var out = items.slice();
    for (var i = 0; i < items.length; i++)
        seen[items[i].id] = true;
    var add = (page && page.items) || [];
    for (var j = 0; j < add.length; j++) {
        if (!seen[add[j].id]) {
            seen[add[j].id] = true;
            out.push(add[j]);
        }
    }
    return out;
}

// Grid sections are libraries to open; row sections show their items in
// place. The libraries (Movies, Shows, a media server's folders) come first,
// at the top where they are found without scrolling past the rows, each
// group in the server's order.
function homeEntries(sections) {
    var all = (sections || []).map(function(s) {
        return { id: s.id, title: s.title, layout: s.layout === "row" ? "row" : "grid" };
    });
    return all.filter(function(s) { return s.layout === "grid"; })
              .concat(all.filter(function(s) { return s.layout === "row"; }));
}

/*
 * Quality: the picture heights a server can play an item at (the stream's
 * heights, tallest first), and the one picked for each kind of server,
 * kept as {provider: height} (0, or none: what the screen shows).
 */
function heightsOf(stream) {
    var seen = {};
    return (stream && Array.isArray(stream.heights) ? stream.heights : []).filter(function(h) {
        if (typeof h !== "number" || h <= 0 || Math.floor(h) !== h || seen[h])
            return false;
        seen[h] = true;
        return true;
    }).sort(function(a, b) { return b - a; });
}

function qualityLabel(height) {
    return height > 0 ? height + "p" : "Auto";
}

function pickedHeights(json) {
    try {
        var v = JSON.parse(json || "{}");
        return v && typeof v === "object" && !Array.isArray(v) ? v : {};
    } catch (e) {
        return {};
    }
}

function pickedHeight(json, provider) {
    var h = pickedHeights(json)[provider];
    return typeof h === "number" && h > 0 ? h : 0;
}

function withPickedHeight(json, provider, height) {
    var v = pickedHeights(json);
    if (height > 0)
        v[provider] = height;
    else
        delete v[provider];
    return JSON.stringify(v);
}

// The tallest picture to ask for: the one picked, else the screen's.
function maxHeightFor(picked, screenHeight) {
    return picked > 0 ? picked : screenHeight;
}

// The choices of the Quality sheet: Auto, then each height; none when the
// server has no choice. The one checked: Auto, else the height playing.
function qualityChoices(heights, picked, playing) {
    if (!heights || heights.length < 2)
        return [];
    var current = picked > 0 ? (playing > 0 ? playing : picked) : 0;
    return [{ label: "Auto", checked: current === 0, key: "quality", value: 0 }].concat(heights.map(function(h) {
        return { label: qualityLabel(h), checked: current === h, key: "quality", value: h };
    }));
}

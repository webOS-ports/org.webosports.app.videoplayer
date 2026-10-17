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
 * Subtitles: SubRip (.srt) files next to a video, read as bytes and decoded
 * here (UTF-8, or Windows-1252/Latin-1 when the bytes are not UTF-8), and
 * the text GStreamer hands over for a subtitle track inside the video,
 * which for SubStation Alpha (ASS/SSA) tracks is the raw event line.
 *
 * Everything that reaches the screen goes through toStyledText(): the only
 * markup kept is <i>, <b> and <u>, the rest is escaped, so a file cannot
 * put links, images or layout into the player.
 */

// ---- decoding ---------------------------------------------------------------

// The bytes as strict UTF-8, or null at the first invalid sequence
// (overlong forms, surrogates and code points past U+10FFFF included).
function decodeUtf8OrNull(bytes) {
    var out = [];
    var i = 0;
    var n = bytes.length;
    while (i < n) {
        var c = bytes[i];
        if (c < 0x80) {
            out.push(String.fromCharCode(c));
            i++;
            continue;
        }
        var extra, cp, min;
        if ((c & 0xe0) === 0xc0) {
            extra = 1; cp = c & 0x1f; min = 0x80;
        } else if ((c & 0xf0) === 0xe0) {
            extra = 2; cp = c & 0x0f; min = 0x800;
        } else if ((c & 0xf8) === 0xf0) {
            extra = 3; cp = c & 0x07; min = 0x10000;
        } else {
            return null;
        }
        if (i + extra >= n)
            return null;
        for (var k = 1; k <= extra; k++) {
            var b = bytes[i + k];
            if (b === undefined || (b & 0xc0) !== 0x80)
                return null;
            cp = (cp << 6) | (b & 0x3f);
        }
        if (cp < min || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff))
            return null;
        out.push(String.fromCodePoint(cp));
        i += extra + 1;
    }
    return out.join("");
}

// Windows-1252 for 0x80-0x9f, where Latin-1 has only control codes; the
// same as ISO-8859-1 everywhere else. Undefined bytes stay as they are.
var cp1252 = {
    0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e, 0x85: 0x2026, 0x86: 0x2020,
    0x87: 0x2021, 0x88: 0x02c6, 0x89: 0x2030, 0x8a: 0x0160, 0x8b: 0x2039, 0x8c: 0x0152,
    0x8e: 0x017d, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201c, 0x94: 0x201d, 0x95: 0x2022,
    0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02dc, 0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a,
    0x9c: 0x0153, 0x9e: 0x017e, 0x9f: 0x0178
};

function decodeSingleByte(bytes) {
    var out = [];
    for (var i = 0; i < bytes.length; i++) {
        var b = bytes[i];
        out.push(String.fromCharCode(cp1252[b] !== undefined ? cp1252[b] : b));
    }
    return out.join("");
}

// { text, encoding }: UTF-8 (a byte order mark is dropped), UTF-16 when it
// starts with a byte order mark, else Windows-1252.
function decode(bytes) {
    if (!bytes || bytes.length === 0)
        return { text: "", encoding: "" };
    if (bytes.length >= 2 && ((bytes[0] === 0xff && bytes[1] === 0xfe) || (bytes[0] === 0xfe && bytes[1] === 0xff))) {
        var little = bytes[0] === 0xff;
        var units = [];
        for (var i = 2; i + 1 < bytes.length; i += 2)
            units.push(little ? (bytes[i] | (bytes[i + 1] << 8)) : ((bytes[i] << 8) | bytes[i + 1]));
        var s = "";
        // In chunks: fromCharCode.apply has an argument limit.
        for (var c = 0; c < units.length; c += 4096)
            s += String.fromCharCode.apply(null, units.slice(c, c + 4096));
        return { text: s, encoding: little ? "UTF-16LE" : "UTF-16BE" };
    }
    var start = (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) ? 3 : 0;
    var body = start ? Array.prototype.slice.call(bytes, start) : bytes;
    var utf8 = decodeUtf8OrNull(body);
    if (utf8 !== null)
        return { text: utf8, encoding: "UTF-8" };
    return { text: decodeSingleByte(bytes), encoding: "Windows-1252" };
}

// ---- SubRip -----------------------------------------------------------------

// "01:02:03,456" (or with a dot, or fewer digits after it) in milliseconds,
// or -1.
function parseTimestamp(text) {
    var m = String(text).trim().match(/^(\d+):(\d{1,2}):(\d{1,2})(?:[,.](\d{1,3}))?/);
    if (!m)
        return -1;
    var frac = m[4] === undefined ? 0 : parseInt((m[4] + "00").substr(0, 3), 10);
    return ((parseInt(m[1], 10) * 60 + parseInt(m[2], 10)) * 60 + parseInt(m[3], 10)) * 1000 + frac;
}

// The cues of a SubRip text, in start order: [{start, end, text}]. Cues
// without a valid time line are skipped; the counter line is optional.
function parseSrt(text) {
    var cues = [];
    var blocks = String(text).replace(/\r\n?/g, "\n").split(/\n[ \t]*\n/);
    for (var i = 0; i < blocks.length; i++) {
        var lines = blocks[i].split("\n");
        var t = -1;
        for (var j = 0; j < lines.length && j < 3; j++) {
            if (lines[j].indexOf("-->") >= 0) {
                t = j;
                break;
            }
        }
        if (t < 0)
            continue;
        var parts = lines[t].split("-->");
        var start = parseTimestamp(parts[0]);
        var end = parseTimestamp(parts[1]);
        if (start < 0 || end < 0 || end <= start)
            continue;
        var body = lines.slice(t + 1).join("\n").replace(/^\n+|\n+$/g, "");
        if (body === "")
            continue;
        cues.push({ start: start, end: end, text: body });
    }
    cues.sort(function(a, b) { return a.start - b.start || a.end - b.end; });
    return cues;
}

// The text of every cue showing at ms, joined (cues may overlap), or "".
function cueAt(cues, ms) {
    if (!cues || cues.length === 0)
        return "";
    // The last cue that starts at or before ms...
    var lo = 0, hi = cues.length - 1, last = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (cues[mid].start <= ms) {
            last = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    // ...and the ones before it that still run.
    var shown = [];
    for (var i = last; i >= 0 && i > last - 8; i--) {
        if (ms < cues[i].end)
            shown.unshift(cues[i].text);
    }
    return shown.join("\n");
}

// ---- SubStation Alpha -------------------------------------------------------

// A subtitle line from GStreamer as plain text with <i>/<b>/<u>, ready for
// toStyledText(). ASS/SSA events come as Matroska stores them -
// "ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text" - or as
// a script's "Dialogue: Layer,Start,End,Style,..." line; the fields before
// the text go, and so do override blocks ({\pos(..)}, {\fad(..)}, ...)
// apart from italic, bold and underline. \N and \n are line breaks, \h a
// space. Drawing commands ({\p1} ... {\p0}) are dropped with what they draw.
// Any other text is returned as it came.
function cleanEventText(line) {
    var s = String(line);
    var fields = -1;
    var dialogue = s.match(/^\s*Dialogue:\s*/i);
    if (dialogue) {
        s = s.substr(dialogue[0].length);
        fields = 9;
    } else if (/^\d+,-?\d+,[^,]*,[^,]*,-?\d+,-?\d+,-?\d+,[^,]*,/.test(s)) {
        fields = 8;
    }
    if (fields < 0)
        return s;
    var at = 0;
    for (var f = 0; f < fields; f++) {
        var comma = s.indexOf(",", at);
        if (comma < 0)
            return "";
        at = comma + 1;
    }
    return assOverridesToTags(s.substr(at));
}

function assOverridesToTags(text) {
    var out = "";
    var drawing = false;
    var open = { i: false, b: false, u: false };
    var i = 0;
    while (i < text.length) {
        var ch = text.charAt(i);
        if (ch === "{") {
            var close = text.indexOf("}", i);
            if (close < 0)
                break;
            var block = text.substring(i + 1, close);
            // Each override: a name of letters, then its value (\i1,
            // \b700, \pos(1,2), \rStyle).
            var re = /\\([a-zA-Z]+)([^\\]*)/g;
            var m;
            while ((m = re.exec(block)) !== null) {
                var name = m[1];
                var tag = name.charAt(0) === "r" ? "r" : name;
                if (tag !== "i" && tag !== "b" && tag !== "u" && tag !== "p" && tag !== "r")
                    continue;
                var digits = m[2].match(/^\d+/);
                // Without a value it goes back to the style: off.
                var value = digits ? parseInt(digits[0], 10) : 0;
                if (tag === "p") {
                    drawing = value > 0;
                } else if (tag === "r") {
                    // Reset to the style: close what is open.
                    ["u", "b", "i"].forEach(function(t) {
                        if (open[t]) { out += "</" + t + ">"; open[t] = false; }
                    });
                } else {
                    // \b takes a weight too: 400 and less is not bold.
                    var on = tag === "b" ? (value === 1 || value > 400) : value !== 0;
                    if (on && !open[tag]) { out += "<" + tag + ">"; open[tag] = true; }
                    else if (!on && open[tag]) { out += "</" + tag + ">"; open[tag] = false; }
                }
            }
            i = close + 1;
            continue;
        }
        if (drawing) {
            i++;
            continue;
        }
        if (ch === "\\" && i + 1 < text.length) {
            var next = text.charAt(i + 1);
            if (next === "N" || next === "n") { out += "\n"; i += 2; continue; }
            if (next === "h") { out += " "; i += 2; continue; }
        }
        out += ch;
        i++;
    }
    ["u", "b", "i"].forEach(function(t) {
        if (open[t]) out += "</" + t + ">";
    });
    return out.replace(/[ \t]+\n/g, "\n").replace(/\n[ \t]+/g, "\n").trim();
}

// ---- display ----------------------------------------------------------------

function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// Text for a Text item in StyledText format: <i>, <b>, <u> (in any case,
// SubRip writes them so) kept, everything else - other tags such as
// <font color=..>, entities, markup - shown as written or dropped (font
// tags), and line breaks as <br>.
function toStyledText(text) {
    var s = String(text === undefined || text === null ? "" : text);
    // SubRip's <font ...> and </font> carry colours we do not show.
    s = s.replace(/<\/?font\b[^>]*>/gi, "");
    s = escapeHtml(s);
    s = s.replace(/&lt;(\/?)([ibu])&gt;/gi, function(all, slash, tag) {
        return "<" + slash + tag.toLowerCase() + ">";
    });
    return s.replace(/\n/g, "<br>");
}

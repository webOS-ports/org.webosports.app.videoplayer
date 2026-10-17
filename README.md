# Videos

The video player for LuneOS: the videos on the device in a library, and a
full-screen player for them, with subtitles, audio tracks, speed and
picking up where you left off.

A QML app on Qt Multimedia (its GStreamer backend), with no C++ of its own.

## Features

**Library**

- Every video on the internal storage, and on memory cards and USB sticks
  mounted under `/media`, in any folder (hidden and system folders left
  out, six levels deep at most). Formats by extension: MP4, M4V, MOV, 3GP,
  MKV, WebM, AVI, MPEG, MPEG-TS, OGV, FLV, WMV, ASF.
- A list on phones, a grid of pictures on a tablet; sorted by name (with
  "Episode 2" before "Episode 10"), date or size from the app menu;
  searched by name and folder (accents ignored) once there are six or more.
- **Continue Watching** at the top: the videos stopped part way, with how
  much is left. Press and hold a video for Play from the Start, or to take
  it off the list.
- The length of each video once it has been played, and a picture of it
  taken a few seconds in. With **Read Video Lengths** in the app menu the
  lengths of all videos are read in the background, one file at a time
  without playing anything (Qt loads the file). That is off by default; see
  AAC below. If reading a file ends the app, the next start says which file
  and switches reading off again.

**Player**

- Full screen, black; a tap shows or hides the bars, which go by
  themselves after five seconds of playing and stay while paused.
- Seek bar with the time played and the time left; back and forward
  10 seconds; play/pause; speed (0.5× to 2×); fit the picture or fill the
  screen with it.
- Audio track picker for videos with more than one.
- Subtitles: a SubRip file beside the video (`movie.srt`, or `movie.en.srt`
  and the like for other languages; UTF-8, UTF-16 or, when the file is not
  UTF-8, Windows-1252/Latin-1), on by default when there is one; or a text
  subtitle track inside the video, including SubStation Alpha (ASS/SSA)
  tracks, shown as text with italic, bold and underline and without their
  positioning codes. Three text sizes.
- Picks up where it was left, with "Resumed at 1:23 - Start over" for a
  few seconds; remembers the audio track and subtitles chosen for each
  video.
- On a tall screen a wide video is turned to fill it, the way the device
  is held (orientation sensor); the turn button turns it back or round.
  Off in the app menu ("Turn Wide Videos on Tall Screens").
- Keeps the screen on while a video plays, and only then.
- Pauses when the card goes to the background, when a phone call starts
  (oFono), and shows it as paused when the sound system pauses it.
- The back gesture closes a picker, then the player, then the app.
- A video that does not start within 15 seconds - some files hang the
  hardware decoder before the first picture - is given up on with a
  message; the app stays usable and plays the next video.

**Opening videos from other apps**

`appinfo.json` registers the app for the video MIME types, so the file
manager and other apps can hand videos over. The launch parameter is

    {"target": "/media/internal/Movies/film.mkv"}

or a `file://` URL. More parameters, for scripts and tests: `position`
(ms), `subtitle` (`"off"`, `"srt"`, `"track:<n>"`), `audioTrack`, `rate`,
`report` (log what happens as `VIDEOPLAYER {json}` lines), `player`
(commands to the open player: `seek`, `rate`, `audioTrack`, `subtitle`,
`pause`, `play`, `close`) and `snapshot` (a PNG of the app's window, drawn
by the app, with `snapshotDelay`).

## The platform underneath

- **Software decoding** (GStreamer's libav decoders) is what plays video on
  devices with the LuneOS images as they are; the hardware decoders through
  gst-droid need Qt Multimedia and gst-droid fixes that are not in the
  images yet. See "Tested on" for what the mindphone plays that way.
- **AAC sound** goes to gst-droid's audio decoder on Halium devices unless
  `GST_PLUGIN_FEATURE_RANK=droidadec:NONE,droidaenc:NONE,avenc_aac:PRIMARY`
  is set for the app; that is a fix for the image (gst-droid's gate), not
  for this app. On the mindphone without it, loading a video with AAC
  sound ends the app (a segmentation fault in a GStreamer thread) - for
  playing it, and for reading its length, which is why that is off by
  default. With it, they play.
- **Hung decoders**: with the gst-droid in the images, some files hang the
  hardware decoder of the TouchPad and the Q25 before the first picture.
  Qt's GStreamer backend sends its requests to GStreamer's threads, so the
  app does not freeze; after 15 seconds it says the video did not start and
  puts that player aside with a new one in its place - destroying a player
  waits for its pipeline, which would freeze the app. The stuck pipeline
  stays in the process until the app ends, and ending the app may then
  hang: the process has to be killed.
- **Subtitles**: Qt draws a subtitle track's text over the video itself, an
  ASS track's raw event line included. The app draws a cleaned copy at its
  own size and gives Qt a zero-width space in its place, of which Qt draws a
  sliver of shade under the app's text while a subtitle shows. Picture
  subtitles (DVD, PGS) are not shown; there is no styled ASS rendering.

## Tests

    tools/run-tests.sh [path to luneos-components]

On the build host with `qmltestrunner` and luneos-components' desktop
stand-ins:

- `tst_subtitles`, `tst_format`, `tst_library`, `tst_playback`: the logic
  in `qml/js/` - decoding (UTF-8, byte order marks, UTF-16, the
  Windows-1252 fallback, invalid UTF-8 forms), SubRip parsing and timing,
  ASS event lines cleaned, what markup reaches the screen; times, lengths,
  sizes, dates; what is a video, which folders, launch targets, subtitle
  files by name, natural order, search; resuming, the remembered state,
  the load time-out, speeds, jumps, turning, track names.
- `tst_scanner`: the scan over `tests/data/library` (hidden, system and too
  deep folders left out, a vanished folder), the length probe with a
  stand-in player (a hang stops it and its player is kept, a rescan while
  busy), the cache's folder.
- `tst_ui`: the app itself with a stand-in player engine
  (`tests/qml/mocks/FakeEngine.qml`) on the TouchPad (1024x768), the
  mindphone (480x800) and the Q25 (720x720): the library, lengths, search,
  the app menu, playing, the bars, play/pause and jumps, the seek bar,
  speed, audio tracks, both kinds of subtitles and their size, fit and
  fill, turning, resuming, a video that never starts, a broken one, the
  back gesture, launch parameters (also before the scan is done),
  interruptions, the end of a video, the library's pictures, reading
  lengths switched off after a crash, and the bars fitting each screen. Screenshots of each
  state go to `build/test-output/ui/`.

`tests/mutation-check.py` breaks the app in one way at a time and checks
that a test fails: 33 ways, all caught (2026-10-16).

There is no C++ in the app, so no compiler, sanitizer or C/C++ static
analysis applies; `qmllint` reports only what the desktop stand-ins cannot
resolve (Qt Sensors is not installed on the build host).

## On a device

    tools/install.sh <adb serial>
    tools/test-device.sh <adb serial> <name> [file...]

`install.sh` packs the app and installs it through
`com.webos.appInstallService`. `test-device.sh` plays the test videos in
`/media/internal/vp-proto` and drives the player over the bus with its
launch parameters, reading back its `VIDEOPLAYER` lines: start, real-time
playback, seeking, the second audio track, the subtitle track inside a
file, the SubRip file beside it (Latin-1), 1.5× speed, the screen held
only while playing, resuming. Pictures of the app, drawn by the app so
that they work with the screen locked, and the log go to
`build/test-output/device/<name>/`. `RANK=<value>` starts the app by hand
with `GST_PLUGIN_FEATURE_RANK` set (for AAC on images without the
gst-droid fix); `HANG=1` adds a file that never opens, for the time-out;
`NO_LIBRARY=1` leaves out the library on devices where some videos hang
the decoder.

## Tested on

2026-10-16, with `tools/test-device.sh`, software decoding, the screen
partly locked (the app draws its own pictures for that). Numbers are the
app's own: video time per second from its position, pictures per second
from Qt's video sink.

| Device | File | Result |
|---|---|---|
| mindphone (armv7, 480x800) | vp9-480p.webm (Vorbis) | started in 1.0-1.3 s; 1.00x, 30 pictures/s; seek, 1.5x, screen held/let go, resume: pass |
| | xvid-ac3.avi (MPEG-4, AC3) | started in 1.0 s; 1.00x, 25 pictures/s; all checks pass |
| | h264-2audio-ass.mkv (AAC + AC3, ASS, .srt) | with RANK: 1.3 s; 1.00x, 30 pictures/s; second audio track, ASS track cleaned to "EMBEDDED ASS two \<i>italic\</i>", the .srt read as Windows-1252 ("Café naïve"), 1.5x: pass |
| | h264-720p.mp4 (AAC) | with RANK: 1.6 s; 1.00x, 30 pictures/s; 1.5x: pass |
| | h264-1080p.mp4 (AAC) | with RANK: 2.1-2.3 s; 1.00x, 30 pictures/s; 1.5x: pass |
| | hevc-720p.mkv (AAC) | with RANK: 1.5 s; 1.00x, 30 pictures/s; 1.5x: pass |
| | AAC files without RANK | the app ends (segmentation fault in GStreamer) |
| | a named pipe (never opens) | given up after 15.2 s with the message; the next video plays |
| TouchPad (armv7, 1024x768) | vp9-480p.webm | started in 3.5 s; 1.01x, 30 pictures/s; seek, 1.5x: pass; screen locked, so not in front and no pictures |

The TouchPad was only given VP9: the gst-droid in its image hangs on
H.264 and MPEG-4. The Q25 was not used.

## Icon

`icon.svg`, drawn into `icon.png` and `icon-256x256.png` by
`tools/make-icon.sh` with Qt's SVG renderer.

## Licence

GNU General Public License version 3 (GPL-3.0-only), see `LICENSE`.

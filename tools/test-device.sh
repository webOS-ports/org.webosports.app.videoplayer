#!/bin/bash
# Plays each test video on a real device and checks what the player says it
# did: it starts (or fails with a message, never a spinner for ever), the
# clock runs at the speed asked, seeking lands, the second audio track and
# the subtitles (the .srt beside the file, Latin-1 included, and an ASS
# track inside it, cleaned) come up, the screen is held on while playing
# and let go while paused, and a closed video resumes where it was left.
# The app is driven over the bus with its launch parameters ("target",
# "report", "player", "snapshot"; see qml/main.qml) and logs
# "VIDEOPLAYER {json}" lines, read back from the journal. Pictures of the
# app are drawn by the app itself ("snapshot"), so they work with the
# screen locked.
#
#   tools/test-device.sh <adb serial> <name> [file...]
#
# Install the app first (tools/install.sh). The files are looked for in
# DIR (default /media/internal/vp-proto). With RANK=<value> the app is
# started by hand with GST_PLUGIN_FEATURE_RANK=<value> in SAM's environment
# instead of through the application manager (for AAC on images without
# the gst-droid rank fix), the way the prototype's devlaunch.sh does.
# NO_LIBRARY=1 leaves out closing the player into the library (see there).
# HANG=1 also checks the load time-out with a file that never opens (a
# named pipe, made in a folder of its own and removed after); the app's
# process is then killed, as a stuck pipeline cannot be stopped.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: tools/test-device.sh <adb serial> <name> [file...]}
NAME=${2:?usage: tools/test-device.sh <adb serial> <name> [file...]}
shift 2
ADB="adb -s $SERIAL"
ID=org.webosports.app.videoplayer
DIR=${DIR:-/media/internal/vp-proto}
OUT=build/test-output/device/$NAME
mkdir -p "$OUT"
FILES=("$@")
[ ${#FILES[@]} -gt 0 ] || FILES=(h264-2audio-ass.mkv h264-720p.mp4 h264-1080p.mp4 xvid-ac3.avi vp9-480p.webm hevc-720p.mkv)
RANK=${RANK:-}
failures=0
LOG=$OUT/journal.txt
: > "$LOG"

close_app() {
    $ADB shell "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' >/dev/null 2>&1; \
        sleep 2; for q in \$(pgrep -x qml-runner); do grep -q $ID /proc/\$q/cmdline 2>/dev/null && kill \$q; done; true"
}

# launch '<params json>': through SAM (a relaunch reaches the running app),
# or by hand with RANK set when the app is not running yet.
launch() {
    if [ -n "$RANK" ] && ! $ADB shell "for q in \$(pgrep -x qml-runner); do grep -q $ID /proc/\$q/cmdline && echo yes; done" | grep -q yes; then
        local p=${1#\{}
        $ADB shell "S=\$(pgrep -x sam | head -n 1); tr '\\0' '\\n' < /proc/\$S/environ | grep -v -E '^(PWD|SHLVL|_|INVOCATION_ID|JOURNAL_STREAM|SYSTEMD_EXEC_PID)=' > /tmp/vpa-env; \
            echo APP_ID=$ID >> /tmp/vpa-env; echo GST_PLUGIN_FEATURE_RANK=$RANK >> /tmp/vpa-env; \
            cd /; nohup env -i \$(cat /tmp/vpa-env) /usr/bin/qml-runner --appid $ID '{\"appId\":\"$ID\",\"main\":\"file:///media/cryptofs/apps/usr/palm/applications/$ID/qml/main.qml\",\"params\":{\"displayAffinity\":0,$p}' > /tmp/vpa-out.log 2>&1 & sleep 3"
    else
        $ADB shell "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\",\"params\":$1}' > /tmp/vpa-l.out 2>&1"
    fi
}

# The app's lines since $since, as JSON, one per line.
events() {
    $ADB shell "{ journalctl --since '$since' --no-pager -o cat 2>/dev/null; cat /tmp/vpa-out.log 2>/dev/null; } | grep -a -o 'VIDEOPLAYER {.*}'" \
        | tr -d '\r' | sed 's/^VIDEOPLAYER //'
}

# check '<python expression over ev (list of events)>' [seconds]: waits for
# it to hold.
check() {
    local expr=$1 secs=${2:-10} i
    for i in $(seq 1 "$secs"); do
        if events | python3 -I -c "
import json, sys
ev = [json.loads(l) for l in sys.stdin if l.strip()]
def last(kind):
    m = [e for e in ev if e.get('event') == kind]
    return m[-1] if m else None
def after(kind, n):
    # Every event after the n-th (from 0) of that kind, that one included.
    idx = [i for i, e in enumerate(ev) if e.get('event') == kind]
    return ev[idx[n]:] if len(idx) > n else []
sys.exit(0 if ($expr) else 1)" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

count() {
    events | python3 -I -c "
import json, sys
print(sum(1 for l in sys.stdin if l.strip() and json.loads(l).get('event') == '$1'))"
}

# Into the media partition: an app started by the application manager
# has a /tmp of its own.
SNAPDIR=/media/internal/vp-app-test
snap() {
    $ADB shell "mkdir -p $SNAPDIR"
    launch "{\"snapshot\":\"$SNAPDIR/snap.png\"}"
    sleep 2
    $ADB pull $SNAPDIR/snap.png "$OUT/$1.png" >/dev/null 2>&1 && $ADB shell rm -f $SNAPDIR/snap.png || echo "   (no picture for $1)"
}
exists() {
    [ "$($ADB shell "[ -f '$1' ] && echo yes" | tr -d '\r')" = yes ]
}
trap '$ADB shell "rm -f $SNAPDIR/snap.png; rmdir $SNAPDIR 2>/dev/null; true"' EXIT

blocked() {
    $ADB shell "luna-send -n 1 luna://com.palm.display/control/getProperty '{\"properties\":[\"requestBlock\"]}'" | grep -o '"requestBlock": *[a-z]*' | grep -o '[a-z]*$'
}

# Video time per second over the last three status lines (four seconds).
rate_now() {
    events | python3 -I -c "
import json, sys
s = [json.loads(l) for l in sys.stdin if l.strip()]
s = [e for e in s if e.get('event') == 'status' and e['playing']]
print('%.2f' % ((s[-1]['position'] - s[-3]['position']) / 4000.0) if len(s) >= 3 else 0)"
}

ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; failures=$((failures + 1)); }

# With RANK the app is started by hand, which the application manager does
# not know of, so it cannot be relaunched with commands: each check is a
# fresh start with launch parameters instead (position, audioTrack,
# subtitle, rate, a picture after a delay). Pausing, the screen and resuming
# do not depend on the codec and are checked without RANK.
fresh() {
    close_app
    # Gone for good before the next start, or it would be relaunched
    # through the application manager without RANK.
    $ADB shell "for i in 1 2 3 4 5; do r=; for q in \$(pgrep -x qml-runner); do grep -q $ID /proc/\$q/cmdline 2>/dev/null && r=\$q; done; \
        [ -z \"\$r\" ] && break; sleep 1; done; [ -n \"\$r\" ] && kill -9 \$r; true"
    since=$($ADB shell 'date "+%Y-%m-%d %H:%M:%S"' | tr -d '\r')
    $ADB shell "rm -f /tmp/vpa-out.log; mkdir -p $SNAPDIR; rm -f $SNAPDIR/snap.png"
    launch "$1"
    check "last('started') or last('error')" 25
}
pull_snap() {
    sleep "${2:-0}"
    $ADB pull $SNAPDIR/snap.png "$OUT/$1.png" >/dev/null 2>&1 && $ADB shell rm -f $SNAPDIR/snap.png || echo "   (no picture for $1)"
}
rank_file() {
    local f=$1 path=$DIR/$1 base=${1%.*}
    if ! fresh "{\"target\":\"$path\",\"report\":true,\"position\":0,\"snapshot\":\"$SNAPDIR/snap.png\",\"snapshotDelay\":6000}"; then
        bad "$f: neither started nor gave an error in 25 s"; events >> "$LOG"; return
    fi
    if check "last('error')" 1; then
        bad "$f: $(events | grep '"error"' | tail -n 1)"; events >> "$LOG"; return
    fi
    started=$(events | grep '"event":"started"' | tail -n 1)
    echo "     $f: $(echo "$started" | python3 -I -c 'import json,sys; e=json.load(sys.stdin); print("started in %d ms, %dx%d, %d ms long, audio %s, subtitles %s" % (e["ms"], e["video"][0], e["video"][1], e["duration"], e["audioTracks"], e["subtitleTracks"]))')"
    pull_snap "$base-playing" 7
    if check "len([e for e in ev if e.get('event')=='status' and e['playing']]) >= 3" 8; then
        rate=$(events | python3 -I -c "
import json, sys
s = [json.loads(l) for l in sys.stdin if l.strip()]
s = [e for e in s if e.get('event') == 'status' and e['playing']]
a, b = s[-3], s[-1]
print('%.2f %.1f' % ((b['position'] - a['position']) / 4000.0, (b['frames'] - a['frames']) / 4.0))")
        fps=${rate#* }; rate=${rate% *}
        awk -v r="$rate" 'BEGIN { exit !(r > 0.8 && r < 1.2) }' && ok "$f: plays at ${rate}x real time, $fps pictures/s" || bad "$f: plays at ${rate}x real time, $fps pictures/s"
    else
        bad "$f: no status lines while playing"
    fi
    [ "$(blocked)" = true ] && ok "$f: screen held on while playing" || bad "$f: screen not held on while playing"
    events >> "$LOG"
    tracks=$(echo "$started" | python3 -I -c 'import json,sys; e=json.load(sys.stdin); print(len(e["audioTracks"]), len(e["subtitleTracks"]))')

    if fresh "{\"target\":\"$path\",\"report\":true,\"position\":15000}" && check "len([e for e in ev if e.get('event')=='status' and e['playing'] and 15000 <= e['position'] < 22000]) >= 2" 8; then
        ok "$f: started at 0:15 and plays on"
    else
        bad "$f: start at 0:15"
    fi
    events >> "$LOG"

    if [ "${tracks% *}" -gt 1 ]; then
        if fresh "{\"target\":\"$path\",\"report\":true,\"position\":2000,\"audioTrack\":1}" \
                && check "len([e for e in ev if e.get('event')=='status' and e['audio']==1 and e['playing']]) >= 2" 10; then
            ok "$f: second audio track, playing"
        else
            bad "$f: second audio track"
        fi
        events >> "$LOG"
    fi
    if [ "${tracks#* }" -gt 0 ]; then
        if fresh "{\"target\":\"$path\",\"report\":true,\"position\":5500,\"subtitle\":\"track:0\",\"snapshot\":\"$SNAPDIR/snap.png\",\"snapshotDelay\":3500}" \
                && check "any('EMBEDDED ASS two <i>italic</i>' == e.get('text') for e in ev if e.get('event')=='subtitle')" 12; then
            ok "$f: subtitle track inside the file, cleaned: EMBEDDED ASS two <i>italic</i>"
            pull_snap "$base-embedded-subtitles" 3
        else
            bad "$f: subtitle track inside the file (got: $(events | grep '"event":"subtitle"' | tail -n 2 | tr '\n' ' '))"
        fi
        events >> "$LOG"
    fi
    if exists "$DIR/$base.srt"; then
        if fresh "{\"target\":\"$path\",\"report\":true,\"position\":8000,\"subtitle\":\"srt\",\"snapshot\":\"$SNAPDIR/snap.png\",\"snapshotDelay\":2500}" \
                && check "any('second line' in e.get('text','') for e in ev if e.get('event')=='subtitle')" 12; then
            ok "$f: .srt beside it ($(events | grep '"event":"srt"' | tail -n 1 | grep -o '"encoding":"[^"]*"'))"
            pull_snap "$base-srt" 1
        else
            bad "$f: .srt beside it"
        fi
        events >> "$LOG"
        if fresh "{\"target\":\"$path\",\"report\":true,\"position\":15500,\"subtitle\":\"srt\"}" \
                && check "any('Caf\u00e9 na\u00efve' in e.get('text','') for e in ev if e.get('event')=='subtitle')" 10; then
            ok "$f: Latin-1 cue read right: Café naïve"
        else
            bad "$f: Latin-1 cue"
        fi
        events >> "$LOG"
    fi
    if fresh "{\"target\":\"$path\",\"report\":true,\"position\":3000,\"rate\":1.5}"; then
        # Once the start and its seek are over: the last four seconds.
        sleep 9
        rate=$(rate_now)
        awk -v r="$rate" 'BEGIN { exit !(r > 1.3 && r < 1.7) }' && ok "$f: 1.5x plays at ${rate}x" || bad "$f: 1.5x plays at ${rate}x"
    else
        bad "$f: 1.5x did not start"
    fi
    events >> "$LOG"
    close_app
}

echo "== $NAME: $($ADB shell uname -m | tr -d '\r'), lock: $($ADB shell "luna-send -n 1 luna://com.palm.display/control/lockStatus '{}'" | grep -o '"lockState":"[a-z]*"')${RANK:+, GST_PLUGIN_FEATURE_RANK=$RANK}"
close_app
for f in "${FILES[@]}"; do
    if [ -n "$RANK" ]; then
        exists "$DIR/$f" && rank_file "$f" || echo "skip $f: not on the device"
        continue
    fi
    path=$DIR/$f
    if ! exists "$path"; then
        echo "skip $f: not on the device"
        continue
    fi
    base=${f%.*}
    since=$($ADB shell 'date "+%Y-%m-%d %H:%M:%S"' | tr -d '\r')
    $ADB shell "rm -f /tmp/vpa-out.log"
    # From the start, whatever was remembered.
    launch "{\"target\":\"$path\",\"report\":true,\"position\":0}"
    if ! check "last('started') or last('error')" 25; then
        bad "$f: neither started nor gave an error in 25 s"; events >> "$LOG"; close_app; continue
    fi
    if check "last('error')" 1; then
        bad "$f: $(events | grep '"error"' | tail -n 1)"
        snap "$base-error"; events >> "$LOG"; close_app; continue
    fi
    started=$(events | grep '"event":"started"' | tail -n 1)
    echo "     $f: $(echo "$started" | python3 -I -c 'import json,sys; e=json.load(sys.stdin); print("started in %d ms, %dx%d, %d ms long, audio %s, subtitles %s" % (e["ms"], e["video"][0], e["video"][1], e["duration"], e["audioTracks"], e["subtitleTracks"]))')"
    sleep 5
    snap "$base-playing"
    # The clock at the normal speed: two status lines four or more seconds apart.
    if check "len([e for e in ev if e.get('event')=='status' and e['playing']]) >= 3" 8; then
        rate=$(events | python3 -I -c "
import json, sys
s = [json.loads(l) for l in sys.stdin if l.strip()]
s = [e for e in s if e.get('event') == 'status' and e['playing']]
a, b = s[-3], s[-1]
print('%.2f %.1f' % ((b['position'] - a['position']) / 4000.0, (b['frames'] - a['frames']) / 4.0))")
        fps=${rate#* }; rate=${rate% *}
        awk -v r="$rate" 'BEGIN { exit !(r > 0.8 && r < 1.2) }' && ok "$f: plays at ${rate}x real time, $fps pictures/s" || bad "$f: plays at ${rate}x real time, $fps pictures/s"
    else
        bad "$f: no status lines while playing"
    fi
    if $ADB shell true && [ "$(blocked)" = true ]; then ok "$f: screen held on while playing"; else bad "$f: screen not held on while playing"; fi

    # Seek.
    n=$(count command)
    launch '{"player":{"seek":15000}}'
    if check "any(e.get('event')=='status' and e['position'] >= 15000 and e['position'] < 22000 for e in after('command', $n))" 8; then
        ok "$f: seek to 0:15"
    else
        bad "$f: seek to 0:15"
    fi

    # The second audio track, when there is one.
    tracks=$(echo "$started" | python3 -I -c 'import json,sys; e=json.load(sys.stdin); print(len(e["audioTracks"]), len(e["subtitleTracks"]))')
    if [ "${tracks% *}" -gt 1 ]; then
        n=$(count command)
        launch '{"player":{"audioTrack":1}}'
        if check "len([e for e in after('command', $n) if e.get('event')=='status' and e['audio']==1 and e['playing']]) >= 2" 10; then
            ok "$f: second audio track, still playing"
        else
            bad "$f: second audio track"
        fi
        launch '{"player":{"seek":2000}}'
    fi

    # Subtitles inside the file (ASS, cleaned).
    if [ "${tracks#* }" -gt 0 ]; then
        launch '{"player":{"subtitle":"track:0","seek":5500}}'
        if check "any('EMBEDDED ASS two <i>italic</i>' == e.get('text') for e in ev if e.get('event')=='subtitle')" 12; then
            ok "$f: subtitle track inside the file, cleaned: EMBEDDED ASS two <i>italic</i>"
            snap "$base-embedded-subtitles"
        else
            bad "$f: subtitle track inside the file (got: $(events | grep '"event":"subtitle"' | tail -n 2 | tr '\n' ' '))"
        fi
    fi

    # Subtitles from a .srt beside it.
    if exists "$DIR/$base.srt"; then
        launch '{"player":{"subtitle":"srt","seek":8000}}'
        if check "any(e.get('event')=='srt' and e.get('cues',0)>0 for e in ev) and any('second line' in e.get('text','') for e in ev if e.get('event')=='subtitle')" 12; then
            ok "$f: .srt beside it ($(events | grep '"event":"srt"' | tail -n 1 | grep -o '"encoding":"[^"]*"'))"
            snap "$base-srt"
        else
            bad "$f: .srt beside it"
        fi
        launch '{"player":{"seek":15500}}'
        if check "any('Café naïve' in e.get('text','') for e in ev if e.get('event')=='subtitle')" 10; then
            ok "$f: Latin-1 cue read right: Café naïve"
        else
            bad "$f: Latin-1 cue (got: $(events | grep '"event":"subtitle"' | tail -n 1))"
        fi
        launch '{"player":{"subtitle":"off"}}'
    fi

    # Faster.
    launch '{"player":{"seek":3000,"rate":1.5}}'
    # Once the seek is over: the last four seconds.
    sleep 9
    rate=$(rate_now)
    awk -v r="$rate" 'BEGIN { exit !(r > 1.3 && r < 1.7) }' && ok "$f: 1.5x plays at ${rate}x" || bad "$f: 1.5x plays at ${rate}x"
    launch '{"player":{"rate":1}}'

    # Paused: the screen let go; playing again: held.
    launch '{"player":{"pause":true,"seek":12000}}'
    sleep 2
    if [ "$(blocked)" = false ]; then ok "$f: screen let go while paused"; else bad "$f: screen still held while paused"; fi
    snap "$base-paused"
    # Closed at 0:12, opened again: it picks up there. (NO_LIBRARY=1 skips
    # this: closing the player shows the library, which reads the length
    # of every video on the device - not wanted where some of them hang
    # the decoders.)
    if [ "${NO_LIBRARY:-0}" = 1 ]; then
        events >> "$LOG"; close_app; continue
    fi
    launch '{"player":{"close":true}}'
    sleep 1
    n=$(count started)
    launch "{\"target\":\"$path\",\"report\":true}"
    if check "any(e.get('resumedFrom',0) >= 11000 and e.get('resumedFrom',0) <= 13000 for e in after('started', $n))" 20; then
        ok "$f: resumed where it was closed ($(events | grep '"event":"started"' | tail -n 1 | grep -o '"resumedFrom":[0-9]*'))"
    else
        bad "$f: resume (got: $(events | grep '"event":"started"' | tail -n 1))"
    fi
    events >> "$LOG"
    close_app
done

if [ "${HANG:-0}" = 1 ]; then
    T=/media/internal/vp-app-test
    $ADB shell "mkdir -p $T && rm -f $T/never.mp4 && mkfifo $T/never.mp4"
    $ADB shell "rm -f /tmp/vpa-out.log"
    since=$($ADB shell 'date "+%Y-%m-%d %H:%M:%S"' | tr -d '\r')
    launch "{\"target\":\"$T/never.mp4\",\"report\":true}"
    if check "last('timeout') and last('error')" 25; then
        ms=$(events | grep '"event":"timeout"' | tail -n 1 | grep -o '"ms":[0-9]*')
        ok "never-opening file: given up with a message after ${ms#\"ms\":} ms"
        snap "timeout"
        # The app still answers: another video plays after it.
        n=$(count started)
        launch "{\"target\":\"$DIR/vp9-480p.webm\",\"report\":true}"
        if check "len(after('started', $n)) > 0" 20; then ok "a video plays after the stuck one"; else bad "no video plays after the stuck one"; fi
    else
        bad "never-opening file: no time-out"
    fi
    events >> "$LOG"
    # The stuck pipeline cannot be stopped: the process is killed, ours only.
    $ADB shell "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' >/dev/null 2>&1; sleep 3; \
        for q in \$(pgrep -x qml-runner); do grep -q $ID /proc/\$q/cmdline 2>/dev/null && { echo \"   process \$q still there after close: killed\"; kill -9 \$q; }; done; \
        rm -f $T/never.mp4"
fi

echo "$([ $failures = 0 ] && echo PASS || echo "FAILED: $failures") - pictures and the journal in $OUT"
exit $failures

# Pat Winlink Quick Start

**Station:** Yaesu FTdx1200 + Digirig-style interface (CP2102N serial + "USB Audio Device" sound card) on Ubuntu, using ARDOP over HF.

**The one rule:** only one program may own `/dev/ttyUSB0` (serial) or the sound card at a time. Close FLRig and QSSTV before starting Pat, and vice versa.

## Quick start (script)

Save as `~/pat-start.sh`, then `chmod +x ~/pat-start.sh` (once). Run with `~/pat-start.sh`, use Pat at http://localhost:8080, press **Ctrl-C** when done — the script kills everything and frees the ports.

```bash
#!/bin/bash
# pat-start.sh -- rig control + ARDOP + Pat, guaranteed teardown

if lsof /dev/ttyUSB0 >/dev/null 2>&1; then
    echo "ERROR: /dev/ttyUSB0 is in use (FLRig? QSSTV? old rigctld?). Close it first."
    exit 1
fi

cleanup() {
    kill $RIGPID $ARDOPPID 2>/dev/null
    sleep 1
    kill -9 $RIGPID $ARDOPPID 2>/dev/null
}
trap cleanup EXIT   # runs on ANY exit: Ctrl-C, crash, closed terminal

# CAT at 38400, PTT via RTS on the same port, no hardware handshake
rigctld -m 1034 -r /dev/ttyUSB0 -s 38400 -P RTS -p /dev/ttyUSB0 \
  --set-conf=serial_handshake=None,stop_bits=1,dtr_state=OFF &
RIGPID=$!

# ARDOP modem on port 8515; sound card addressed by name so it survives reboots
ardopc64 8515 plughw:CARD=Device,DEV=0 plughw:CARD=Device,DEV=0 &
ARDOPPID=$!

sleep 2
pat http   # foreground; Ctrl-C here ends the session
```

## Running the pieces manually

Three terminals (or background the first two with `&`), in this order:

```bash
# 1. Rig control daemon (CAT + PTT)
rigctld -m 1034 -r /dev/ttyUSB0 -s 38400 -P RTS -p /dev/ttyUSB0 \
  --set-conf=serial_handshake=None,stop_bits=1,dtr_state=OFF

# 2. ARDOP modem
ardopc64 8515 plughw:CARD=Device,DEV=0 plughw:CARD=Device,DEV=0

# 3. Pat
pat http
```

Then browse to http://localhost:8080. Find stations with `pat rmslist ardop`.

Key config (`~/.config/pat/config.json`) — the rig name must match everywhere:

```json
"hamlib_rigs": {
  "ftdx1200": {"network": "tcp", "address": "localhost:4532", "VFO": ""}
},
"ardop": {
  "rig": "ftdx1200",
  "ptt_ctrl": true,
  ...
}
```

## Radio settings

- Mode: **DATA-U** (rear-jack audio, correct sideband). Pat's QSY changes frequency only — the band-stack may flip you back to LSB on 40m, so check the mode after every QSY.
- Drive level: alsamixer → `alsamixer -c Device` → Speaker slider. Set by listening on a second receiver: back off until the tones are clean, not harsh. Zero ALC with good power out (METER → PO) is ideal; overdrive kills decodes even though it "sounds strong."

## Troubleshooting

Diagnose in layers. Each test below assumes the previous layer passed.

**Who's squatting?** The cause of most mystery failures:
```bash
pgrep -a rigctld; pgrep -a ardopc64      # stale daemons
lsof /dev/ttyUSB0                         # serial port owner
lsof /dev/snd/*                           # sound card owner (zombie QSSTV etc.)
```
`pkill rigctld`, `pkill ardopc64`, `pkill qsstv` as needed.

**CAT alive?** With rigctld running:
```bash
printf "f\n" | nc -q 1 127.0.0.1 4532     # should print dial freq in Hz
```
- Hangs/times out → rigctld can't talk to the radio: port busy, radio off, wrong baud (radio menu 39 = 38400), or hardware handshake got re-enabled (keep `serial_handshake=None` — without it the FTdx backend raises RTS on open and **keys the radio instantly**, plus all CAT reads time out).
- `rigctl -m 2` client says "No such file or directory" → often rigctld still starting up, or IPv6 localhost weirdness; use `127.0.0.1`, wait for `ss -ltn | grep 4532` to show LISTEN, or just use the `nc` test — Pat speaks to the socket the same way.

**PTT alive?**
```bash
printf "T 1\n" | nc -q 1 127.0.0.1 4532   # radio should key
printf "T 0\n" | nc -q 1 127.0.0.1 4532
```
`RPRT 0` but no keying → PTT config not latching; use the `-P RTS -p /dev/ttyUSB0` flags (not `--set-conf` for PTT). Bypass hamlib entirely to test the wiring:
```bash
python3 -c "import serial,time; s=serial.Serial('/dev/ttyUSB0'); s.rts=True; time.sleep(3); s.rts=False; s.close()"
```

**TX audio alive?** Kill ardop first (sound card is exclusive), key manually, send a tone:
```bash
printf "T 1\n" | nc -q 1 127.0.0.1 4532
speaker-test -D plughw:CARD=Device,DEV=0 -c 2 -t sine -f 1500   # Ctrl-C to stop
printf "T 0\n" | nc -q 1 127.0.0.1 4532
```
Keys but zero power → radio not in DATA-U, audio device muted (`MM` in alsamixer — press M), or wrong sound card. `Device or resource busy` → something else holds the card (see "Who's squatting?").

**Keys in short bursts ~10 times then "Connect timeout"?** That's normal shape for an unanswered connect. Check: clean (not overdriven) audio, DATA-U mode, real power out, then blame propagation — try other stations from `pat rmslist ardop`.

**`invalid character ':' after top-level value` on startup** → broken JSON in `~/.config/pat/config.json` (e.g. missing opening `{`). Validate: `python3 -m json.tool ~/.config/pat/config.json`.

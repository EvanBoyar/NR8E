#!/bin/bash
# pat-start.sh -- rig control + ARDOP + Pat, guaranteed teardown

if lsof /dev/ttyUSB0 >/dev/null 2>&1; then
    echo "ERROR: /dev/ttyUSB0 is in use (FLRig? QSSTV? old rigctld?). Close it first."
    exit 1
fi

cleanup() {
    # Kill daemons if still alive; suppress "no such process" noise
    kill $RIGPID $ARDOPPID 2>/dev/null
    # Give them a moment, then force-kill any survivor
    sleep 1
    kill -9 $RIGPID $ARDOPPID 2>/dev/null
}
# Run cleanup() when the script exits FOR ANY REASON:
# normal end, Ctrl-C (INT), or terminal closing (HUP/TERM)
trap cleanup EXIT

rigctld -m 1034 -r /dev/ttyUSB0 -s 38400 -P RTS -p /dev/ttyUSB0 \
  --set-conf=serial_handshake=None,stop_bits=1,dtr_state=OFF &
RIGPID=$!

ardopc64 8515 plughw:CARD=Device,DEV=0 plughw:CARD=Device,DEV=0 &
ARDOPPID=$!

sleep 2
pat http

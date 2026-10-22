#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/airshot-juggle-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
for function in RegisterJuggleDirectHit ResetJuggleState QueueAirShotBroadcast ResetAirShotBroadcastState; do
    sed -n "/^\(void\|bool\) $function(/,/^}/p" "$root/scripting/whaletracker/gameplay_whaletracker.sp"
done > "$work/airshot_juggle_under_test.inc"
cp "$root/tests/airshot_juggle_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"

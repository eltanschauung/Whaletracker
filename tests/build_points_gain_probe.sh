#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scripting=${1:-$HOME/hlserver/tf2/tf/addons/sourcemod/scripting}
output=${2:-/tmp/points-gain-probe.smx}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp "$root/scripting/whaletracker/points_gain_whaletracker.sp" "$work/"
cp "$root/tests/points_gain_probe.sp" "$work/probe.sp"
"$scripting/spcomp" "$work/probe.sp" -i "$scripting/include" -o "$output"

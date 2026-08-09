#!/bin/sh
set -eu

device_directory="/sdcard/Download/DeterministicTodoTests"
destination_directory="${1:-/tmp/deterministic-todo-gpx}"

adb get-state >/dev/null
latest_file="$(adb shell ls -1t "$device_directory"/*.gpx 2>/dev/null | sed -n '1p' | tr -d '\r')"
if [ -z "$latest_file" ]; then
  echo "Nessun GPX trovato in $device_directory" >&2
  exit 1
fi

mkdir -p "$destination_directory"
destination="$destination_directory/latest.gpx"
adb pull "$latest_file" "$destination" >/dev/null
echo "$destination"

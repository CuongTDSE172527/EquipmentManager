#!/usr/bin/env bash
set -euo pipefail
package=vn.cah.equipment_manager
trap 'adb logcat -d > android-reminder-logcat.txt 2>/dev/null || true' EXIT
adb install -r build/app/outputs/flutter-apk/app-debug.apk
api=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
if [ "$api" -ge 33 ]; then adb shell pm grant "$package" android.permission.POST_NOTIFICATIONS; fi
if [ "$api" -ge 31 ]; then adb shell appops set "$package" SCHEDULE_EXACT_ALARM allow; fi
adb logcat -c || true
adb shell am start -W -n "$package/.MainActivity"
ready=0
for attempt in $(seq 1 35); do
  if adb shell run-as "$package" cat files/smoke-ready.txt 2>/dev/null | grep -q ARMED; then ready=1; break; fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then adb logcat -d; echo 'Harness did not arm its alarm'; exit 1; fi
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am kill "$package"
sleep 2
remaining=$(adb shell pidof "$package" | tr -d '\r' || true)
if [ -n "$remaining" ]; then
  for pid in $remaining; do adb shell run-as "$package" kill -9 "$pid"; done
  sleep 1
  after=$(adb shell pidof "$package" | tr -d '\r' || true)
  if [ "$after" = "$remaining" ]; then echo 'Original process was not terminated'; exit 1; fi
fi
echo 'Application process closed. Waiting for the production background callback.'
found=0
for attempt in $(seq 1 90); do
  adb shell dumpsys notification --noredact > notification-dump.txt
  if grep -q '1 quá hạn, 0 sắp đến hạn' notification-dump.txt; then found=1; break; fi
  sleep 1
done
adb logcat -d > android-reminder-logcat.txt
if [ "$found" -ne 1 ]; then cat android-reminder-logcat.txt; echo 'Background summary notification did not appear'; exit 1; fi
echo "PASS: production dailyReminder posted the expected summary after process termination on API $api"

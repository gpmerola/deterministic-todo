#!/usr/bin/env python3
"""Seed an Android emulator with synthetic calendars and events.

For UI work on the Agenda without touching a real phone or real data:
three local calendars (no account sync), a busy week with overlaps,
all-day and multi-day events, a weekly series and an event in another
time zone. Usage:

    python3 tools/emulator_agenda_seed.py [--serial emulator-5554]

Refuses to run against anything that is not an emulator.
"""

from __future__ import annotations

import argparse
import re
import shlex
import datetime as dt
import subprocess
import sys
from zoneinfo import ZoneInfo

ZONE = ZoneInfo("Europe/London")
ACCOUNT = "agenda-demo"
CALENDARS = [
    ("Lavoro (demo)", 0xFF039BE5),
    ("Clinica (demo)", 0xFF7CB342),
    ("Personale (demo)", 0xFFD50000),
]


def adb(serial: str, *args: str) -> str:
    return subprocess.run(
        ["adb", "-s", serial, *args], check=True, capture_output=True, text=True
    ).stdout


def content_insert(serial: str, uri: str, values: dict[str, object]) -> None:
    # One remote shell command, each argument quoted for the device shell.
    parts = ["content", "insert", "--uri", uri]
    for key, value in values.items():
        if isinstance(value, bool):
            parts += ["--bind", f"{key}:i:{int(value)}"]
        elif isinstance(value, int):
            parts += ["--bind", f"{key}:l:{value}"]
        else:
            # The content tool splits bindings on ':'; escape it in values.
            parts += ["--bind", f"{key}:s:{str(value).replace(':', chr(92) + ':')}"]
    adb(serial, "shell", " ".join(shlex.quote(part) for part in parts))


def calendar_ids(serial: str) -> dict[str, int]:
    out = adb(
        serial, "shell", "content", "query", "--uri",
        "content://com.android.calendar/calendars",
        "--projection", "_id:calendar_displayName:account_name",
    )
    ids: dict[str, int] = {}
    for line in out.splitlines():
        if f"account_name={ACCOUNT}" not in line:
            continue
        found = dict(re.findall(r"(\w+)=([^,]*)", line))
        ids[found["calendar_displayName"].strip()] = int(found["_id"])
    return ids


def millis(day: dt.date, hour: int, minute: int = 0, zone=ZONE) -> int:
    return int(dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=zone).timestamp() * 1000)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", default="emulator-5554")
    args = parser.parse_args()
    if not args.serial.startswith("emulator-"):
        print("Only emulators: this script writes calendars.", file=sys.stderr)
        return 1
    if adb(args.serial, "shell", "getprop", "ro.kernel.qemu").strip() != "1" and \
            "emulator" not in adb(args.serial, "shell", "getprop", "ro.hardware").lower() and \
            "ranchu" not in adb(args.serial, "shell", "getprop", "ro.hardware").lower():
        print("Device does not look like an emulator; stopping.", file=sys.stderr)
        return 1

    sync = (
        "content://com.android.calendar/calendars?caller_is_syncadapter=true"
        f"&account_name={ACCOUNT}&account_type=LOCAL"
    )
    existing = calendar_ids(args.serial)
    for name, color in CALENDARS:
        if name in existing:
            continue
        content_insert(args.serial, sync, {
            "account_name": ACCOUNT,
            "account_type": "LOCAL",
            "name": name,
            "calendar_displayName": name,
            "calendar_color": color - (1 << 32),
            "calendar_access_level": 700,
            "ownerAccount": "demo@example.com",
            "visible": True,
            "sync_events": True,
            "calendar_timezone": "Europe/London",
        })
    ids = calendar_ids(args.serial)
    work, clinic, personal = (ids[name] for name, _ in CALENDARS)

    # Idempotent: the demo calendars' events are replaced on every run.
    adb(args.serial, "shell", " ".join(shlex.quote(part) for part in [
        "content", "delete", "--uri",
        "content://com.android.calendar/events?caller_is_syncadapter=true"
        f"&account_name={ACCOUNT}&account_type=LOCAL",
        "--where", f"calendar_id IN ({work},{clinic},{personal})",
    ]))

    today = dt.date.today()
    monday = today - dt.timedelta(days=today.weekday())
    events: list[dict[str, object]] = []

    def timed(cal: int, title: str, day: dt.date, start: tuple[int, int], end: tuple[int, int], **extra):
        events.append({
            "calendar_id": cal,
            "title": title,
            "dtstart": millis(day, *start),
            "dtend": millis(day, *end),
            "eventTimezone": "Europe/London",
            **extra,
        })

    def all_day(cal: int, title: str, first: dt.date, days: int = 1):
        start = dt.datetime(first.year, first.month, first.day, tzinfo=dt.timezone.utc)
        events.append({
            "calendar_id": cal,
            "title": title,
            "dtstart": int(start.timestamp() * 1000),
            "dtend": int((start + dt.timedelta(days=days)).timestamp() * 1000),
            "allDay": 1,
            "eventTimezone": "UTC",
        })

    for week in range(-1, 4):
        base = monday + dt.timedelta(weeks=week)
        timed(work, "Riunione di reparto", base, (9, 0), (10, 0))
        timed(clinic, "Prima visita (adulto) 60'", base, (11, 30), (12, 30))
        timed(clinic, "Follow-up 15'", base, (16, 0), (16, 15))
        timed(clinic, "Follow-up 15'", base, (16, 30), (16, 45))
        timed(work, "Case based discussion", base + dt.timedelta(days=1), (11, 0), (12, 0))
        timed(work, "TNG Meeting", base + dt.timedelta(days=1), (11, 0), (12, 0),
              description="https://teams.microsoft.com/l/meetup-join/demo")
        timed(clinic, "ADHD Assessment (Child & Adolescent) 75'", base + dt.timedelta(days=1), (17, 0), (18, 15))
        timed(work, "Mrcpsych paper b Pearson Professional", base + dt.timedelta(days=2), (8, 15), (9, 15))
        timed(work, "Peer Review & Safeguarding Concerns", base + dt.timedelta(days=2), (13, 0), (13, 30))
        timed(work, "NADS VNS assessment slot", base + dt.timedelta(days=2), (14, 0), (16, 0))
        timed(personal, "Giuseppe", base + dt.timedelta(days=2), (15, 45), (16, 30))
        timed(clinic, "Prima visita (adulto) 60'", base + dt.timedelta(days=3), (10, 30), (11, 30))
        timed(work, "TNG Drug Projects Meeting", base + dt.timedelta(days=3), (15, 30), (16, 30))
        timed(personal, "Dan & Giuseppe", base + dt.timedelta(days=4), (12, 30), (13, 0))
        timed(work, "PRADA KCL planning and strategy", base + dt.timedelta(days=4), (14, 0), (15, 30))
        timed(personal, "Corsa al parco", base + dt.timedelta(days=5), (9, 0), (10, 0))
    all_day(personal, "Sollecito pagamento", monday + dt.timedelta(days=7))
    all_day(work, "Congresso a Roma", monday + dt.timedelta(days=9), 3)
    all_day(personal, "Compleanno Anna", today)
    timed(work, "Call con New York", today + dt.timedelta(days=2), (15, 0), (16, 0),
          eventTimezone="America/New_York")
    # A Teams meeting starting soon (Today strip countdown and join button).
    soon = dt.datetime.now(ZONE).replace(second=0, microsecond=0) + dt.timedelta(minutes=20)
    events.append({
        "calendar_id": work,
        "title": "Stand-up (demo)",
        "dtstart": int(soon.timestamp() * 1000),
        "dtend": int((soon + dt.timedelta(minutes=30)).timestamp() * 1000),
        "eventTimezone": "Europe/London",
        "description": "Join: https://teams.microsoft.com/l/meetup-join/demo-standup",
    })
    # An invitation from someone else, not yet answered (drawn outlined).
    events.append({
        "calendar_id": work,
        "title": "Grand Round (invito)",
        "dtstart": millis(today + dt.timedelta(days=1), 15, 0),
        "dtend": millis(today + dt.timedelta(days=1), 16, 0),
        "eventTimezone": "Europe/London",
        "organizer": "boss@example.com",
        "hasAttendeeData": 1,
    })
    for event in events:
        content_insert(args.serial, "content://com.android.calendar/events", event)
    invite = adb(
        args.serial, "shell", "content", "query", "--uri",
        "content://com.android.calendar/events", "--projection", "_id",
        "--where", shlex.quote("title='Grand Round (invito)'"),
    )
    for event_id in re.findall(r"_id=(\d+)", invite):
        content_insert(args.serial, "content://com.android.calendar/attendees", {
            "event_id": int(event_id),
            "attendeeEmail": "demo@example.com",
            "attendeeName": "Demo",
            "attendeeRelationship": 1,
            "attendeeType": 1,
            "attendeeStatus": 3,
        })
    print(f"{len(ids)} calendars, {len(events)} synthetic events on {args.serial}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

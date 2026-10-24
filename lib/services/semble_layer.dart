import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/agenda.dart';
import '../domain/semble_availability.dart';
import '../domain/semble_bookings.dart';
import '../domain/task.dart';
import 'semble_client.dart';
import 'semble_settings.dart';

/// The Calendar's Semble layer: rules for a window around today, kept in
/// memory for the app session and reread on Calendar loads at most every
/// [minAge] (pull-to-refresh forces it). Nothing is stored on disk.
class SembleLayer extends ChangeNotifier {
  SembleLayer({
    SembleSettings? settings,
    SembleClient? client,
    this.zoneShift = sembleZoneShift,
  }) : _settings = settings ?? SembleSettings(),
       _client = client ?? SembleClient();

  /// Minutes from London to the phone's zone on a day; tests pin it.
  final int Function(CivilDate day) zoneShift;

  /// The app's instance, shared by the Calendar views and their routes.
  static final shared = SembleLayer();

  static const daysBack = 7;
  static const daysAhead = 92;
  static const minAge = Duration(minutes: 15);

  /// Bookings read for the Calendar (build 289): from yesterday to four
  /// weeks ahead, where a new booking matters before iCal brings it.
  static const bookingDaysAhead = 28;

  final SembleSettings _settings;
  final SembleClient _client;

  List<SembleRule> _rules = const [];
  List<SembleBooking> _bookings = const [];

  /// Bumped whenever the bookings change, so Calendar pages re-read.
  int bookingsRevision = 0;
  CivilDate? _first;
  CivilDate? _last;
  DateTime? _fetchedAt;
  bool _enabled = false;
  bool _zoneMatches = true;
  Future<void>? _running;

  /// Last failure, for the Settings page; cleared by a successful read.
  SembleFailure? failure;

  bool _canBlock = false;

  /// Key, user and room are saved, so the new event offers "Blocca in
  /// Semble" (build 297). Known after the first read; never a network call.
  bool get canBlock => _canBlock;

  /// Shown in any zone: London times are converted (build 296).
  bool get active => _enabled && _first != null;
  bool get zoneMatches => _zoneMatches;
  int get ruleCount => _rules.length;
  int get bookingCount => _bookings.length;

  /// Applies the user's Semble bookings to the Calendar entries (see
  /// [sembleAdjustEntries]); null when there is nothing to apply.
  List<AgendaEntry> Function(List<AgendaEntry> merged)? adjustEntries(
    List<AgendaCalendar> calendars,
    Set<String> hiddenCalendarIds,
  ) {
    _sembleCalendarIds = {
      for (final calendar in calendars)
        if (isSembleCalendar(calendar)) calendar.id,
    };
    final bookings = _bookings;
    if (!_enabled || bookings.isEmpty) return null;
    return (merged) => sembleAdjustEntries(
      bookings: bookings,
      merged: merged,
      calendars: calendars,
      hiddenCalendarIds: hiddenCalendarIds,
    );
  }

  DateTime? get fetchedAt => _fetchedAt;
  CivilDate? get first => _first;
  CivilDate? get last => _last;

  /// Bands for [day], or none outside the window read: a one-off rule
  /// there would be missing and the layer would look complete.
  /// [busy] are the day's events: their time is not shown as free
  /// (build 287).
  List<SembleBand> bandsFor(
    CivilDate day, {
    Iterable<AgendaEntry> busy = const [],
  }) => sembleFreeBands(_bandsOf(day), agendaBusyMinutes(busy, day));

  List<SembleBand> _bandsOf(CivilDate day) {
    final first = _first;
    final last = _last;
    if (!active || first == null || last == null) return const [];
    if (day.compareTo(first) < 0 || day.compareTo(last) > 0) return const [];
    return sembleShiftBands(sembleBandsFor(_rules, day), zoneShift(day));
  }

  /// Ids of [entries] on [day] that are not Semble visits but fall in
  /// bookable Semble time (build 300): the Calendar highlights them.
  /// Only events not yet over (build 302).
  /// Without [includeIgnored], not those whose edge the user removed.
  Set<String> overlapsFor(
    CivilDate day,
    Iterable<AgendaEntry> entries, {
    DateTime Function() now = DateTime.now,
    bool includeIgnored = false,
  }) {
    final bands = _bandsOf(day);
    if (bands.isEmpty) return const {};
    final shown = includeIgnored || _ignored.isEmpty
        ? entries
        : entries.where((entry) => !isIgnored(entry));
    return sembleOverlaps(shown, day, bands, isVisit, now: now());
  }

  /// Amber edges removed by hand, one occurrence each (build 307): the
  /// rules and Semble are untouched.
  Map<String, int> _ignored = const {};

  bool isIgnored(AgendaEntry entry) =>
      _ignored.containsKey(sembleOverlapKey(entry));

  Future<void> setIgnored(AgendaEntry entry, bool ignored) async {
    final next = await _settings.ignoredOverlaps();
    if (ignored) {
      next[sembleOverlapKey(entry)] = entry.end.millisecondsSinceEpoch;
    } else {
      next.remove(sembleOverlapKey(entry));
    }
    await _settings.saveIgnoredOverlaps(next);
    _ignored = next;
    notifyListeners();
  }

  /// A booking read from Semble or an event of a Semble calendar.
  bool isVisit(AgendaEntry entry) =>
      entry.isSembleBooking ||
      entry.calendarIds.any(_sembleCalendarIds.contains);

  Set<String> _sembleCalendarIds = const {};

  /// [zoneLabel] as shown by the Calendar ("Europe/London · UTC+1").
  /// Concurrent calls share one read.
  Future<void> refresh({
    required CivilDate today,
    String? zoneLabel,
    bool force = false,
    DateTime Function() now = DateTime.now,
  }) {
    // Unknown zone (null) keeps the last answer.
    final zoneMatches = zoneLabel == null
        ? _zoneMatches
        : zoneLabel.split(' ').first == sembleZone;
    if (zoneMatches != _zoneMatches) {
      _zoneMatches = zoneMatches;
      notifyListeners();
    }
    return _running ??= _refresh(
      today,
      force,
      now,
    ).whenComplete(() => _running = null);
  }

  Future<void> _refresh(
    CivilDate today,
    bool force,
    DateTime Function() now,
  ) async {
    final config = await _settings.read();
    _canBlock = config.ready && config.roomId != null;
    _ignored = await _settings.ignoredOverlaps();
    final key = config.ready && config.enabled
        ? await _settings.apiKey()
        : null;
    if (key == null || config.userId == null) {
      final changed = _enabled || _first != null || _bookings.isNotEmpty;
      _enabled = false;
      _rules = const [];
      _setBookings(const []);
      _first = _last = _fetchedAt = null;
      if (changed) notifyListeners();
      return;
    }
    _enabled = true;
    final first = today.addDays(-daysBack);
    final last = today.addDays(daysAhead);
    final fetched = _fetchedAt;
    if (!force &&
        _first == first &&
        fetched != null &&
        now().difference(fetched) < minAge) {
      return;
    }
    try {
      _rules = await _client.rules(
        key: key,
        userId: config.userId!,
        first: first,
        last: last,
      );
      _first = first;
      _last = last;
      _fetchedAt = now();
      failure = null;
      try {
        await _settings.saveRules(_rules, first, last);
      } on Object {
        // Only the background conflict check misses the newest rules.
      }
    } on SembleException catch (error) {
      // The previous rules stay drawn; Settings shows the failure.
      failure = error.failure;
    }
    final doctor = config.doctorName;
    if (doctor == null) {
      _setBookings(const []);
    } else {
      try {
        _setBookings(
          await _client.bookings(
            key: key,
            first: today.addDays(-1),
            last: today.addDays(bookingDaysAhead),
            doctorName: doctor,
          ),
        );
      } on SembleException catch (error) {
        // Old bookings stay until the next read; iCal still brings them.
        failure ??= error.failure;
      }
    }
    notifyListeners();
  }

  void _setBookings(List<SembleBooking> bookings) {
    if (bookings.isEmpty && _bookings.isEmpty) return;
    _bookings = bookings;
    bookingsRevision++;
  }

  /// After Settings changes: drop everything and read again.
  Future<void> reset({required CivilDate today, String? zoneLabel}) async {
    _rules = const [];
    _setBookings(const []);
    _first = _last = _fetchedAt = null;
    failure = null;
    notifyListeners();
    await refresh(today: today, zoneLabel: zoneLabel, force: true);
  }

  @visibleForTesting
  void seedBookings(List<SembleBooking> bookings) {
    _enabled = true;
    _setBookings(bookings);
    notifyListeners();
  }

  @visibleForTesting
  void seed(List<SembleRule> rules, CivilDate first, CivilDate last) {
    _rules = rules;
    _first = first;
    _last = last;
    _enabled = true;
    _zoneMatches = true;
    _canBlock = false;
    notifyListeners();
  }
}

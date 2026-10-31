import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/agenda.dart';
import '../domain/semble_availability.dart';
import '../domain/semble_bookings.dart';
import '../domain/task.dart';
import 'semble_client.dart';
import 'semble_ical_client.dart';
import 'semble_settings.dart';

/// Where the Calendar's Semble bookings come from (build 312).
enum SembleBookingsSource {
  /// Read now with the API key.
  api,

  /// Read now from the iCal link, without the key.
  ical,

  /// Neither answered: the visits are only the Semble calendar in Google
  /// (build 313).
  google,

  /// Not read: Semble is off, or the surname is missing.
  none,
}

/// The Calendar's Semble layer: rules for a window around today, kept in
/// memory for the app session and reread on Calendar loads at most every
/// [minAge] (pull-to-refresh forces it). From build 312 the last rules read
/// are drawn when Semble cannot be read, and an iCal link brings bookings
/// without the key; otherwise the visits are those of the Semble calendar
/// in Google (build 313).
class SembleLayer extends ChangeNotifier {
  SembleLayer({
    SembleSettings? settings,
    SembleClient? client,
    SembleIcalClient? ical,
    this.zoneShift = sembleZoneShift,
  }) : _settings = settings ?? SembleSettings(),
       _client = client ?? SembleClient(),
       _ical = ical ?? SembleIcalClient();

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
  final SembleIcalClient _ical;

  List<SembleRule> _rules = const [];
  List<SembleBooking> _bookings = const [];

  /// Bumped whenever the bookings change, so Calendar pages re-read.
  int bookingsRevision = 0;
  CivilDate? _first;
  CivilDate? _last;
  DateTime? _fetchedAt;
  CivilDate? _readFor;
  DateTime? _attemptedAt;
  DateTime? _rulesSavedAt;
  DateTime? _bookingsSavedAt;

  /// The rules drawn are the last ones read, not today's (build 312).
  bool rulesFromCache = false;

  /// Where the bookings drawn come from (build 312).
  SembleBookingsSource bookingsSource = SembleBookingsSource.none;

  /// Last failure of the iCal link, for the Settings page.
  SembleIcalFailure? icalFailure;

  /// When the rules drawn were read from Semble; null if unknown (rules
  /// saved before build 312).
  DateTime? get rulesSavedAt => _rulesSavedAt;

  /// When the bookings drawn were read.
  DateTime? get bookingsSavedAt => _bookingsSavedAt;

  /// Whether the last Calendar load found a visible Semble calendar
  /// (build 313): without the API it is where the visits come from. Null
  /// until a Calendar load.
  bool? googleCalendarVisible;

  bool _droppedSavedBookings = false;

  /// End of the window the iCal feed was read for (build 314).
  DateTime? _feedUntil;
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
    googleCalendarVisible = _sembleCalendarIds.any(
      (id) => !hiddenCalendarIds.contains(id),
    );
    final bookings = _bookings;
    if (!_enabled || bookings.isEmpty) return null;
    final feedUntil = bookingsSource == SembleBookingsSource.ical
        ? _feedUntil
        : null;
    return (merged) => sembleAdjustEntries(
      bookings: bookings,
      merged: merged,
      calendars: calendars,
      hiddenCalendarIds: hiddenCalendarIds,
      feedUntil: feedUntil,
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
    if (!_droppedSavedBookings) {
      _droppedSavedBookings = true;
      try {
        await _settings.deleteSavedBookings();
      } on Object {
        // Retried by the next app session.
      }
    }
    _ignored = await _settings.ignoredOverlaps();
    final key = config.ready && config.enabled
        ? await _settings.apiKey()
        : null;
    // Build 312: the iCal link alone keeps visits in the Calendar.
    final link = config.enabled ? await _settings.icalLink() : null;
    if ((key == null || config.userId == null) && link == null) {
      final changed = _enabled || _first != null || _bookings.isNotEmpty;
      _enabled = false;
      _canBlock = false;
      _rules = const [];
      _setBookings(const []);
      _first = _last = _fetchedAt = _readFor = _attemptedAt = null;
      _rulesSavedAt = _bookingsSavedAt = null;
      rulesFromCache = false;
      bookingsSource = SembleBookingsSource.none;
      failure = icalFailure = null;
      if (changed) notifyListeners();
      return;
    }
    _enabled = true;
    final attempted = _attemptedAt;
    // Throttled per attempt, so a refused key or link is not asked again
    // on every Calendar load (build 312); pull-to-refresh forces it.
    if (!force &&
        _readFor == today &&
        attempted != null &&
        now().difference(attempted) < minAge) {
      return;
    }
    _readFor = today;
    _attemptedAt = now();
    final first = today.addDays(-daysBack);
    final last = today.addDays(daysAhead);
    failure = icalFailure = null;
    var rulesRead = false;
    if (key != null && config.userId != null) {
      try {
        _rules = await _client.rules(
          key: key,
          userId: config.userId!,
          first: first,
          last: last,
        );
        _first = first;
        _last = last;
        _fetchedAt = _rulesSavedAt = now();
        rulesFromCache = false;
        rulesRead = true;
        try {
          await _settings.saveRules(_rules, first, last, savedAt: now());
        } on Object {
          // Only the background check and the fallback miss the newest.
        }
      } on SembleException catch (error) {
        failure = error.failure;
      }
    } else {
      failure = SembleFailure.noKey;
    }
    if (!rulesRead && _first == null) {
      // Build 312: the last rules read stay drawn, marked as such.
      final cache = await _settings.cachedRules();
      if (cache != null) {
        _rules = cache.rules;
        _first = cache.first;
        _last = cache.last;
        _rulesSavedAt = cache.savedAt;
        rulesFromCache = true;
      }
    } else if (!rulesRead) {
      rulesFromCache = true;
    }
    // Writes need a working key: no «Blocca» offer with a refused one.
    _canBlock =
        config.ready &&
        config.roomId != null &&
        failure != SembleFailure.rejected;
    await _refreshBookings(config, rulesRead ? key : null, link, today, now);
    notifyListeners();
  }

  /// Bookings from the API, else from the iCal link (build 312), else none:
  /// the Semble calendar in Google still shows the visits (build 313). A
  /// visit shown twice is avoided by [sembleAdjustEntries].
  Future<void> _refreshBookings(
    SembleConfig config,
    String? key,
    String? link,
    CivilDate today,
    DateTime Function() now,
  ) async {
    final doctor = config.doctorName;
    List<SembleBooking>? read;
    var source = SembleBookingsSource.none;
    if (key != null && doctor != null) {
      try {
        read = await _client.bookings(
          key: key,
          first: today.addDays(-1),
          last: today.addDays(bookingDaysAhead),
          doctorName: doctor,
        );
        source = SembleBookingsSource.api;
      } on SembleException catch (error) {
        failure ??= error.failure;
      }
    }
    if (read == null && link != null) {
      try {
        final until = today.addDays(bookingDaysAhead + 1).asLocalDate;
        read = await _ical.bookings(
          link: link,
          from: today.addDays(-1).asLocalDate,
          to: until,
        );
        source = SembleBookingsSource.ical;
        _feedUntil = until;
      } on SembleIcalException catch (error) {
        icalFailure = error.failure;
      }
    }
    if (read != null) {
      _setBookings(read);
      bookingsSource = source;
      _bookingsSavedAt = now();
      return;
    }
    // Build 313: without the API or the link the Semble calendar in Google
    // (filled by the user's script every 30 minutes) is the only source of
    // visits; older bookings would show visits cancelled since then.
    _setBookings(const []);
    _bookingsSavedAt = null;
    bookingsSource = key != null && doctor == null && link == null
        ? SembleBookingsSource.none
        : SembleBookingsSource.google;
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
    _first = _last = _fetchedAt = _readFor = _attemptedAt = null;
    _rulesSavedAt = _bookingsSavedAt = null;
    rulesFromCache = false;
    bookingsSource = SembleBookingsSource.none;
    failure = icalFailure = null;
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

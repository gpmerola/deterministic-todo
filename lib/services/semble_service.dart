import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/agenda.dart';
import '../domain/semble_availability.dart';
import '../domain/semble_bookings.dart';
import '../domain/task.dart';

/// Semble public API (GraphQL). The key authenticates with `x-token`.
const sembleEndpoint = 'https://open.semble.io/graphql';

/// Semble availability rules are set in the clinic's zone; the layer is
/// drawn only when the phone is in it, so wall-clock times line up.
const sembleZone = 'Europe/London';

/// The only operations this app ever sends to Semble (build 285): a token
/// check and a read of the clinician's availability rules. No `room`
/// selection (forbidden for this key, `settingsGeneral`). Comments are not
/// read: they may name patients. The only mutations are the confirmed
/// unavailability block and its undo (build 297, below).
const sembleCheckQuery = 'query { __typename }';

String sembleRulesQuery({required bool exclusions}) =>
    '''
query SembleAvailability(\$userIds: [String], \$range: DateRange, \$page: Pagination) {
  availabilityRules(userIds: \$userIds, dateRange: \$range, pagination: \$page) {
    data {
      id unavailability startDate endDate startTime endTime
      ${exclusions ? 'exclusions' : ''}
      recurrence { frequency interval daysOfTheWeek }
    }
  }
}''';

/// Bookings of the whole clinic for a date range (build 288): the key has
/// no clinician filter, so the app keeps the user's by `doctorName`. Only
/// times, deletion, type, clinician name and the reception journey are
/// read; never `patient`, `comments`, `reference` or `cancellationReason`.
String sembleBookingsQuery({
  required CivilDate first,
  required CivilDate end,
  required int page,
  required int pageSize,
}) =>
    '''
query {
  bookings(dateRange: {start: "$first", end: "$end"}, pagination: {page: $page, pageSize: $pageSize}) {
    data {
      start end deleted doctorName
      appointment { title }
      bookingJourney { arrived consultation departed dna }
    }
    pageInfo { hasMore }
  }
}''';

/// The only writes this app sends (build 297), each after a confirmation.
const sembleCreateBlockMutation =
    r'''mutation($data: CreateResourceAvailabilityInput!) { createAvailability(data: $data) { data { id } } }''';
const sembleDeleteBlockMutation =
    r'''mutation($id: ID!) { deleteAvailability(id: $id) { data { id } } }''';

/// Semble's `UnavailabilityType` values; Todo sends only `other` (build 300).
enum SembleBlockType {
  other('Altro'),
  clinicalAdmin('Admin clinico'),
  generalAdmin('Admin'),
  teamMeeting('Riunione'),
  annualLeave('Ferie'),
  sickness('Malattia'),
  cpd('CPD'),
  studyLeave('Studio');

  const SembleBlockType(this.label);
  final String label;
}

enum SembleFailure { noKey, rejected, forbidden, unreachable, badResponse }

class SembleException implements Exception {
  const SembleException(this.failure);
  final SembleFailure failure;

  String get message => switch (failure) {
    SembleFailure.noKey =>
      'Configura chiave e User ID in Impostazioni → Semble.',
    SembleFailure.rejected => 'Semble ha rifiutato la chiave API.',
    SembleFailure.forbidden =>
      'La chiave non ha il permesso per questa operazione su Semble.',
    SembleFailure.unreachable =>
      'Semble non raggiungibile: controlla la rete e riprova.',
    SembleFailure.badResponse => 'Risposta di Semble non comprensibile.',
  };
}

final class SembleConfig {
  const SembleConfig({
    required this.maskedKey,
    required this.userId,
    required this.enabled,
    this.doctorName,
    this.roomId,
  });

  /// Semble room of the user's availability (build 297): required by
  /// `createAvailability`; the key cannot read rooms, so it is typed in.
  final String? roomId;

  /// Surname as Semble writes it in `doctorName` (build 288): picks the
  /// user's bookings, since the key cannot read the clinician's id.
  final String? doctorName;

  /// "…a1b2" or null; the key itself never returns to the UI.
  final String? maskedKey;
  final String? userId;

  /// Whether the Calendar draws the layer.
  final bool enabled;

  bool get ready => maskedKey != null && userId != null;
}

/// Key and Semble user id in the Android Keystore, like the assistant key:
/// never in SQLite, backups, logs or Supabase.
class SembleSettings {
  SembleSettings({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _apiKey = 'semble_api_key';
  static const _userId = 'semble_user_id';
  static const _enabled = 'semble_layer_enabled';
  static const _doctorName = 'semble_doctor_name';
  static const _roomId = 'semble_room_id';

  final FlutterSecureStorage _storage;

  static String mask(String key) =>
      key.length <= 4 ? '…' : '…${key.substring(key.length - 4)}';

  Future<SembleConfig> read() async {
    final key = await _storage.read(key: _apiKey);
    final user = await _storage.read(key: _userId);
    return SembleConfig(
      maskedKey: key == null || key.isEmpty ? null : mask(key),
      userId: user == null || user.isEmpty ? null : user,
      enabled: await _storage.read(key: _enabled) != 'false',
      doctorName: switch (await _storage.read(key: _doctorName)) {
        final name? when name.trim().isNotEmpty => name.trim(),
        _ => null,
      },
      roomId: switch (await _storage.read(key: _roomId)) {
        final room? when room.trim().isNotEmpty => room.trim(),
        _ => null,
      },
    );
  }

  Future<String?> apiKey() => _storage.read(key: _apiKey);

  Future<void> save({
    String? key,
    required String userId,
    String? doctorName,
    String? roomId,
  }) async {
    final trimmedUser = userId.trim();
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(trimmedUser)) {
      throw const FormatException('User ID non valido');
    }
    if (key != null) {
      final trimmed = key.trim();
      if (trimmed.isEmpty) throw const FormatException('Chiave vuota');
      await _storage.write(key: _apiKey, value: trimmed);
    }
    await _storage.write(key: _userId, value: trimmedUser);
    if (doctorName != null) {
      await _storage.write(key: _doctorName, value: doctorName.trim());
    }
    if (roomId != null) {
      final room = roomId.trim();
      if (room.isNotEmpty && !RegExp(r'^[A-Za-z0-9]+$').hasMatch(room)) {
        throw const FormatException('ID stanza non valido');
      }
      await _storage.write(key: _roomId, value: room);
    }
  }

  Future<void> setEnabled(bool enabled) =>
      _storage.write(key: _enabled, value: '$enabled');

  Future<void> clear() async {
    await _storage.delete(key: _apiKey);
    await _storage.delete(key: _userId);
    await _storage.delete(key: _enabled);
    await _storage.delete(key: _doctorName);
    await _storage.delete(key: _roomId);
  }
}

/// Semble client. Reads, plus one explicit write the user confirms: an
/// unavailability block and its undo (build 297). Errors are classified,
/// never logged: the key travels in the headers.
class SembleClient {
  SembleClient({http.Client? client})
    : _client = client; // ignore: prefer_initializing_formals

  static const timeout = Duration(seconds: 15);
  static const pageSize = 50;
  static const maxPages = 10;

  final http.Client? _client;

  Future<void> check(String key) async {
    await _post(key, sembleCheckQuery, const {});
  }

  /// Rules touching [first]…[last] (inclusive). Recurring rules come with
  /// their own start date, often before [first].
  Future<List<SembleRule>> rules({
    required String key,
    required String userId,
    required CivilDate first,
    required CivilDate last,
  }) async {
    try {
      return await _rules(key, userId, first, last, exclusions: true);
    } on _SchemaMismatch {
      // `exclusions` may be an object type in this schema: read without it.
      return _rules(key, userId, first, last, exclusions: false);
    }
  }

  /// The user's bookings from [first] to [last] inclusive. [doctorName]
  /// null keeps every booking (matching then relies on time and type).
  Future<List<SembleBooking>> bookings({
    required String key,
    required CivilDate first,
    required CivilDate last,
    String? doctorName,
    int pageSize = 100,
    int maxPages = 20,
  }) async {
    final bookings = <SembleBooking>[];
    for (var page = 1; page <= maxPages; page++) {
      final data = await _post(
        key,
        sembleBookingsQuery(
          first: first,
          end: last.addDays(1),
          page: page,
          pageSize: pageSize,
        ),
        const {},
      );
      final (list, hasMore) = switch (data['bookings']) {
        {'data': final List<Object?> list, 'pageInfo': final Object? info} => (
          list,
          info is Map<String, Object?> && info['hasMore'] == true,
        ),
        {'data': final List<Object?> list} => (list, false),
        _ => throw const SembleException(SembleFailure.badResponse),
      };
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final booking = SembleBooking.fromJson(item);
        if (booking != null && sembleBookingIsMine(booking, doctorName)) {
          bookings.add(booking);
        }
      }
      if (!hasMore || list.isEmpty) break;
    }
    return bookings;
  }

  Future<List<SembleRule>> _rules(
    String key,
    String userId,
    CivilDate first,
    CivilDate last, {
    required bool exclusions,
  }) async {
    final rules = <SembleRule>[];
    for (var page = 1; page <= maxPages; page++) {
      final data = await _post(key, sembleRulesQuery(exclusions: exclusions), {
        'userIds': [userId],
        // Semble requires end after start; the end day is included.
        'range': {'start': '$first', 'end': '${last.addDays(1)}'},
        'page': {'page': page, 'pageSize': pageSize},
      });
      final list = switch (data['availabilityRules']) {
        {'data': final List<Object?> list} => list,
        _ => throw const SembleException(SembleFailure.badResponse),
      };
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final rule = SembleRule.fromJson(item);
        if (rule != null) rules.add(rule);
      }
      if (list.length < pageSize) break;
    }
    return rules;
  }

  /// Creates a one-day unavailability from [start] to [end] (phone time,
  /// converted to London wall clock as Semble wants) and returns its id.
  /// For one day Semble wants no `endDate`: it rejects one without a
  /// recurrence (tested on 23 October 2026).
  Future<String> createUnavailability({
    required String key,
    required String userId,
    required String roomId,
    required DateTime start,
    required DateTime end,
    SembleBlockType type = SembleBlockType.other,
    String? comment,
  }) async {
    final block = sembleBlockFor(start, end);
    if (block == null) throw const FormatException('Orario non valido');
    final data = await _post(key, sembleCreateBlockMutation, {
      'data': {
        'unavailability': true,
        'room': roomId,
        'user': userId,
        'startDate': '${block.date}',
        'startTime': block.startTime,
        'endTime': block.endTime,
        'unavailabilityType': type.name,
        // No comment unless asked (build 300: the user wants none).
        'comment': ?comment,
      },
    });
    final id = switch (data['createAvailability']) {
      {'data': {'id': final String id}} => id,
      _ => null,
    };
    if (id == null) throw const SembleException(SembleFailure.badResponse);
    return id;
  }

  /// Removes the block [id] this app has just created (the undo).
  Future<void> deleteUnavailability({
    required String key,
    required String id,
  }) async {
    await _post(key, sembleDeleteBlockMutation, {'id': id});
  }

  Future<Map<String, Object?>> _post(
    String key,
    String query,
    Map<String, Object?> variables,
  ) async {
    final client = _client ?? http.Client();
    final http.Response response;
    try {
      response = await client
          .post(
            Uri.parse(sembleEndpoint),
            headers: {'x-token': key, 'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(timeout);
    } on Object {
      throw const SembleException(SembleFailure.unreachable);
    } finally {
      if (_client == null) client.close();
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SembleException(SembleFailure.rejected);
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (body is! Map<String, Object?>) {
      throw SembleException(
        response.statusCode >= 500
            ? SembleFailure.unreachable
            : SembleFailure.badResponse,
      );
    }
    // GraphQL reports most failures with HTTP 200 and an `errors` list.
    if (body['errors'] case final List<Object?> errors when errors.isNotEmpty) {
      final codes = <String>{};
      var mentionsExclusions = false;
      for (final error in errors) {
        if (error is! Map<String, Object?>) continue;
        if (error['extensions'] case {'code': final String code}) {
          codes.add(code);
        }
        if ('${error['message']}'.contains('exclusions')) {
          mentionsExclusions = true;
        }
      }
      if (codes.contains('UNAUTHENTICATED')) {
        throw const SembleException(SembleFailure.rejected);
      }
      if (codes.contains('FORBIDDEN')) {
        throw const SembleException(SembleFailure.forbidden);
      }
      if (mentionsExclusions) throw const _SchemaMismatch();
      throw const SembleException(SembleFailure.badResponse);
    }
    if (response.statusCode != 200) {
      throw const SembleException(SembleFailure.unreachable);
    }
    return switch (body['data']) {
      final Map<String, Object?> data => data,
      _ => throw const SembleException(SembleFailure.badResponse),
    };
  }
}

final class _SchemaMismatch implements Exception {
  const _SchemaMismatch();
}

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
  Set<String> overlapsFor(
    CivilDate day,
    Iterable<AgendaEntry> entries, {
    DateTime Function() now = DateTime.now,
  }) {
    final bands = _bandsOf(day);
    if (bands.isEmpty) return const {};
    return sembleOverlaps(entries, day, bands, isVisit, now: now());
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

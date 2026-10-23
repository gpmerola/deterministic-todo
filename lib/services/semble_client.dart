import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/semble_availability.dart';
import '../domain/semble_bookings.dart';
import '../domain/task.dart';

/// Semble public API (GraphQL). The key authenticates with `x-token`.
const sembleEndpoint = 'https://open.semble.io/graphql';

/// Every operation this app may send to Semble, all defined in this file:
/// reads: [sembleCheckQuery] (token check), [sembleRulesQuery]
///   (availability rules) and [sembleBookingsQuery] (bookings, without
///   patient data);
/// writes, only on the user's tap: [sembleCreateBlockMutation] (an
///   unavailability of type Other, build 297/300) and
///   [sembleDeleteBlockMutation] (its Annulla).
/// No `room` selection (forbidden for this key, `settingsGeneral`) and no
/// comments: they may name patients.
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

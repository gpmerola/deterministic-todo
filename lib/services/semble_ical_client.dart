import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/semble_bookings.dart';
import '../domain/semble_ical.dart';

export '../domain/semble_ical.dart' show sembleIcalUri;

enum SembleIcalFailure { invalid, rejected, unreachable, badResponse }

class SembleIcalException implements Exception {
  const SembleIcalException(this.failure);

  final SembleIcalFailure failure;

  String get message => switch (failure) {
    SembleIcalFailure.invalid =>
      'Link iCal non valido: deve iniziare con '
          'https:// o webcal://.',
    SembleIcalFailure.rejected => 'Semble non riconosce più il link iCal.',
    SembleIcalFailure.unreachable => 'Link iCal non raggiungibile.',
    SembleIcalFailure.badResponse => 'Il link non restituisce un calendario.',
  };

  @override
  String toString() => 'SembleIcalException($failure)';
}

/// Reads the user's Semble iCal feed (build 312): the fallback for
/// bookings when the API key is missing or refused. One GET, no key, no
/// writes; the link is never logged.
class SembleIcalClient {
  SembleIcalClient({http.Client? client, this.timeout = _timeout})
    : _client = client; // ignore: prefer_initializing_formals

  static const _timeout = Duration(seconds: 20);

  final http.Client? _client;
  final Duration timeout;

  Future<List<SembleBooking>> bookings({
    required String link,
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = sembleIcalUri(link);
    if (uri == null) {
      throw const SembleIcalException(SembleIcalFailure.invalid);
    }
    final client = _client ?? http.Client();
    final http.Response response;
    try {
      response = await client
          .get(uri, headers: const {'Accept': 'text/calendar'})
          .timeout(timeout);
    } on Object {
      throw const SembleIcalException(SembleIcalFailure.unreachable);
    } finally {
      if (_client == null) client.close();
    }
    if (const {401, 403, 404, 410}.contains(response.statusCode)) {
      throw const SembleIcalException(SembleIcalFailure.rejected);
    }
    if (response.statusCode != 200) {
      throw const SembleIcalException(SembleIcalFailure.unreachable);
    }
    // iCal is UTF-8 (RFC 5545) even when the server names no charset.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!body.toUpperCase().contains('BEGIN:VCALENDAR')) {
      throw const SembleIcalException(SembleIcalFailure.badResponse);
    }
    return parseSembleIcal(body, from: from, to: to);
  }
}

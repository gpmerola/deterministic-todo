/// Meeting and map links found in calendar events.
library;

import 'agenda.dart';

final class MeetingLink {
  const MeetingLink(this.provider, this.url);
  final String provider;
  final Uri url;
}

final _meetingPatterns = <(String, RegExp)>[
  ('Teams', RegExp(r'https://teams\.microsoft\.com/l/meetup-join/[^\s<>"]+')),
  ('Teams', RegExp(r'https://teams\.microsoft\.com/meet/[^\s<>"]+')),
  ('Teams', RegExp(r'https://teams\.live\.com/meet/[^\s<>"]+')),
  ('Zoom', RegExp(r'https://[\w.-]*zoom\.us/j/[^\s<>"]+')),
  ('Meet', RegExp(r'https://meet\.google\.com/[a-z]+-[a-z]+-[a-z]+')),
];

/// First online-meeting link in url, then location, then description.
MeetingLink? findMeetingLink(AgendaSourceEvent event) {
  for (final text in [event.url, event.location, event.description]) {
    if (text == null || text.isEmpty) continue;
    for (final (provider, pattern) in _meetingPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      // Outlook wraps links in <…> or ends them with punctuation.
      final raw = match.group(0)!.replaceFirst(RegExp(r'[>)\].,;]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri != null) return MeetingLink(provider, uri);
    }
  }
  return null;
}

/// Google Maps search for an event's place, or null when there is nothing
/// to find on a map: blank text, a link or an online meeting.
///
/// The https form opens the Google Maps app on Android and the site on the
/// web; the address is only sent when the user taps it.
Uri? agendaMapsUri(String? location) {
  final place = location?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  if (place.isEmpty) return null;
  if (RegExp(r'https?://|www\.', caseSensitive: false).hasMatch(place)) {
    return null;
  }
  if (RegExp(
    r'^(riunione di )?(microsoft teams|teams|zoom|google meet|meet)'
    r'( (meeting|riunione))?$',
    caseSensitive: false,
  ).hasMatch(place)) {
    return null;
  }
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': place,
  });
}

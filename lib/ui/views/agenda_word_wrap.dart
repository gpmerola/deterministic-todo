import 'package:flutter/material.dart';

/// Lines of [text] broken only between words. A word wider than the line
/// stays whole on its own line, to be ellipsized, instead of being split
/// across lines as Flutter does ("Mrcpscy / h paper", UI review build 218).
///
/// Results are memoised: measuring is most of the cost of building a dense
/// week (diagnostics of 13 October 2026), and the same titles come back on
/// every page change and for recurring meetings. Same inputs give the same
/// lines, so what is drawn does not change.
List<String> wrapWords(
  String text,
  TextStyle style,
  double maxWidth,
  TextScaler scaler,
) {
  final key = (text, style, maxWidth, scaler);
  final cached = _wrapCache.remove(key);
  if (cached != null) return _wrapCache[key] = cached;
  final lines = List<String>.unmodifiable(
    _measureWrap(text, style, maxWidth, scaler),
  );
  _wrapCache[key] = lines;
  if (_wrapCache.length > wrapCacheCapacity) {
    _wrapCache.remove(_wrapCache.keys.first);
  }
  _listenForFontChanges();
  return lines;
}

/// Enough for a few dense weeks; least recently used entries go first.
@visibleForTesting
const wrapCacheCapacity = 1024;

/// Insertion-ordered (a Dart map literal), so the first key is the oldest.
final _wrapCache = <(String, TextStyle, double, TextScaler), List<String>>{};

var _fontListener = false;

/// Widths change when system fonts are (re)loaded.
void _listenForFontChanges() {
  if (_fontListener) return;
  _fontListener = true;
  PaintingBinding.instance.systemFonts.addListener(clearWrapWordsCache);
}

@visibleForTesting
int get wrapCacheLength => _wrapCache.length;

void clearWrapWordsCache() => _wrapCache.clear();

List<String> _measureWrap(
  String text,
  TextStyle style,
  double maxWidth,
  TextScaler scaler,
) {
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  );
  double widthOf(String value) {
    painter
      ..text = TextSpan(text: value, style: style)
      ..layout();
    return painter.width;
  }

  final lines = <String>[];
  var current = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final candidate = current.isEmpty ? word : '$current $word';
    if (current.isEmpty || widthOf(candidate) <= maxWidth) {
      current = candidate;
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  painter.dispose();
  return lines;
}

/// [text] in as many whole-word lines as fit the box; a too-long word ends
/// with "…".
class AgendaWordWrap extends StatelessWidget {
  const AgendaWordWrap(this.text, {required this.style, super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final lines = wrapWords(text, style, constraints.maxWidth, scaler);
      return ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              Text(
                line,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
          ],
        ),
      );
    },
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/agenda.dart';
import 'agenda_colors.dart';
import 'agenda_month_view.dart' show compactTime;
import 'agenda_word_wrap.dart';

/// A timed event of the week and three-day grids, painted by one
/// [CustomPaint] instead of a Material, InkWell and two LayoutBuilders per
/// event: a dense week builds 84 of them on every page change (build 268,
/// measurements in docs/diagnostics/2026-10-13-calendar-week-build.md).
/// Layout and colours are those of the widget version: start time when the
/// block is at least 30 high, the whole span when at least 90 wide, title in
/// whole words with "…" on a word wider than the line.
class AgendaWeekEventBlock extends StatelessWidget {
  const AgendaWeekEventBlock({
    required this.entry,
    required this.color,
    required this.onOpen,
    this.onLongPress,
    this.clash = false,
    super.key,
  });

  final AgendaEntry entry;
  final Color color;
  final bool clash;
  final Future<void> Function(AgendaEntry entry) onOpen;
  final Future<void> Function(AgendaEntry entry)? onLongPress;

  static String titleOf(AgendaEntry entry) =>
      entry.title.isEmpty ? '(senza titolo)' : entry.title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = agendaEventFill(color, scheme);
    // Unanswered invitations: outlined, not filled, like Google Calendar.
    final outlined = entry.unanswered;
    final title = titleOf(entry);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(onOpen(entry)),
      onLongPress: onLongPress == null
          ? null
          : () => unawaited(onLongPress!(entry)),
      child: Semantics(
        button: true,
        label: '${compactTime(entry.start)}–${compactTime(entry.end)}, $title',
        child: CustomPaint(
          size: Size.infinite,
          painter: AgendaWeekBlockPainter(
            start: entry.start,
            end: entry.end,
            title: title,
            background: outlined ? scheme.surface : fill,
            // Overlapping another timed event: outlined in the error colour.
            border: clash
                ? BorderSide(color: scheme.error, width: 1.5)
                : outlined
                ? BorderSide(color: fill, width: 1.5)
                : BorderSide(
                    color: agendaAccentText(color, scheme),
                    width: 0.8,
                  ),
            textColor: outlined ? scheme.onSurface : agendaOnFill(fill),
            baseStyle: DefaultTextStyle.of(context).style,
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

/// Paints one event block. Text is laid out once per size and reused for
/// repaints.
class AgendaWeekBlockPainter extends CustomPainter {
  AgendaWeekBlockPainter({
    required this.start,
    required this.end,
    required this.title,
    required this.background,
    required this.border,
    required this.textColor,
    required this.baseStyle,
    required this.textScaler,
    required this.textDirection,
  });

  final DateTime start, end;
  final String title;
  final Color background, textColor;
  final BorderSide border;
  final TextStyle baseStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;

  static const _padding = EdgeInsets.fromLTRB(2, 1, 1, 0);
  static const _radius = Radius.circular(3);

  Size? _laidOutFor;
  TextPainter? _time;

  /// Start times repeat across days and weeks: laid out once per text and
  /// style, shared by every block, never disposed.
  static final _times =
      <(String, TextStyle, TextScaler, TextDirection), TextPainter>{};
  final _lines = <_TitleLine>[];

  void _layout(Size size) {
    if (_laidOutFor == size) return;
    _dispose();
    _laidOutFor = size;
    final width = math.max(0.0, size.width - _padding.horizontal);
    final height = size.height - _padding.vertical;
    final wide = width >= 90;
    final style = baseStyle.merge(
      TextStyle(color: textColor, fontSize: wide ? 11 : 9.5, height: 1.15),
    );
    if (height >= 30) {
      // Clipped, not ellipsized: the time is never shortened to "1…".
      final text = wide
          ? '${compactTime(start)}–${compactTime(end)}'
          : compactTime(start);
      final timeStyle = style.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: wide ? 10.5 : 9,
      );
      if (_times.length > 512) _times.clear();
      _time = _times[(text, timeStyle, textScaler, textDirection)] ??=
          TextPainter(
            text: TextSpan(text: text, style: timeStyle),
            maxLines: 1,
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout();
    }
    final titleStyle = style.copyWith(fontWeight: FontWeight.w600);
    if (_singleRun(titleStyle, width)) return;
    for (final line in wrapWords(title, titleStyle, width, textScaler)) {
      _lines.add((
        painter: TextPainter(
          text: TextSpan(text: line, style: titleStyle),
          maxLines: 1,
          ellipsis: '…',
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: width),
        from: 0,
        clipLeft: double.negativeInfinity,
        clipRight: double.infinity,
        ellipsis: null,
      ));
    }
  }

  static final _irregular = RegExp(
    r'\s\s|[^ \S]|^\s|\s$|[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]',
  );
  static final _word = RegExp(r'\S+');

  /// The same whole-word lines as [wrapWords], cut from one single-line
  /// layout of the title: the edges of each word give every candidate
  /// width, instead of one text layout per candidate and one per line.
  /// Left to [wrapWords] for right-to-left text and unusual spacing.
  bool _singleRun(TextStyle style, double width) {
    if (textDirection != TextDirection.ltr || _irregular.hasMatch(title)) {
      return false;
    }
    final run = TextPainter(
      text: TextSpan(text: title, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final words = [
      for (final match in _word.allMatches(title))
        (start: match.start, end: match.end),
    ];
    final left = <double>[], right = <double>[];
    for (final word in words) {
      final boxes = run.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      );
      if (boxes.isEmpty) {
        run.dispose();
        return false;
      }
      left.add(boxes.first.left);
      right.add(boxes.last.right);
    }
    void line(int first, int last) {
      final from = left[first];
      var clipRight = last == words.length - 1
          ? double.infinity
          : left[last + 1];
      ({TextPainter painter, double at})? cut;
      if (right[last] - from > width) {
        // A single word wider than the line: as much as fits, then "…".
        final ellipsis = _ellipsis(style);
        final limit = from + width - ellipsis.width;
        final word = words[last];
        var k = run
            .getPositionForOffset(Offset(limit, run.height / 2))
            .offset
            .clamp(word.start, word.end);
        double edge(int k) => k <= word.start
            ? from
            : run
                  .getBoxesForSelection(
                    TextSelection(baseOffset: word.start, extentOffset: k),
                  )
                  .last
                  .right;
        while (k > word.start &&
            (edge(k) > limit || _isLowSurrogate(title.codeUnitAt(k - 1)))) {
          k--;
        }
        clipRight = edge(k);
        cut = (painter: ellipsis, at: clipRight - from);
      }
      _lines.add((
        painter: run,
        from: from,
        clipLeft: first == 0 ? double.negativeInfinity : from,
        clipRight: clipRight,
        ellipsis: cut,
      ));
    }

    var first = 0;
    for (var i = 1; i < words.length; i++) {
      if (right[i] - left[first] > width) {
        line(first, i - 1);
        first = i;
      }
    }
    if (words.isNotEmpty) {
      line(first, words.length - 1);
    } else {
      run.dispose();
    }
    return true;
  }

  /// "…" laid out once per style: shared by every block, never disposed.
  static final _ellipses = <(TextStyle, TextScaler), TextPainter>{};
  TextPainter _ellipsis(TextStyle style) {
    // A handful of styles in practice; the bound only guards misuse.
    if (_ellipses.length > 32) _ellipses.clear();
    return _ellipses[(style, textScaler)] ??= TextPainter(
      text: TextSpan(text: '…', style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// The visible text of each line, for tests.
  @visibleForTesting
  List<String> debugText(Size size) {
    _layout(size);
    String text(_TitleLine line) {
      final painter = line.painter;
      final plain = painter.plainText;
      if (line.clipLeft.isInfinite && line.clipRight.isInfinite) {
        return painter.didExceedMaxLines ? '$plain…' : plain;
      }
      int at(double dx) =>
          painter.getPositionForOffset(Offset(dx, painter.height / 2)).offset;
      final left = line.clipLeft.isInfinite ? 0 : at(line.from);
      final right = line.clipRight.isInfinite
          ? plain.length
          : at(line.clipRight);
      return plain.substring(left, right).trim() +
          (line.ellipsis == null ? '' : '…');
    }

    return [
      if (_time case final time?) time.plainText,
      for (final line in _lines) text(line),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _layout(size);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, _radius);
    canvas.drawRRect(outer, Paint()..color = background);
    canvas.save();
    canvas.clipRRect(outer);
    final content = _padding.deflateRect(Offset.zero & size);
    canvas.clipRect(content);
    var y = content.top;
    if (_time case final time?) {
      time.paint(canvas, Offset(content.left, y));
      y += time.height;
    }
    for (final line in _lines) {
      if (y >= content.bottom) break;
      final painter = line.painter;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          line.clipLeft.isFinite ? content.left + line.clipLeft - line.from : 0,
          y,
          line.clipRight.isFinite
              ? content.left + line.clipRight - line.from
              : size.width,
          y + painter.height,
        ),
      );
      painter.paint(canvas, Offset(content.left - line.from, y));
      canvas.restore();
      if (line.ellipsis case final cut?) {
        cut.painter.paint(canvas, Offset(content.left + cut.at, y));
      }
      y += painter.height;
    }
    canvas.restore();
    // Border inside the shape, as a Material's RoundedRectangleBorder side.
    canvas.drawRRect(
      outer.deflate(border.width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = border.width
        ..color = border.color,
    );
  }

  void _dispose() {
    _time = null;
    // Lines of one title share its layout; times and ellipses are shared
    // by every block.
    final owned = <TextPainter>{for (final line in _lines) line.painter};
    for (final painter in owned) {
      painter.dispose();
    }
    _lines.clear();
  }

  @override
  bool shouldRepaint(AgendaWeekBlockPainter old) =>
      old.start != start ||
      old.end != end ||
      old.title != title ||
      old.background != background ||
      old.border != border ||
      old.textColor != textColor ||
      old.baseStyle != baseStyle ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection;
}

/// Folded night hours and hour lines of one day column, painted together
/// instead of one positioned widget per line.
class AgendaWeekGridPainter extends CustomPainter {
  AgendaWeekGridPainter({
    required this.scale,
    required this.line,
    required this.folded,
  });

  final TimelineScale scale;
  final Color line, folded;

  @override
  void paint(Canvas canvas, Size size) {
    final fold = Paint()..color = folded;
    for (var hour = 0; hour < 24; hour++) {
      if (scale.isFolded(hour)) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            scale.y(hour * 60),
            size.width,
            scale.hourHeights[hour],
          ),
          fold,
        );
      }
    }
    final stroke = Paint()..color = line;
    for (var hour = 1; hour < 24; hour++) {
      canvas.drawRect(
        Rect.fromLTWH(0, scale.y(hour * 60), size.width, 0.5),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(AgendaWeekGridPainter old) =>
      old.line != line ||
      old.folded != folded ||
      !_sameHeights(old.scale.hourHeights, scale.hourHeights);

  static bool _sameHeights(List<double> a, List<double> b) {
    for (var i = 0; i < 24; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A title line: [painter] shifted left by [from] and clipped to
/// [clipLeft]–[clipRight] in its own coordinates, then [ellipsis] when a
/// word was cut. Infinite clips leave that side to the block.
typedef _TitleLine = ({
  TextPainter painter,
  double from,
  double clipLeft,
  double clipRight,
  ({TextPainter painter, double at})? ellipsis,
});

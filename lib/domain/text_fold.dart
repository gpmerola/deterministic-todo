/// Accent-insensitive matching for search: "attivita" finds "attività".
/// Covers Latin letters with the accents used in Italian, French, Spanish,
/// Portuguese and German; other characters are left as they are.
const accentFolds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y', //
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A', //
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', //
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', //
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O', //
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', //
  'Ç': 'C', 'Ñ': 'N', 'Ý': 'Y',
};

/// [text] without accents, case kept.
String foldAccents(String text) {
  if (text.codeUnits.every((unit) => unit < 0xC0)) return text;
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    buffer.write(accentFolds[char] ?? char);
  }
  return buffer.toString();
}

/// Lower case and without accents: the form both sides of a match use.
String foldForSearch(String text) => foldAccents(text).toLowerCase();

/// SQL expression folding accents of [column] with nested `replace`, so the
/// same query works on native SQLite and on the Web build without custom
/// functions. `LIKE` then folds ASCII case.
String sqlFoldAccents(String column) {
  var expression = column;
  for (final entry in accentFolds.entries) {
    expression = "replace($expression, '${entry.key}', '${entry.value}')";
  }
  return expression;
}

/// `LIKE` pattern (without the surrounding `%`) that narrows a search for
/// the folded [needle] in a database that cannot fold accents: letters that
/// have accented forms match any one character (`_`), wildcards in the text
/// stay literal. A superset; the caller confirms with [foldForSearch].
String likePrefilter(String needle) {
  final buffer = StringBuffer();
  for (final char in needle.split('')) {
    if ('aeiouycn'.contains(char)) {
      buffer.write('_');
    } else if (char == '%' || char == '_' || char == r'\') {
      buffer.write('\\$char');
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

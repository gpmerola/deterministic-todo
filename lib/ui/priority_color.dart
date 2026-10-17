import 'package:flutter/material.dart';

/// Raw priority 4 is P1 (highest), 1 is "no priority".
Color priorityColor(int rawPriority) => switch (rawPriority) {
  4 => Colors.red,
  3 => Colors.orange,
  2 => Colors.blue,
  _ => Colors.grey,
};

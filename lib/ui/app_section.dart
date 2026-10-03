import 'package:flutter/material.dart';

/// Top-level destinations of the shell. Inbox items live in Today.
enum AppSection { today, upcoming, projects, completed, settings }

extension AppSectionPresentation on AppSection {
  String get label => switch (this) {
    AppSection.today => 'Oggi',
    AppSection.upcoming => 'Prossime',
    AppSection.projects => 'Progetti',
    AppSection.completed => 'Completate',
    AppSection.settings => 'Impostazioni',
  };

  IconData get icon => switch (this) {
    AppSection.today => Icons.today_outlined,
    AppSection.upcoming => Icons.event_outlined,
    AppSection.projects => Icons.folder_outlined,
    AppSection.completed => Icons.check_circle_outline,
    AppSection.settings => Icons.settings_outlined,
  };
}

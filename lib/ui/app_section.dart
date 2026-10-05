import 'package:flutter/material.dart';

/// Top-level destinations of the shell. Inbox items live in Today.
enum AppSection { today, upcoming, projects, agenda, completed, settings }

extension AppSectionPresentation on AppSection {
  String get label => switch (this) {
    AppSection.today => 'Oggi',
    AppSection.upcoming => 'Prossime',
    AppSection.projects => 'Progetti',
    AppSection.agenda => 'Agenda',
    AppSection.completed => 'Completate',
    AppSection.settings => 'Impostazioni',
  };

  /// Distinct shapes: three calendar icons (Today, Upcoming, Agenda) were
  /// hard to tell apart without labels (UI review, build 218).
  IconData get icon => switch (this) {
    AppSection.today => Icons.wb_sunny_outlined,
    AppSection.upcoming => Icons.upcoming_outlined,
    AppSection.projects => Icons.folder_outlined,
    AppSection.agenda => Icons.calendar_month_outlined,
    AppSection.completed => Icons.check_circle_outline,
    AppSection.settings => Icons.settings_outlined,
  };
}

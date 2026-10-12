import '../app_section.dart';

/// In-memory navigation only. Editor persistence stays in the shell and must
/// finish before calling these transitions.
class ShellNavigation {
  AppSection section = AppSection.today;
  final List<AppSection> _history = [];
  String? selectedProjectId;
  String? selectedUpcomingDate;
  int upcomingDays = 30;
  int upcomingVisit = 0;

  bool get canExit => section == AppSection.today && _history.isEmpty;

  void navigateTo(AppSection destination) {
    if (destination == section) return;
    _history.add(section);
    if (_history.length > 20) _history.removeAt(0);
    _enter(destination);
  }

  void back() {
    if (section == AppSection.projects && selectedProjectId != null) {
      selectedProjectId = null;
    } else {
      _enter(_history.isEmpty ? AppSection.today : _history.removeLast());
    }
  }

  void selectUpcomingDate(String date) {
    selectedUpcomingDate = date;
    upcomingDays = 30;
    upcomingVisit++;
  }

  void _enter(AppSection destination) {
    section = destination;
    if (destination == AppSection.upcoming) {
      upcomingVisit++;
      upcomingDays = 30;
    }
  }
}

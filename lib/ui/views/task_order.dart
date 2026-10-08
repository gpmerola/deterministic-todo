import '../../data/local/database.dart';

/// Presentation order inside a view. Membership is decided by SQL
/// (`TaskRepository.watchView`); these functions never filter.
///
/// Higher priority first, then today's items, then manual position,
/// creation time and id as deterministic tie-breakers.
int compareByPriority(Task a, Task b, String today) {
  final byPriority = b.priority.compareTo(a.priority);
  return byPriority != 0 ? byPriority : compareStable(a, b, today);
}

/// Upcoming is grouped by day: date first, then [compareByPriority].
int compareByDateThenPriority(Task a, Task b, String today) {
  final byDate = (a.showDate ?? '').compareTo(b.showDate ?? '');
  return byDate != 0 ? byDate : compareByPriority(a, b, today);
}

int compareStable(Task a, Task b, String today) {
  int group(Task task) => task.showDate == today ? 0 : 1;
  final byGroup = group(a).compareTo(group(b));
  if (byGroup != 0) return byGroup;
  final byPosition = a.position.compareTo(b.position);
  if (byPosition != 0) return byPosition;
  final byCreation = a.createdAt.compareTo(b.createdAt);
  return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
}

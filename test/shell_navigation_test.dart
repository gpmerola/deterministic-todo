import 'package:deterministic_todo/ui/app_section.dart';
import 'package:deterministic_todo/ui/shell/shell_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('back leaves project before consuming section history', () {
    final navigation = ShellNavigation();
    expect(navigation.canExit, isTrue);
    navigation.navigateTo(AppSection.projects);
    navigation.selectedProjectId = 'synthetic-project';
    navigation.navigateTo(AppSection.settings);
    navigation.back();
    expect(navigation.section, AppSection.projects);
    expect(navigation.selectedProjectId, 'synthetic-project');
    navigation.back();
    expect(navigation.selectedProjectId, isNull);
    expect(navigation.section, AppSection.projects);
    navigation.back();
    expect(navigation.canExit, isTrue);
  });

  test(
    'reentering upcoming resets window and scroll identity but keeps date',
    () {
      final navigation = ShellNavigation();
      navigation.navigateTo(AppSection.upcoming);
      navigation.selectUpcomingDate('2026-11-10');
      navigation.upcomingDays = 90;
      final visit = navigation.upcomingVisit;
      navigation.navigateTo(AppSection.upcoming);
      expect(navigation.upcomingDays, 90);
      expect(navigation.upcomingVisit, visit);
      navigation.navigateTo(AppSection.settings);
      navigation.back();
      expect(navigation.upcomingDays, 30);
      expect(navigation.upcomingVisit, visit + 1);
      expect(navigation.selectedUpcomingDate, '2026-11-10');
    },
  );

  test('history remains bounded and eventually returns to today', () {
    final navigation = ShellNavigation();
    for (var i = 0; i < 50; i++) {
      navigation.navigateTo(
        i.isEven ? AppSection.projects : AppSection.settings,
      );
    }
    for (var i = 0; i < 21; i++) {
      navigation.back();
    }
    expect(navigation.canExit, isTrue);
  });
}

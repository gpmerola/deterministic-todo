part of '../../main.dart';

/// Scaffold of the shell: navigation, shortcuts, desktop split and FAB.
extension _ShellLayout on _TaskShellState {
  Widget _buildShell(BuildContext context) => PopScope(
    canPop: _canExitFromBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
      },
      child: Actions(
        actions: {
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              _handleBack();
              return null;
            },
          ),
        },
        child: StreamBuilder<List<Task>>(
          stream: _visibleTasks(),
          builder: (context, snapshot) {
            // StreamBuilder retains the previous stream's data while switching.
            // A new view must not render rows from the old query (Inbox has no dates).
            final loaded =
                snapshot.connectionState == ConnectionState.active ||
                snapshot.connectionState == ConnectionState.done;
            final tasks = loaded
                ? snapshot.data ?? const <Task>[]
                : const <Task>[];
            final primarySections = [
              AppSection.today,
              AppSection.upcoming,
              AppSection.projects,
              if (_agendaAvailable) AppSection.agenda,
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                final pageIdentity =
                    '${navigation.section.name}:'
                    '${navigation.section == AppSection.projects ? navigation.selectedProjectId ?? 'root' : ''}';
                final selectedDesktopTask = desktop
                    ? tasks
                          .where((task) => task.id == selectedDesktopTaskId)
                          .firstOrNull
                    : null;
                final content = Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: desktop ? 1180 : 720,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            key: const ValueKey('page-motion'),
                            duration: _pageMotion,
                            reverseDuration: _pageMotionOut,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.012, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: KeyedSubtree(
                              key: ValueKey('page-$pageIdentity'),
                              child: _content(
                                tasks,
                                loaded: loaded && snapshot.hasData,
                              ),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: _pageMotion,
                          reverseDuration: _pageMotionOut,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.centerRight,
                          child: selectedDesktopTask == null
                              ? const SizedBox.shrink()
                              : SizedBox(
                                  width: 331,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const VerticalDivider(width: 1),
                                      Expanded(
                                        child: ClipRect(
                                          child: _desktopItemDetails(
                                            selectedDesktopTask,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
                return Scaffold(
                  // Agenda gives its whole height to the days; search and
                  // settings move into its own header menu.
                  appBar: navigation.section == AppSection.agenda
                      ? null
                      : AppBar(
                          leadingWidth: desktop ? 80 : null,
                          leading:
                              desktop &&
                                  navigation.section != AppSection.settings &&
                                  navigation.section != AppSection.completed
                              ? const SizedBox.shrink()
                              : navigation.section == AppSection.settings ||
                                    navigation.section == AppSection.completed
                              ? IconButton(
                                  tooltip: 'Indietro',
                                  onPressed: _handleBack,
                                  icon: const Icon(Icons.arrow_back),
                                )
                              : null,
                          title: AnimatedSwitcher(
                            key: const ValueKey('appbar-title-motion'),
                            duration: _microMotion,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: Text(
                              navigation.section.label,
                              key: ValueKey(
                                'appbar-title-${navigation.section.name}',
                              ),
                            ),
                          ),
                          actions: [
                            // Steps only in Today: five actions cut the
                            // title elsewhere ("Prossi…", build 217).
                            if (widget.enablePlatformServices &&
                                isAndroidPlatform &&
                                navigation.section == AppSection.today)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: ListenableBuilder(
                                  listenable: steps,
                                  builder: (context, _) =>
                                      DailyStepGoalIndicator(
                                        key: const ValueKey('daily-step-goal'),
                                        steps: steps.progress?.steps ?? 0,
                                        goal: steps.goal,
                                        onTap: _showDailySteps,
                                      ),
                                ),
                              ),
                            if (widget.syncService != null)
                              SyncStatusAction(
                                service: widget.syncService!,
                                repository: widget.repository,
                              ),
                            if (navigation.section != AppSection.settings) ...[
                              if (widget.enablePlatformServices &&
                                  isAndroidPlatform)
                                IconButton(
                                  key: const ValueKey('ai-capture-open'),
                                  tooltip: 'Assistente: scrivi o detta',
                                  onPressed: _openAiCapture,
                                  icon: const Icon(Icons.auto_awesome),
                                ),
                              IconButton(
                                tooltip: 'Comando universale',
                                onPressed: _showUniversalCommand,
                                icon: const Icon(Icons.search_rounded),
                              ),
                              IconButton(
                                tooltip: 'Impostazioni',
                                onPressed: () =>
                                    _navigateTo(AppSection.settings),
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ],
                          ],
                        ),
                  body: desktop
                      ? Row(
                          children: [
                            NavigationRail(
                              selectedIndex:
                                  primarySections.contains(navigation.section)
                                  ? primarySections.indexOf(navigation.section)
                                  : null,
                              onDestinationSelected: (index) =>
                                  _navigateTo(primarySections[index]),
                              labelType: NavigationRailLabelType.all,
                              leading: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: IconButton.filled(
                                  tooltip: 'Nuova attività',
                                  onPressed: _showQuickAddSheet,
                                  icon: const Icon(Icons.add),
                                ),
                              ),
                              destinations: [
                                for (final item in primarySections)
                                  NavigationRailDestination(
                                    icon: Icon(item.icon),
                                    label: Text(item.label),
                                  ),
                              ],
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                  floatingActionButton:
                      !desktop &&
                          navigation.section != AppSection.settings &&
                          navigation.section != AppSection.projects &&
                          navigation.section != AppSection.agenda &&
                          navigation.section != AppSection.completed
                      ? FloatingActionButton(
                          tooltip: 'Nuova attività',
                          onPressed: _showQuickAddSheet,
                          child: const Icon(Icons.add),
                        )
                      : null,
                  bottomNavigationBar:
                      desktop ||
                          navigation.section == AppSection.settings ||
                          navigation.section == AppSection.completed
                      ? null
                      : Center(
                          heightFactor: 1,
                          child: SizedBox(
                            width: 720,
                            // Same bar in every section (it was lower and
                            // without labels in Agenda until build 217).
                            child: NavigationBar(
                              height: 64,
                              labelBehavior:
                                  NavigationDestinationLabelBehavior.alwaysShow,
                              selectedIndex: primarySections
                                  .indexOf(navigation.section)
                                  .clamp(0, primarySections.length - 1),
                              onDestinationSelected: (index) =>
                                  _navigateTo(primarySections[index]),
                              destinations: [
                                for (final item in primarySections)
                                  NavigationDestination(
                                    icon: Icon(item.icon),
                                    label: item.label,
                                  ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

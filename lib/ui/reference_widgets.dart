part of '../main.dart';

class ReferenceTile extends StatelessWidget {
  const ReferenceTile({
    required this.item,
    required this.repository,
    this.onSelected,
    super.key,
  });

  final Task item;
  final TaskRepository repository;
  final VoidCallback? onSelected;

  Future<void> _openEditor(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 45),
      reverseDuration: Duration(milliseconds: 25),
    ),
    builder: (_) => ReferenceEditor(item: item, repository: repository),
  );

  Future<void> _delete(BuildContext context) async {
    await repository.softDelete(item);
    if (!context.mounted) return;
    AppUndo.show(
      context,
      message: 'Riferimento nel cestino',
      undo: () => repository.restore(item),
    );
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('reference-${item.id}'),
    leading: const Icon(Icons.bookmark_outline),
    title: TodoistLinkText(item.title),
    subtitle: item.notes?.trim().isEmpty ?? true
        ? null
        : TodoistLinkText(
            item.notes!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: PopupMenuButton<String>(
      tooltip: 'Azioni riferimento',
      onSelected: (action) {
        if (action == 'edit') {
          _openEditor(context);
        } else if (action == 'delete') {
          _delete(context);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Modifica')),
        PopupMenuItem(value: 'delete', child: Text('Cestino')),
      ],
    ),
    onTap: onSelected ?? () => _openEditor(context),
  );
}

class ReferenceEditor extends StatefulWidget {
  const ReferenceEditor({
    required this.item,
    required this.repository,
    this.embedded = false,
    this.onDeleted,
    super.key,
  });

  final Task item;
  final TaskRepository repository;
  final bool embedded;
  final VoidCallback? onDeleted;

  @override
  State<ReferenceEditor> createState() => _ReferenceEditorState();
}

class _ReferenceEditorState extends State<ReferenceEditor> {
  late final LinkTextEditingController title =
      LinkTextEditingController.fromMarkdown(widget.item.title);
  late final LinkTextEditingController notes =
      LinkTextEditingController.fromMarkdown(widget.item.notes);
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.repository.updateDetails(
        widget.item,
        title: linkifyPlainUrls(title.toMarkdown()),
        notes: notes.text.trim().isEmpty
            ? null
            : linkifyPlainUrls(notes.toMarkdown().trim()),
        showDate: null,
        recurrence: null,
        priority: 1,
        projectId: null,
        sectionId: null,
        updateProject: true,
      );
      if (mounted && !widget.embedded) Navigator.pop(context);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _delete() async {
    await widget.repository.softDelete(widget.item);
    if (!mounted) return;
    AppUndo.show(
      context,
      message: 'Riferimento nel cestino',
      undo: () => widget.repository.restore(widget.item),
    );
    if (widget.embedded) {
      widget.onDeleted?.call();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 12,
    ),
    child: Column(
      mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('reference-editor-title'),
          controller: title,
          autofocus: !widget.embedded,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            hintText: 'Titolo',
            prefixIcon: Icon(Icons.bookmark_outline),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('reference-editor-notes'),
          controller: notes,
          minLines: 3,
          maxLines: widget.embedded ? 10 : 6,
          decoration: const InputDecoration(
            hintText: 'Testo o link',
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
        if (widget.embedded) const Spacer() else const SizedBox(height: 12),
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Cestino'),
            ),
            FilledButton.icon(
              key: const ValueKey('reference-editor-save'),
              onPressed: saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(saving ? 'Salvataggio' : 'Salva'),
            ),
          ],
        ),
      ],
    ),
  );
}

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../../domain/body_metrics.dart';
import '../../../domain/meal_plan.dart';
import 'meal_type_picker.dart';

/// Full-screen meal logger: pick the slot, add dishes (typed or picked
/// from recent foods), log them as one meal. Pops the [Meal], or null.
///
/// A page rather than a dialog: no blurred barrier to repaint while the
/// keyboard animates, and typing only rebuilds the parts that depend on
/// the text (suggestions and the total bar).
class LogMealPage extends StatefulWidget {
  const LogMealPage({super.key, required this.type, this.recent = const []});

  /// Initially selected meal slot.
  final String type;

  /// Recently logged dishes, newest first, offered for one-tap re-logging.
  final List<MealItem> recent;

  /// Distinct dishes from [log], newest day first (at most [limit]).
  static List<MealItem> recentItems(FoodLog log, {int limit = 30}) {
    final keys = log.days.keys.toList()..sort((a, b) => b.compareTo(a));
    final seen = <String>{};
    final items = <MealItem>[];
    for (final key in keys) {
      for (final entry in log.days[key]!.reversed) {
        for (final item in entry.meal.items) {
          if (seen.add(item.name.trim().toLowerCase())) items.add(item);
          if (items.length >= limit) return items;
        }
      }
    }
    return items;
  }

  @override
  State<LogMealPage> createState() => _LogMealPageState();
}

class _LogMealPageState extends State<LogMealPage> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _nameFocus = FocusNode();
  late final _form = Listenable.merge([_name, _kcal, _protein, _carbs, _fat]);

  late String _type = widget.type;
  final _items = <MealItem>[];
  bool _showMacros = false;

  @override
  void dispose() {
    for (final controller in [_name, _kcal, _protein, _carbs, _fat]) {
      controller.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  /// Optional grams: empty → 0, invalid → null.
  static double? _grams(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    final value = BodyMetrics.parseDecimal(text);
    return value == null || value < 0 || value > 1000 ? null : value;
  }

  /// The dish typed in the form, or null while incomplete / invalid.
  MealItem? get _draft {
    final name = _name.text.trim();
    final kcal = int.tryParse(_kcal.text.trim());
    final protein = _grams(_protein);
    final carbs = _grams(_carbs);
    final fat = _grams(_fat);
    if (name.isEmpty || kcal == null || kcal <= 0 || kcal > 10000) return null;
    if (protein == null || carbs == null || fat == null) return null;
    return MealItem(
      name: name,
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    );
  }

  bool get _formBlank => [
    _name,
    _kcal,
    _protein,
    _carbs,
    _fat,
  ].every((controller) => controller.text.trim().isEmpty);

  /// Everything that would be logged now: added dishes plus a complete
  /// dish still in the form (so a single dish needs no "Add" tap).
  List<MealItem> get _pending => [..._items, ?_draft];

  void _clearForm() {
    for (final controller in [_name, _kcal, _protein, _carbs, _fat]) {
      controller.clear();
    }
  }

  void _addDraft() {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _items.add(draft));
    _clearForm();
    _nameFocus.requestFocus();
  }

  /// Adds a recent dish. A complete dish still in the form is added
  /// first; a name typed only to search is cleared; anything else
  /// half-typed stays in the form.
  void _addRecent(MealItem item) {
    final draft = _draft;
    final searchOnly = [
      _kcal,
      _protein,
      _carbs,
      _fat,
    ].every((controller) => controller.text.trim().isEmpty);
    setState(() => _items.addAll([?draft, item]));
    if (draft != null || searchOnly) _clearForm();
  }

  /// A macro field holds something that is not a valid gram amount.
  bool get _macrosInvalid =>
      [_protein, _carbs, _fat].any((controller) => _grams(controller) == null);

  void _submit() {
    final items = _pending;
    // A half-filled form would be silently dropped — keep the user here.
    if (items.isEmpty || (!_formBlank && _draft == null)) return;
    Navigator.pop(context, Meal(label: _type, items: items));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: colors.mutedForeground);
    const grams = TextInputType.numberWithOptions(decimal: true);
    return FScaffold(
      resizeToAvoidBottomInset: true,
      header: FHeader.nested(
        title: const Text('Log a meal'),
        prefixes: [FHeaderAction.x(onPress: () => Navigator.pop(context))],
      ),
      footer: _TotalBar(
        listenable: _form,
        type: _type,
        pending: () => _pending,
        canSubmit: () => _pending.isNotEmpty && (_formBlank || _draft != null),
        onSubmit: _submit,
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          MealTypePicker(
            selected: _type,
            onChanged: (type) => setState(() => _type = type),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_items.isNotEmpty) ...[
            AppCard(
              child: Column(
                children: [
                  for (final (index, item) in _items.indexed) ...[
                    if (index > 0) const _RowDivider(),
                    _DishRow(
                      item: item,
                      onRemove: () => setState(() => _items.removeAt(index)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            _items.isEmpty ? 'What did you eat?' : 'Add another dish',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                flex: 3,
                child: FTextField(
                  key: const Key('log-meal-name'),
                  control: .managed(controller: _name),
                  focusNode: _nameFocus,
                  hint: 'Dish name',
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                ),
              ),
              Expanded(
                flex: 2,
                child: FTextField(
                  key: const Key('log-meal-kcal'),
                  control: .managed(controller: _kcal),
                  hint: 'kcal',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmit: (_) => _addDraft(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              FButton(
                key: const Key('log-meal-macros'),
                variant: .ghost,
                size: .sm,
                mainAxisSize: .min,
                onPress: () => setState(() => _showMacros = !_showMacros),
                suffix: Icon(
                  _showMacros
                      ? FLucideIcons.chevronUp
                      : FLucideIcons.chevronDown,
                ),
                child: const Text('Macros (optional)'),
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: _form,
                builder: (context, _) => FButton(
                  key: const Key('log-meal-add-item'),
                  variant: .outline,
                  size: .sm,
                  mainAxisSize: .min,
                  onPress: _draft == null ? null : _addDraft,
                  prefix: const Icon(FLucideIcons.plus),
                  child: const Text('Add dish'),
                ),
              ),
            ],
          ),
          // Stays open while a macro is invalid, so what blocks logging is
          // never hidden.
          if (_showMacros || _macrosInvalid) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              spacing: AppSpacing.sm,
              children: [
                for (final (controller, label) in [
                  (_protein, 'Protein g'),
                  (_carbs, 'Carbs g'),
                  (_fat, 'Fat g'),
                ])
                  Expanded(
                    child: FTextField(
                      control: .managed(
                        controller: controller,
                        onChange: (_) => setState(() {}),
                      ),
                      label: Text(label),
                      keyboardType: grams,
                    ),
                  ),
              ],
            ),
            if (_macrosInvalid) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Macros must be numbers between 0 and 1000 g.',
                style: TextStyle(fontSize: 12, color: colors.destructive),
              ),
            ],
          ],
          if (widget.recent.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            ValueListenableBuilder(
              valueListenable: _name,
              builder: (context, value, _) {
                final query = value.text.trim().toLowerCase();
                final matches = [
                  for (final item in widget.recent)
                    if (query.isEmpty ||
                        item.name.toLowerCase().contains(query))
                      item,
                ].take(8).toList();
                if (matches.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      query.isEmpty ? 'Recent foods' : 'Matching recent foods',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to add with its calories and macros.',
                      style: muted,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppCard(
                      child: Column(
                        children: [
                          for (final (index, item) in matches.indexed) ...[
                            if (index > 0) const _RowDivider(),
                            _DishRow(item: item, onAdd: () => _addRecent(item)),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Hairline between dish rows.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.theme.colors.border,
    child: const SizedBox(height: 1, width: double.infinity),
  );
}

/// A dish line: name, macros, kcal and one action (add or remove).
class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, this.onAdd, this.onRemove});

  final MealItem item;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textTheme = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: textTheme.bodyMedium),
                Text(
                  'P ${item.proteinG.round()}g · C ${item.carbsG.round()}g · '
                  'F ${item.fatG.round()}g',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${item.kcal} kcal',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (onRemove != null)
            Semantics(
              label: 'Remove ${item.name}',
              child: FButton.icon(
                variant: .ghost,
                size: .sm,
                onPress: onRemove,
                child: Icon(FLucideIcons.x, color: colors.mutedForeground),
              ),
            ),
          if (onAdd != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(FLucideIcons.circlePlus, color: colors.primary),
            ),
        ],
      ),
    );
    if (onAdd == null) return row;
    return Semantics(
      button: true,
      label: 'Add ${item.name}, ${item.kcal} kilocalories',
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('recent-${item.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onAdd,
        child: row,
      ),
    );
  }
}

/// Sticky footer: what will be logged and the log button. Rebuilds with
/// the form (so a typed dish counts) without rebuilding the page.
class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.listenable,
    required this.type,
    required this.pending,
    required this.canSubmit,
    required this.onSubmit,
  });

  final Listenable listenable;
  final String type;
  final List<MealItem> Function() pending;
  final bool Function() canSubmit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: listenable,
    builder: (context, _) {
      final items = pending();
      final total = FoodLog.totals([Meal(label: type, items: items)]);
      final colors = context.theme.colors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${total.kcal} kcal',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      items.isEmpty
                          ? 'No dishes yet'
                          : '${items.length} '
                                '${items.length == 1 ? 'dish' : 'dishes'} · '
                                'P ${total.proteinG.round()}g · '
                                'C ${total.carbsG.round()}g · '
                                'F ${total.fatG.round()}g',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              FButton(
                key: const Key('log-meal-submit'),
                mainAxisSize: .min,
                onPress: canSubmit() ? onSubmit : null,
                prefix: const Icon(FLucideIcons.check),
                child: Text('Log to $type'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

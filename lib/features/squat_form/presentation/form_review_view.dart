import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/form_result.dart';
import '../domain/form_record.dart';

String formFaultLabel(String code) => switch (code) {
  'shallowDepth' => 'Shallow depth',
  'kneeValgus' => 'Knees caved in',
  'forwardLean' => 'Leaning forward',
  'heelsUp' => 'Heels lifted',
  'asymmetry' => 'Uneven sides',
  'fastEccentric' => 'Dropped too fast',
  'hipSag' => 'Hips sagging',
  'hipPike' => 'Hips too high',
  'noLockout' => 'Arms not locked out',
  'unevenArms' => 'Uneven arms',
  'partialRange' => 'Partial range',
  'elbowDrift' => 'Elbows drifted forward',
  'noFullExtension' => 'Arms not straightened',
  'elbowFlare' => 'Elbows flared',
  _ => code,
};

String _seconds(int ms) => '${(ms / 1000).round()}s';

/// "4/5 clean reps", or "18s/20s good" for a hold.
String formSummaryLabel(FormResult result) {
  final hold = result.hold;
  if (hold != null) {
    return '${_seconds(hold.goodMs)}/${_seconds(hold.trackedMs)} good';
  }
  final clean = result.reps.where((rep) => rep.clean).length;
  return '$clean/${result.reps.length} clean reps';
}

/// Per-rep verdicts (or a hold breakdown) of one camera-judged set: shown
/// right after the set and again from the session's history.
class FormReviewView extends StatelessWidget {
  const FormReviewView({required this.result, super.key});

  final FormResult result;

  Widget _faults(Iterable<String> labels) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final label in labels)
        FBadge(variant: .destructive, child: Text(label)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hold = result.hold;
    // A press or curl goes up first: its first half isn't a descent.
    final upFirst = formExerciseOf(result)?.upFirst ?? false;
    if (hold != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_seconds(hold.goodMs)} in good form', style: text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          if (hold.sagMs < 1000 && hold.pikeMs < 1000)
            Text('Clean hold', style: text.bodySmall)
          else
            _faults([
              if (hold.sagMs >= 1000)
                '${formFaultLabel('hipSag')} · ${_seconds(hold.sagMs)}',
              if (hold.pikeMs >= 1000)
                '${formFaultLabel('hipPike')} · ${_seconds(hold.pikeMs)}',
            ]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rep in result.reps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    'Rep ${rep.number}',
                    if (rep.minKneeAngle case final angle?)
                      '${angle.round()}° depth',
                    if (rep.firstHalfMs > 0)
                      upFirst
                          ? '↑${rep.firstHalfMs}ms ↓${rep.secondHalfMs}ms'
                          : '↓${rep.firstHalfMs}ms ↑${rep.secondHalfMs}ms',
                  ].join(' · '),
                  style: text.titleSmall,
                ),
                if (rep.clean)
                  Text('Clean rep', style: text.bodySmall)
                else
                  _faults(rep.faults.map(formFaultLabel)),
              ],
            ),
          ),
      ],
    );
  }
}

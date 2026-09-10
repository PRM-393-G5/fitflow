import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.action, super.key});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      ?action,
    ],
  );
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_localizations.dart';

/// The only deliberately bilingual screen: it appears before a fresh
/// installation has a language in which to explain itself.
class LanguageChoiceScreen extends StatelessWidget {
  final Future<void> Function(AppLanguage language) onSelected;

  const LanguageChoiceScreen({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.translate, size: 54, color: t.accent),
                  const SizedBox(height: 22),
                  Text(
                    'בחירת שפה  ·  Choose your language',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: t.ink,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'אפשר לשנות בכל עת בהגדרות\n'
                    'You can change this at any time in Settings',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.inkMuted),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => onSelected(AppLanguage.hebrew),
                      child: const Text('עברית'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => onSelected(AppLanguage.english),
                      child: const Text('English'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

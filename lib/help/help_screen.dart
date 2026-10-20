import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';
import 'help_content.dart';

class HelpScreen extends StatefulWidget {
  /// Supplying a catalog keeps previews and widget tests independent of the
  /// asset bundle. The application loads the bundled catalog by default.
  final HelpCatalog? catalog;

  const HelpScreen({super.key, this.catalog});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final Future<HelpCatalog> _catalog = widget.catalog == null
      ? HelpCatalog.load()
      : Future.value(widget.catalog);
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pick(he: 'עזרה', en: 'Help')),
      ),
      body: SoferPage(
        maxWidth: 920,
        child: FutureBuilder<HelpCatalog>(
          future: _catalog,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _loadError();
            final catalog = snapshot.data;
            if (catalog == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content(catalog);
          },
        ),
      ),
    );
  }

  Widget _loadError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.pick(
              he: 'לא ניתן לטעון את תוכן העזרה.',
              en: 'The help content could not be loaded.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _content(HelpCatalog catalog) {
    final terms =
        _normalise(_query).split(' ').where((term) => term.isNotEmpty);
    final matches = <({HelpSection section, List<HelpQuestion> questions})>[];
    for (final section in catalog.sections) {
      final questions = section.questions.where((question) {
        final haystack = _normalise(question.searchableText);
        return terms.every(haystack.contains);
      }).toList(growable: false);
      if (questions.isNotEmpty) {
        matches.add((section: section, questions: questions));
      }
    }
    final shown =
        matches.fold(0, (total, item) => total + item.questions.length);
    final searching = _query.trim().isNotEmpty;
    final t = SoferTokens.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: context.l10n.pick(
                he: 'חיפוש בשאלות ובתשובות',
                en: 'Search questions and answers',
              ),
              hintText: context.l10n.pick(
                he: 'למשל: שורה חלקית, גיבוי, רווח לשעה',
                en: 'For example: backup or line time',
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? IconButton(
                      tooltip: context.l10n.pick(
                        he: 'נקה חיפוש',
                        en: 'Clear search',
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              searching
                  ? context.l10n.pick(
                      he: '$shown תוצאות',
                      en: '$shown results',
                    )
                  : context.l10n.pick(
                      he: '${catalog.questionCount} שאלות ב־${catalog.sections.length} נושאים',
                      en: '${catalog.questionCount} questions in ${catalog.sections.length} topics · Hebrew content',
                    ),
              style: TextStyle(color: t.inkMuted),
            ),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? _emptyResults()
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final item = matches[index];
                    return searching
                        ? _SearchSection(
                            section: item.section,
                            questions: item.questions,
                          )
                        : _TopicTile(section: item.section);
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyResults() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 42, color: SoferTokens.of(context).inkFaint),
              const SizedBox(height: 12),
              Text(
                context.l10n.pick(
                  he: 'לא נמצאו שאלות מתאימות',
                  en: 'No matching questions were found',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u0591-\u05c7]'), '')
      .replaceAll(RegExp(r'["״׳־–—.,?!():/+]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _TopicTile extends StatelessWidget {
  final HelpSection section;

  const _TopicTile({required this.section});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Padding(
      padding: t.isCards
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 5)
          : EdgeInsets.zero,
      child: Material(
        color: t.isCards ? t.panel : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.isCards ? t.panelRadius : 0),
          side: BorderSide(color: t.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey('help-topic-${section.id}'),
          leading: Icon(_topicIcon(section.id), color: t.accent),
          title: Text(section.title),
          subtitle: Text('${section.questions.length} שאלות'),
          children: [
            for (final question in section.questions)
              _QuestionTile(question: question),
          ],
        ),
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  final HelpSection section;
  final List<HelpQuestion> questions;

  const _SearchSection({required this.section, required this.questions});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoferSectionTitle('${section.title} · ${questions.length}'),
          for (final question in questions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: _QuestionTile(question: question, outlined: true),
            ),
        ],
      );
}

class _QuestionTile extends StatelessWidget {
  final HelpQuestion question;
  final bool outlined;

  const _QuestionTile({required this.question, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Material(
      color: outlined && t.isCards ? t.panel : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(outlined && t.isCards ? 10 : 0),
        side: BorderSide(color: t.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('help-question-${question.id}'),
        title: Text(
          question.question,
          style: TextStyle(
            fontFamily: t.labelFamily,
            fontWeight: FontWeight.w600,
            color: t.ink,
          ),
        ),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            question.answer,
            style: TextStyle(
              fontFamily: t.labelFamily,
              height: 1.65,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _topicIcon(String id) => switch (id) {
      'start' => Icons.flag_outlined,
      'projects' => Icons.folder_outlined,
      'timer' => Icons.timer_outlined,
      'manual' => Icons.edit_note,
      'paged' => Icons.menu_book_outlined,
      'mezuza' => Icons.article_outlined,
      'tefillin' => Icons.grid_view_outlined,
      'corrections' => Icons.restore_from_trash_outlined,
      'journal' => Icons.table_chart_outlined,
      'orders' => Icons.assignment_outlined,
      'goals' => Icons.flag_circle_outlined,
      'calendar' => Icons.calendar_month_outlined,
      'money' => Icons.payments_outlined,
      'proofreading' => Icons.fact_check_outlined,
      'quotes' => Icons.calculate_outlined,
      'reports' => Icons.bar_chart_outlined,
      'backup' => Icons.backup_outlined,
      'settings' => Icons.tune_outlined,
      'desktop' => Icons.computer_outlined,
      'support' => Icons.build_outlined,
      _ => Icons.help_outline,
    };

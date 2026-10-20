import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../logic/tefillin_text.dart';

Future<int?> showTefillinWords({
  required BuildContext context,
  required int parshiya,
  required StamScript script,
  required String unitLabel,
  int fromWord = 0,
  int? selectedWord,
  bool locatingLegacyPosition = false,
  bool allowNoProgress = false,
}) =>
    showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TefillinWordsDialog(
          parshiya: parshiya,
          script: script,
          unitLabel: unitLabel,
          fromWord: fromWord,
          selectedWord: selectedWord,
          locatingLegacyPosition: locatingLegacyPosition,
          allowNoProgress: allowNoProgress),
    );

class TefillinWordsDialog extends StatefulWidget {
  final int parshiya;
  final StamScript script;
  final String unitLabel;
  final int fromWord;
  final int? selectedWord;
  final bool locatingLegacyPosition;
  final bool allowNoProgress;
  const TefillinWordsDialog(
      {super.key,
      required this.parshiya,
      required this.script,
      required this.unitLabel,
      this.fromWord = 0,
      this.selectedWord,
      this.locatingLegacyPosition = false,
      this.allowNoProgress = false});
  @override
  State<TefillinWordsDialog> createState() => _TefillinWordsDialogState();
}

class _TefillinWordsDialogState extends State<TefillinWordsDialog> {
  static const savedWordColor = Color(0xFFB71C1C);
  static const selectedWordColor = Color(0xFF1B5E20);
  late final text = TefillinText.of(widget.parshiya);
  late final keys = List.generate(text.words.length, (_) => GlobalKey());
  final focus = FocusNode();
  final transform = TransformationController();
  int? selected;
  double size = 32;

  @override
  void initState() {
    super.initState();
    final initial = widget.selectedWord;
    selected = initial != null &&
            initial > widget.fromWord &&
            initial <= text.words.length
        ? initial
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        _reveal(selected ?? (widget.fromWord > 0 ? widget.fromWord : 1)));
  }

  @override
  void dispose() {
    focus.dispose();
    transform.dispose();
    super.dispose();
  }

  void _reveal(int boundary) {
    final target =
        keys[(boundary - 1).clamp(0, keys.length - 1)].currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
          alignment: .35, duration: const Duration(milliseconds: 180));
    }
  }

  void _select(int boundary) {
    if (boundary <= widget.fromWord ||
        boundary > text.words.length ||
        (widget.locatingLegacyPosition && boundary == text.words.length)) {
      return;
    }
    setState(() => selected = boundary);
    focus.requestFocus();
  }

  void _move(int delta) {
    final next = ((selected ?? widget.fromWord) + delta)
        .clamp(widget.fromWord + 1, text.words.length);
    _select(next);
    _reveal(next);
  }

  void _confirm() {
    if (selected != null && selected! > widget.fromWord) {
      Navigator.pop(context, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 1000,
        height: screen.height * .9,
        child: Focus(
          focusNode: focus,
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowDown) {
              _move(1);
            } else if (key == LogicalKeyboardKey.arrowRight ||
                key == LogicalKeyboardKey.arrowUp) {
              _move(-1);
            } else if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.space) {
              _confirm();
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('${widget.unitLabel} · ${widget.script.label}',
                    style: Theme.of(context).textTheme.titleMedium)),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(widget.locatingLegacyPosition
                    ? l.pick(
                        he:
                            'מעבר מרישום לפי שורות: סמן את המילה האחרונה שכבר נרשמה בעבר. סימון זה קובע את נקודת ההמשך בלבד.',
                        en:
                            'Switching from lines: select the last word already recorded. This sets the continuation point only.')
                    : l.pick(
                        he: 'סמן את המילה השלמה האחרונה שסיימת לכתוב.',
                        en: 'Select the last whole word you finished writing.'))),
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                    l.pick(
                        he: widget.fromWord == 0
                            ? 'מילה אחרונה שנשמרה: טרם נרשמה'
                            : 'מילה אחרונה שנשמרה: ${text.wordAt(widget.fromWord)} (${widget.fromWord})',
                        en: widget.fromWord == 0
                            ? 'Last saved word: none'
                            : 'Last saved word: ${text.wordAt(widget.fromWord)} (${widget.fromWord})'),
                    style: const TextStyle(color: savedWordColor))),
            Row(children: [
              const SizedBox(width: 12),
              IconButton(
                  tooltip: l.pick(he: 'הקטנה', en: 'Zoom out'),
                  onPressed: () =>
                      setState(() => size = (size - 4).clamp(20, 76)),
                  icon: const Icon(Icons.remove)),
              Expanded(
                  child: Slider(
                      value: size,
                      min: 20,
                      max: 76,
                      onChanged: (v) => setState(() => size = v))),
              IconButton(
                  tooltip: l.pick(he: 'הגדלה', en: 'Zoom in'),
                  onPressed: () =>
                      setState(() => size = (size + 4).clamp(20, 76)),
                  icon: const Icon(Icons.add)),
              IconButton(
                  tooltip: l.pick(he: 'איפוס הגדלה', en: 'Reset zoom'),
                  onPressed: () => setState(() {
                        size = 32;
                        transform.value = Matrix4.identity();
                      }),
                  icon: const Icon(Icons.fit_screen)),
              const SizedBox(width: 12),
            ]),
            Expanded(
                child: ColoredBox(
              color: Colors.white,
              child: InteractiveViewer(
                transformationController: transform,
                minScale: 1,
                maxScale: 8,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                          alignment: WrapAlignment.start,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          spacing: size * .25,
                          runSpacing: size * .12,
                          children: [
                            for (var i = 0; i < text.words.length; i++)
                              Semantics(
                                label: '${text.words[i]}, ${i + 1}'
                                    '${i + 1 == widget.fromWord ? l.pick(he: ', המילה האחרונה שנשמרה', en: ', last saved word') : ''}'
                                    '${selected == i + 1 ? l.pick(he: ', המילה שנבחרה', en: ', selected word') : ''}',
                                button: true,
                                selected: selected == i + 1,
                                child: GestureDetector(
                                  key: keys[i],
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _select(i + 1),
                                  child: Text(text.words[i],
                                      textScaler: TextScaler.noScaling,
                                      strutStyle: StrutStyle(
                                          fontFamily: widget.script.family,
                                          fontSize: size,
                                          height: 1.8,
                                          forceStrutHeight: true),
                                      style: TextStyle(
                                          fontFamily: widget.script.family,
                                          fontSize: size,
                                          height: 1.8,
                                          color: selected == i + 1
                                              ? selectedWordColor
                                              : widget.fromWord == i + 1
                                                  ? savedWordColor
                                                  : Colors.black,
                                          fontWeight: FontWeight.normal)),
                                ),
                              ),
                          ]),
                    ),
                  ),
                ),
              ),
            )),
            Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Text(
                    selected == null
                        ? l.pick(he: 'טרם נבחרה מילה', en: 'No word selected')
                        : l.pick(
                            he:
                                'נבחרה: ${text.wordAt(selected!)} — מילה $selected מתוך ${text.words.length}',
                            en:
                                'Selected: ${text.wordAt(selected!)} — word $selected of ${text.words.length}'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: selected == null ? null : selectedWordColor))),
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child:
                    Wrap(alignment: WrapAlignment.end, spacing: 12, children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.cancel)),
                  if (widget.allowNoProgress)
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(context, widget.fromWord),
                        child: Text(
                            l.pick(he: 'שמור זמן בלבד', en: 'Save time only'))),
                  FilledButton(
                      onPressed: selected == null ? null : _confirm,
                      child:
                          Text(l.pick(he: 'אישור המילה', en: 'Confirm word'))),
                ])),
          ]),
        ),
      ),
    );
  }
}

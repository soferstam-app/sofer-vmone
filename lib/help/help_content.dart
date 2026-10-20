import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

const String helpAssetPath = 'docs/help/FAQ.he.json';

class HelpQuestion {
  final String id;
  final String question;
  final String answer;
  final List<String> keywords;

  const HelpQuestion({
    required this.id,
    required this.question,
    required this.answer,
    this.keywords = const [],
  });

  factory HelpQuestion.fromJson(Map<String, dynamic> json) => HelpQuestion(
        id: json['id'] as String,
        question: json['question'] as String,
        answer: json['answerMarkdown'] as String,
        keywords: (json['keywords'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );

  String get searchableText => [question, answer, ...keywords].join(' ');
}

class HelpSection {
  final String id;
  final String title;
  final List<HelpQuestion> questions;

  const HelpSection({
    required this.id,
    required this.title,
    required this.questions,
  });

  factory HelpSection.fromJson(Map<String, dynamic> json) => HelpSection(
        id: json['id'] as String,
        title: json['title'] as String,
        questions: (json['questions'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(HelpQuestion.fromJson)
            .toList(growable: false),
      );
}

class HelpCatalog {
  final List<HelpSection> sections;

  const HelpCatalog(this.sections);

  int get questionCount =>
      sections.fold(0, (total, section) => total + section.questions.length);

  factory HelpCatalog.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['sections'] is! List) {
      throw const FormatException('Invalid help catalog');
    }
    final sections = (decoded['sections'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(HelpSection.fromJson)
        .toList(growable: false);
    if (sections.isEmpty ||
        sections.any((section) => section.questions.isEmpty)) {
      throw const FormatException('Help catalog is empty');
    }
    return HelpCatalog(sections);
  }

  static Future<HelpCatalog> load() async =>
      HelpCatalog.fromJsonString(await rootBundle.loadString(helpAssetPath));
}

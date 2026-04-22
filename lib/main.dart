import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProGradeTestTakerApp());
}

const String kDemoBankJson = r'''
{
  "questions": [
    {
      "id": "math-1",
      "category": "Mathematics",
      "subcategory": "Algebra",
      "type": "multipleChoice",
      "difficulty": 2,
      "prompt": "Solve: $$x^2 - 5x + 6 = 0$$",
      "options": ["1 and 6", "2 and 3", "3 and 4", "0 and 6"],
      "answer": [1],
      "explanation": "Factor the expression: (x - 2)(x - 3) = 0, so the roots are 2 and 3.",
      "tags": ["roots", "quadratics"]
    },
    {
      "id": "sci-1",
      "category": "Science",
      "subcategory": "Physics",
      "type": "trueFalse",
      "difficulty": 1,
      "prompt": "True or false: Light travels faster than sound.",
      "options": ["True", "False"],
      "answer": ["True"],
      "explanation": "Light is much faster than sound in air."
    },
    {
      "id": "ver-1",
      "category": "Verbal",
      "subcategory": "Vocabulary",
      "type": "shortAnswer",
      "difficulty": 2,
      "prompt": "Fill in the blank: A concise answer is the opposite of a ____ answer.",
      "answer": ["verbose", "wordy"],
      "explanation": "Both 'verbose' and 'wordy' are acceptable."
    },
    {
      "id": "gen-1",
      "category": "General Knowledge",
      "subcategory": "Logic",
      "type": "multiSelect",
      "difficulty": 2,
      "prompt": "Select all prime numbers.",
      "options": ["2", "3", "4", "5"],
      "answer": [0, 1, 3],
      "explanation": "2, 3, and 5 are prime."
    },
    {
      "id": "num-1",
      "category": "Mathematics",
      "subcategory": "Arithmetic",
      "type": "numeric",
      "difficulty": 1,
      "prompt": "Compute: 18 ÷ 3 + 4",
      "answer": [10],
      "tolerance": 0,
      "explanation": "18 ÷ 3 = 6, then 6 + 4 = 10."
    }
  ]
}
''';

enum QuestionType {
  multipleChoice,
  multiSelect,
  trueFalse,
  numeric,
  shortAnswer,
  essay,
}

extension QuestionTypeLabel on QuestionType {
  String get label {
    switch (this) {
      case QuestionType.multipleChoice:
        return 'MCQ';
      case QuestionType.multiSelect:
        return 'Multi-select';
      case QuestionType.trueFalse:
        return 'True / False';
      case QuestionType.numeric:
        return 'Numeric';
      case QuestionType.shortAnswer:
        return 'Short answer';
      case QuestionType.essay:
        return 'Essay';
    }
  }
}

String _newId([String prefix = 'id']) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}

String _cleanText(String input) {
  return input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}

String _normalize(String input) {
  return _cleanText(input)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

List<String> _asStringList(dynamic value) {
  if (value == null) return <String>[];
  if (value is List) {
    return value
        .map((e) => _asString(e).trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return <String>[];
    if (s.contains('\n') || s.contains('|') || s.contains(';')) {
      return s
          .split(RegExp(r'[\n|;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[s];
  }
  final s = _asString(value).trim();
  return s.isEmpty ? <String>[] : <String>[s];
}

String _asString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value.map(_asString).where((e) => e.trim().isNotEmpty).join('\n');
  }
  if (value is Map) {
    return value.entries
        .map((e) => '${e.key}: ${_asString(e.value)}')
        .where((e) => e.trim().isNotEmpty)
        .join('\n');
  }
  return value.toString();
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final s = value.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }
  return false;
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    final s = value.trim();
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d != null) return d.round();
  }
  return fallback;
}

double _asDouble(dynamic value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    final s = value.trim().replaceAll(',', '.');
    final d = double.tryParse(s);
    if (d != null) return d;
  }
  return fallback;
}

int _difficultyOf(dynamic value) {
  final raw = _asString(value).trim().toLowerCase();
  if (raw.isEmpty) return 3;
  if (raw == 'easy') return 1;
  if (raw == 'medium' || raw == 'normal') return 3;
  if (raw == 'hard') return 5;
  final i = int.tryParse(raw);
  if (i != null) return i.clamp(1, 5);
  final d = double.tryParse(raw);
  if (d != null) return d.round().clamp(1, 5);
  return 3;
}

QuestionType _parseQuestionType({
  required String rawType,
  required List<String> options,
  required List<String> answers,
  required String prompt,
}) {
  final t = _normalize(rawType);
  final p = _normalize(prompt);

  if (t.contains('essay') || t.contains('long') || t.contains('free')) {
    return QuestionType.essay;
  }
  if (t.contains('multi') || t.contains('checkbox') || t.contains('select')) {
    return QuestionType.multiSelect;
  }
  if (t.contains('true') && t.contains('false')) {
    return QuestionType.trueFalse;
  }
  if (t.contains('numeric') || t.contains('number') || t.contains('calculation')) {
    return QuestionType.numeric;
  }
  if (t.contains('short') || t.contains('fill') || t.contains('blank')) {
    return QuestionType.shortAnswer;
  }

  if (options.isNotEmpty) {
    if (answers.length > 1) return QuestionType.multiSelect;
    return QuestionType.multipleChoice;
  }

  if (p.contains('true or false') || p.startsWith('true/false')) {
    return QuestionType.trueFalse;
  }

  return QuestionType.shortAnswer;
}

List<String> _parseOptions(Map<String, dynamic> json) {
  const optionKeys = <String>[
    'options',
    'choices',
    'variants',
    'optionList',
    'answerChoices',
    'answerOptions',
  ];

  for (final key in optionKeys) {
    final value = json[key];
    if (value is List) {
      final options = value
          .map((e) => _asString(e).trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (options.isNotEmpty) return options;
    }
  }

  final ordered = <String>[
    'option1',
    'option2',
    'option3',
    'option4',
    'option5',
    'option6',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
  ];

  final out = <String>[];
  for (final key in ordered) {
    if (json.containsKey(key)) {
      final text = _asString(json[key]).trim();
      if (text.isNotEmpty) out.add(text);
    }
  }
  return out;
}

List<String> _parseAnswers(Map<String, dynamic> json) {
  const answerKeys = <String>[
    'answer',
    'answers',
    'correct',
    'correctAnswer',
    'correctAnswers',
    'solution',
  ];

  for (final key in answerKeys) {
    final value = json[key];
    final answers = _asStringList(value);
    if (answers.isNotEmpty) return answers;
  }
  return <String>[];
}

bool _looksLikeSingleQuestion(Map<String, dynamic> json) {
  final hasPrompt = json.containsKey('prompt') ||
      json.containsKey('question') ||
      json.containsKey('stem') ||
      json.containsKey('text') ||
      json.containsKey('body') ||
      json.containsKey('content');
  final hasAnswer = json.containsKey('answer') ||
      json.containsKey('answers') ||
      json.containsKey('correct') ||
      json.containsKey('correctAnswer') ||
      json.containsKey('correctAnswers');
  return hasPrompt || hasAnswer;
}

class QuestionAttempt {
  final String questionId;
  final List<String> selectedValues;
  final bool? correct;
  final bool scored;
  final int timeSpentMs;
  final String correctAnswerDisplay;
  final String note;

  const QuestionAttempt({
    required this.questionId,
    required this.selectedValues,
    required this.correct,
    required this.scored,
    required this.timeSpentMs,
    required this.correctAnswerDisplay,
    required this.note,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'questionId': questionId,
        'selectedValues': selectedValues,
        'correct': correct,
        'scored': scored,
        'timeSpentMs': timeSpentMs,
        'correctAnswerDisplay': correctAnswerDisplay,
        'note': note,
      };

  factory QuestionAttempt.fromJson(Map<String, dynamic> json) {
    return QuestionAttempt(
      questionId: _asString(json['questionId']),
      selectedValues: _asStringList(json['selectedValues']),
      correct: json['correct'] as bool?,
      scored: _asBool(json['scored']),
      timeSpentMs: _asInt(json['timeSpentMs']),
      correctAnswerDisplay: _asString(json['correctAnswerDisplay']),
      note: _asString(json['note']),
    );
  }
}

class SessionReport {
  final String id;
  final String modeLabel;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<QuestionAttempt> attempts;

  const SessionReport({
    required this.id,
    required this.modeLabel,
    required this.startedAt,
    required this.endedAt,
    required this.attempts,
  });

  int get totalQuestions => attempts.length;
  int get scoredCount => attempts.where((a) => a.scored).length;
  int get correctCount => attempts.where((a) => a.scored && a.correct == true).length;
  int get skippedCount => attempts.where((a) => !a.scored).length;
  int get totalTimeMs => attempts.fold<int>(0, (sum, attempt) => sum + attempt.timeSpentMs);

  double get accuracy => scoredCount == 0 ? 0 : correctCount / scoredCount.toDouble();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'modeLabel': modeLabel,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'attempts': attempts.map((e) => e.toJson()).toList(),
      };

  factory SessionReport.fromJson(Map<String, dynamic> json) {
    final rawAttempts = json['attempts'];
    final attempts = rawAttempts is List
        ? rawAttempts.map((e) => QuestionAttempt.fromJson(_asMap(e))).toList()
        : <QuestionAttempt>[];

    return SessionReport(
      id: _asString(json['id']),
      modeLabel: _asString(json['modeLabel']),
      startedAt: DateTime.tryParse(_asString(json['startedAt'])) ?? DateTime.now(),
      endedAt: DateTime.tryParse(_asString(json['endedAt'])) ?? DateTime.now(),
      attempts: attempts,
    );
  }
}

class TestQuestion {
  String id;
  String prompt;
  String explanation;
  String category;
  String subcategory;
  QuestionType type;
  int difficulty;
  List<String> options;
  List<String> correctAnswers;
  List<String> tags;
  bool favorite;
  double tolerance;

  int seenCount;
  int scoredCount;
  int correctCount;
  int skippedCount;
  int totalTimeMs;
  DateTime? lastAttemptAt;

  TestQuestion({
    required this.id,
    required this.prompt,
    required this.explanation,
    required this.category,
    required this.subcategory,
    required this.type,
    required this.difficulty,
    required this.options,
    required this.correctAnswers,
    required this.tags,
    required this.favorite,
    required this.tolerance,
    required this.seenCount,
    required this.scoredCount,
    required this.correctCount,
    required this.skippedCount,
    required this.totalTimeMs,
    required this.lastAttemptAt,
  });

  factory TestQuestion.fromFlexibleJson(dynamic raw, {String? fallbackId}) {
    if (raw is String) {
      return TestQuestion.fromPrompt(
        raw,
        fallbackId: fallbackId,
        category: 'General',
        subcategory: '',
        difficulty: 3,
      );
    }

    final map = _asMap(raw);
    final prompt = _firstNonEmptyString(map, const <String>[
      'prompt',
      'question',
      'stem',
      'text',
      'body',
      'content',
      'statement',
      'title',
    ]);

    final explanation = _firstNonEmptyString(map, const <String>[
      'explanation',
      'solution',
      'rationale',
      'details',
      'answerExplanation',
      'hint',
    ]);

    final options = _parseOptions(map);
    final answers = _parseAnswers(map);

    final type = _parseQuestionType(
      rawType: _firstNonEmptyString(map, const <String>[
        'type',
        'questionType',
        'kind',
        'format',
      ]),
      options: options,
      answers: answers,
      prompt: prompt,
    );

    final category = _firstNonEmptyString(map, const <String>[
      'category',
      'subject',
      'testCategory',
      'section',
      'paper',
    ]);

    final subcategory = _firstNonEmptyString(map, const <String>[
      'subcategory',
      'topic',
      'chapter',
      'unit',
      'skill',
    ]);

    final tags = <String>{
      ..._asStringList(_firstValue(map, const <String>['tags', 'labels', 'keywords'])),
      if (category.isNotEmpty) category,
      if (subcategory.isNotEmpty) subcategory,
    }.toList();

    return TestQuestion(
      id: _uniqueId(_firstNonEmptyString(map, const <String>[
            'id',
            'questionId',
            'qid',
            'uuid',
          ]), fallbackId: fallbackId),
      prompt: prompt.isNotEmpty ? prompt : 'Untitled question',
      explanation: explanation,
      category: category.isNotEmpty ? category : 'General',
      subcategory: subcategory,
      type: type,
      difficulty: _difficultyOf(_firstValue(map, const <String>[
        'difficulty',
        'level',
        'tier',
      ])),
      options: options,
      correctAnswers: answers,
      tags: tags,
      favorite: _asBool(_firstValue(map, const <String>['favorite', 'starred'])),
      tolerance: _asDouble(_firstValue(map, const <String>['tolerance', 'epsilon']), 0),
      seenCount: _asInt(_firstValue(map, const <String>['seenCount', 'timesSeen']), 0),
      scoredCount: _asInt(_firstValue(map, const <String>['scoredCount', 'timesScored']), 0),
      correctCount: _asInt(_firstValue(map, const <String>['correctCount', 'timesCorrect']), 0),
      skippedCount: _asInt(_firstValue(map, const <String>['skippedCount', 'timesSkipped']), 0),
      totalTimeMs: _asInt(_firstValue(map, const <String>['totalTimeMs', 'timeSpentMs']), 0),
      lastAttemptAt: DateTime.tryParse(
        _asString(_firstValue(map, const <String>['lastAttemptAt', 'lastSeenAt'])),
      ),
    );
  }

  factory TestQuestion.fromPrompt(
    String prompt, {
    String? fallbackId,
    String category = 'General',
    String subcategory = '',
    int difficulty = 3,
  }) {
    return TestQuestion(
      id: _uniqueId('', fallbackId: fallbackId),
      prompt: _cleanText(prompt).isEmpty ? 'Untitled question' : _cleanText(prompt),
      explanation: '',
      category: category,
      subcategory: subcategory,
      type: QuestionType.shortAnswer,
      difficulty: difficulty.clamp(1, 5),
      options: <String>[],
      correctAnswers: <String>[],
      tags: <String>[category, if (subcategory.isNotEmpty) subcategory],
      favorite: false,
      tolerance: 0,
      seenCount: 0,
      scoredCount: 0,
      correctCount: 0,
      skippedCount: 0,
      totalTimeMs: 0,
      lastAttemptAt: null,
    );
  }

  factory TestQuestion.fromJson(Map<String, dynamic> json) {
    final typeName = _asString(json['type']);
    final type = QuestionType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => QuestionType.shortAnswer,
    );

    return TestQuestion(
      id: _uniqueId(_asString(json['id'])),
      prompt: _asString(json['prompt']).isEmpty ? 'Untitled question' : _asString(json['prompt']),
      explanation: _asString(json['explanation']),
      category: _asString(json['category']).isEmpty ? 'General' : _asString(json['category']),
      subcategory: _asString(json['subcategory']),
      type: type,
      difficulty: _difficultyOf(json['difficulty']),
      options: _asStringList(json['options']),
      correctAnswers: _asStringList(json['correctAnswers']),
      tags: _asStringList(json['tags']),
      favorite: _asBool(json['favorite']),
      tolerance: _asDouble(json['tolerance'], 0),
      seenCount: _asInt(json['seenCount']),
      scoredCount: _asInt(json['scoredCount']),
      correctCount: _asInt(json['correctCount']),
      skippedCount: _asInt(json['skippedCount']),
      totalTimeMs: _asInt(json['totalTimeMs']),
      lastAttemptAt: DateTime.tryParse(_asString(json['lastAttemptAt'])),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'prompt': prompt,
        'explanation': explanation,
        'category': category,
        'subcategory': subcategory,
        'type': type.name,
        'difficulty': difficulty,
        'options': options,
        'correctAnswers': correctAnswers,
        'tags': tags,
        'favorite': favorite,
        'tolerance': tolerance,
        'seenCount': seenCount,
        'scoredCount': scoredCount,
        'correctCount': correctCount,
        'skippedCount': skippedCount,
        'totalTimeMs': totalTimeMs,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      };

  double get accuracy => scoredCount == 0 ? 0 : correctCount / scoredCount.toDouble();

  String get typeLabel => type.label;

  List<int> correctOptionIndexes() {
    final indexes = <int>{};
    if (options.isEmpty) return <int>[];

    for (final answer in correctAnswers) {
      final token = _normalize(answer);
      if (token.isEmpty) continue;

      final numeric = int.tryParse(token);
      if (numeric != null) {
        if (numeric >= 0 && numeric < options.length) {
          indexes.add(numeric);
          continue;
        }
        if (numeric >= 1 && numeric <= options.length) {
          indexes.add(numeric - 1);
          continue;
        }
      }

      if (token.length == 1 && RegExp(r'^[a-z]$').hasMatch(token)) {
        final idx = token.codeUnitAt(0) - 97;
        if (idx >= 0 && idx < options.length) {
          indexes.add(idx);
          continue;
        }
      }

      for (var i = 0; i < options.length; i++) {
        if (_normalize(options[i]) == token) {
          indexes.add(i);
        }
      }
    }

    final out = indexes.toList()..sort();
    return out;
  }

  String correctAnswerDisplay() {
    if (correctAnswers.isEmpty) return '—';
    final optionIndexes = correctOptionIndexes();
    if (optionIndexes.isNotEmpty) {
      return optionIndexes.map((i) => options[i]).join(' • ');
    }
    return correctAnswers.join(' • ');
  }

  void applyAttempt(QuestionAttempt attempt, DateTime time) {
    seenCount += 1;
    totalTimeMs += attempt.timeSpentMs;
    lastAttemptAt = time;
    if (!attempt.scored) {
      skippedCount += 1;
      return;
    }
    scoredCount += 1;
    if (attempt.correct == true) {
      correctCount += 1;
    }
  }

  static String _firstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (!map.containsKey(key)) continue;
      final s = _asString(map[key]).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static dynamic _firstValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) return map[key];
    }
    return null;
  }

  static String _uniqueId(String current, {String? fallbackId}) {
    var candidate = current.trim().isNotEmpty
        ? current.trim()
        : (fallbackId?.trim().isNotEmpty == true ? fallbackId!.trim() : _newId('q'));
    return candidate.isEmpty ? _newId('q') : candidate;
  }
}

class BucketStat {
  int attempts = 0;
  int scored = 0;
  int correct = 0;
  int skipped = 0;
  int totalTimeMs = 0;

  void add({
    required bool scoredAttempt,
    required bool? correctAttempt,
    required int timeMs,
  }) {
    attempts += 1;
    totalTimeMs += timeMs;
    if (!scoredAttempt) {
      skipped += 1;
      return;
    }
    scored += 1;
    if (correctAttempt == true) correct += 1;
  }

  double get accuracy => scored == 0 ? 0 : correct / scored.toDouble();
  double get avgTimeSeconds => attempts == 0 ? 0 : totalTimeMs / attempts / 1000.0;
}

class AppStore extends ChangeNotifier {
  final List<TestQuestion> _questions = <TestQuestion>[];
  final List<SessionReport> _sessions = <SessionReport>[];

  List<TestQuestion> get questions => List.unmodifiable(_questions);
  List<SessionReport> get sessions => List.unmodifiable(_sessions);

  int get totalQuestions => _questions.length;
  int get totalSessions => _sessions.length;
  int get totalAttempts => _sessions.fold<int>(0, (sum, session) => sum + session.totalQuestions);
  int get totalScoredAttempts => _sessions.fold<int>(0, (sum, session) => sum + session.scoredCount);
  int get totalCorrectAttempts => _sessions.fold<int>(0, (sum, session) => sum + session.correctCount);
  int get totalSkippedAttempts => _sessions.fold<int>(0, (sum, session) => sum + session.skippedCount);
  int get totalTimeMs => _sessions.fold<int>(0, (sum, session) => sum + session.totalTimeMs);

  double get accuracy =>
      totalScoredAttempts == 0 ? 0 : totalCorrectAttempts / totalScoredAttempts.toDouble();

  double get avgQuestionTimeSeconds =>
      totalAttempts == 0 ? 0 : totalTimeMs / totalAttempts / 1000.0;

  List<String> get categories {
    final set = <String>{};
    for (final q in _questions) {
      set.add(q.category);
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  TestQuestion? questionById(String id) {
    for (final q in _questions) {
      if (q.id == id) return q;
    }
    return null;
  }

  void clearAll() {
    _questions.clear();
    _sessions.clear();
    notifyListeners();
  }

  void loadDemoBank() {
    importFromText(kDemoBankJson, replaceAll: true);
  }

  void toggleFavorite(String questionId) {
    final q = questionById(questionId);
    if (q == null) return;
    q.favorite = !q.favorite;
    notifyListeners();
  }

  void deleteQuestion(String questionId) {
    _questions.removeWhere((q) => q.id == questionId);
    notifyListeners();
  }

  void recordSession(SessionReport session) {
    _sessions.insert(0, session);
    for (final attempt in session.attempts) {
      final q = questionById(attempt.questionId);
      if (q != null) {
        q.applyAttempt(attempt, session.endedAt);
      }
    }
    notifyListeners();
  }

  String exportJson() {
    final payload = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'questions': _questions.map((q) => q.toJson()).toList(),
      'sessions': _sessions.map((s) => s.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  int importFromText(String input, {required bool replaceAll}) {
    final raw = input.trim();
    if (raw.isEmpty) return 0;

    if (replaceAll) {
      clearAll();
    }

    final existingIds = _questions.map((e) => e.id).toSet();
    final importedQuestions = <TestQuestion>[];
    final importedSessions = <SessionReport>[];

    void addQuestion(dynamic value) {
      final q = TestQuestion.fromFlexibleJson(value);
      q.id = _ensureUniqueId(q.id, existingIds);
      existingIds.add(q.id);
      importedQuestions.add(q);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          addQuestion(item);
        }
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['questions'] is List) {
          for (final item in decoded['questions'] as List) {
            addQuestion(item);
          }
        } else if (_looksLikeSingleQuestion(decoded)) {
          addQuestion(decoded);
        } else if (decoded['question'] != null) {
          addQuestion(decoded['question']);
        }

        if (decoded['sessions'] is List) {
          for (final item in decoded['sessions'] as List) {
            importedSessions.add(SessionReport.fromJson(_asMap(item)));
          }
        }
      } else if (decoded is String) {
        addQuestion(decoded);
      } else {
        addQuestion(raw);
      }
    } on FormatException {
      addQuestion(raw);
    }

    _questions.addAll(importedQuestions);
    _sessions.addAll(importedSessions);
    _sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    notifyListeners();
    return importedQuestions.length;
  }

  Map<String, BucketStat> categoryBuckets() {
    final buckets = <String, BucketStat>{};
    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        final key = question?.category ?? 'Deleted / Unknown';
        buckets.putIfAbsent(key, BucketStat());
        buckets[key]!.add(
          scoredAttempt: attempt.scored,
          correctAttempt: attempt.correct,
          timeMs: attempt.timeSpentMs,
        );
      }
    }
    final out = buckets.entries.toList()
      ..sort((a, b) => b.value.attempts.compareTo(a.value.attempts));
    return Map<String, BucketStat>.fromEntries(out);
  }

  Map<int, BucketStat> difficultyBuckets() {
    final buckets = <int, BucketStat>{};
    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        final key = question?.difficulty ?? 0;
        buckets.putIfAbsent(key, BucketStat());
        buckets[key]!.add(
          scoredAttempt: attempt.scored,
          correctAttempt: attempt.correct,
          timeMs: attempt.timeSpentMs,
        );
      }
    }
    final keys = buckets.keys.toList()..sort();
    return {for (final k in keys) k: buckets[k]!};
  }

  Map<QuestionType, BucketStat> typeBuckets() {
    final buckets = <QuestionType, BucketStat>{};
    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        final key = question?.type ?? QuestionType.shortAnswer;
        buckets.putIfAbsent(key, BucketStat());
        buckets[key]!.add(
          scoredAttempt: attempt.scored,
          correctAttempt: attempt.correct,
          timeMs: attempt.timeSpentMs,
        );
      }
    }
    return buckets;
  }

  List<SessionReport> recentSessions([int limit = 10]) {
    return _sessions.take(limit).toList();
  }

  String _ensureUniqueId(String base, Set<String> existing) {
    var candidate = base.trim().isEmpty ? _newId('q') : base.trim();
    var n = 1;
    while (existing.contains(candidate) || _questions.any((q) => q.id == candidate)) {
      candidate = '${base.trim().isEmpty ? 'q' : base.trim()}-$n';
      n += 1;
    }
    return candidate;
  }
}

class ProGradeTestTakerApp extends StatelessWidget {
  const ProGradeTestTakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ProGrade Test Taker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      home: const AppShell(),
    );
  }
}

enum _MenuAction { importJson, exportJson, loadDemo, clearAll }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppStore store = AppStore();
  int tabIndex = 0;

  String get title {
    switch (tabIndex) {
      case 0:
        return 'Practice';
      case 1:
        return 'Library';
      default:
        return 'Statistics';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              PopupMenuButton<_MenuAction>(
                onSelected: _handleMenuAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _MenuAction.importJson,
                    child: Text('Import JSON / text'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.exportJson,
                    child: Text('Export JSON'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.loadDemo,
                    child: Text('Load demo bank'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.clearAll,
                    child: Text('Clear all'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(
              index: tabIndex,
              children: [
                PracticePage(store: store),
                LibraryPage(store: store),
                StatsPage(store: store),
              ],
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: tabIndex,
            type: BottomNavigationBarType.fixed,
            onTap: (value) => setState(() => tabIndex = value),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.play_circle_outline),
                label: 'Practice',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_books_outlined),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.query_stats_outlined),
                label: 'Stats',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleMenuAction(_MenuAction action) async {
    switch (action) {
      case _MenuAction.importJson:
        await _showImportDialog();
        return;
      case _MenuAction.exportJson:
        await _showExportDialog();
        return;
      case _MenuAction.loadDemo:
        store.loadDemoBank();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demo bank loaded.')),
          );
        }
        return;
      case _MenuAction.clearAll:
        await _confirmClearAll();
        return;
    }
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Import'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Paste JSON here. A plain text paste becomes one short-answer question.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 10,
                    maxLines: 18,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'JSON or plain text...',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  try {
                    final count = store.importFromText(
                      controller.text,
                      replaceAll: false,
                    );
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Imported $count question(s).')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Import failed: $e')),
                    );
                  }
                },
                child: const Text('Merge'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    final count = store.importFromText(
                      controller.text,
                      replaceAll: true,
                    );
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Imported $count question(s).')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Import failed: $e')),
                    );
                  }
                },
                child: const Text('Replace all'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showExportDialog() async {
    final exportText = store.exportJson();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export JSON'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                exportText,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: exportText));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export copied to clipboard.')),
                  );
                }
              },
              child: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear everything?'),
          content: const Text('This removes all questions and sessions from memory.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      store.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared.')),
        );
      }
    }
  }
}

class PracticePage extends StatefulWidget {
  final AppStore store;

  const PracticePage({super.key, required this.store});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

enum PracticeFilterMode { all, weak, unseen, favorites }

class _PracticePageState extends State<PracticePage> {
  final TextEditingController searchController = TextEditingController();
  String category = 'All';
  int difficulty = 0;
  PracticeFilterMode filterMode = PracticeFilterMode.all;
  int sessionSize = 10;
  bool shuffle = true;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<TestQuestion> _filteredQuestions() {
    final query = _normalize(searchController.text);
    final items = widget.store.questions.where((q) {
      if (category != 'All' && q.category != category) return false;
      if (difficulty > 0 && q.difficulty != difficulty) return false;

      switch (filterMode) {
        case PracticeFilterMode.all:
          break;
        case PracticeFilterMode.weak:
          if (!(q.scoredCount >= 3 && q.accuracy < 0.7)) return false;
          break;
        case PracticeFilterMode.unseen:
          if (q.seenCount > 0) return false;
          break;
        case PracticeFilterMode.favorites:
          if (!q.favorite) return false;
          break;
      }

      if (query.isEmpty) return true;

      final haystack = <String>[
        q.prompt,
        q.explanation,
        q.category,
        q.subcategory,
        q.tags.join(' '),
        q.correctAnswerDisplay(),
        q.typeLabel,
      ].join(' ');
      return _normalize(haystack).contains(query);
    }).toList();

    items.sort((a, b) {
      final fav = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
      if (fav != 0) return fav;
      return b.seenCount.compareTo(a.seenCount);
    });

    return items;
  }

  void _startQuiz(List<TestQuestion> questions) {
    final copy = List<TestQuestion>.from(questions);
    if (shuffle) {
      copy.shuffle();
    }
    final count = sessionSize <= 0 || sessionSize > copy.length ? copy.length : sessionSize;
    final picked = copy.take(count).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          store: widget.store,
          questions: picked,
          modeLabel: _modeLabel(picked.length),
        ),
      ),
    );
  }

  String _modeLabel(int count) {
    final parts = <String>[
      if (filterMode != PracticeFilterMode.all) filterMode.name,
      if (category != 'All') category,
      if (difficulty > 0) 'D$difficulty',
      if (shuffle) 'shuffled',
      '$count question(s)',
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>['All', ...widget.store.categories];
    final questions = _filteredQuestions();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search prompt, explanation, tags, answers...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in PracticeFilterMode.values)
                      ChoiceChip(
                        label: Text(mode.name),
                        selected: filterMode == mode,
                        onSelected: (_) => setState(() => filterMode = mode),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Category', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in categories)
                      ChoiceChip(
                        label: Text(c),
                        selected: category == c,
                        onSelected: (_) => setState(() => category = c),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Difficulty', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: difficulty == 0,
                      onSelected: (_) => setState(() => difficulty = 0),
                    ),
                    for (final level in [1, 2, 3, 4, 5])
                      ChoiceChip(
                        label: Text('$level'),
                        selected: difficulty == level,
                        onSelected: (_) => setState(() => difficulty = level),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: sessionSize,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Questions per test',
                        ),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5')),
                          DropdownMenuItem(value: 10, child: Text('10')),
                          DropdownMenuItem(value: 20, child: Text('20')),
                          DropdownMenuItem(value: 50, child: Text('50')),
                          DropdownMenuItem(value: -1, child: Text('All')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => sessionSize = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: shuffle,
                        title: const Text('Shuffle'),
                        onChanged: (value) => setState(() => shuffle = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: questions.isEmpty ? null : () => _startQuiz(questions),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Start test (${questions.length} ready)'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Questions: ${widget.store.totalQuestions} • Sessions: ${widget.store.totalSessions} • Accuracy: ${(widget.store.accuracy * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (questions.isEmpty)
          const _EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No matching questions',
            subtitle: 'Import JSON or load the demo bank from the menu.',
          )
        else
          ...questions.take(10).map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: QuestionSummaryCard(
                    question: q,
                    subtitle: _summaryLine(q),
                    trailing: IconButton(
                      icon: Icon(q.favorite ? Icons.star : Icons.star_border),
                      color: q.favorite ? Colors.amber : null,
                      onPressed: () => widget.store.toggleFavorite(q.id),
                    ),
                    onTap: () => _showQuestionDialog(context, widget.store, q),
                  ),
                ),
              ),
        if (questions.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Showing 10 of ${questions.length} matching question(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  String _summaryLine(TestQuestion q) {
    final accuracy = (q.accuracy * 100).toStringAsFixed(1);
    final avgTime = q.seenCount == 0 ? 0.0 : q.totalTimeMs / q.seenCount / 1000.0;
    return '${q.typeLabel} • D${q.difficulty} • Seen ${q.seenCount} • $accuracy% correct • ${avgTime.toStringAsFixed(1)}s avg';
  }
}

class LibraryPage extends StatefulWidget {
  final AppStore store;

  const LibraryPage({super.key, required this.store});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController searchController = TextEditingController();
  String category = 'All';
  bool favoritesOnly = false;
  bool weakOnly = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<TestQuestion> _filteredQuestions() {
    final query = _normalize(searchController.text);
    return widget.store.questions.where((q) {
      if (category != 'All' && q.category != category) return false;
      if (favoritesOnly && !q.favorite) return false;
      if (weakOnly && !(q.scoredCount >= 3 && q.accuracy < 0.7)) return false;
      if (query.isEmpty) return true;

      final haystack = <String>[
        q.prompt,
        q.explanation,
        q.category,
        q.subcategory,
        q.tags.join(' '),
        q.correctAnswerDisplay(),
        q.typeLabel,
      ].join(' ');
      return _normalize(haystack).contains(query);
    }).toList()
      ..sort((a, b) {
        final c = a.category.toLowerCase().compareTo(b.category.toLowerCase());
        if (c != 0) return c;
        return b.seenCount.compareTo(a.seenCount);
      });
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>['All', ...widget.store.categories];
    final questions = _filteredQuestions();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search the question bank...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: favoritesOnly,
                          title: const Text('Favorites'),
                          onChanged: (value) => setState(() => favoritesOnly = value),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: weakOnly,
                          title: const Text('Weak only'),
                          onChanged: (value) => setState(() => weakOnly = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in categories)
                          ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (_) => setState(() => category = c),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${questions.length} visible • ${widget.store.totalQuestions} total',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: questions.isEmpty
              ? const _EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No questions here yet',
                  subtitle: 'Import JSON or load the demo bank from the menu.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: questions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final q = questions[index];
                    return QuestionSummaryCard(
                      question: q,
                      subtitle: _summaryLine(q),
                      trailing: IconButton(
                        icon: Icon(q.favorite ? Icons.star : Icons.star_border),
                        color: q.favorite ? Colors.amber : null,
                        onPressed: () => widget.store.toggleFavorite(q.id),
                      ),
                      onTap: () => _showQuestionDialog(context, widget.store, q),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _summaryLine(TestQuestion q) {
    return '${q.category} • ${q.typeLabel} • D${q.difficulty} • Seen ${q.seenCount} • ${(q.accuracy * 100).toStringAsFixed(1)}% correct';
  }
}

class StatsPage extends StatelessWidget {
  final AppStore store;

  const StatsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.totalQuestions == 0 && store.totalSessions == 0) {
      return const _EmptyState(
        icon: Icons.query_stats_outlined,
        title: 'No stats yet',
        subtitle: 'Load questions and take a test to build analytics.',
      );
    }

    final categoryBuckets = store.categoryBuckets();
    final difficultyBuckets = store.difficultyBuckets();
    final typeBuckets = store.typeBuckets();

    final topCategories = categoryBuckets.entries.toList()
      ..sort((a, b) => b.value.attempts.compareTo(a.value.attempts));

    final weakCategories = categoryBuckets.entries
        .where((e) => e.value.scored >= 3)
        .toList()
      ..sort((a, b) => a.value.accuracy.compareTo(b.value.accuracy));

    final recentSessions = store.recentSessions(10);

    final maxCategoryAttempts = topCategories.isEmpty
        ? 1.0
        : topCategories.first.value.attempts.toDouble();
    final maxDifficultyAttempts = difficultyBuckets.values.isEmpty
        ? 1.0
        : difficultyBuckets.values.map((e) => e.attempts).reduce((a, b) => a > b ? a : b).toDouble();
    final maxTypeAttempts = typeBuckets.values.isEmpty
        ? 1.0
        : typeBuckets.values.map((e) => e.attempts).reduce((a, b) => a > b ? a : b).toDouble();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(label: 'Questions', value: '${store.totalQuestions}', icon: Icons.quiz_outlined),
            _MetricCard(label: 'Sessions', value: '${store.totalSessions}', icon: Icons.history_edu_outlined),
            _MetricCard(label: 'Accuracy', value: '${(store.accuracy * 100).toStringAsFixed(1)}%', icon: Icons.check_circle_outline),
            _MetricCard(label: 'Avg time', value: '${store.avgQuestionTimeSeconds.toStringAsFixed(1)}s', icon: Icons.schedule_outlined),
            _MetricCard(label: 'Scored', value: '${store.totalScoredAttempts}', icon: Icons.fact_check_outlined),
            _MetricCard(label: 'Skipped', value: '${store.totalSkippedAttempts}', icon: Icons.do_not_disturb_on_outlined),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Top categories'),
                const SizedBox(height: 12),
                if (topCategories.isEmpty)
                  const Text('No category stats yet.')
                else
                  ...topCategories.take(6).map(
                        (entry) => _BarRow(
                          label: entry.key,
                          valueText: '${entry.value.attempts} attempts • ${(entry.value.accuracy * 100).toStringAsFixed(1)}%',
                          fraction: entry.value.attempts / maxCategoryAttempts,
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Difficulty distribution'),
                const SizedBox(height: 12),
                if (difficultyBuckets.isEmpty)
                  const Text('No difficulty stats yet.')
                else
                  ...difficultyBuckets.entries.map(
                        (entry) => _BarRow(
                          label: 'Level ${entry.key}',
                          valueText: '${entry.value.attempts} attempts • ${(entry.value.accuracy * 100).toStringAsFixed(1)}%',
                          fraction: entry.value.attempts / maxDifficultyAttempts,
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Question types'),
                const SizedBox(height: 12),
                if (typeBuckets.isEmpty)
                  const Text('No type stats yet.')
                else
                  ...typeBuckets.entries.map(
                        (entry) => _BarRow(
                          label: entry.key.label,
                          valueText: '${entry.value.attempts} attempts • ${(entry.value.accuracy * 100).toStringAsFixed(1)}%',
                          fraction: entry.value.attempts / maxTypeAttempts,
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Weakest categories'),
                const SizedBox(height: 12),
                if (weakCategories.isEmpty)
                  const Text('Need more practice data first.')
                else
                  ...weakCategories.take(5).map(
                        (entry) => _BarRow(
                          label: entry.key,
                          valueText: '${(entry.value.accuracy * 100).toStringAsFixed(1)}% accuracy',
                          fraction: entry.value.accuracy.clamp(0.0, 1.0),
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Recent sessions'),
                const SizedBox(height: 12),
                if (recentSessions.isEmpty)
                  const Text('No sessions yet.')
                else
                  ...recentSessions.map(
                        (session) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101A35),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.history),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        session.modeLabel,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${session.totalQuestions} q • ${(session.accuracy * 100).toStringAsFixed(1)}% • ${_formatDuration(session.totalTimeMs)}',
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _dateLabel(session.startedAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class QuizPage extends StatefulWidget {
  final AppStore store;
  final List<TestQuestion> questions;
  final String modeLabel;

  const QuizPage({
    super.key,
    required this.store,
    required this.questions,
    required this.modeLabel,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final DateTime startedAt;
  late final Stopwatch stopwatch;
  late final TextEditingController answerController;

  int index = 0;
  bool completed = false;
  bool sessionSaved = false;

  final Set<int> selectedIndexes = <int>{};
  final List<QuestionAttempt> attempts = <QuestionAttempt>[];

  bool? lastCorrect;
  String feedback = '';
  String selectedText = '';

  @override
  void initState() {
    super.initState();
    startedAt = DateTime.now();
    stopwatch = Stopwatch()..start();
    answerController = TextEditingController();
  }

  @override
  void dispose() {
    stopwatch.stop();
    answerController.dispose();
    super.dispose();
  }

  TestQuestion get question => widget.questions[index];

  bool get isLast => index == widget.questions.length - 1;

  bool get hasOptions => question.options.isNotEmpty;

  bool get canSubmit {
    if (lastCorrect != null) return true;
    if (hasOptions) {
      return selectedIndexes.isNotEmpty;
    }
    if (question.type == QuestionType.essay) return true;
    return answerController.text.trim().isNotEmpty;
  }

  void _resetAnswerState() {
    selectedIndexes.clear();
    answerController.clear();
    lastCorrect = null;
    feedback = '';
    selectedText = '';
    stopwatch
      ..reset()
      ..start();
  }

  void _submit({required bool skip}) {
    stopwatch.stop();

    final result = _evaluate(
      question,
      skip: skip,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );

    attempts.add(result);

    setState(() {
      lastCorrect = result.correct;
      feedback = result.note;
      selectedText = result.selectedValues.join(', ');
    });
  }

  QuestionAttempt _evaluate(
    TestQuestion q, {
    required bool skip,
    required int elapsedMs,
  }) {
    if (skip) {
      return QuestionAttempt(
        questionId: q.id,
        selectedValues: const <String>[],
        correct: null,
        scored: false,
        timeSpentMs: elapsedMs,
        correctAnswerDisplay: q.correctAnswerDisplay(),
        note: 'Skipped. Correct answer: ${q.correctAnswerDisplay()}',
      );
    }

    if (q.type == QuestionType.essay) {
      final typed = answerController.text.trim();
      return QuestionAttempt(
        questionId: q.id,
        selectedValues: typed.isEmpty ? const <String>[] : <String>[typed],
        correct: null,
        scored: false,
        timeSpentMs: elapsedMs,
        correctAnswerDisplay: q.correctAnswerDisplay(),
        note: 'Saved as review. Model answer: ${q.correctAnswerDisplay()}',
      );
    }

    if (q.type == QuestionType.numeric) {
      final typed = answerController.text.trim();
      final entered = double.tryParse(typed.replaceAll(',', '.'));
      final answers = q.correctAnswers
          .map((e) => double.tryParse(e.replaceAll(',', '.')))
          .whereType<double>()
          .toList();

      bool? correct;
      if (entered != null && answers.isNotEmpty) {
        final tol = q.tolerance <= 0 ? 0.000001 : q.tolerance;
        correct = answers.any((a) => (a - entered).abs() <= tol);
      } else if (answers.isNotEmpty) {
        correct = false;
      } else {
        final accepted = q.correctAnswers.map(_normalize).toSet();
        correct = accepted.isNotEmpty ? accepted.contains(_normalize(typed)) : null;
      }

      return QuestionAttempt(
        questionId: q.id,
        selectedValues: typed.isEmpty ? const <String>[] : <String>[typed],
        correct: correct,
        scored: correct != null,
        timeSpentMs: elapsedMs,
        correctAnswerDisplay: q.correctAnswerDisplay(),
        note: correct == true
            ? 'Correct.'
            : 'Correct answer: ${q.correctAnswerDisplay()}',
      );
    }

    if (q.type == QuestionType.shortAnswer) {
      final typed = answerController.text.trim();
      final accepted = q.correctAnswers.map(_normalize).toSet();
      bool? correct;
      if (accepted.isNotEmpty) {
        correct = accepted.contains(_normalize(typed));
      } else {
        correct = null;
      }

      return QuestionAttempt(
        questionId: q.id,
        selectedValues: typed.isEmpty ? const <String>[] : <String>[typed],
        correct: correct,
        scored: correct != null,
        timeSpentMs: elapsedMs,
        correctAnswerDisplay: q.correctAnswerDisplay(),
        note: correct == true
            ? 'Correct.'
            : 'Correct answer: ${q.correctAnswerDisplay()}',
      );
    }

    final chosenIndexes = selectedIndexes.toList()..sort();
    final chosenTexts = chosenIndexes
        .where((i) => i >= 0 && i < q.options.length)
        .map((i) => q.options[i])
        .toList();

    final correctIndexes = q.correctOptionIndexes();
    bool? correct;
    if (q.options.isNotEmpty && correctIndexes.isNotEmpty) {
      correct = _sameSet<int>(chosenIndexes.toSet(), correctIndexes.toSet());
    } else if (q.correctAnswers.isNotEmpty) {
      final selectedNorm = chosenTexts.map(_normalize).toSet();
      final answerNorm = q.correctAnswers.map(_normalize).toSet();
      correct = _sameSet<String>(selectedNorm, answerNorm);
    } else {
      correct = null;
    }

    return QuestionAttempt(
      questionId: q.id,
      selectedValues: chosenTexts,
      correct: correct,
      scored: correct != null,
      timeSpentMs: elapsedMs,
      correctAnswerDisplay: q.correctAnswerDisplay(),
      note: correct == true
          ? 'Correct.'
          : 'Correct answer: ${q.correctAnswerDisplay()}',
    );
  }

  void _next() {
    if (index + 1 < widget.questions.length) {
      setState(() {
        index += 1;
        _resetAnswerState();
      });
    } else {
      _finish();
    }
  }

  void _finish() {
    stopwatch.stop();
    if (!sessionSaved) {
      widget.store.recordSession(
        SessionReport(
          id: _newId('session'),
          modeLabel: widget.modeLabel,
          startedAt: startedAt,
          endedAt: DateTime.now(),
          attempts: List<QuestionAttempt>.from(attempts),
        ),
      );
      sessionSaved = true;
    }
    setState(() => completed = true);
  }

  Widget _choiceTile({
    required int idx,
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: lastCorrect != null ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A2152) : const Color(0xFF101A35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.deepPurpleAccent : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (completed) {
      final scored = attempts.where((a) => a.scored).length;
      final correct = attempts.where((a) => a.scored && a.correct == true).length;
      final accuracy = scored == 0 ? 0.0 : correct / scored.toDouble();
      final totalTime = attempts.fold<int>(0, (sum, a) => sum + a.timeSpentMs);

      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_outlined, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'Test complete',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  _MetricCard(
                    label: 'Score',
                    value: '$correct / $scored',
                    icon: Icons.grade_outlined,
                  ),
                  const SizedBox(height: 12),
                  _MetricCard(
                    label: 'Accuracy',
                    value: '${(accuracy * 100).toStringAsFixed(1)}%',
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(height: 12),
                  _MetricCard(
                    label: 'Time',
                    value: _formatDuration(totalTime),
                    icon: Icons.schedule_outlined,
                  ),
                  const SizedBox(height: 16),
                  Text(widget.modeLabel, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final q = question;
    final openEnded = !hasOptions ||
        q.type == QuestionType.numeric ||
        q.type == QuestionType.shortAnswer ||
        q.type == QuestionType.essay;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (widget.questions.isEmpty ? 0 : (index + 1) / widget.questions.length)
                      .clamp(0.0, 1.0),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('${index + 1}/${widget.questions.length}')),
                    Chip(label: Text(q.typeLabel)),
                    Chip(label: Text('D${q.difficulty}')),
                    Chip(label: Text(_formatDuration(stopwatch.elapsedMilliseconds))),
                  ],
                ),
                const SizedBox(height: 16),
                RichBody(text: q.prompt),
                const SizedBox(height: 16),
                if (q.options.isNotEmpty && q.type == QuestionType.multiSelect) ...[
                  for (var i = 0; i < q.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: selectedIndexes.contains(i),
                        onChanged: lastCorrect != null
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedIndexes.add(i);
                                  } else {
                                    selectedIndexes.remove(i);
                                  }
                                });
                              },
                        title: Text(q.options[i]),
                        controlAffinity: ListTileControlAffinity.leading,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        tileColor: const Color(0xFF101A35),
                      ),
                    ),
                ] else if (q.options.isNotEmpty) ...[
                  for (var i = 0; i < q.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _choiceTile(
                        idx: i,
                        text: q.options[i],
                        selected: selectedIndexes.contains(i),
                        onTap: () {
                          setState(() {
                            selectedIndexes
                              ..clear()
                              ..add(i);
                          });
                        },
                      ),
                    ),
                ] else
                  TextField(
                    controller: answerController,
                    enabled: lastCorrect == null,
                    minLines: q.type == QuestionType.essay ? 6 : 1,
                    maxLines: q.type == QuestionType.essay ? 10 : 4,
                    keyboardType: q.type == QuestionType.numeric
                        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: q.type == QuestionType.essay
                          ? 'Write your response...'
                          : 'Type your answer...',
                    ),
                  ),
                const SizedBox(height: 16),
                if (lastCorrect != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (lastCorrect == true
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.red.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: lastCorrect == true ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lastCorrect == true
                              ? 'Correct'
                              : (q.type == QuestionType.essay ? 'Saved for review' : 'Incorrect'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(feedback),
                        if (selectedText.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Your answer: $selectedText'),
                        ],
                        if (q.explanation.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Explanation',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          RichBody(text: q.explanation),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: lastCorrect != null ? _next : () => _submit(skip: true),
                        child: Text(lastCorrect != null ? (isLast ? 'Finish' : 'Next') : 'Skip'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: lastCorrect != null
                            ? (isLast ? _finish : _next)
                            : (canSubmit ? () => _submit(skip: false) : null),
                        child: Text(
                          lastCorrect != null
                              ? (isLast ? 'Finish test' : 'Next question')
                              : (q.type == QuestionType.essay ? 'Save response' : 'Submit'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class QuestionSummaryCard extends StatelessWidget {
  final TestQuestion question;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const QuestionSummaryCard({
    super.key,
    required this.question,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = question.prompt.replaceAll('\n', ' ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Text(
                  question.typeLabel.substring(0, question.typeLabel.length > 2 ? 2 : 1).toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class RichBody extends StatelessWidget {
  final String text;

  const RichBody({super.key, required this.text});

  TextSpan _inlineSpan(BuildContext context, String input) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`|\*[^*\n]+\*)');
    var index = 0;

    for (final match in regex.allMatches(input)) {
      if (match.start > index) {
        spans.add(TextSpan(text: input.substring(index, match.start), style: base));
      }

      final token = input.substring(match.start, match.end);
      if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: base.copyWith(fontWeight: FontWeight.w800),
          ),
        );
      } else if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: base.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0x22111111),
            ),
          ),
        );
      } else if (token.startsWith('*')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      index = match.end;
    }

    if (index < input.length) {
      spans.add(TextSpan(text: input.substring(index), style: base));
    }

    return TextSpan(style: base, children: spans);
  }

  Widget _codeBox(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101A35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: SelectableText(
        content,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }

  Widget _bulletList(BuildContext context, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• '),
                Expanded(
                  child: RichText(
                    text: _inlineSpan(context, line.trimLeft().replaceFirst(RegExp(r'^[-*]\s+'), '')),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleaned = _cleanText(text);
    if (cleaned.isEmpty) return const SizedBox.shrink();

    final blocks = cleaned.split(RegExp(r'\n{2,}'));
    final widgets = <Widget>[];

    for (final rawBlock in blocks) {
      final block = rawBlock.trim();
      if (block.isEmpty) continue;

      if (block.startsWith('$$') && block.endsWith('$$') && block.length > 4) {
        widgets.add(_codeBox(block.substring(2, block.length - 2).trim()));
        continue;
      }

      if (block.startsWith('```') && block.endsWith('```') && block.length > 6) {
        widgets.add(_codeBox(block.substring(3, block.length - 3).trim()));
        continue;
      }

      final lines = block.split('\n');
      if (lines.length > 1 &&
          lines.every((line) => line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* '))) {
        widgets.add(_bulletList(context, lines));
        continue;
      }

      if (block.startsWith('#')) {
        final title = block.replaceFirst(RegExp(r'^#+\s*'), '');
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        );
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RichText(
            text: _inlineSpan(context, block),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final String valueText;
  final double fraction;

  const _BarRow({
    required this.label,
    required this.valueText,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(valueText, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showQuestionDialog(BuildContext context, AppStore store, TestQuestion q) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final jsonText = const JsonEncoder.withIndent('  ').convert(q.toJson());

      return AlertDialog(
        title: Text(q.typeLabel),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichBody(text: q.prompt),
                const SizedBox(height: 16),
                if (q.options.isNotEmpty) ...[
                  const Text('Options', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final option in q.options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $option'),
                    ),
                  const SizedBox(height: 10),
                ],
                const Text('Answer', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(q.correctAnswerDisplay()),
                const SizedBox(height: 12),
                if (q.explanation.isNotEmpty) ...[
                  const Text('Explanation', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  RichBody(text: q.explanation),
                  const SizedBox(height: 12),
                ],
                Text('Category: ${q.category}'),
                Text('Subcategory: ${q.subcategory.isEmpty ? '—' : q.subcategory}'),
                Text('Difficulty: ${q.difficulty}'),
                Text('Seen: ${q.seenCount}'),
                Text('Accuracy: ${(q.accuracy * 100).toStringAsFixed(1)}%'),
                const SizedBox(height: 12),
                const Text('Question JSON', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101A35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SelectableText(
                    jsonText,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Question JSON copied.')),
                );
              }
            },
            child: const Text('Copy JSON'),
          ),
          FilledButton.tonal(
            onPressed: () {
              store.toggleFavorite(q.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(q.favorite ? 'Unstar' : 'Star'),
          ),
          FilledButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete question?'),
                  content: const Text('This removes the question from the bank.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                store.deleteQuestion(q.id);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
}

String _formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours}:$minutes:$seconds';
  }
  final minutes = duration.inMinutes.toString();
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _dateLabel(DateTime time) {
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

T _sameSet<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

String _firstNonEmptyString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (!map.containsKey(key)) continue;
    final value = _asString(map[key]).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TestTakingApp());
}

const String kDemoStateJson = '''
{
  "questions": [
    {
      "id": "math-1",
      "category": "Mathematics",
      "subcategory": "Algebra",
      "type": "multipleChoice",
      "difficulty": 2,
      "prompt": "Solve the equation: $$x^2 - 5x + 6 = 0$$\\n\\nChoose the correct pair of roots.",
      "options": ["1 and 6", "2 and 3", "3 and 4", "0 and 6"],
      "answer": [1],
      "explanation": "Factor it as (x - 2)(x - 3) = 0, so the roots are 2 and 3.",
      "tags": ["algebra", "roots"]
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
      "difficulty": 3,
      "prompt": "Fill in the blank: A concise answer is the opposite of a ____ answer.",
      "answer": ["verbose", "wordy"],
      "explanation": "Both 'verbose' and 'wordy' are acceptable."
    },
    {
      "id": "gen-1",
      "category": "General Knowledge",
      "subcategory": "Current Affairs",
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
      "difficulty": 2,
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
        return 'True/False';
      case QuestionType.numeric:
        return 'Numeric';
      case QuestionType.shortAnswer:
        return 'Short answer';
      case QuestionType.essay:
        return 'Essay';
    }
  }
}

String _newId([String prefix = 'id']) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

String _cleanText(String input) {
  return input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
}

String _normalize(String input) {
  return _cleanText(input)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

String _stringOf(dynamic value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value.map(_stringOf).where((e) => e.isNotEmpty).join('\n');
  }
  if (value is Map) {
    return value.entries
        .map((e) => '${e.key}: ${_stringOf(e.value)}')
        .where((e) => e.trim().isNotEmpty)
        .join('\n');
  }
  return value.toString();
}

Map<String, dynamic> _mapOf(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value as Map);
  }
  return <String, dynamic>{};
}

List<String> _stringListOf(dynamic value) {
  if (value == null) return <String>[];
  if (value is List) {
    return value
        .map(_stringOf)
        .map((e) => e.trim())
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
  return <String>[_stringOf(value)].where((e) => e.trim().isNotEmpty).toList();
}

bool _boolOf(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final s = value.trim().toLowerCase();
    return s == 'true' || s == 'yes' || s == '1' || s == 'y';
  }
  return false;
}

int _intOf(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    final n = int.tryParse(value.trim());
    if (n != null) return n;
    final d = double.tryParse(value.trim());
    if (d != null) return d.round();
  }
  return fallback;
}

double _doubleOf(dynamic value, [double fallback = 0]) {
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
  final raw = _stringOf(value).toLowerCase().trim();
  if (raw.isEmpty) return 3;
  if (raw == 'easy') return 1;
  if (raw == 'medium' || raw == 'normal') return 3;
  if (raw == 'hard') return 5;
  if (raw == 'very hard' || raw == 'extreme') return 5;
  final n = int.tryParse(raw);
  if (n != null) return n.clamp(1, 5);
  final d = double.tryParse(raw);
  if (d != null) return d.round().clamp(1, 5);
  return 3;
}

QuestionType _parseQuestionType(
  String? rawType,
  List<String> options,
  List<String> answers,
  String prompt,
) {
  final t = _normalize(rawType ?? '');
  final p = _normalize(prompt);

  if (t.contains('essay') || t.contains('long') || t.contains('freeform')) {
    return QuestionType.essay;
  }
  if (t.contains('multi') || t.contains('select') || t.contains('checkbox')) {
    return QuestionType.multiSelect;
  }
  if (t.contains('true') && t.contains('false')) {
    return QuestionType.trueFalse;
  }
  if (t.contains('numeric') ||
      t.contains('number') ||
      t.contains('math') ||
      t.contains('calculation') ||
      t.contains('calc')) {
    return QuestionType.numeric;
  }
  if (t.contains('short') || t.contains('fill') || t.contains('open')) {
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

List<String> _parseOptionsFromMap(Map<String, dynamic> json) {
  final listKeys = <String>[
    'options',
    'choices',
    'variants',
    'answersChoices',
    'answerChoices',
    'optionList',
  ];
  for (final key in listKeys) {
    final value = json[key];
    if (value is List) {
      final options = value
          .map(_stringOf)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (options.isNotEmpty) return options;
    }
  }

  final entries = <MapEntry<int, String>>[];
  final orderedKeys = <String>[
    'option1',
    'option2',
    'option3',
    'option4',
    'option5',
    'option6',
    'option7',
    'option8',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
  ];

  for (final key in orderedKeys) {
    if (json.containsKey(key)) {
      final text = _stringOf(json[key]).trim();
      if (text.isNotEmpty) {
        entries.add(MapEntry(entries.length, text));
      }
    }
  }

  return entries.map((e) => e.value).toList();
}

List<String> _parseAnswersFromMap(Map<String, dynamic> json) {
  final keys = <String>[
    'answer',
    'answers',
    'correct',
    'correctAnswer',
    'correctAnswers',
    'solutionAnswer',
    'response',
  ];
  for (final key in keys) {
    final value = json[key];
    final answers = _stringListOf(value);
    if (answers.isNotEmpty) return answers;
  }
  return <String>[];
}

String _firstText(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (!map.containsKey(key)) continue;
    final value = _stringOf(map[key]).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

dynamic _firstValue(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (map.containsKey(key)) return map[key];
  }
  return null;
}

bool _sameSet<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
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

  Map<String, dynamic> toJson() => {
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
      questionId: _stringOf(json['questionId']),
      selectedValues: _stringListOf(json['selectedValues']),
      correct: json['correct'] as bool?,
      scored: _boolOf(json['scored']),
      timeSpentMs: _intOf(json['timeSpentMs']),
      correctAnswerDisplay: _stringOf(json['correctAnswerDisplay']),
      note: _stringOf(json['note']),
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
  int get unansweredCount => attempts.where((a) => !a.scored).length;
  int get totalTimeMs =>
      attempts.fold<int>(0, (sum, attempt) => sum + attempt.timeSpentMs);

  double get accuracy =>
      scoredCount == 0 ? 0 : correctCount / scoredCount.toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'modeLabel': modeLabel,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'attempts': attempts.map((e) => e.toJson()).toList(),
      };

  factory SessionReport.fromJson(Map<String, dynamic> json) {
    return SessionReport(
      id: _stringOf(json['id']),
      modeLabel: _stringOf(json['modeLabel']),
      startedAt: DateTime.tryParse(_stringOf(json['startedAt'])) ?? DateTime.now(),
      endedAt: DateTime.tryParse(_stringOf(json['endedAt'])) ?? DateTime.now(),
      attempts: (_firstValue(json, ['attempts']) as List? ?? const [])
          .map((e) => QuestionAttempt.fromJson(_mapOf(e)))
          .toList(),
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

  int seenCount;
  int scoredCount;
  int correctCount;
  int unscoredCount;
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
    required this.seenCount,
    required this.scoredCount,
    required this.correctCount,
    required this.unscoredCount,
    required this.totalTimeMs,
    required this.lastAttemptAt,
  });

  factory TestQuestion.fromFlexibleJson(dynamic raw, {String? fallbackId}) {
    if (raw is String) {
      raw = {'prompt': raw};
    }

    final map = _mapOf(raw);
    final prompt = _firstText(
      map,
      const [
        'prompt',
        'question',
        'stem',
        'text',
        'body',
        'content',
        'statement',
        'title',
      ],
    );

    final explanation = _firstText(
      map,
      const [
        'explanation',
        'solution',
        'rationale',
        'details',
        'answerExplanation',
        'hint',
      ],
    );

    final options = _parseOptionsFromMap(map);
    final answers = _parseAnswersFromMap(map);

    final type = _parseQuestionType(
      _firstText(map, const ['type', 'questionType', 'format', 'kind']),
      options,
      answers,
      prompt,
    );

    final id = _firstText(map, const ['id', 'questionId', 'qid', 'uuid']);
    final category = _firstText(
      map,
      const ['category', 'subject', 'testCategory', 'section', 'paper'],
    );
    final subcategory = _firstText(
      map,
      const ['subcategory', 'topic', 'chapter', 'unit', 'skill'],
    );
    final tags = <String>{
      ..._stringListOf(_firstValue(map, const ['tags', 'labels', 'keywords'])),
      if (category.isNotEmpty) category,
      if (subcategory.isNotEmpty) subcategory,
    }.toList();

    return TestQuestion(
      id: id.isNotEmpty ? id : (fallbackId ?? _newId('q')),
      prompt: prompt.isNotEmpty ? prompt : 'Untitled question',
      explanation: explanation,
      category: category.isNotEmpty ? category : 'General',
      subcategory: subcategory,
      type: type,
      difficulty: _difficultyOf(_firstValue(map, const ['difficulty', 'level', 'tier'])),
      options: options,
      correctAnswers: answers,
      tags: tags,
      favorite: _boolOf(_firstValue(map, const ['favorite', 'starred'])),
      seenCount: _intOf(_firstValue(map, const ['seenCount', 'timesSeen']), 0),
      scoredCount: _intOf(_firstValue(map, const ['scoredCount', 'timesScored']), 0),
      correctCount: _intOf(_firstValue(map, const ['correctCount', 'timesCorrect']), 0),
      unscoredCount: _intOf(_firstValue(map, const ['unscoredCount', 'timesSkipped']), 0),
      totalTimeMs: _intOf(_firstValue(map, const ['totalTimeMs', 'timeSpentMs']), 0),
      lastAttemptAt: DateTime.tryParse(_stringOf(_firstValue(
        map,
        const ['lastAttemptAt', 'lastSeenAt'],
      ))),
    );
  }

  factory TestQuestion.fromJson(Map<String, dynamic> json) {
    return TestQuestion(
      id: _stringOf(json['id']).isNotEmpty ? _stringOf(json['id']) : _newId('q'),
      prompt: _stringOf(json['prompt']).isNotEmpty ? _stringOf(json['prompt']) : 'Untitled question',
      explanation: _stringOf(json['explanation']),
      category: _stringOf(json['category']).isNotEmpty ? _stringOf(json['category']) : 'General',
      subcategory: _stringOf(json['subcategory']),
      type: QuestionType.values.firstWhere(
        (e) => e.name == _stringOf(json['type']),
        orElse: () => QuestionType.shortAnswer,
      ),
      difficulty: _difficultyOf(json['difficulty']),
      options: _stringListOf(json['options']),
      correctAnswers: _stringListOf(json['correctAnswers']),
      tags: _stringListOf(json['tags']),
      favorite: _boolOf(json['favorite']),
      seenCount: _intOf(json['seenCount']),
      scoredCount: _intOf(json['scoredCount']),
      correctCount: _intOf(json['correctCount']),
      unscoredCount: _intOf(json['unscoredCount']),
      totalTimeMs: _intOf(json['totalTimeMs']),
      lastAttemptAt: DateTime.tryParse(_stringOf(json['lastAttemptAt'])),
    );
  }

  void applyAttempt(QuestionAttempt attempt, DateTime at) {
    seenCount += 1;
    totalTimeMs += attempt.timeSpentMs;
    lastAttemptAt = at;
    if (!attempt.scored) {
      unscoredCount += 1;
      return;
    }
    scoredCount += 1;
    if (attempt.correct == true) {
      correctCount += 1;
    }
  }

  double get accuracy => scoredCount == 0 ? 0 : correctCount / scoredCount.toDouble();

  String get typeLabel => type.label;

  List<int> _correctIndexesForOptionCount(int optionCount) {
    final indexes = <int>{};
    for (final answer in correctAnswers) {
      final token = _normalize(answer);
      if (token.isEmpty) continue;

      final numeric = int.tryParse(token);
      if (numeric != null) {
        if (numeric >= 0 && numeric < optionCount) {
          indexes.add(numeric);
          continue;
        }
        if (numeric >= 1 && numeric <= optionCount) {
          indexes.add(numeric - 1);
          continue;
        }
      }

      if (token.length == 1 && RegExp(r'^[a-z]$').hasMatch(token)) {
        final idx = token.codeUnitAt(0) - 97;
        if (idx >= 0 && idx < optionCount) {
          indexes.add(idx);
        }
      }
    }
    return indexes.toList()..sort();
  }

  String correctAnswerDisplay() {
    if (correctAnswers.isEmpty) return '—';
    if (options.isNotEmpty) {
      final idx = _correctIndexesForOptionCount(options.length);
      if (idx.isNotEmpty) {
        return idx.map((i) => options[i]).join(' • ');
      }
    }
    return correctAnswers.join(' • ');
  }

  Map<String, dynamic> toJson() => {
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
        'seenCount': seenCount,
        'scoredCount': scoredCount,
        'correctCount': correctCount,
        'unscoredCount': unscoredCount,
        'totalTimeMs': totalTimeMs,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      };
}

class BucketStats {
  int attempts;
  int scored;
  int correct;
  int totalTimeMs;

  BucketStats({
    this.attempts = 0,
    this.scored = 0,
    this.correct = 0,
    this.totalTimeMs = 0,
  });

  void add({
    required bool scoredAttempt,
    required bool? correctAttempt,
    required int timeMs,
  }) {
    attempts += 1;
    totalTimeMs += timeMs;
    if (!scoredAttempt) return;
    scored += 1;
    if (correctAttempt == true) correct += 1;
  }

  double get accuracy => scored == 0 ? 0 : correct / scored.toDouble();
  double get avgTimeSeconds => attempts == 0 ? 0 : totalTimeMs / attempts / 1000.0;
}

class AppController extends ChangeNotifier {
  final List<TestQuestion> _questions = <TestQuestion>[];
  final List<SessionReport> _sessions = <SessionReport>[];

  List<TestQuestion> get questions => List.unmodifiable(_questions);
  List<SessionReport> get sessions => List.unmodifiable(_sessions);

  int get totalQuestions => _questions.length;
  int get totalSessions => _sessions.length;
  int get totalAttempts =>
      _sessions.fold<int>(0, (sum, session) => sum + session.totalQuestions);
  int get totalScoredAttempts =>
      _sessions.fold<int>(0, (sum, session) => sum + session.scoredCount);
  int get totalCorrectAttempts =>
      _sessions.fold<int>(0, (sum, session) => sum + session.correctCount);
  int get totalUnscoredAttempts =>
      _sessions.fold<int>(0, (sum, session) => sum + session.unansweredCount);
  int get totalTimeMs =>
      _sessions.fold<int>(0, (sum, session) => sum + session.totalTimeMs);
  double get accuracy =>
      totalScoredAttempts == 0 ? 0 : totalCorrectAttempts / totalScoredAttempts.toDouble();
  double get averageQuestionTimeSeconds =>
      totalAttempts == 0 ? 0 : totalTimeMs / totalAttempts / 1000.0;

  List<String> get categories {
    final set = <String>{};
    for (final question in _questions) {
      set.add(question.category);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  TestQuestion? questionById(String id) {
    for (final question in _questions) {
      if (question.id == id) return question;
    }
    return null;
  }

  void clearAll() {
    _questions.clear();
    _sessions.clear();
    notifyListeners();
  }

  int importFromText(String text, {required bool replaceAll}) {
    final decoded = jsonDecode(text);

    final importedQuestions = <TestQuestion>[];
    final importedSessions = <SessionReport>[];

    if (replaceAll) {
      clearAll();
    }

    if (decoded is List) {
      for (final item in decoded) {
        importedQuestions.add(TestQuestion.fromFlexibleJson(item));
      }
    } else if (decoded is Map<String, dynamic>) {
      final hasQuestions = decoded['questions'] is List;
      final hasSessions = decoded['sessions'] is List;

      if (hasQuestions) {
        for (final item in decoded['questions'] as List) {
          importedQuestions.add(TestQuestion.fromFlexibleJson(item));
        }
      } else if (_looksLikeSingleQuestion(decoded)) {
        importedQuestions.add(TestQuestion.fromFlexibleJson(decoded));
      } else if (decoded['question'] != null) {
        importedQuestions.add(TestQuestion.fromFlexibleJson(decoded['question']));
      }

      if (hasSessions) {
        for (final item in decoded['sessions'] as List) {
          importedSessions.add(SessionReport.fromJson(_mapOf(item)));
        }
      }
    } else if (decoded is String) {
      importedQuestions.add(TestQuestion.fromFlexibleJson(decoded));
    } else {
      throw const FormatException('Unsupported JSON structure.');
    }

    final existingIds = _questions.map((q) => q.id).toSet();
    for (final question in importedQuestions) {
      question.id = _uniqueQuestionId(question.id, existingIds);
      existingIds.add(question.id);
      _questions.add(question);
    }

    for (final session in importedSessions) {
      _sessions.add(session);
    }
    _sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    _rebuildQuestionStatsIfNeeded();
    notifyListeners();
    return importedQuestions.length;
  }

  void loadDemoBank() {
    importFromText(kDemoStateJson, replaceAll: true);
  }

  void toggleFavorite(String questionId) {
    final question = questionById(questionId);
    if (question == null) return;
    question.favorite = !question.favorite;
    notifyListeners();
  }

  void deleteQuestion(String questionId) {
    _questions.removeWhere((q) => q.id == questionId);
    notifyListeners();
  }

  void recordSession(SessionReport session) {
    _sessions.insert(0, session);
    for (final attempt in session.attempts) {
      final question = questionById(attempt.questionId);
      if (question != null) {
        question.applyAttempt(attempt, session.endedAt);
      }
    }
    notifyListeners();
  }

  String exportStateJson() {
    final payload = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'questions': _questions.map((q) => q.toJson()).toList(),
      'sessions': _sessions.map((s) => s.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, BucketStats> categoryBuckets() {
    final buckets = <String, BucketStats>{};
    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        final key = question?.category ?? 'Deleted';
        buckets.putIfAbsent(key, BucketStats());
        buckets[key]!.add(
          scoredAttempt: attempt.scored,
          correctAttempt: attempt.correct,
          timeMs: attempt.timeSpentMs,
        );
      }
    }
    final sortedEntries = buckets.entries.toList()
      ..sort((a, b) => b.value.attempts.compareTo(a.value.attempts));
    return Map<String, BucketStats>.fromEntries(sortedEntries);
  }

  Map<int, BucketStats> difficultyBuckets() {
    final buckets = <int, BucketStats>{};
    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        final key = question?.difficulty ?? 0;
        buckets.putIfAbsent(key, BucketStats());
        buckets[key]!.add(
          scoredAttempt: attempt.scored,
          correctAttempt: attempt.correct,
          timeMs: attempt.timeSpentMs,
        );
      }
    }
    final keys = buckets.keys.toList()..sort();
    return {for (final key in keys) key: buckets[key]!};
  }

  Map<QuestionType, BucketStats> typeBuckets() {
    final buckets = <QuestionType, BucketStats>{};
    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        final key = question?.type ?? QuestionType.shortAnswer;
        buckets.putIfAbsent(key, BucketStats());
        buckets[key]!.add(
          scoredAttempt: attempt.scored,
          correctAttempt: attempt.correct,
          timeMs: attempt.timeSpentMs,
        );
      }
    }
    return buckets;
  }

  List<SessionReport> recentSessions([int limit = 10]) =>
      _sessions.take(limit).toList();

  void _rebuildQuestionStatsIfNeeded() {
    if (_questions.isEmpty || _sessions.isEmpty) return;
    final hasStats = _questions.any(
      (q) => q.seenCount > 0 || q.scoredCount > 0 || q.correctCount > 0 || q.unscoredCount > 0,
    );
    if (hasStats) return;

    for (final session in _sessions.reversed) {
      for (final attempt in session.attempts) {
        final question = questionById(attempt.questionId);
        if (question != null) {
          question.applyAttempt(attempt, session.endedAt);
        }
      }
    }
  }

  bool _looksLikeSingleQuestion(Map<String, dynamic> json) {
    final hasPrompt = json.containsKey('prompt') ||
        json.containsKey('question') ||
        json.containsKey('stem') ||
        json.containsKey('text') ||
        json.containsKey('body');
    final hasAnswer = json.containsKey('answer') ||
        json.containsKey('answers') ||
        json.containsKey('correct') ||
        json.containsKey('correctAnswer');
    return hasPrompt || hasAnswer;
  }

  String _uniqueQuestionId(String baseId, Set<String> existingIds) {
    var candidate = baseId.trim().isEmpty ? _newId('q') : baseId.trim();
    var suffix = 1;
    while (existingIds.contains(candidate) || _questions.any((q) => q.id == candidate)) {
      candidate = '$baseId-$suffix';
      suffix += 1;
    }
    return candidate;
  }
}

class TestTakingApp extends StatelessWidget {
  const TestTakingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ProGrade Test Taker',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0A1020),
        cardTheme: CardTheme(
          color: const Color(0xFF111A33),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: const AppShell(),
    );
  }
}

enum _MenuAction {
  importJson,
  exportState,
  loadDemo,
  clearAll,
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppController controller = AppController();
  late final List<Widget> _pages;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _pages = [
      PracticePage(controller: controller),
      LibraryPage(controller: controller),
      StatsPage(controller: controller),
    ];
  }

  String get _title {
    switch (_tabIndex) {
      case 0:
        return 'Practice';
      case 1:
        return 'Library';
      default:
        return 'Statistics';
    }
  }

  Future<void> _handleMenuAction(_MenuAction action) async {
    switch (action) {
      case _MenuAction.importJson:
        await _showImportDialog();
        break;
      case _MenuAction.exportState:
        await _showExportDialog();
        break;
      case _MenuAction.loadDemo:
        controller.loadDemoBank();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demo bank loaded.')),
          );
        }
        break;
      case _MenuAction.clearAll:
        await _confirmClearAll();
        break;
    }
  }

  Future<void> _showImportDialog() async {
    final textController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Import JSON'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Paste a question list, a single question, or a full export JSON.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    minLines: 10,
                    maxLines: 18,
                    decoration: const InputDecoration(
                      hintText: 'Paste JSON here...',
                      border: OutlineInputBorder(),
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
                    final count = controller.importFromText(
                      textController.text,
                      replaceAll: false,
                    );
                    Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Imported $count questions (merged).')),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Import failed: $e')),
                    );
                  }
                },
                child: const Text('Merge'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    final count = controller.importFromText(
                      textController.text,
                      replaceAll: true,
                    );
                    Navigator.pop(dialogContext);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Imported $count questions (replaced all).')),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
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
      textController.dispose();
    }
  }

  Future<void> _showExportDialog() async {
    final exportText = controller.exportStateJson();
    final textController = TextEditingController(text: exportText);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Export JSON'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                controller: textController,
                minLines: 12,
                maxLines: 20,
                readOnly: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
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
    } finally {
      textController.dispose();
    }
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear everything?'),
          content: const Text(
            'This removes all questions and all sessions from memory.',
          ),
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
      controller.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_title),
            actions: [
              PopupMenuButton<_MenuAction>(
                onSelected: _handleMenuAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _MenuAction.importJson,
                    child: Text('Import JSON'),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.exportState,
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
              index: _tabIndex,
              children: _pages,
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tabIndex,
            onTap: (value) => setState(() => _tabIndex = value),
            type: BottomNavigationBarType.fixed,
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
}

class PracticePage extends StatefulWidget {
  final AppController controller;

  const PracticePage({super.key, required this.controller});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

enum FilterMode {
  all,
  weak,
  unseen,
  favorites,
}

class _PracticePageState extends State<PracticePage> {
  final TextEditingController _searchController = TextEditingController();
  String _category = 'All';
  int _difficulty = 0;
  FilterMode _mode = FilterMode.all;
  int _sessionSize = 10;
  bool _shuffle = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TestQuestion> _filteredQuestions() {
    final query = _normalize(_searchController.text);
    final category = _category;
    final questions = widget.controller.questions.where((q) {
      if (category != 'All' && q.category != category) return false;
      if (_difficulty > 0 && q.difficulty != _difficulty) return false;

      switch (_mode) {
        case FilterMode.all:
          break;
        case FilterMode.weak:
          if (!(q.scoredCount >= 3 && q.accuracy < 0.7)) return false;
          break;
        case FilterMode.unseen:
          if (q.seenCount > 0) return false;
          break;
        case FilterMode.favorites:
          if (!q.favorite) return false;
          break;
      }

      if (query.isEmpty) return true;

      final haystack = <String>[
        q.prompt,
        q.explanation,
        q.category,
        q.subcategory,
        ...q.tags,
        q.correctAnswerDisplay(),
      ].join(' ');
      return _normalize(haystack).contains(query);
    }).toList();

    questions.sort((a, b) {
      final favorites = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
      if (favorites != 0) return favorites;
      return b.seenCount.compareTo(a.seenCount);
    });
    return questions;
  }

  void _startQuiz(List<TestQuestion> questions) {
    final list = List<TestQuestion>.from(questions);
    if (_shuffle) {
      list.shuffle();
    }

    final takeCount = _sessionSize <= 0 || _sessionSize > list.length
        ? list.length
        : _sessionSize;
    final picked = list.take(takeCount).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          controller: widget.controller,
          questions: picked,
          modeLabel: _buildModeLabel(picked.length),
        ),
      ),
    );
  }

  String _buildModeLabel(int count) {
    final parts = <String>[
      if (_mode != FilterMode.all) _mode.name,
      if (_category != 'All') _category,
      if (_difficulty > 0) 'Difficulty $_difficulty',
      if (_shuffle) 'Shuffled',
      '$count questions',
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final questions = _filteredQuestions();
    final categories = <String>['All', ...widget.controller.categories];
    final readyCount = questions.length;

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
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search prompt, tags, category, answer...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in FilterMode.values)
                      ChoiceChip(
                        label: Text(mode.name),
                        selected: _mode == mode,
                        onSelected: (_) => setState(() => _mode = mode),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in categories)
                      ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Difficulty',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _difficulty == 0,
                      onSelected: (_) => setState(() => _difficulty = 0),
                    ),
                    for (final level in [1, 2, 3, 4, 5])
                      ChoiceChip(
                        label: Text(level.toString()),
                        selected: _difficulty == level,
                        onSelected: (_) => setState(() => _difficulty = level),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _sessionSize,
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
                          setState(() => _sessionSize = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _shuffle,
                        title: const Text('Shuffle'),
                        onChanged: (value) => setState(() => _shuffle = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: readyCount == 0 ? null : () => _startQuiz(questions),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Start test ($readyCount ready)'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Questions: ${widget.controller.totalQuestions}  •  Sessions: ${widget.controller.totalSessions}  •  Accuracy: ${(widget.controller.accuracy * 100).toStringAsFixed(1)}%',
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
            subtitle: 'Import JSON or load the demo bank to begin.',
          )
        else
          ...questions.take(10).map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: QuestionSummaryCard(
                    question: q,
                    subtitle: _questionStatsLine(q),
                    trailing: IconButton(
                      icon: Icon(
                        q.favorite ? Icons.star : Icons.star_border,
                        color: q.favorite ? Colors.amber : null,
                      ),
                      onPressed: () => widget.controller.toggleFavorite(q.id),
                    ),
                    onTap: () => _showQuestionDetails(q),
                  ),
                ),
              ),
        if (questions.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Showing 10 of ${questions.length} questions',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  String _questionStatsLine(TestQuestion q) {
    final acc = (q.accuracy * 100).toStringAsFixed(1);
    final avgSec = q.seenCount == 0 ? 0 : q.totalTimeMs / q.seenCount / 1000.0;
    return '${q.typeLabel} • D${q.difficulty} • Seen ${q.seenCount} • $acc% correct • ${avgSec.toStringAsFixed(1)}s avg';
  }

  Future<void> _showQuestionDetails(TestQuestion q) async {
    final controller = widget.controller;
    final jsonText = const JsonEncoder.withIndent('  ').convert(q.toJson());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(q.typeLabel),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichBody(text: q.prompt),
                  const SizedBox(height: 16),
                  if (q.options.isNotEmpty) ...[
                    const Text(
                      'Options',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < q.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• ${q.options[i]}'),
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (q.correctAnswers.isNotEmpty) ...[
                    const Text(
                      'Answer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(q.correctAnswerDisplay()),
                    const SizedBox(height: 12),
                  ],
                  if (q.explanation.isNotEmpty) ...[
                    const Text(
                      'Explanation',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    RichBody(text: q.explanation),
                    const SizedBox(height: 12),
                  ],
                  Text('Category: ${q.category}'),
                  if (q.subcategory.isNotEmpty) Text('Subcategory: ${q.subcategory}'),
                  Text('Difficulty: ${q.difficulty}'),
                  Text('Tags: ${q.tags.join(', ')}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: jsonText),
                    readOnly: true,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Question JSON',
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Question JSON copied.')),
                  );
                }
              },
              child: const Text('Copy JSON'),
            ),
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(dialogContext);
                controller.toggleFavorite(q.id);
              },
              child: Text(q.favorite ? 'Unstar' : 'Star'),
            ),
            FilledButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete question?'),
                    content: const Text('This will remove the question from the bank.'),
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
                  controller.deleteQuestion(q.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Question deleted.')),
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class LibraryPage extends StatefulWidget {
  final AppController controller;

  const LibraryPage({super.key, required this.controller});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _category = 'All';
  bool _favoritesOnly = false;
  bool _showOnlyWeak = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TestQuestion> _filteredQuestions() {
    final query = _normalize(_searchController.text);
    return widget.controller.questions.where((q) {
      if (_category != 'All' && q.category != _category) return false;
      if (_favoritesOnly && !q.favorite) return false;
      if (_showOnlyWeak && !(q.scoredCount >= 3 && q.accuracy < 0.7)) return false;
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
        final cmp = a.category.toLowerCase().compareTo(b.category.toLowerCase());
        if (cmp != 0) return cmp;
        return b.seenCount.compareTo(a.seenCount);
      });
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>['All', ...widget.controller.categories];
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
                    controller: _searchController,
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
                          value: _favoritesOnly,
                          title: const Text('Favorites'),
                          onChanged: (value) => setState(() => _favoritesOnly = value),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _showOnlyWeak,
                          title: const Text('Weak only'),
                          onChanged: (value) => setState(() => _showOnlyWeak = value),
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
                        for (final category in categories)
                          ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: (_) => setState(() => _category = category),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${questions.length} questions visible • ${widget.controller.totalQuestions} total',
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
                      subtitle: _questionStatsLine(q),
                      trailing: IconButton(
                        icon: Icon(
                          q.favorite ? Icons.star : Icons.star_border,
                          color: q.favorite ? Colors.amber : null,
                        ),
                        onPressed: () => widget.controller.toggleFavorite(q.id),
                      ),
                      onTap: () => _showQuestionDetails(q),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _questionStatsLine(TestQuestion q) {
    final acc = (q.accuracy * 100).toStringAsFixed(1);
    return '${q.category} • ${q.typeLabel} • D${q.difficulty} • Seen ${q.seenCount} • $acc% correct';
  }

  Future<void> _showQuestionDetails(TestQuestion q) async {
    final jsonText = const JsonEncoder.withIndent('  ').convert(q.toJson());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(q.category),
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
                    for (var i = 0; i < q.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• ${q.options[i]}'),
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
                  Text('Subcategory: ${q.subcategory.isEmpty ? '—' : q.subcategory}'),
                  Text('Difficulty: ${q.difficulty}'),
                  Text('Seen: ${q.seenCount}'),
                  Text('Accuracy: ${(q.accuracy * 100).toStringAsFixed(1)}%'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(text: jsonText),
                    readOnly: true,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Question JSON',
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Question JSON copied.')),
                  );
                }
              },
              child: const Text('Copy JSON'),
            ),
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(dialogContext);
                widget.controller.toggleFavorite(q.id);
              },
              child: Text(q.favorite ? 'Unstar' : 'Star'),
            ),
            FilledButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
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
                  widget.controller.deleteQuestion(q.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Question deleted.')),
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class StatsPage extends StatelessWidget {
  final AppController controller;

  const StatsPage({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.totalQuestions == 0 && controller.totalSessions == 0) {
      return const _EmptyState(
        icon: Icons.query_stats_outlined,
        title: 'No stats yet',
        subtitle: 'Load questions and take a test to build analytics.',
      );
    }

    final categoryBuckets = controller.categoryBuckets();
    final difficultyBuckets = controller.difficultyBuckets();
    final typeBuckets = controller.typeBuckets();

    final topCategories = categoryBuckets.entries
        .where((e) => e.value.attempts > 0)
        .toList()
      ..sort((a, b) => b.value.attempts.compareTo(a.value.attempts));

    final weakCategories = categoryBuckets.entries
        .where((e) => e.value.scored >= 3)
        .toList()
      ..sort((a, b) => a.value.accuracy.compareTo(b.value.accuracy));

    final recentSessions = controller.recentSessions(10);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(
              label: 'Questions',
              value: controller.totalQuestions.toString(),
              icon: Icons.quiz_outlined,
            ),
            _StatCard(
              label: 'Sessions',
              value: controller.totalSessions.toString(),
              icon: Icons.history_edu_outlined,
            ),
            _StatCard(
              label: 'Accuracy',
              value: '${(controller.accuracy * 100).toStringAsFixed(1)}%',
              icon: Icons.check_circle_outline,
            ),
            _StatCard(
              label: 'Avg time',
              value: '${controller.averageQuestionTimeSeconds.toStringAsFixed(1)}s',
              icon: Icons.schedule_outlined,
            ),
            _StatCard(
              label: 'Scored',
              value: controller.totalScoredAttempts.toString(),
              icon: Icons.fact_check_outlined,
            ),
            _StatCard(
              label: 'Skipped',
              value: controller.totalUnscoredAttempts.toString(),
              icon: Icons.do_not_disturb_on_outlined,
            ),
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
                          valueText:
                              '${entry.value.attempts} attempts • ${(entry.value.accuracy * 100).toStringAsFixed(1)}%',
                          fraction: _barFraction(topCategories.first.value.attempts.toDouble(), entry.value.attempts.toDouble()),
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
                          valueText:
                              '${entry.value.attempts} attempts • ${(entry.value.accuracy * 100).toStringAsFixed(1)}%',
                          fraction: _barFraction(difficultyBuckets.values.map((e) => e.attempts).reduce((a, b) => a > b ? a : b).toDouble(), entry.value.attempts.toDouble()),
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
                          valueText:
                              '${entry.value.attempts} attempts • ${(entry.value.accuracy * 100).toStringAsFixed(1)}%',
                          fraction: _barFraction(typeBuckets.values.map((e) => e.attempts).reduce((a, b) => a > b ? a : b).toDouble(), entry.value.attempts.toDouble()),
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
                          valueText:
                              '${(entry.value.accuracy * 100).toStringAsFixed(1)}% accuracy',
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
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E1730),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(12),
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

  double _barFraction(double max, double value) {
    if (max <= 0) return 0;
    return (value / max).clamp(0.0, 1.0);
  }
}

class QuizPage extends StatefulWidget {
  final AppController controller;
  final List<TestQuestion> questions;
  final String modeLabel;

  const QuizPage({
    super.key,
    required this.controller,
    required this.questions,
    required this.modeLabel,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int _index = 0;
  bool _completed = false;
  late final DateTime _startedAt;
  late final Stopwatch _stopwatch;
  late final TextEditingController _inputController;
  final Set<int> _selectedIndexes = <int>{};
  final List<QuestionAttempt> _attempts = <QuestionAttempt>[];

  bool? _lastCorrect;
  String _feedback = '';
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _stopwatch = Stopwatch()..start();
    _inputController = TextEditingController();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _inputController.dispose();
    super.dispose();
  }

  TestQuestion get _question => widget.questions[_index];

  bool get _isLast => _index == widget.questions.length - 1;

  void _resetAnswerState() {
    _selectedIndexes.clear();
    _selectedText = '';
    _lastCorrect = null;
    _feedback = '';
    _inputController.clear();
    _stopwatch
      ..reset()
      ..start();
    setState(() {});
  }

  void _nextQuestion() {
    if (_index + 1 < widget.questions.length) {
      setState(() {
        _index += 1;
      });
      _resetAnswerState();
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() {
    _stopwatch.stop();
    final report = SessionReport(
      id: _newId('session'),
      modeLabel: widget.modeLabel,
      startedAt: _startedAt,
      endedAt: DateTime.now(),
      attempts: List<QuestionAttempt>.from(_attempts),
    );
    widget.controller.recordSession(report);
    setState(() {
      _completed = true;
    });
  }

  void _submit({required bool skip}) {
    final question = _question;
    final elapsedMs = _stopwatch.elapsedMilliseconds;
    _stopwatch.stop();

    final evaluation = _evaluate(question, skip: skip, elapsedMs: elapsedMs);
    _attempts.add(evaluation);

    setState(() {
      _lastCorrect = evaluation.correct;
      _feedback = evaluation.note;
      _selectedText = evaluation.selectedValues.join(', ');
    });
  }

  QuestionAttempt _evaluate(
    TestQuestion question, {
    required bool skip,
    required int elapsedMs,
  }) {
    if (skip) {
      return QuestionAttempt(
        questionId: question.id,
        selectedValues: const [],
        correct: null,
        scored: false,
        timeSpentMs: elapsedMs,
        correctAnswerDisplay: question.correctAnswerDisplay(),
        note: 'Skipped. Correct answer: ${question.correctAnswerDisplay()}',
      );
    }

    switch (question.type) {
      case QuestionType.multipleChoice:
      case QuestionType.multiSelect:
      case QuestionType.trueFalse:
        final selected = _selectedIndexes.toList()..sort();
        final selectedTexts = selected
            .where((i) => i >= 0 && i < question.options.length)
            .map((i) => question.options[i])
            .toList();

        final correctIndexes = question.options.isNotEmpty
            ? question._correctIndexesForOptionCount(question.options.length)
            : <int>[];

        bool? correct;
        String note;

        if (question.options.isNotEmpty) {
          if (correctIndexes.isNotEmpty) {
            correct = _sameSet(selected.toSet(), correctIndexes.toSet());
          } else if (question.correctAnswers.isNotEmpty) {
            final selectedNorm = selectedTexts.map(_normalize).toSet();
            final correctNorm = question.correctAnswers.map(_normalize).toSet();
            correct = _sameSet(selectedNorm, correctNorm);
          } else {
            correct = null;
          }
          note = correct == true
              ? 'Correct.'
              : 'Correct answer: ${question.correctAnswerDisplay()}';
        } else {
          final typed = _normalize(_inputController.text);
          final accepted = question.correctAnswers.map(_normalize).toSet();
          correct = accepted.isNotEmpty ? accepted.contains(typed) : null;
          note = correct == true
              ? 'Correct.'
              : 'Correct answer: ${question.correctAnswerDisplay()}';
        }

        return QuestionAttempt(
          questionId: question.id,
          selectedValues: selectedTexts,
          correct: correct,
          scored: correct != null,
          timeSpentMs: elapsedMs,
          correctAnswerDisplay: question.correctAnswerDisplay(),
          note: note,
        );

      case QuestionType.numeric:
        final typed = _inputController.text.trim();
        final selectedList = typed.isEmpty ? const <String>[] : <String>[typed];
        final entered = double.tryParse(typed.replaceAll(',', '.'));
        final answers = question.correctAnswers
            .map((e) => double.tryParse(e.replaceAll(',', '.')))
            .whereType<double>()
            .toList();
        final tolerance = 0.000001;

        bool? correct;
        if (entered != null && answers.isNotEmpty) {
          correct = answers.any((a) => (a - entered).abs() <= tolerance);
        } else if (answers.isEmpty) {
          final accepted = question.correctAnswers.map(_normalize).toSet();
          correct = accepted.isNotEmpty ? accepted.contains(_normalize(typed)) : null;
        } else {
          correct = false;
        }

        return QuestionAttempt(
          questionId: question.id,
          selectedValues: selectedList,
          correct: correct,
          scored: correct != null,
          timeSpentMs: elapsedMs,
          correctAnswerDisplay: question.correctAnswerDisplay(),
          note: correct == true
              ? 'Correct.'
              : 'Correct answer: ${question.correctAnswerDisplay()}',
        );

      case QuestionType.shortAnswer:
        final typed = _inputController.text.trim();
        final selectedList = typed.isEmpty ? const <String>[] : <String>[typed];
        final accepted = question.correctAnswers.map(_normalize).toSet();
        bool? correct;
        if (accepted.isNotEmpty) {
          correct = accepted.contains(_normalize(typed));
        } else {
          correct = null;
        }
        return QuestionAttempt(
          questionId: question.id,
          selectedValues: selectedList,
          correct: correct,
          scored: correct != null,
          timeSpentMs: elapsedMs,
          correctAnswerDisplay: question.correctAnswerDisplay(),
          note: correct == true
              ? 'Correct.'
              : 'Correct answer: ${question.correctAnswerDisplay()}',
        );

      case QuestionType.essay:
        final typed = _inputController.text.trim();
        return QuestionAttempt(
          questionId: question.id,
          selectedValues: typed.isEmpty ? const <String>[] : <String>[typed],
          correct: null,
          scored: false,
          timeSpentMs: elapsedMs,
          correctAnswerDisplay: question.correctAnswerDisplay(),
          note: 'Saved as review. Model answer: ${question.correctAnswerDisplay()}',
        );
    }
  }

  Widget _buildOption(int index, String option) {
    final question = _question;
    final isSelected = _selectedIndexes.contains(index);

    if (question.type == QuestionType.multiSelect) {
      return CheckboxListTile(
        value: isSelected,
        onChanged: _lastCorrect != null
            ? null
            : (value) {
                setState(() {
                  if (value == true) {
                    _selectedIndexes.add(index);
                  } else {
                    _selectedIndexes.remove(index);
                  }
                });
              },
        title: Text(option),
        controlAffinity: ListTileControlAffinity.leading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: const Color(0xFF111A33),
      );
    }

    return RadioListTile<int>(
      value: index,
      groupValue: isSelected ? index : (_selectedIndexes.isEmpty ? null : _selectedIndexes.first),
      onChanged: _lastCorrect != null
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                _selectedIndexes
                  ..clear()
                  ..add(value);
              });
            },
      title: Text(option),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: const Color(0xFF111A33),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      final session = widget.controller.sessions.isEmpty ? null : widget.controller.sessions.first;
      final scored = _attempts.where((a) => a.scored).length;
      final correct = _attempts.where((a) => a.scored && a.correct == true).length;
      final accuracy = scored == 0 ? 0.0 : correct / scored.toDouble();
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
                  _StatCard(
                    label: 'Score',
                    value: '$correct / $scored',
                    icon: Icons.grade_outlined,
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    label: 'Accuracy',
                    value: '${(accuracy * 100).toStringAsFixed(1)}%',
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    label: 'Time',
                    value: _formatDuration(_attempts.fold<int>(0, (s, a) => s + a.timeSpentMs)),
                    icon: Icons.schedule_outlined,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    session?.modeLabel ?? widget.modeLabel,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
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

    final question = _question;
    final answered = _lastCorrect != null;
    final isOpenEnded = question.options.isEmpty ||
        question.type == QuestionType.numeric ||
        question.type == QuestionType.shortAnswer ||
        question.type == QuestionType.essay;

    return WillPopScope(
      onWillPop: () async {
        if (_completed) return true;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave quiz?'),
            content: const Text('Your current test will be abandoned.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        return leave == true;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: (widget.questions.isEmpty ? 0 : (_index + 1) / widget.questions.length)
                        .clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Chip(label: Text('${_index + 1}/${widget.questions.length}')),
                      const SizedBox(width: 8),
                      Chip(label: Text(question.typeLabel)),
                      const SizedBox(width: 8),
                      Chip(label: Text('D${question.difficulty}')),
                      const Spacer(),
                      Chip(label: Text(_formatDuration(_stopwatch.elapsedMilliseconds))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RichBody(text: question.prompt),
                  const SizedBox(height: 16),
                  if (question.options.isNotEmpty) ...[
                    for (var i = 0; i < question.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildOption(i, question.options[i]),
                      ),
                  ] else ...[
                    TextField(
                      controller: _inputController,
                      minLines: question.type == QuestionType.essay ? 6 : 1,
                      maxLines: question.type == QuestionType.essay ? 10 : 3,
                      keyboardType: question.type == QuestionType.numeric
                          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: question.type == QuestionType.essay
                            ? 'Write your response...'
                            : 'Type your answer...',
                      ),
                      enabled: !answered,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (answered) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _lastCorrect == true
                            ? Colors.green.withOpacity(0.12)
                            : Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _lastCorrect == true
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lastCorrect == true
                                ? 'Correct'
                                : (question.type == QuestionType.essay ? 'Saved' : 'Incorrect'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(_feedback),
                          if (_selectedText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('Your answer: $_selectedText'),
                          ],
                          if (question.explanation.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Explanation',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            RichBody(text: question.explanation),
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
                          onPressed: answered ? _nextQuestion : () => _submit(skip: true),
                          child: Text(answered ? (_isLast ? 'Finish' : 'Next') : 'Skip'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: answered
                              ? (_isLast ? _finishQuiz : _nextQuestion)
                              : ((question.type == QuestionType.essay)
                                  ? () => _submit(skip: false)
                                  : (isOpenEnded
                                      ? () {
                                          if (_inputController.text.trim().isEmpty) return;
                                          _submit(skip: false);
                                        }
                                      : (_selectedIndexes.isEmpty
                                          ? null
                                          : () => _submit(skip: false)))),
                          child: Text(answered
                              ? (_isLast ? 'Finish test' : 'Next question')
                              : (question.type == QuestionType.essay ? 'Save response' : 'Submit')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    final promptPreview = question.prompt.replaceAll('\n', ' ');
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
                      promptPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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

  Widget _box(BuildContext context, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1730),
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
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
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
        widgets.add(_box(context, block.substring(2, block.length - 2).trim()));
        continue;
      }

      if (block.startsWith('```') && block.endsWith('```') && block.length > 6) {
        widgets.add(_box(context, block.substring(3, block.length - 3).trim()));
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
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
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
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
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int ms) {
  final duration = Duration(milliseconds: ms);
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours}:${minutes}:$seconds';
  }
  final minutes = duration.inMinutes.toString();
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _dateLabel(DateTime time) {
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

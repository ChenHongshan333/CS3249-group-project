import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aggregated reply-time samples and computed medians (in milliseconds).
class ReplyTimeSummary {
  final List<int> llmAskSamples;
  final List<int> localActionSamples;
  final List<int> checkStepLlmSamples;
  final List<int> checkStepTotalSamples;

  const ReplyTimeSummary({
    this.llmAskSamples = const [],
    this.localActionSamples = const [],
    this.checkStepLlmSamples = const [],
    this.checkStepTotalSamples = const [],
  });

  int get llmAskCount => llmAskSamples.length;
  int get localActionCount => localActionSamples.length;
  int get checkStepCount => checkStepLlmSamples.length;

  int? get llmAskMedianMs => ReplyTimeStore.medianMs(llmAskSamples);
  int? get localActionMedianMs => ReplyTimeStore.medianMs(localActionSamples);
  int? get checkStepLlmMedianMs =>
      ReplyTimeStore.medianMs(checkStepLlmSamples);
  int? get checkStepTotalMedianMs =>
      ReplyTimeStore.medianMs(checkStepTotalSamples);

  Map<String, dynamic> toExportMap() => {
    'llmAsk': {
      'count': llmAskCount,
      'medianMs': llmAskMedianMs,
      'samplesMs': llmAskSamples,
    },
    'localAction': {
      'count': localActionCount,
      'medianMs': localActionMedianMs,
      'samplesMs': localActionSamples,
    },
    'checkStep': {
      'count': checkStepCount,
      'llmMedianMs': checkStepLlmMedianMs,
      'totalMedianMs': checkStepTotalMedianMs,
      'llmSamplesMs': checkStepLlmSamples,
      'totalSamplesMs': checkStepTotalSamples,
    },
  };

  String toExportJson() => const JsonEncoder.withIndent('  ').convert(
    toExportMap(),
  );
}

/// Persists end-of-utterance reply-time samples locally in [SharedPreferences]
/// so Profile → Developer can inspect medians across sessions.
class ReplyTimeStore {
  ReplyTimeStore({this.storageKey = defaultStorageKey});

  static const String defaultStorageKey = 'cooktogether.replyTimes.v1';
  static const int maxSamplesPerBucket = 500;

  static final ReplyTimeStore instance = ReplyTimeStore();

  final String storageKey;
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  Future<void> _writeQueue = Future<void>.value();

  /// Returns the median in milliseconds, or null when [samples] is empty.
  static int? medianMs(List<int> samples) {
    if (samples.isEmpty) return null;
    final sorted = List<int>.from(samples)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  Future<ReplyTimeSummary> loadSummary() async {
    await _writeQueue;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decodeSummary(prefs.getString(storageKey));
    } catch (_) {
      return const ReplyTimeSummary();
    }
  }

  Future<void> recordLlmAsk(int ms) => _append((data) {
    _pushCapped(data.llmAsk, ms);
  });

  Future<void> recordLocalAction(int ms) => _append((data) {
    _pushCapped(data.localAction, ms);
  });

  Future<void> recordVisualCheck({required int llmMs, required int totalMs}) =>
      _append((data) {
        _pushCapped(data.checkStepLlm, llmMs);
        _pushCapped(data.checkStepTotal, totalMs);
      });

  Future<void> reset() {
    return _enqueue(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(storageKey);
        version.value++;
      } catch (_) {}
    });
  }

  Future<void> _append(void Function(_MutableBuckets data) mutate) {
    return _enqueue(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final current = _decodeSummary(prefs.getString(storageKey));
        final mutable = _MutableBuckets.fromSummary(current);
        mutate(mutable);
        await prefs.setString(storageKey, jsonEncode(mutable.toJson()));
        version.value++;
      } catch (_) {}
    });
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _writeQueue.then((_) => task(), onError: (_) => task());
    _writeQueue = next.catchError((_) {});
    return next;
  }

  static void _pushCapped(List<int> list, int ms) {
    final clamped = ms < 0 ? 0 : ms;
    list.add(clamped);
    if (list.length > maxSamplesPerBucket) {
      list.removeRange(0, list.length - maxSamplesPerBucket);
    }
  }

  static ReplyTimeSummary _decodeSummary(String? raw) {
    if (raw == null || raw.isEmpty) return const ReplyTimeSummary();
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return const ReplyTimeSummary();
      return ReplyTimeSummary(
        llmAskSamples: _intList(map['llmAsk']),
        localActionSamples: _intList(map['localAction']),
        checkStepLlmSamples: _intList(map['checkStepLlm']),
        checkStepTotalSamples: _intList(map['checkStepTotal']),
      );
    } catch (_) {
      return const ReplyTimeSummary();
    }
  }

  static List<int> _intList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is num && item >= 0) item.round(),
    ];
  }
}

class _MutableBuckets {
  final List<int> llmAsk;
  final List<int> localAction;
  final List<int> checkStepLlm;
  final List<int> checkStepTotal;

  _MutableBuckets({
    required this.llmAsk,
    required this.localAction,
    required this.checkStepLlm,
    required this.checkStepTotal,
  });

  factory _MutableBuckets.fromSummary(ReplyTimeSummary s) => _MutableBuckets(
    llmAsk: List<int>.from(s.llmAskSamples),
    localAction: List<int>.from(s.localActionSamples),
    checkStepLlm: List<int>.from(s.checkStepLlmSamples),
    checkStepTotal: List<int>.from(s.checkStepTotalSamples),
  );

  Map<String, dynamic> toJson() => {
    'llmAsk': llmAsk,
    'localAction': localAction,
    'checkStepLlm': checkStepLlm,
    'checkStepTotal': checkStepTotal,
  };
}

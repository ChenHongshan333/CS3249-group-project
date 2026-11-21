import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/reply_time_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('medianMs handles empty, odd, and even sample lists', () {
    expect(ReplyTimeStore.medianMs(const []), isNull);
    expect(ReplyTimeStore.medianMs(const [420]), 420);
    expect(ReplyTimeStore.medianMs(const [900, 300, 600]), 600);
    expect(ReplyTimeStore.medianMs(const [100, 400, 200, 300]), 250);
    expect(ReplyTimeStore.medianMs(const [100, 101]), 101);
  });

  test('persists buckets across instances and resets cleanly', () async {
    final store = ReplyTimeStore(storageKey: 'test.replyTimes');
    await store.recordLlmAsk(1200);
    await store.recordLlmAsk(1800);
    await store.recordLlmAsk(1400);
    await store.recordLocalAction(300);
    await store.recordLocalAction(500);
    await store.recordVisualCheck(llmMs: 1100, totalMs: 4200);

    final reader = ReplyTimeStore(storageKey: 'test.replyTimes');
    final summary = await reader.loadSummary();
    expect(summary.llmAskCount, 3);
    expect(summary.llmAskMedianMs, 1400);
    expect(summary.localActionCount, 2);
    expect(summary.localActionMedianMs, 400);
    expect(summary.checkStepCount, 1);
    expect(summary.checkStepLlmMedianMs, 1100);
    expect(summary.checkStepTotalMedianMs, 4200);

    final exported = jsonDecode(summary.toExportJson()) as Map<String, dynamic>;
    expect((exported['llmAsk'] as Map)['medianMs'], 1400);
    expect((exported['localAction'] as Map)['medianMs'], 400);
    expect((exported['checkStep'] as Map)['llmMedianMs'], 1100);
    expect((exported['checkStep'] as Map)['totalMedianMs'], 4200);

    await store.reset();
    final cleared = await reader.loadSummary();
    expect(cleared.llmAskCount, 0);
    expect(cleared.localActionCount, 0);
    expect(cleared.checkStepCount, 0);
    expect(cleared.llmAskMedianMs, isNull);
  });

  test('caps each bucket at maxSamplesPerBucket', () async {
    final store = ReplyTimeStore(storageKey: 'test.replyTimes.cap');
    for (var i = 0; i < ReplyTimeStore.maxSamplesPerBucket + 10; i++) {
      await store.recordLocalAction(i);
    }
    final summary = await store.loadSummary();
    expect(summary.localActionCount, ReplyTimeStore.maxSamplesPerBucket);
    expect(summary.localActionSamples.first, 10);
    expect(
      summary.localActionSamples.last,
      ReplyTimeStore.maxSamplesPerBucket + 9,
    );
  });
}

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'bert_tokenizer.dart';
import 'voice_intent_parser.dart';

/// Result of an on-device TFLite intent classification.
class TfliteClassificationResult {
  final VoiceIntentType type;
  final double confidence;
  final Map<VoiceIntentType, double> allScores;

  const TfliteClassificationResult({
    required this.type,
    required this.confidence,
    required this.allScores,
  });

  @override
  String toString() =>
      'TfliteClassificationResult(type: ${type.name}, confidence: ${confidence.toStringAsFixed(3)})';
}

/// On-device semantic intent classifier powered by `tflite_flutter` and
/// sentence embeddings (`all-MiniLM-L6-v2`).
///
/// Pre-computes and caches centroid vectors for each of the major cooking
/// intents at startup and logs granular performance benchmarks.
class TfliteIntentClassifier {
  static final TfliteIntentClassifier instance = TfliteIntentClassifier._();

  TfliteIntentClassifier._();

  Interpreter? _interpreter;
  BertWordPieceTokenizer? _tokenizer;
  bool _isReady = false;
  bool _isLoading = false;

  int _inputIdsIndex = 0;
  int _attentionMaskIndex = 1;

  final Map<VoiceIntentType, List<double>> _centroids = {};

  bool get isReady => _isReady;

  /// Confidence threshold above which a semantic match triggers the intent.
  /// Matches below this threshold fall back to `VoiceIntentType.generalQuestion`.
  double confidenceThreshold = 0.70;

  /// Canonical exemplar phrases used to build centroid vectors for each intent.
  static const Map<VoiceIntentType, List<String>> intentExemplars = {
    VoiceIntentType.nextStep: [
      'next step',
      'go to next step',
      'move on to next step',
      'done with this step',
      'i finished this step',
      'go to the next instruction',
      'move to the next step',
      'next instruction',
    ],
    VoiceIntentType.carryOn: [
      'we can continue',
      'carry on',
      'keep going',
      'continue cooking',
      "i'm back",
      "let's continue",
      'we can keep going',
    ],
    VoiceIntentType.previousStep: [
      'previous step',
      'go back',
      'back a step',
      'last step',
      'go to previous step',
      'back to last step',
    ],
    VoiceIntentType.repeatStep: [
      'repeat that',
      'say that again',
      'read step again',
      'what is this step',
      'could you repeat the instructions',
      'repeat current step',
    ],
    VoiceIntentType.openStepsSheet: [
      'show all steps',
      'open steps list',
      'view ingredients',
      'see recipe overview',
      'show ingredient checklist',
      'open ingredients',
    ],
    VoiceIntentType.startTimer: [
      'set a timer for 5 minutes',
      'start a three minute timer',
      'put on a timer for 10 minutes',
      'start timer',
      'timer for 2 minutes',
      'can you set a timer',
      'set timer for 3 minutes',
    ],
    VoiceIntentType.pauseTimer: [
      'pause the timer',
      'pause timer',
      'hold the timer',
      'pause my timer',
    ],
    VoiceIntentType.cancelTimer: [
      'cancel the timer',
      'stop timer',
      'turn off timer',
      'clear timer',
      'delete timer',
      'cancel timer',
    ],
    VoiceIntentType.pauseSession: [
      'pause cooking',
      'pause session',
      'pause the cooking',
      'pause the session',
      'pause for now',
    ],
    VoiceIntentType.resumeSession: [
      'resume session',
      'resume cooking',
      'continue session',
      'unpause cooking',
      'resume the cooking',
    ],
    VoiceIntentType.muteAudio: [
      'mute audio',
      'mute voice',
      'quiet',
      'stop speaking',
      'turn off voice',
      'silence audio',
    ],
    VoiceIntentType.unmuteAudio: [
      'unmute audio',
      'unmute voice',
      'speak aloud',
      'turn on sound',
      'turn on voice',
    ],
    VoiceIntentType.finishCooking: [
      'finish cooking',
      'finish recipe',
      'complete session',
      'we are done cooking',
      'finish the dish',
    ],
    VoiceIntentType.visualCheckStep: [
      'check this step',
      'check my pan',
      'check my bowl',
      'verify this step',
      'check my food',
      'verify my progress',
    ],
    VoiceIntentType.visualQuestion: [
      'does this look done',
      'is this cooked enough',
      'can you see the middle',
      'how does this look',
      'are these chopped small enough',
      'help me look at this',
      'does this look right',
    ],
  };

  /// Initializes the TFLite model, loads tokenizer vocabulary, and computes
  /// centroid vectors for all intents while logging startup timing.
  Future<void> initialize({
    String modelAssetPath = 'assets/models/all-MiniLM-L6-v2-quant.tflite',
    String vocabAssetPath = 'assets/models/vocab.txt',
  }) async {
    if (_isReady || _isLoading) return;
    _isLoading = true;

    final totalStopwatch = Stopwatch()..start();

    try {
      debugPrint('[TfliteNLU] ──────────────────────────────────────────');
      debugPrint('[TfliteNLU] Loading model & tokenizer from assets...');

      final loadStopwatch = Stopwatch()..start();

      // 1. Load vocabulary and initialize tokenizer
      final vocabString = await rootBundle.loadString(vocabAssetPath);
      _tokenizer = BertWordPieceTokenizer.fromVocabString(vocabString);

      // 2. Load TFLite model interpreter
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(modelAssetPath, options: options);

      // In this quantized MiniLM model:
      // - input 0 (named 'serving_default_inputs_1:0') receives input_ids
      // - input 1 (named 'serving_default_inputs:0') receives attention_mask
      final inputTensors = _interpreter!.getInputTensors();
      for (int i = 0; i < inputTensors.length; i++) {
        final name = inputTensors[i].name.toLowerCase();
        if (name.contains('inputs_1') || name.contains('id')) {
          _inputIdsIndex = i;
        } else if (name.contains('inputs') || name.contains('mask')) {
          _attentionMaskIndex = i;
        }
      }

      loadStopwatch.stop();
      debugPrint(
        '[TfliteNLU] Model loaded in ${loadStopwatch.elapsedMilliseconds}ms '
        '(Interpreter ready, inputIds: $_inputIdsIndex, mask: $_attentionMaskIndex)',
      );

      // 3. Compute centroid vectors for each intent and log benchmarks
      final totalExemplars = intentExemplars.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      debugPrint(
        '[TfliteNLU] Computing centroids for ${intentExemplars.length} intents '
        '($totalExemplars total exemplar phrases)...',
      );

      final centroidStopwatch = Stopwatch()..start();

      for (final entry in intentExemplars.entries) {
        final intentType = entry.key;
        final phrases = entry.value;

        final intentStopwatch = Stopwatch()..start();
        final vectors = <List<double>>[];

        for (final phrase in phrases) {
          final emb = _embed(phrase);
          if (emb != null) {
            vectors.add(emb);
          }
        }

        if (vectors.isNotEmpty) {
          _centroids[intentType] = _computeCentroid(vectors);
        }

        intentStopwatch.stop();
        final intentName = intentType.name.padRight(18);
        debugPrint(
          '[TfliteNLU]   ├── $intentName (${phrases.length} phrases): '
          '${intentStopwatch.elapsedMilliseconds.toString().padLeft(4)}ms',
        );
      }

      centroidStopwatch.stop();
      totalStopwatch.stop();

      debugPrint(
        '[TfliteNLU] Centroid computation finished in ${centroidStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '[TfliteNLU] Total warm-up time: ${totalStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('[TfliteNLU] ──────────────────────────────────────────');

      _isReady = true;
    } catch (e) {
      debugPrint(
        '[TfliteNLU] TFLite is unavailable on this environment: $e. '
        'Falling back to rule-based parser.',
      );
      _isReady = false;
    } finally {
      _isLoading = false;
    }
  }

  /// Classifies [utterance] against the intent centroid vectors.
  /// Returns null if the classifier is not ready or fails.
  TfliteClassificationResult? classify(String utterance) {
    if (!_isReady || _interpreter == null || _tokenizer == null) {
      return null;
    }

    try {
      final queryVector = _embed(utterance);
      if (queryVector == null) return null;

      final scores = <VoiceIntentType, double>{};
      VoiceIntentType? topIntent;
      double topScore = -1.0;

      for (final entry in _centroids.entries) {
        final score = _cosineSimilarity(queryVector, entry.value);
        scores[entry.key] = score;
        if (score > topScore) {
          topScore = score;
          topIntent = entry.key;
        }
      }

      if (topIntent == null) return null;

      return TfliteClassificationResult(
        type: topIntent,
        confidence: topScore,
        allScores: scores,
      );
    } catch (e) {
      debugPrint('[TfliteNLU] Error during classification: $e');
      return null;
    }
  }

  /// Extracts a 384-dimensional normalized sentence embedding vector.
  List<double>? _embed(String text) {
    if (_interpreter == null || _tokenizer == null) return null;

    final tokenized = _tokenizer!.tokenize(text, maxSeqLength: 32);

    final inputs = <Object>[];
    if (_inputIdsIndex == 0) {
      inputs.add([tokenized.inputIds]);
      inputs.add([tokenized.attentionMask]);
    } else {
      inputs.add([tokenized.attentionMask]);
      inputs.add([tokenized.inputIds]);
    }

    final output = [List<double>.filled(384, 0.0)];
    final outputs = <int, Object>{0: output};

    _interpreter!.runForMultipleInputs(inputs, outputs);

    final rawVector = output[0];
    return _l2Normalize(rawVector);
  }

  /// Computes the normalized centroid vector from a list of normalized vectors.
  List<double> _computeCentroid(List<List<double>> vectors) {
    final dim = vectors.first.length;
    final centroid = List<double>.filled(dim, 0.0);

    for (final v in vectors) {
      for (int i = 0; i < dim; i++) {
        centroid[i] += v[i];
      }
    }

    return _l2Normalize(centroid);
  }

  /// Cosine similarity between two L2-normalized vectors is their dot product.
  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0;
    final len = math.min(a.length, b.length);
    for (int i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /// L2 normalization: v / ||v||_2
  List<double> _l2Normalize(List<double> v) {
    double sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0.0) return v;
    return [for (final x in v) x / norm];
  }

  /// Releases resources when no longer needed.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _tokenizer = null;
    _centroids.clear();
    _isReady = false;
  }
}

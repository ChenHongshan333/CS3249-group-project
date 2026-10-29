/// Lightweight Bert WordPiece Tokenizer in pure Dart.
///
/// Converts text into input_ids and attention_mask tensors suitable for
/// MiniLM / BERT / MobileBERT models.
class BertWordPieceTokenizer {
  static const String padToken = '[PAD]';
  static const String unkToken = '[UNK]';
  static const String clsToken = '[CLS]';
  static const String sepToken = '[SEP]';

  final Map<String, int> vocab;
  final int padId;
  final int unkId;
  final int clsId;
  final int sepId;

  BertWordPieceTokenizer({
    required this.vocab,
    this.padId = 0,
    this.unkId = 100,
    this.clsId = 101,
    this.sepId = 102,
  });

  /// Factory to construct tokenizer from a vocab.txt file content.
  factory BertWordPieceTokenizer.fromVocabString(String vocabContent) {
    final vocab = <String, int>{};
    final lines = vocabContent.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        vocab[line] = i;
      }
    }
    return BertWordPieceTokenizer(
      vocab: vocab,
      padId: vocab[padToken] ?? 0,
      unkId: vocab[unkToken] ?? 100,
      clsId: vocab[clsToken] ?? 101,
      sepId: vocab[sepToken] ?? 102,
    );
  }

  /// Tokenizes [text] and returns a record of (inputIds, attentionMask).
  ({List<int> inputIds, List<int> attentionMask}) tokenize(
    String text, {
    int maxSeqLength = 64,
  }) {
    final normalized = _normalize(text);
    final basicTokens = _basicTokenize(normalized);

    final tokenIds = <int>[clsId];

    for (final token in basicTokens) {
      if (tokenIds.length >= maxSeqLength - 1) break;
      final subIds = _wordPieceTokenize(token);
      for (final id in subIds) {
        if (tokenIds.length >= maxSeqLength - 1) break;
        tokenIds.add(id);
      }
    }

    tokenIds.add(sepId);

    final inputIds = List<int>.filled(maxSeqLength, padId);
    final attentionMask = List<int>.filled(maxSeqLength, 0);

    for (int i = 0; i < tokenIds.length; i++) {
      inputIds[i] = tokenIds[i];
      attentionMask[i] = 1;
    }

    return (inputIds: inputIds, attentionMask: attentionMask);
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll('’', "'");
  }

  List<String> _basicTokenize(String text) {
    final tokens = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    }

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (_isWhitespace(char)) {
        flush();
      } else if (_isPunctuation(char)) {
        flush();
        tokens.add(char);
      } else {
        buffer.write(char);
      }
    }
    flush();
    return tokens;
  }

  List<int> _wordPieceTokenize(String word) {
    if (vocab.containsKey(word)) {
      return [vocab[word]!];
    }

    final subTokenIds = <int>[];
    int start = 0;

    while (start < word.length) {
      int end = word.length;
      int? curId;

      while (start < end) {
        final sub = (start == 0 ? '' : '##') + word.substring(start, end);
        if (vocab.containsKey(sub)) {
          curId = vocab[sub];
          break;
        }
        end--;
      }

      if (curId == null) {
        return [unkId];
      }

      subTokenIds.add(curId);
      start = end;
    }

    return subTokenIds;
  }

  static bool _isWhitespace(String char) {
    final code = char.codeUnitAt(0);
    return code == 0x20 ||
        code == 0x09 ||
        code == 0x0A ||
        code == 0x0D ||
        char.trim().isEmpty;
  }

  static bool _isPunctuation(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 33 && code <= 47) ||
        (code >= 58 && code <= 64) ||
        (code >= 91 && code <= 96) ||
        (code >= 123 && code <= 126);
  }
}

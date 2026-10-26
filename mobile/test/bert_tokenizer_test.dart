import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/bert_tokenizer.dart';

void main() {
  test('BertWordPieceTokenizer tokenizes common phrases correctly', () {
    final vocabFile = File('assets/models/vocab.txt');
    expect(vocabFile.existsSync(), isTrue);

    final tokenizer = BertWordPieceTokenizer.fromVocabString(
      vocabFile.readAsStringSync(),
    );

    final result = tokenizer.tokenize('next step please', maxSeqLength: 8);
    // [CLS] next step please [SEP] [PAD] [PAD] [PAD]
    expect(result.inputIds.length, 8);
    expect(result.attentionMask.length, 8);
    expect(result.inputIds[0], 101); // [CLS]
    expect(result.attentionMask, [1, 1, 1, 1, 1, 0, 0, 0]);

    // Check subword handling
    final subword = tokenizer.tokenize('unmuting', maxSeqLength: 8);
    expect(subword.inputIds[0], 101);
    expect(subword.attentionMask.where((m) => m == 1).length, greaterThanOrEqualTo(3));
  });
}

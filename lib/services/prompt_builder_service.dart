import '../models/exercise_page_item.dart';
import '../models/gguf_model_info.dart';

class PromptBuilderService {
  static const String systemTeacherPrompt = '''
You are an expert English Grammar, Reading Comprehension, and Vocabulary Teacher.
The user will provide text extracted from ONE or MULTIPLE ordered images (Pages/Parts) of an English exercise.
CRITICAL MULTI-IMAGE CONTEXT RULES:
1. Treat [Page 1], [Page 2], etc. as a single continuous, connected exercise in strict chronological order.
2. If an earlier image contains a reading passage, grammar rule box, word bank, or context paragraph, use that exact context to answer the questions in subsequent images.
3. If a sentence or question is split across the bottom of [Page N] and the top of [Page N+1], seamlessly merge and reconstruct it before solving.
4. Clean up any minor OCR typos, solve every question in order, and provide a clear English explanation followed by a brief Arabic explanation (شرح مبسط بالعربية) and the grammar formula.
''';

  /// Rebuilds the combined context string with clear delimiters for multi-page exercises
  static String buildCombinedContext(List<ExercisePageItem> pages) {
    if (pages.isEmpty) return '';

    final StringBuffer buffer = StringBuffer();
    final int total = pages.length;

    for (int i = 0; i < total; i++) {
      final page = pages[i];
      final pageNum = i + 1;
      buffer.writeln('=== [Page $pageNum of $total - ${page.pageRoleLabel}] ===');
      buffer.writeln(page.extractedText.trim());
      if (i < total - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Wraps the system prompt and combined user OCR text into the model's chat template
  static String formatPromptForModel({
    required String userOcrText,
    required ChatTemplateType templateType,
  }) {
    final cleanUserText = userOcrText.trim();

    switch (templateType) {
      case ChatTemplateType.chatml:
        return '<|system|>\n$systemTeacherPrompt<|end|>\n'
            '<|user|>\nPlease solve and explain the following English exercise thoroughly:\n\n$cleanUserText<|end|>\n'
            '<|assistant|>\n';

      case ChatTemplateType.gemma2:
        return '<start_of_turn>user\n'
            '$systemTeacherPrompt\n\n'
            'Please solve and explain the following English exercise thoroughly:\n\n'
            '$cleanUserText<end_of_turn>\n'
            '<start_of_turn>model\n';
    }
  }
}

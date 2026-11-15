import 'dart:io';

class ExercisePageItem {
  final String id;
  final File imageFile;
  final String extractedText;
  final List<String> lines;
  final String pageRoleLabel;

  static const String roleReadingPassage =
      'قطعة القراءة / السياق (Reading Passage)';
  static const String roleWordBank = 'صندوق المفردات (Word Bank)';
  static const String roleExerciseQuestions = 'أسئلة التمرين (Exercise Questions)';

  static const List<String> availableRoles = [
    roleReadingPassage,
    roleWordBank,
    roleExerciseQuestions,
  ];

  ExercisePageItem({
    required this.id,
    required this.imageFile,
    required this.extractedText,
    required this.lines,
    required this.pageRoleLabel,
  });

  ExercisePageItem copyWith({
    String? id,
    File? imageFile,
    String? extractedText,
    List<String>? lines,
    String? pageRoleLabel,
  }) {
    return ExercisePageItem(
      id: id ?? this.id,
      imageFile: imageFile ?? this.imageFile,
      extractedText: extractedText ?? this.extractedText,
      lines: lines ?? this.lines,
      pageRoleLabel: pageRoleLabel ?? this.pageRoleLabel,
    );
  }
}

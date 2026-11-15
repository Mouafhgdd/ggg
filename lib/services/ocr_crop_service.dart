import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../models/exercise_page_item.dart';

class OcrCropService {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Picks multiple images from gallery or captures from camera,
  /// immediately presenting the crop UI for each image, then performs OCR and sorting.
  Future<List<ExercisePageItem>> captureOrPickAndProcess({
    required ImageSource source,
    int existingCount = 0,
  }) async {
    List<XFile> rawImages = [];

    if (source == ImageSource.camera) {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (photo != null) {
        rawImages.add(photo);
      }
    } else {
      final List<XFile> pickedList = await _picker.pickMultiImage(
        imageQuality: 95,
      );
      rawImages.addAll(pickedList);
    }

    if (rawImages.isEmpty) return [];

    final List<ExercisePageItem> processedPages = [];

    for (int i = 0; i < rawImages.length; i++) {
      final XFile rawFile = rawImages[i];
      final File? cropped = await cropImageFile(File(rawFile.path));
      final File finalFile = cropped ?? File(rawFile.path);

      final pageItem = await processSingleImage(
        imageFile: finalFile,
        index: existingCount + i + 1,
      );
      processedPages.add(pageItem);
    }

    return processedPages;
  }

  /// Interactive native crop UI for an image
  Future<File?> cropImageFile(File file) async {
    try {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'تحديد منطقة السؤال / النص',
            toolbarColor: const Color(0xFF1E1B4B),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            activeControlsWidgetColor: const Color(0xFF6366F1),
          ),
          IOSUiSettings(
            title: 'تحديد منطقة السؤال / النص',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );

      if (croppedFile != null) {
        return File(croppedFile.path);
      }
    } catch (e) {
      debugPrint('Error cropping image: $e');
    }
    return null;
  }

  /// Processes single image with offline ML Kit OCR, geometric line sorting,
  /// punctuation normalization, and automatic role detection.
  Future<ExercisePageItem> processSingleImage({
    required File imageFile,
    required int index,
  }) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText =
        await _textRecognizer.processImage(inputImage);

    // Extract all lines across blocks
    final List<TextLine> allLines = [];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }

    // Geometric Line Sorting:
    // Sort top-to-bottom. If two lines share approximately the same Y (within 12.0 px),
    // sort left-to-right to keep horizontal options (A, B, C, D) in natural reading order.
    allLines.sort((a, b) {
      final double topDiff = a.boundingBox.top - b.boundingBox.top;
      if (topDiff.abs() < 12.0) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return topDiff.compareTo(0.0);
    });

    // Normalize consecutive dots (...) and underscores (___) into standard blanks
    final List<String> sortedNormalizedLines = [];
    for (final line in allLines) {
      String cleanText = line.text;
      cleanText = cleanText.replaceAll(RegExp(r'\.{2,}|\u2026'), ' _____ ');
      cleanText = cleanText.replaceAll(RegExp(r'_{2,}'), ' _____ ');
      cleanText = cleanText.replaceAll(RegExp(r'\s{2,}'), ' ');
      sortedNormalizedLines.add(cleanText.trim());
    }

    final String extractedCombined = sortedNormalizedLines.join('\n');
    final String detectedRole = detectPageRole(extractedCombined, index);

    return ExercisePageItem(
      id: '${DateTime.now().millisecondsSinceEpoch}_$index',
      imageFile: imageFile,
      extractedText: extractedCombined,
      lines: sortedNormalizedLines,
      pageRoleLabel: detectedRole,
    );
  }

  /// Automatic Page Role Detection based on content heuristics
  String detectPageRole(String text, int index) {
    final lower = text.toLowerCase();

    // Word Bank heuristic
    if (lower.contains('word bank') ||
        lower.contains('words in the box') ||
        lower.contains('choose from the box') ||
        lower.contains('box below') ||
        lower.contains('vocabulary bank')) {
      return ExercisePageItem.roleWordBank;
    }

    // Reading passage heuristic
    if (lower.contains('read the text') ||
        lower.contains('read the following') ||
        lower.contains('reading comprehension') ||
        lower.contains('passage') ||
        lower.contains('paragraph') ||
        lower.contains('once upon a time')) {
      return ExercisePageItem.roleReadingPassage;
    }

    // Exercise Questions heuristic
    final bool hasNumberedQuestions = RegExp(r'(\d+[\.\)]|[a-dA-D][\.\)])')
        .allMatches(text)
        .length >= 3;
    final bool hasExerciseKeywords = lower.contains('choose the correct') ||
        lower.contains('fill in') ||
        lower.contains('circle the') ||
        lower.contains('complete the sentence') ||
        lower.contains('question') ||
        lower.contains('exercise');

    if (hasNumberedQuestions || hasExerciseKeywords) {
      return ExercisePageItem.roleExerciseQuestions;
    }

    return 'الجزء $index من التمرين';
  }

  void dispose() {
    _textRecognizer.close();
  }
}

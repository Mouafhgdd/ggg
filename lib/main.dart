import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';

import 'models/exercise_page_item.dart';
import 'models/gguf_model_info.dart';
import 'services/local_llm_service.dart';
import 'services/model_download_service.dart';
import 'services/ocr_crop_service.dart';
import 'services/prompt_builder_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OfflineEnglishTutorApp());
}

class OfflineEnglishTutorApp extends StatelessWidget {
  const OfflineEnglishTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'معلم الإنجليزية الذكي - Offline AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          primary: const Color(0xFF4F46E5),
          secondary: const Color(0xFF06B6D4),
          surface: const Color(0xFFF8FAFC),
        ),
        fontFamily: 'Segoe UI',
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [
        Locale('ar', 'SA'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const TutorHomeScreen(),
    );
  }
}

class TutorHomeScreen extends StatefulWidget {
  const TutorHomeScreen({super.key});

  @override
  State<TutorHomeScreen> createState() => _TutorHomeScreenState();
}

class _TutorHomeScreenState extends State<TutorHomeScreen> {
  // Services
  final OcrCropService _ocrService = OcrCropService();
  final ModelDownloadService _downloadService = ModelDownloadService();
  final LocalLlmService _llmService = LocalLlmService();

  // Multi-image sequence state
  final List<ExercisePageItem> _pages = [];

  // OCR Combined Controller (LTR)
  final TextEditingController _combinedOcrController = TextEditingController();

  // Model selection
  GgufModelInfo _selectedModel = GgufModelInfo.defaultPresets.first;
  bool _isModelDownloaded = false;

  // Solving & Solution Streaming State
  String _solutionText = '';
  bool _isSolving = false;
  double _tokensPerSec = 0.0;
  int _totalTokens = 0;

  @override
  void initState() {
    super.initState();
    _checkSelectedModelDownloaded();
    _downloadService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          if (status.isCompleted) {
            _isModelDownloaded = true;
          }
        });
      }
    });

    _llmService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isSolving = state.isGenerating;
          _solutionText = state.outputText;
          _tokensPerSec = state.tokensPerSecond;
          _totalTokens = state.totalTokens;
        });
      }
    });
  }

  @override
  void dispose() {
    _ocrService.dispose();
    _downloadService.dispose();
    _llmService.dispose();
    _combinedOcrController.dispose();
    super.dispose();
  }

  Future<void> _checkSelectedModelDownloaded() async {
    final downloaded = await _downloadService.isModelDownloaded(_selectedModel);
    if (mounted) {
      setState(() {
        _isModelDownloaded = downloaded;
      });
    }
  }

  void _rebuildCombinedOcrText() {
    final combined = PromptBuilderService.buildCombinedContext(_pages);
    _combinedOcrController.text = combined;
  }

  Future<void> _addImages(ImageSource source) async {
    try {
      final newPages = await _ocrService.captureOrPickAndProcess(
        source: source,
        existingCount: _pages.length,
      );

      if (newPages.isNotEmpty && mounted) {
        setState(() {
          _pages.addAll(newPages);
          _rebuildCombinedOcrText();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم مسح واستخراج نصوص ${newPages.length} صفحة/صفحات بنجاح',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء المسح الضوئي: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _recropPage(int index) async {
    final currentItem = _pages[index];
    final cropped = await _ocrService.cropImageFile(currentItem.imageFile);
    if (cropped != null) {
      final updated = await _ocrService.processSingleImage(
        imageFile: cropped,
        index: index + 1,
      );
      if (mounted) {
        setState(() {
          _pages[index] = updated;
          _rebuildCombinedOcrText();
        });
      }
    }
  }

  void _movePage(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _pages.length) return;
    setState(() {
      final item = _pages.removeAt(index);
      _pages.insert(newIndex, item);
      _rebuildCombinedOcrText();
    });
  }

  void _deletePage(int index) {
    setState(() {
      _pages.removeAt(index);
      _rebuildCombinedOcrText();
    });
  }

  void _updatePageRole(int index, String newRole) {
    setState(() {
      _pages[index] = _pages[index].copyWith(pageRoleLabel: newRole);
      _rebuildCombinedOcrText();
    });
  }

  Future<void> _solveExercise() async {
    final textToSolve = _combinedOcrController.text.trim();
    if (textToSolve.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى التقاط صورة للتمرين أولاً أو كتابة النص يدوياً.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_isModelDownloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحميل نموذج الذكاء الاصطناعي أولاً من بطاقة النموذج أعلاه.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _solutionText = '';
      _isSolving = true;
      _totalTokens = 0;
      _tokensPerSec = 0.0;
    });

    final prompt = PromptBuilderService.formatPromptForModel(
      userOcrText: textToSolve,
      templateType: _selectedModel.templateType,
    );

    try {
      final modelPath = await _downloadService.getModelPath(_selectedModel);
      final stream = _llmService.generateStreaming(
        prompt: prompt,
        modelPath: modelPath,
      );

      await for (final _ in stream) {
        // Stream updates captured via _llmService.stateStream
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء الاستنتاج: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSolving = false;
        });
      }
    }
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'إعدادات الاستنتاج والنموذج',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Temperature
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'درجة الحرارة (Temperature):',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _llmService.temperature.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: _llmService.temperature,
                    min: 0.05,
                    max: 0.80,
                    divisions: 15,
                    label: _llmService.temperature.toStringAsFixed(2),
                    onChanged: (val) {
                      setModalState(() {
                        _llmService.temperature = val;
                      });
                      setState(() {});
                    },
                  ),
                  const Text(
                    'درجة حرارة منخفضة (0.10 - 0.20) تضمن إجابات قواعدية دقيقة وصارمة بدون تخمين.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Backend Selection
                  const Text(
                    'محرك التنفيذ المحلي:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<LlmBackend>(
                    segments: const [
                      ButtonSegment(
                        value: LlmBackend.flutterLlama,
                        label: Text('GPU / Vulkan'),
                        icon: Icon(Icons.speed),
                      ),
                      ButtonSegment(
                        value: LlmBackend.llamaCppDart,
                        label: Text('Isolate CPU'),
                        icon: Icon(Icons.memory),
                      ),
                    ],
                    selected: {_llmService.currentBackend},
                    onSelectionChanged: (newSelection) {
                      setModalState(() {
                        _llmService.currentBackend = newSelection.first;
                      });
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'معلم الإنجليزية الذكي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Offline On-Device AI 100%',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'إعدادات الاستنتاج',
            onPressed: _showSettingsBottomSheet,
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Model Management Card
              _buildModelManagerCard(),

              const SizedBox(height: 16),

              // 2. Multi-Image Queue & Ordering
              _buildImageQueueSection(),

              const SizedBox(height: 16),

              // 3. OCR Combined Text Editor (LTR)
              _buildOcrEditorSection(),

              const SizedBox(height: 16),

              // 4. Solve Action & Streaming Status
              _buildActionSection(),

              const SizedBox(height: 16),

              // 5. Solution & Grammar Explanation Card
              if (_solutionText.isNotEmpty || _isSolving)
                _buildSolutionCard(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildModelManagerCard() {
    final status = _downloadService.currentStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.offline_bolt, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                const Text(
                  'إدارة نموذج الذكاء الاصطناعي (أوفلاين)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isModelDownloaded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                        SizedBox(width: 4),
                        Text(
                          'جاهز ومحمّل',
                          style: TextStyle(color: Color(0xFF16A34A), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Model Presets Dropdown
            DropdownButtonFormField<GgufModelInfo>(
              value: _selectedModel,
              decoration: InputDecoration(
                labelText: 'اختر النموذج المحلي (GGUF Q4_K_M)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: GgufModelInfo.defaultPresets.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text('${model.name} (${model.sizeLabel})'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedModel = val;
                  });
                  _checkSelectedModelDownloaded();
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              _selectedModel.descriptionAr,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            Text(
              _selectedModel.recommendedFor,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            // Download Progress / Controls
            if (!_isModelDownloaded || status.isDownloading) ...[
              if (status.isDownloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: status.progress > 0 ? status.progress : null,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${status.percentInt}% (${status.receivedMB} / ${status.totalMB} م.ب)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      status.speedLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: status.isDownloading
                            ? Colors.amber.shade700
                            : const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(status.isDownloading ? Icons.pause : Icons.download),
                      label: Text(
                        status.isDownloading
                            ? 'إيقاف التحميل مؤقتاً'
                            : (_isModelDownloaded ? 'إعادة التحميل' : 'بدء تحميل النموذج'),
                      ),
                      onPressed: () {
                        if (status.isDownloading) {
                          _downloadService.pauseOrCancel();
                        } else {
                          _downloadService.startOrResumeDownload(_selectedModel);
                        }
                      },
                    ),
                  ),
                  if (_isModelDownloaded || status.receivedBytes > 0) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'حذف ملف النموذج لتحرير المساحة',
                      onPressed: () async {
                        await _downloadService.deleteModel(_selectedModel);
                        await _checkSelectedModelDownloaded();
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageQueueSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_outlined, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                Text(
                  'صور صفحات التمرين (${_pages.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('كاميرا'),
                  onPressed: () => _addImages(ImageSource.camera),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('المعرض'),
                  onPressed: () => _addImages(ImageSource.gallery),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_pages.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.document_scanner, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'لم يتم إضافة أي صفحة حتى الآن',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'التقط صور صفحات التمرين المتعاقبة (القطعة ثم الأسئلة) ليتم دمج سياقها وحلها ككتلة واحدة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pages.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _pages.removeAt(oldIndex);
                    _pages.insert(newIndex, item);
                    _rebuildCombinedOcrText();
                  });
                },
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Card(
                    key: ValueKey(page.id),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    color: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Sequence Badge
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFF4F46E5),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Image Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              page.imageFile,
                              width: 50,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Role Selector & 2-line OCR preview
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButton<String>(
                                  isDense: true,
                                  value: ExercisePageItem.availableRoles.contains(page.pageRoleLabel)
                                      ? page.pageRoleLabel
                                      : ExercisePageItem.roleExerciseQuestions,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                  underline: const SizedBox(),
                                  items: ExercisePageItem.availableRoles.map((role) {
                                    return DropdownMenuItem(
                                      value: role,
                                      child: Text(role),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      _updatePageRole(index, val);
                                    }
                                  },
                                ),
                                const SizedBox(height: 4),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    page.extractedText.replaceAll('\n', ' '),
                                    maxLines: 2,
                                    overflow: TextDirection.ltr == TextDirection.ltr
                                        ? TextOverflow.ellipsis
                                        : TextOverflow.clip,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Actions: Move up/down, Crop, Delete
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.arrow_upward, size: 18),
                                    onPressed: index > 0 ? () => _movePage(index, -1) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.arrow_downward, size: 18),
                                    onPressed: index < _pages.length - 1
                                        ? () => _movePage(index, 1)
                                        : null,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.crop, size: 18, color: Color(0xFF4F46E5)),
                                    tooltip: 'إعادة تحديد وقص',
                                    onPressed: () => _recropPage(index),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                                    tooltip: 'حذف الصفحة',
                                    onPressed: () => _deletePage(index),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrEditorSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                const Text(
                  'النص المستخرج والسياق المدمج (قابل للتعديل)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'مسح النص',
                  onPressed: () {
                    setState(() {
                      _combinedOcrController.clear();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك مراجعة النص وتصحيح أي خطأ إملائي أو إضافة أسئلة يدوياً قبل الضغط على حل التمرين:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _combinedOcrController,
                maxLines: 8,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFF1E293B),
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  hintText: 'OCR extracted context & questions will appear here...',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSolving)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.stop_circle),
            label: const Text(
              'إيقاف التوليد فوراً (Stop)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              _llmService.stopGeneration();
            },
          )
        else
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.psychology),
            label: const Text(
              'حل التمرين وشرح القواعد (Solve & Explain)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _solveExercise,
          ),
      ],
    );
  }

  Widget _buildSolutionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text(
                  'الحل والشرح القواعدي المفصل',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_tokensPerSec > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E7FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_tokensPerSec.toStringAsFixed(1)} token/s ($_totalTokens tokens)',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF4F46E5)),
                    ),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: 'نسخ الحل بالكامل',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _solutionText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم نسخ الحل والشرح إلى الحافظة!'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            if (_isSolving && _solutionText.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFF4F46E5)),
                      SizedBox(height: 12),
                      Text(
                        'جاري التفكير وتحليل سياق الصفحات وقواعد اللغة...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              SelectableText(
                _solutionText,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF1E293B),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum ChatTemplateType {
  chatml,
  gemma2,
}

class GgufModelInfo {
  final String id;
  final String name;
  final String fileName;
  final String downloadUrl;
  final int estimatedSizeBytes;
  final String sizeLabel;
  final ChatTemplateType templateType;
  final String descriptionAr;
  final String recommendedFor;

  const GgufModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.estimatedSizeBytes,
    required this.sizeLabel,
    required this.templateType,
    required this.descriptionAr,
    required this.recommendedFor,
  });

  static const List<GgufModelInfo> defaultPresets = [
    GgufModelInfo(
      id: 'phi35_mini',
      name: 'Phi-3.5 Mini Instruct (3.8B)',
      fileName: 'Phi-3.5-mini-instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      estimatedSizeBytes: 2394544608, // ~2.23 GB
      sizeLabel: '2.23 جيجابايت',
      templateType: ChatTemplateType.chatml,
      descriptionAr: 'الأفضل في القواعد المعقدة وتحليل النصوص الطويلة (سياق 4096+).',
      recommendedFor: 'الأجهزة ذات الرام 6+ جيجابايت - دقة فائقة في الاستنتاج',
    ),
    GgufModelInfo(
      id: 'qwen25_3b',
      name: 'Qwen2.5 3B Instruct',
      fileName: 'Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      estimatedSizeBytes: 2070000000, // ~1.93 GB
      sizeLabel: '1.93 جيجابايت',
      templateType: ChatTemplateType.chatml,
      descriptionAr: 'توازن مثالي وسرعة توليد عالية مع فهم ممتاز للتعليمات.',
      recommendedFor: 'الأجهزة المتوسطة (4 إلى 6 جيجابايت رام) - سريع ومتوازن',
    ),
    GgufModelInfo(
      id: 'gemma2_2b',
      name: 'Gemma-2 2B Instruct',
      fileName: 'gemma-2-2b-it-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      estimatedSizeBytes: 1835000000, // ~1.71 GB
      sizeLabel: '1.71 جيجابايت',
      templateType: ChatTemplateType.gemma2,
      descriptionAr: 'أخف نموذج وأقل استهلاكاً للذاكرة والبطارية.',
      recommendedFor: 'الأجهزة الاقتصادية (4 جيجابايت رام) - خفيف وسريع',
    ),
  ];
}

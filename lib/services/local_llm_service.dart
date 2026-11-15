import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:flutter_llama/flutter_llama.dart' as fllama;

enum LlmBackend {
  flutterLlama,
  llamaCppDart,
}

class LlmGenerationState {
  final bool isGenerating;
  final String outputText;
  final double tokensPerSecond;
  final int totalTokens;
  final String? error;

  const LlmGenerationState({
    this.isGenerating = false,
    this.outputText = '',
    this.tokensPerSecond = 0.0,
    this.totalTokens = 0,
    this.error,
  });

  LlmGenerationState copyWith({
    bool? isGenerating,
    String? outputText,
    double? tokensPerSecond,
    int? totalTokens,
    String? error,
  }) {
    return LlmGenerationState(
      isGenerating: isGenerating ?? this.isGenerating,
      outputText: outputText ?? this.outputText,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      totalTokens: totalTokens ?? this.totalTokens,
      error: error ?? this.error,
    );
  }
}

class LocalLlmService {
  LlmBackend currentBackend = LlmBackend.flutterLlama;
  double temperature = 0.15;
  int contextSize = 4096;
  int threads = 4;

  bool _isCancelled = false;
  bool _isBusy = false;
  bool get isBusy => _isBusy;

  // Llama.cpp instance reference
  Llama? _llamaInstance;

  final StreamController<LlmGenerationState> _stateController =
      StreamController<LlmGenerationState>.broadcast();
  Stream<LlmGenerationState> get stateStream => _stateController.stream;

  LlmGenerationState _currentState = const LlmGenerationState();
  LlmGenerationState get currentState => _currentState;

  /// Loads model and initializes on-device engine
  Future<void> initializeEngine({
    required String modelPath,
    LlmBackend? backend,
  }) async {
    if (backend != null) {
      currentBackend = backend;
    }

    final file = File(modelPath);
    if (!await file.exists()) {
      throw Exception('ملف النموذج غير موجود في المسار: $modelPath');
    }

    debugPrint('Initializing local LLM on $currentBackend at $modelPath');

    if (currentBackend == LlmBackend.llamaCppDart) {
      _llamaInstance?.dispose();
      final contextParams = ContextParams();
      contextParams.context = contextSize;
      contextParams.threads = threads;

      final modelParams = ModelParams();
      _llamaInstance = Llama(
        modelPath,
        modelParams,
        contextParams,
      );
    } else {
      // flutter_llama initialization
      try {
        await fllama.FlutterLlama.init(
          modelPath: modelPath,
          contextSize: contextSize,
          threads: threads,
        );
      } catch (e) {
        debugPrint('flutter_llama init note: $e');
      }
    }
  }

  /// Streams generated tokens live to the UI
  Stream<String> generateStreaming({
    required String prompt,
    required String modelPath,
  }) async* {
    if (_isBusy) {
      throw Exception('النموذج قيد التوليد بالفعل. يرجى الانتظار.');
    }

    _isBusy = true;
    _isCancelled = false;
    final StringBuffer outputBuffer = StringBuffer();
    int tokenCount = 0;
    final DateTime startTime = DateTime.now();

    _currentState = LlmGenerationState(
      isGenerating: true,
      outputText: '',
      tokensPerSecond: 0.0,
      totalTokens: 0,
    );
    _stateController.add(_currentState);

    try {
      if (currentBackend == LlmBackend.flutterLlama) {
        // Stream using flutter_llama
        final stream = fllama.FlutterLlama.generateStream(
          prompt: prompt,
          temperature: temperature,
          maxTokens: 2048,
        );

        await for (final token in stream) {
          if (_isCancelled) break;
          tokenCount++;
          outputBuffer.write(token);
          yield token;

          final elapsedSeconds =
              DateTime.now().difference(startTime).inMilliseconds / 1000.0;
          final speed = elapsedSeconds > 0 ? (tokenCount / elapsedSeconds) : 0.0;

          _currentState = _currentState.copyWith(
            outputText: outputBuffer.toString(),
            totalTokens: tokenCount,
            tokensPerSecond: speed,
          );
          _stateController.add(_currentState);
        }
      } else {
        // llama_cpp_dart engine
        if (_llamaInstance == null) {
          await initializeEngine(
            modelPath: modelPath,
            backend: LlmBackend.llamaCppDart,
          );
        }

        _llamaInstance!.setPrompt(prompt);
        while (!_isCancelled) {
          final (token, done) = _llamaInstance!.getNext();
          if (token.isNotEmpty) {
            tokenCount++;
            outputBuffer.write(token);
            yield token;

            final elapsedSeconds =
                DateTime.now().difference(startTime).inMilliseconds / 1000.0;
            final speed =
                elapsedSeconds > 0 ? (tokenCount / elapsedSeconds) : 0.0;

            _currentState = _currentState.copyWith(
              outputText: outputBuffer.toString(),
              totalTokens: tokenCount,
              tokensPerSecond: speed,
            );
            _stateController.add(_currentState);
          }
          if (done) break;
        }
      }
    } catch (e) {
      _currentState = _currentState.copyWith(
        isGenerating: false,
        error: 'خطأ أثناء التوليد المحلي: ${e.toString()}',
      );
      _stateController.add(_currentState);
      rethrow;
    } finally {
      _isBusy = false;
      _currentState = _currentState.copyWith(isGenerating: false);
      _stateController.add(_currentState);
    }
  }

  /// Cancels generation immediately
  void stopGeneration() {
    _isCancelled = true;
    _isBusy = false;
    _currentState = _currentState.copyWith(isGenerating: false);
    _stateController.add(_currentState);
  }

  void dispose() {
    _llamaInstance?.dispose();
    _stateController.close();
  }
}

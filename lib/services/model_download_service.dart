import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/gguf_model_info.dart';

class DownloadStatus {
  final int receivedBytes;
  final int totalBytes;
  final double speedMBs;
  final double progress; // 0.0 to 1.0
  final bool isDownloading;
  final bool isCompleted;
  final String? error;

  const DownloadStatus({
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedMBs = 0.0,
    this.progress = 0.0,
    this.isDownloading = false,
    this.isCompleted = false,
    this.error,
  });

  String get receivedMB => (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
  String get totalMB => (totalBytes / (1024 * 1024)).toStringAsFixed(1);
  String get speedLabel => '${speedMBs.toStringAsFixed(2)} ميجابايت/ثانية';
  int get percentInt => (progress * 100).clamp(0, 100).toInt();
}

class ModelDownloadService {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  final StreamController<DownloadStatus> _statusController =
      StreamController<DownloadStatus>.broadcast();
  Stream<DownloadStatus> get statusStream => _statusController.stream;

  DownloadStatus _currentStatus = const DownloadStatus();
  DownloadStatus get currentStatus => _currentStatus;

  Future<Directory> getModelsDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  Future<String> getModelPath(GgufModelInfo model) async {
    final dir = await getModelsDirectory();
    return p.join(dir.path, model.fileName);
  }

  Future<bool> isModelDownloaded(GgufModelInfo model) async {
    final path = await getModelPath(model);
    final file = File(path);
    if (!await file.exists()) return false;
    final length = await file.length();
    // Check if file is at least roughly expected size (greater than 50MB)
    return length > 50 * 1024 * 1024;
  }

  Future<void> startOrResumeDownload(GgufModelInfo model) async {
    final dir = await getModelsDirectory();
    final completedFilePath = p.join(dir.path, model.fileName);
    final partFilePath = p.join(dir.path, '${model.fileName}.part');

    final completedFile = File(completedFilePath);
    if (await completedFile.exists()) {
      _currentStatus = DownloadStatus(
        receivedBytes: await completedFile.length(),
        totalBytes: await completedFile.length(),
        progress: 1.0,
        isCompleted: true,
      );
      _statusController.add(_currentStatus);
      return;
    }

    final partFile = File(partFilePath);
    int existingBytes = 0;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
    }

    _cancelToken = CancelToken();

    _currentStatus = DownloadStatus(
      receivedBytes: existingBytes,
      totalBytes: model.estimatedSizeBytes,
      progress: existingBytes / model.estimatedSizeBytes,
      isDownloading: true,
    );
    _statusController.add(_currentStatus);

    int lastBytes = existingBytes;
    DateTime lastTime = DateTime.now();

    try {
      final options = Options(
        responseType: ResponseType.stream,
        headers: {
          if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
        },
      );

      final response = await _dio.get<ResponseBody>(
        model.downloadUrl,
        options: options,
        cancelToken: _cancelToken,
      );

      final int statusCode = response.statusCode ?? 200;
      final int contentLength =
          int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;
      final int totalBytes = (statusCode == 206)
          ? existingBytes + contentLength
          : (contentLength > 0 ? contentLength : model.estimatedSizeBytes);

      final IOSink fileSink = partFile.openWrite(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );

      await for (final chunk in response.data!.stream) {
        fileSink.add(chunk);
        existingBytes += chunk.length;

        final now = DateTime.now();
        final msDelta = now.difference(lastTime).inMilliseconds;
        if (msDelta >= 400) {
          final bytesDelta = existingBytes - lastBytes;
          final speedMBs = (bytesDelta / (1024 * 1024)) / (msDelta / 1000.0);
          lastBytes = existingBytes;
          lastTime = now;

          final progress =
              totalBytes > 0 ? (existingBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
          _currentStatus = DownloadStatus(
            receivedBytes: existingBytes,
            totalBytes: totalBytes,
            speedMBs: speedMBs,
            progress: progress,
            isDownloading: true,
          );
          _statusController.add(_currentStatus);
        }
      }

      await fileSink.flush();
      await fileSink.close();

      // Rename .part to .gguf upon completion
      if (await partFile.exists()) {
        await partFile.rename(completedFilePath);
      }

      _currentStatus = DownloadStatus(
        receivedBytes: totalBytes,
        totalBytes: totalBytes,
        progress: 1.0,
        isCompleted: true,
      );
      _statusController.add(_currentStatus);
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _currentStatus = DownloadStatus(
          receivedBytes: existingBytes,
          totalBytes: model.estimatedSizeBytes,
          progress: existingBytes / model.estimatedSizeBytes,
          isDownloading: false,
          error: 'تم إيقاف التحميل مؤقتاً',
        );
      } else {
        _currentStatus = DownloadStatus(
          receivedBytes: existingBytes,
          totalBytes: model.estimatedSizeBytes,
          progress: existingBytes / model.estimatedSizeBytes,
          isDownloading: false,
          error: 'خطأ أثناء التحميل: ${e.toString()}',
        );
      }
      _statusController.add(_currentStatus);
    }
  }

  void pauseOrCancel() {
    _cancelToken?.cancel('User stopped download');
    _cancelToken = null;
  }

  Future<void> deleteModel(GgufModelInfo model) async {
    pauseOrCancel();
    final dir = await getModelsDirectory();
    final completedFile = File(p.join(dir.path, model.fileName));
    final partFile = File(p.join(dir.path, '${model.fileName}.part'));

    if (await completedFile.exists()) {
      await completedFile.delete();
    }
    if (await partFile.exists()) {
      await partFile.delete();
    }

    _currentStatus = const DownloadStatus();
    _statusController.add(_currentStatus);
  }

  void dispose() {
    _statusController.close();
  }
}

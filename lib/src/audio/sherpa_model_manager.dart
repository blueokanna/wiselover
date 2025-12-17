import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 生产级 Sherpa-ONNX 模型管理器
///
/// 功能：
/// - 从 assets/sherpa/chinese/ 加载本地预置模型
/// - 支持完整的中文语音识别模型（encoder, decoder, joiner, tokens）
/// - 自动解压和缓存模型文件到应用目录
/// - 提供模型可用性检查和完整的错误处理
class SherpaModelManager {
  SherpaModelManager._();

  static final SherpaModelManager instance = SherpaModelManager._();

  /// 本地模型目录路径
  late final Directory _modelDir;

  /// Sherpa 模型资源文件配置
  static const String _assetBase = 'assets/sherpa/chinese';
  static const Map<String, String> _modelFiles = {
    'encoder.onnx': '$_assetBase/encoder.int8.onnx',
    'decoder.onnx': '$_assetBase/decoder.onnx',
    'joiner.onnx': '$_assetBase/joiner.int8.onnx',
    'tokens.txt': '$_assetBase/tokens.txt',
    'bpe.model': '$_assetBase/bpe.model',
  };

  /// 初始化 Sherpa 模型
  ///
  /// 流程：
  /// 1. 检查应用缓存目录
  /// 2. 如果模型文件不存在，从 assets 复制到缓存目录
  /// 3. 验证所有必需文件
  Future<void> init() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      _modelDir = Directory(p.join(baseDir.path, 'sherpa_onnx'));

      if (!await _modelDir.exists()) {
        await _modelDir.create(recursive: true);
        if (kDebugMode) {
          debugPrint('✓ Created model directory: ${_modelDir.path}');
        }
      }

      // 检查并复制模型文件
      await _ensureModelFiles();

      if (kDebugMode) {
        debugPrint('✓ Sherpa model initialized successfully');
        debugPrint('  Model path: ${_modelDir.path}');
        debugPrint('  Files: ${_modelFiles.keys.join(", ")}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('✗ Sherpa model initialization failed: $e');
      }
      rethrow;
    }
  }

  /// 确保所有模型文件都存在并有效
  Future<void> _ensureModelFiles() async {
    for (final entry in _modelFiles.entries) {
      final fileName = entry.key;
      final assetPath = entry.value;
      final localFile = File(p.join(_modelDir.path, fileName));

      if (!await localFile.exists()) {
        if (kDebugMode) {
          debugPrint('Copying $fileName from assets...');
        }
        try {
          final data = await rootBundle.load(assetPath);
          await localFile.writeAsBytes(data.buffer.asUint8List());
          if (kDebugMode) {
            debugPrint('✓ Copied $fileName (${data.lengthInBytes} bytes)');
          }
        } catch (e) {
          throw Exception('Failed to load $assetPath from assets: $e');
        }
      } else {
        if (kDebugMode) {
          final size = await localFile.length();
          debugPrint('✓ $fileName already exists ($size bytes)');
        }
      }
    }
  }

  /// 获取 encoder 模型文件路径
  String get encoderPath => p.join(_modelDir.path, 'encoder.onnx');

  /// 获取 decoder 模型文件路径
  String get decoderPath => p.join(_modelDir.path, 'decoder.onnx');

  /// 获取 joiner 模型文件路径
  String get joinerPath => p.join(_modelDir.path, 'joiner.onnx');

  /// 获取 tokens 文件路径
  String get tokensPath => p.join(_modelDir.path, 'tokens.txt');

  /// 获取 BPE 模型文件路径
  String get bpePath => p.join(_modelDir.path, 'bpe.model');

  /// 获取完整的模型配置对象
  Future<SherpaModelConfig> getModelConfig() async {
    if (!await hasModel) {
      throw Exception('Sherpa model not initialized');
    }

    return SherpaModelConfig(
      encoderPath: encoderPath,
      decoderPath: decoderPath,
      joinerPath: joinerPath,
      tokensPath: tokensPath,
      bpePath: bpePath,
    );
  }

  /// 检查模型是否已加载
  Future<bool> get hasModel async {
    for (final fileName in _modelFiles.keys) {
      final file = File(p.join(_modelDir.path, fileName));
      if (!await file.exists()) {
        return false;
      }
    }
    return true;
  }

  /// 获取模型大小（字节）
  Future<int> getModelSize() async {
    int totalSize = 0;
    for (final fileName in _modelFiles.keys) {
      final file = File(p.join(_modelDir.path, fileName));
      if (await file.exists()) {
        totalSize += await file.length();
      }
    }
    return totalSize;
  }

  /// 清除本地缓存的模型文件
  Future<void> clearCache() async {
    if (await _modelDir.exists()) {
      await _modelDir.delete(recursive: true);
      if (kDebugMode) {
        debugPrint('✓ Model cache cleared');
      }
    }
  }
}

/// Sherpa 模型配置类
class SherpaModelConfig {
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final String bpePath;

  SherpaModelConfig({
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    required this.bpePath,
  });

  /// 验证所有模型文件都存在
  Future<bool> validate() async {
    final files = [encoderPath, decoderPath, joinerPath, tokensPath, bpePath];
    for (final path in files) {
      if (!await File(path).exists()) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      '''
SherpaModelConfig(
  encoder: $encoderPath
  decoder: $decoderPath
  joiner: $joinerPath
  tokens: $tokensPath
  bpe: $bpePath
)''';
}

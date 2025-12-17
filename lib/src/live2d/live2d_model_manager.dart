import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiselover/src/rust/api/live2d_model_api.dart';
import 'package:wiselover/src/rust/api/wise_lover_boot_api.dart';

class Live2DModelSetting {
  String? moc;
  List<String> textures = [];
  Map<String, String> expressions = {};

  Live2DModelSetting.fromJson(Map<String, dynamic> json) {
    // Parse FileReferences
    if (json['FileReferences'] != null) {
      final refs = json['FileReferences'];
      moc = refs['Moc'];
      if (refs['Textures'] != null) {
        textures = List<String>.from(refs['Textures']);
      }
      if (refs['Expressions'] != null) {
        final exps = refs['Expressions'];
        if (exps is List) {
          for (var exp in exps) {
            if (exp['Name'] != null && exp['File'] != null) {
              expressions[exp['Name']] = exp['File'];
            }
          }
        }
      }
    }
  }
}

class Live2DModelManager extends ChangeNotifier {
  Live2DModelManager._();
  static final Live2DModelManager instance = Live2DModelManager._();

  BigInt? _modelHandle;
  List<ui.Image> _textures = [];
  FrameDto? _currentFrame;

  bool _initialized = false;
  String? _currentModelPath;

  Map<String, String> _expressions = {};
  Set<String> _availableParameters = {};

  static const String _prefKeyModelPath = 'live2d_model_path';

  /// 获取所有可用的模型列表 (从 Assets)
  Future<List<Map<String, String>>> getAvailableModels() async {
    List<String> assetKeys = [];
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(manifestContent);
      assetKeys = manifest.keys.toList();
    } catch (e) {
      debugPrint('Warning: Failed to load AssetManifest.json: $e');
      // Fallback list
      assetKeys = [
        'assets/live2d/mao_pro/runtime/mao_pro.model3.json',
        'assets/live2d/juanjuan/juanjuan.model3.json',
        'assets/live2d/PurpleBird/PurpleBird.model3.json',
      ];
    }

    final models = <Map<String, String>>[];

    // 1. Find .model3.json files
    for (final key in assetKeys) {
      if (key.endsWith('.model3.json') && key.contains('assets/live2d/')) {
        // Extract name from path (e.g. assets/live2d/mao_pro/runtime/mao_pro.model3.json -> mao_pro)
        final name = path
            .basenameWithoutExtension(key)
            .replaceAll('.model3', '');
        models.add({'name': name, 'path': key, 'type': 'json'});
      }
    }

    // 2. Find .moc3 files (if no json exists for them)
    for (final key in assetKeys) {
      if (key.endsWith('.moc3') && key.contains('assets/live2d/')) {
        final name = path.basenameWithoutExtension(key);
        // Check if we already have this model via json
        if (!models.any((m) => m['name'] == name)) {
          models.add({'name': name, 'path': key, 'type': 'moc3'});
        }
      }
    }

    return models;
  }

  Future<void> loadModel() async {
    try {
      List<String> assetKeys = [];

      try {
        final manifestContent = await rootBundle.loadString(
          'AssetManifest.json',
        );
        final Map<String, dynamic> manifest = json.decode(manifestContent);
        assetKeys = manifest.keys.toList();
      } catch (e) {
        debugPrint('Warning: Failed to load AssetManifest.json: $e');
        debugPrint('Using hardcoded fallback assets.');
        assetKeys = [
          'assets/live2d/mao_pro/runtime/mao_pro.model3.json',
          'assets/live2d/shizuku/shizuku.model3.json',
          'assets/live2d/juanjuan/juanjuan.model3.json',
          'assets/live2d/PurpleBird/PurpleBird.model3.json',
        ];
      }

      // 寻找包含 .model3.json 的路径
      String? model3JsonPath;
      for (final key in assetKeys) {
        if (key.endsWith('.model3.json') && key.contains('assets/live2d/')) {
          model3JsonPath = key;
          break;
        }
      }

      if (model3JsonPath != null) {
        debugPrint('Found default model config: $model3JsonPath');
        await loadModelFromAssetJson(model3JsonPath);
      } else {
        // Fallback: 尝试寻找 .moc3
        String? mocPath;
        for (final key in assetKeys) {
          if (key.endsWith('.moc3') && key.contains('assets/live2d/')) {
            mocPath = key;
            break;
          }
        }

        if (mocPath != null) {
          debugPrint('Found default moc: $mocPath');
          // 尝试查找纹理
          final dir = path.dirname(mocPath).replaceAll('\\', '/');
          final texturePaths =
              assetKeys
                  .where((k) => k.endsWith('.png') && k.contains(dir))
                  .toList()
                ..sort();

          if (texturePaths.isNotEmpty) {
            await _loadModelInternal(
              mocPath: mocPath,
              texturePaths: texturePaths,
              isAsset: true,
            );
          } else {
            debugPrint('Warning: No textures found for moc: $mocPath');
          }
        } else {
          debugPrint('Warning: No model found in assets.');
        }
      }

      _currentModelPath = null;
      await _saveModelPath(null);
    } catch (e) {
      debugPrint('Note: Default asset model auto-load failed: $e');
      _initialized = false;
    }
  }

  Future<void> loadModelByPath(String modelPath, bool isJson) async {
    if (isJson) {
      await loadModelFromAssetJson(modelPath);
    } else {
      // Fallback for raw moc3 in assets
      // This part assumes textures are in the same folder
      // We can reuse the logic from loadModel() fallback
      final dir = path.dirname(modelPath).replaceAll('\\', '/');
      // We need to find textures again... this is getting complicated.
      // Let's just support JSON for now as it's the standard.
      // Or try to find textures using AssetManifest again.
      try {
        final manifestContent = await rootBundle.loadString(
          'AssetManifest.json',
        );
        final Map<String, dynamic> manifest = json.decode(manifestContent);
        final assetKeys = manifest.keys.toList();

        final texturePaths =
            assetKeys
                .where((k) => k.endsWith('.png') && k.contains(dir))
                .toList()
              ..sort();

        if (texturePaths.isNotEmpty) {
          await _loadModelInternal(
            mocPath: modelPath,
            texturePaths: texturePaths,
            isAsset: true,
          );
        } else {
          throw Exception('No textures found for $modelPath');
        }
      } catch (e) {
        // If manifest fails, we can't easily find textures for raw moc3
        throw Exception(
          'Failed to load raw moc3 from assets without manifest: $e',
        );
      }
    }
    _currentModelPath = null; // Asset model doesn't have a local path
    await _saveModelPath(null);
  }

  Future<void> loadModelFromAssetJson(String jsonPath) async {
    final jsonContent = await rootBundle.loadString(jsonPath);
    final setting = Live2DModelSetting.fromJson(json.decode(jsonContent));

    if (setting.moc == null)
      throw Exception('Moc file not defined in $jsonPath');

    // Ensure we use forward slashes for assets
    final dir = path.dirname(jsonPath).replaceAll('\\', '/');
    String joinAsset(String p1, String p2) => '$p1/$p2'.replaceAll('//', '/');

    final mocPath = joinAsset(dir, setting.moc!);
    final texturePaths = setting.textures
        .map((t) => joinAsset(dir, t))
        .toList();

    // 处理表情
    _expressions.clear();
    setting.expressions.forEach((name, file) {
      _expressions[name] = joinAsset(dir, file);
    });

    await _loadModelInternal(
      mocPath: mocPath,
      texturePaths: texturePaths,
      isAsset: true,
    );
  }

  /// 从 .moc3 文件路径加载模型
  Future<void> loadModelFromMocFile(String mocPath) async {
    final mocFile = File(mocPath);
    if (!await mocFile.exists()) {
      throw Exception('Moc file not found: $mocPath');
    }

    final dir = mocFile.parent;

    // 查找纹理 (简单策略：查找同级目录或 texture 目录下的 png)
    // 1. 查找同级目录下的 png
    var textureFiles = await dir
        .list()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .map((f) => f.path)
        .toList();

    // 2. 如果同级没找到，查找子目录 (如 textures, *.4096 等)
    if (textureFiles.isEmpty) {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final subTextures = await entity
              .list()
              .where((f) => f.path.toLowerCase().endsWith('.png'))
              .map((f) => f.path)
              .toList();
          textureFiles.addAll(subTextures);
        }
      }
    }

    textureFiles.sort();

    if (textureFiles.isEmpty) {
      throw Exception('No texture (.png) files found near $mocPath');
    }

    await _loadModelInternal(
      mocPath: mocPath,
      texturePaths: textureFiles,
      isAsset: false,
    );

    // 保存模型路径 (保存包含 moc3 的文件夹路径)
    _currentModelPath = dir.path;
    await _saveModelPath(dir.path);
  }

  /// 加载保存的模型路径（如果存在）
  Future<void> loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_prefKeyModelPath);

    if (savedPath != null && await Directory(savedPath).exists()) {
      try {
        await loadModelFromDir(savedPath);
        _currentModelPath = savedPath;
        if (kDebugMode) {
          debugPrint('✓ Loaded saved model from: $savedPath');
        }
      } catch (e) {
        debugPrint('⚠ Failed to load saved model: $e');
        // 如果加载失败，清除保存的路径并加载默认模型
        await _saveModelPath(null);
        await loadModel();
      }
    } else {
      // 没有保存的模型，加载默认模型
      await loadModel();
    }
  }

  /// 保存模型路径
  Future<void> _saveModelPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_prefKeyModelPath);
    } else {
      await prefs.setString(_prefKeyModelPath, path);
    }
  }

  /// 从本地目录加载模型
  Future<void> loadModelFromDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw Exception('Directory not found: $dirPath');
    }

    // 1. 优先查找 .model3.json
    final files = await dir.list(recursive: true).toList();
    File? model3JsonFile;
    try {
      model3JsonFile =
          files.firstWhere((f) => f.path.toLowerCase().endsWith('.model3.json'))
              as File;
    } catch (_) {}

    if (model3JsonFile != null) {
      debugPrint('Found model config: ${model3JsonFile.path}');
      await _loadModelFromJsonFile(model3JsonFile);
    } else {
      // Fallback: 查找 .moc3
      final mocFile =
          files.firstWhere(
                (f) => f.path.toLowerCase().endsWith('.moc3'),
                orElse: () =>
                    throw Exception('No .moc3 file found in $dirPath'),
              )
              as File;

      // 查找纹理
      final textureFiles =
          files
              .where((f) => f.path.toLowerCase().endsWith('.png'))
              .map((f) => f.path)
              .toList()
            ..sort();

      if (textureFiles.isEmpty) {
        throw Exception('No texture (.png) files found in $dirPath');
      }

      await _loadModelInternal(
        mocPath: mocFile.path,
        texturePaths: textureFiles,
        isAsset: false,
      );
    }

    // 保存模型路径
    _currentModelPath = dirPath;
    await _saveModelPath(dirPath);
  }

  Future<void> _loadModelFromJsonFile(File jsonFile) async {
    final jsonContent = await jsonFile.readAsString();
    final setting = Live2DModelSetting.fromJson(json.decode(jsonContent));

    if (setting.moc == null)
      throw Exception('Moc file not defined in ${jsonFile.path}');

    final dir = jsonFile.parent.path;
    final mocPath = path.join(dir, setting.moc!);
    final texturePaths = setting.textures
        .map((t) => path.join(dir, t))
        .toList();

    // 处理表情
    _expressions.clear();
    setting.expressions.forEach((name, file) {
      _expressions[name] = path.join(dir, file);
    });
    debugPrint('Loaded ${_expressions.length} expressions');

    await _loadModelInternal(
      mocPath: mocPath,
      texturePaths: texturePaths,
      isAsset: false,
    );
  }

  Future<void> _loadModelInternal({
    required String mocPath,
    required List<String> texturePaths,
    required bool isAsset,
  }) async {
    // 卸载旧模型
    if (_initialized) {
      unload();
    }

    try {
      if (kDebugMode) {
        debugPrint('🎬 Starting Live2D model initialization from $mocPath...');
      }

      // 加载 .moc3 文件
      Uint8List moc3Data;
      if (isAsset) {
        final bytes = await rootBundle.load(mocPath);
        moc3Data = bytes.buffer.asUint8List();
      } else {
        moc3Data = await File(mocPath).readAsBytes();
      }

      if (kDebugMode) {
        debugPrint('✓ Loaded moc3 (${moc3Data.length} bytes)');
      }

      // 确保数据是有效的 List<int>，并且不为空
      final mocBytes = moc3Data.toList();
      if (mocBytes.isEmpty) {
        throw Exception('Moc3 data is empty');
      }

      // 检查模型版本兼容性
      // 注意：某些情况下，直接传递未对齐的字节数组给 Rust 的检查函数会导致 panic (slice::from_raw_parts alignment check)
      // live2DModelLoad 内部通常会处理对齐问题，所以我们可以跳过这个检查以避免崩溃
      // await _checkModelVersion(mocBytes);

      // 加载模型到 Rust
      _modelHandle = live2DModelLoad(mocBytes: mocBytes);

      if (_modelHandle == null) {
        throw Exception('Failed to load model: null handle returned');
      }

      if (kDebugMode) {
        debugPrint('✓ Live2D model loaded: $_modelHandle');
      }

      // 打印调试信息并初始化默认状态
      _initDebugInfo();

      // 加载纹理图片
      await _loadTextures(texturePaths, isAsset);

      // 生成第一帧
      _updateFrame();

      if (kDebugMode) {
        if (_currentFrame != null) {
          debugPrint(
            '✓ First frame generated: ${_currentFrame!.drawables.length} drawables',
          );
          debugPrint(
            '  Canvas size: ${_currentFrame!.canvasWidth}x${_currentFrame!.canvasHeight}',
          );
        } else {
          debugPrint('⚠ Warning: First frame is null');
        }
      }

      _initialized = true;

      if (kDebugMode) {
        debugPrint('✅ Live2D model initialization completed');
      }

      // 通知监听者模型已加载
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading Live2D model: $e');
      _initialized = false;
      rethrow;
    }
  }

  /// 检查模型版本兼容性
  Future<void> _checkModelVersion(List<int> mocBytes) async {
    try {
      // 获取 Core 版本信息
      final coreVersion = live2DCoreVersion();
      final latestMocVersion = live2DCoreLatestMocVersion();

      debugPrint('Live2D Core version: $coreVersion');
      debugPrint('Latest supported moc version: $latestMocVersion');

      // 检查模型一致性
      final isConsistent = live2DCoreCheckMocConsistency(mocBytes: mocBytes);
      if (!isConsistent) {
        throw Exception('Model consistency check failed');
      }

      // 获取模型的实际版本
      try {
        final modelVersion = live2DCoreMocVersion(mocBytes: mocBytes);
        debugPrint('Model moc version: $modelVersion');

        // 验证版本兼容性
        if (modelVersion != latestMocVersion) {
          debugPrint(
            'Warning: Model version ($modelVersion) differs from latest supported version ($latestMocVersion). '
            'This may cause compatibility issues.',
          );
        } else {
          debugPrint('Model version is compatible with Live2D Core');
        }
      } catch (e) {
        debugPrint('Warning: Could not determine model version: $e');
        // 继续加载，因为版本检查可能不是必需的
      }
    } catch (e) {
      debugPrint('Warning: Model version check failed: $e');
    }
  }

  /// 加载纹理图片
  Future<void> _loadTextures(List<String> texturePaths, bool isAsset) async {
    _textures.clear();

    for (int i = 0; i < texturePaths.length; i++) {
      try {
        final texturePath = texturePaths[i];
        debugPrint('Loading texture $i from: $texturePath');

        Uint8List bytes;
        if (isAsset) {
          final byteData = await rootBundle.load(texturePath);
          bytes = byteData.buffer.asUint8List();
        } else {
          bytes = await File(texturePath).readAsBytes();
        }

        if (bytes.isEmpty) {
          debugPrint('Warning: Texture $i is empty: $texturePath');
          continue;
        }

        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        _textures.add(frame.image);
        debugPrint(
          'Successfully loaded texture $i: ${frame.image.width}x${frame.image.height}',
        );
      } catch (e, stackTrace) {
        debugPrint('Error loading texture $i from ${texturePaths[i]}: $e');
        debugPrint('Stack trace: $stackTrace');
        // 继续加载其他纹理，不中断整个过程
      }
    }

    if (_textures.isEmpty) {
      throw Exception(
        'Failed to load any textures. '
        'Please ensure assets are properly configured or file path is correct.',
      );
    }

    debugPrint(
      'Total textures loaded: ${_textures.length}/${texturePaths.length}',
    );
  }

  /// 更新当前帧
  void _updateFrame() {
    if (_modelHandle == null) return;
    try {
      final newFrame = live2DModelStep(handle: _modelHandle!);
      _currentFrame = newFrame;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating frame: $e');
    }
  }

  FrameDto? get currentFrame => _currentFrame;
  List<ui.Image> get textures => _textures;
  bool get isLoaded => _modelHandle != null && _textures.isNotEmpty;
  String? get currentModelPath => _currentModelPath;
  List<String> get availableExpressions => _expressions.keys.toList();

  /// 卸载模型
  void unload() {
    if (_modelHandle != null) {
      try {
        live2DModelUnload(handle: _modelHandle!);
        if (kDebugMode) {
          debugPrint('✓ Model unloaded');
        }
      } catch (e) {
        debugPrint('⚠ Error unloading: $e');
      }
      _modelHandle = null;
    }
    _textures.clear();
    _currentFrame = null;
    _initialized = false;
  }

  void _initDebugInfo() {
    if (_modelHandle == null) return;

    try {
      final parts = live2DModelGetPartIds(handle: _modelHandle!);
      debugPrint('📦 Available Parts (${parts.length}):');
      for (final p in parts) {
        debugPrint('  - $p');
      }

      final armParts = parts
          .where((p) => p.toLowerCase().contains('arm'))
          .toList();
      if (armParts.length > 2) {
        debugPrint(
          '  -> Detected multiple arm parts, attempting to auto-hide variants...',
        );
        for (final p in armParts) {
          final lower = p.toLowerCase();
          if (lower.contains('02') ||
              (lower.contains('b') && !lower.contains('body')) ||
              lower.contains('down') ||
              lower.contains('back')) {
            setPartOpacity(p, 0.0);
            debugPrint('  -> Auto-hiding part: $p');
          } else {
            setPartOpacity(p, 1.0);
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting parts: $e');
    }

    try {
      final params = live2DModelGetParameterIds(handle: _modelHandle!);
      _availableParameters = Set.from(params);
      debugPrint('🔧 Available Parameters (${params.length}):');
      for (final p in params) {
        debugPrint('  - $p');
      }
    } catch (e) {
      debugPrint('Error getting parameters: $e');
    }
  }

  void setParameter(String parameterId, double value) {
    if (_modelHandle == null || !_initialized) return;

    // 检查参数是否存在，避免报错
    if (!_availableParameters.contains(parameterId)) {
      return;
    }

    try {
      live2DModelSetParameter(
        handle: _modelHandle!,
        parameterId: parameterId,
        value: value,
      );
    } catch (e) {
      debugPrint('Error setting parameter $parameterId: $e');
    }
  }

  /// 设置 Part 不透明度
  void setPartOpacity(String partId, double opacity) {
    if (_modelHandle == null) return;
    try {
      live2DModelSetPartOpacity(
        handle: _modelHandle!,
        partId: partId,
        opacity: opacity,
      );
    } catch (e) {
      debugPrint('Error setting part $partId: $e');
    }
  }

  /// 设置表情
  Future<void> setExpression(String expressionName) async {
    final expPath = _expressions[expressionName];
    if (expPath == null) {
      debugPrint('Expression not found: $expressionName');
      return;
    }

    try {
      String content;
      // Check if it's an asset or file
      if (expPath.startsWith('assets/') || expPath.startsWith('assets\\')) {
        content = await rootBundle.loadString(expPath);
      } else {
        content = await File(expPath).readAsString();
      }

      final jsonMap = json.decode(content);
      final params = jsonMap['Parameters'];
      if (params is List) {
        for (var p in params) {
          final id = p['Id'];
          final value = p['Value'];
          // Blend mode is ignored for now
          if (id != null && value is num) {
            setParameter(id, value.toDouble());
          }
        }
      }
      debugPrint('Applied expression: $expressionName');
    } catch (e) {
      debugPrint('Failed to load expression $expressionName: $e');
    }
  }

  /// 更新动画帧（可以在定时器中调用）
  void update() {
    if (_modelHandle == null || !_initialized) return;
    _updateFrame();
  }
}

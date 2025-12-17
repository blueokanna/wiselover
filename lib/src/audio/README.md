# Sherpa-ONNX 语音识别模块

## 概述

本模块提供基于 Sherpa-ONNX 的中文语音识别功能的完整集成。

## 模型配置

### 模型文件结构

```
assets/sherpa/chinese/
├── encoder.int8.onnx      # 编码器（量化版本）
├── decoder.onnx           # 解码器
├── joiner.int8.onnx       # 联接器（量化版本）
├── tokens.txt             # 词表
└── bpe.model              # BPE 分词器
```

### 使用方法

#### 1. 初始化模型

```dart
import 'package:wiselover/src/audio/sherpa_model_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await SherpaModelManager.instance.init();
    print('✓ 模型初始化成功');
  } catch (e) {
    print('✗ 模型初始化失败: $e');
  }
  
  runApp(const MyApp());
}
```

#### 2. 检查模型可用性

```dart
// 检查所有模型文件是否已加载
bool hasModel = await SherpaModelManager.instance.hasModel;
if (hasModel) {
  print('✓ 所有模型文件已就绪');
} else {
  print('⚠ 模型文件不完整');
}
```

#### 3. 获取模型配置

```dart
try {
  final config = await SherpaModelManager.instance.getModelConfig();
  print(config); // 打印完整配置
  
  // 使用各个模型路径
  final encoderPath = config.encoderPath;
  final decoderPath = config.decoderPath;
  // ...
} catch (e) {
  print('模型未初始化: $e');
}
```

#### 4. 查看模型大小

```dart
final sizeInBytes = await SherpaModelManager.instance.getModelSize();
final sizeInMB = sizeInBytes / (1024 * 1024);
print('模型大小: ${sizeInMB.toStringAsFixed(2)} MB');
```

#### 5. 清除模型缓存

```dart
// 删除本地缓存的模型文件（重新初始化时会重新复制）
await SherpaModelManager.instance.clearCache();
```

## 模型说明

### Encoder（编码器）
- **文件**: `encoder.int8.onnx`
- **大小**: ~761 MB（INT8 量化版本）
- **功能**: 处理音频输入，生成编码表示

### Decoder（解码器）
- **文件**: `decoder.onnx`
- **大小**: ~8.5 MB
- **功能**: 基于编码表示生成预测 token

### Joiner（联接器）
- **文件**: `joiner.int8.onnx`
- **大小**: ~1.5 MB（INT8 量化版本）
- **功能**: 联接编码器和解码器的输出

### Tokens & BPE
- **tokens.txt**: 词汇表（中文 token）
- **bpe.model**: 字节对编码（BPE）分词器

## 工作流程

```
1. init() 
   ↓
2. 检查应用缓存目录
   ↓
3. 如果文件不存在，从 assets 复制
   ↓
4. 验证所有必需文件
   ↓
5. 模型就绪
```

## 错误处理

### 常见错误

| 错误 | 原因 | 解决方案 |
|-----|------|--------|
| `Failed to load assets` | assets 文件不存在 | 检查 `pubspec.yaml` 中的 assets 声明 |
| `Permission denied` | 缓存目录权限问题 | 检查应用权限配置 |
| `File not found` | 模型文件复制失败 | 检查磁盘空间和权限 |

## 性能特性

- **内存高效**: 使用 INT8 量化模型，减少内存占用
- **流式处理**: 支持实时语音输入
- **低延迟**: 优化的模型架构
- **中文优化**: 专为中文语音识别调优

## 集成示例

```dart
class AudioRecognizer {
  final SherpaModelManager _modelManager = SherpaModelManager.instance;
  late SherpaModelConfig _config;
  
  Future<void> initialize() async {
    await _modelManager.init();
    _config = await _modelManager.getModelConfig();
  }
  
  Future<String?> recognize(String audioPath) async {
    if (!await _modelManager.hasModel) {
      throw Exception('Model not available');
    }
    
    // 使用 _config 中的模型路径进行识别
    // encoder: _config.encoderPath
    // decoder: _config.decoderPath
    // joiner: _config.joinerPath
    // tokens: _config.tokensPath
    // bpe: _config.bpePath
    
    return 'Recognized text'; // 实现识别逻辑
  }
}
```

## 调试

启用调试日志查看初始化过程：

```dart
// 在 debug 构建时自动打印详细日志
// 日志示例：
// ✓ Created model directory: /data/user/0/com.example.app/app_support/sherpa_onnx
// Copying encoder.onnx from assets...
// ✓ Copied encoder.onnx (761133737 bytes)
// ✓ Sherpa model initialized successfully
```

## 参考资源

- [Sherpa-ONNX 官方文档](https://github.com/k2-fsa/sherpa-onnx)
- [预训练模型列表](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html)
- [中文 ASR 模型](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html#zipformer-transducer-models)

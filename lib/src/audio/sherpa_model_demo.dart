import 'package:flutter/material.dart';
import 'package:wiselover/src/audio/sherpa_model_manager.dart';

/// Sherpa 模型管理示例和集成测试
class SherpaModelDemo extends StatefulWidget {
  const SherpaModelDemo({super.key});

  @override
  State<SherpaModelDemo> createState() => _SherpaModelDemoState();
}

class _SherpaModelDemoState extends State<SherpaModelDemo> {
  String _status = '初始化中...';
  bool _isInitialized = false;
  SherpaModelConfig? _modelConfig;
  int _modelSize = 0;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      // 初始化模型
      await SherpaModelManager.instance.init();

      // 检查模型可用性
      final hasModel = await SherpaModelManager.instance.hasModel;

      // 获取模型配置
      final config = await SherpaModelManager.instance.getModelConfig();

      // 获取模型大小
      final size = await SherpaModelManager.instance.getModelSize();

      setState(() {
        _isInitialized = hasModel;
        _modelConfig = config;
        _modelSize = size;
        _status = hasModel
            ? '✓ 模型初始化成功\n'
                  '模型大小: ${(size / (1024 * 1024)).toStringAsFixed(2)} MB'
            : '⚠ 模型文件不完整';
      });
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _status = '✗ 初始化失败:\n$e';
      });
    }
  }

  Future<void> _clearCache() async {
    try {
      await SherpaModelManager.instance.clearCache();
      setState(() {
        _status = '✓ 缓存已清除\n请重启应用重新加载模型';
        _isInitialized = false;
      });
    } catch (e) {
      setState(() {
        _status = '✗ 清除失败:\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sherpa 模型配置')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 状态显示
              Card(
                color: _isInitialized
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: _isInitialized ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 模型配置详情
              if (_modelConfig != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '模型配置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildConfigRow('Encoder', _modelConfig!.encoderPath),
                        _buildConfigRow('Decoder', _modelConfig!.decoderPath),
                        _buildConfigRow('Joiner', _modelConfig!.joinerPath),
                        _buildConfigRow('Tokens', _modelConfig!.tokensPath),
                        _buildConfigRow('BPE', _modelConfig!.bpePath),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // 操作按钮
              Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _initializeModel,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载模型'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _clearCache,
                    icon: const Icon(Icons.delete),
                    label: const Text('清除缓存'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 模型信息
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '模型信息',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('• 类型: Sherpa-ONNX 流式转录器'),
                      Text('• 语言: 中文'),
                      Text('• 架构: Zipformer Transducer'),
                      Text('• 量化: INT8（编码器、联接器）'),
                      Text(
                        '• 大小: ${(_modelSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigRow(String label, String path) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            path,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

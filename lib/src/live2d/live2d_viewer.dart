import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wiselover/src/rust/api/live2d_model_api.dart';
import 'package:wiselover/src/live2d/live2d_model_manager.dart';

enum Live2DEmotion { neutral, happy, angry, sad, surprised, shy }

/// Live2D 模型查看器 Widget
class Live2DViewer extends StatefulWidget {
  final bool wireframe;
  final Live2DEmotion emotion;

  const Live2DViewer({
    super.key,
    this.wireframe = false,
    this.emotion = Live2DEmotion.neutral,
  });

  @override
  State<Live2DViewer> createState() => _Live2DViewerState();
}

class _Live2DViewerState extends State<Live2DViewer> {
  bool _isLoading = true;
  String? _error;
  Timer? _updateTimer;

  // 交互目标位置
  double _targetX = 0.0;
  double _targetY = 0.0;

  // 当前平滑位置
  double _currentX = 0.0;
  double _currentY = 0.0;

  // 情绪参数平滑过渡
  final Map<String, double> _currentParams = {};

  // 随机动作状态
  double _saccadeX = 0.0;
  double _saccadeY = 0.0;
  double _saccadeTimer = 0.0;
  double _blinkTimer = 0.0;
  double _nextBlinkTime = 3.0;

  // Shader cache
  final Map<ui.Image, ui.ImageShader> _shaderCache = {};
  List<ui.Image>? _lastTextures;

  @override
  void initState() {
    super.initState();
    Live2DModelManager.instance.addListener(_onModelUpdate);
    _loadModel();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    Live2DModelManager.instance.removeListener(_onModelUpdate);
    _shaderCache.clear();
    super.dispose();
  }

  void _onModelUpdate() {
    if (Live2DModelManager.instance.textures != _lastTextures) {
      _shaderCache.clear();
      _lastTextures = Live2DModelManager.instance.textures;
    }
    if (mounted) setState(() {});

    // 确保定时器在运行
    if (_updateTimer == null || !_updateTimer!.isActive) {
      _loadModel();
    }
  }

  Future<void> _loadModel() async {
    try {
      // 1. 确保模型已加载
      if (!Live2DModelManager.instance.isLoaded) {
        await Live2DModelManager.instance.loadSavedModel();
      }

      if (!Live2DModelManager.instance.isLoaded) {
        throw Exception('Model loaded but isLoaded returns false');
      }

      // 2. 启动动画循环
      _updateTimer?.cancel();
      var animationTime = 0.0;
      final random = math.Random();

      _updateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (mounted && Live2DModelManager.instance.isLoaded) {
          animationTime += 0.016;

          // --- 1. 基础交互平滑 (Interaction Smoothing) ---
          _currentX += (_targetX - _currentX) * 0.1;
          _currentY += (_targetY - _currentY) * 0.1;

          // --- 2. 心理学微动作 (Psychological Micro-movements) ---

          // Saccades (眼球快速扫视): 模拟人类不自觉的眼球运动
          _saccadeTimer += 0.016;
          if (_saccadeTimer > 2.0 + random.nextDouble() * 3.0) {
            _saccadeTimer = 0;
            // 只有在非专注模式(Neutral/Idle)下才会有明显的扫视
            if (widget.emotion == Live2DEmotion.neutral) {
              _saccadeX = (random.nextDouble() - 0.5) * 0.2;
              _saccadeY = (random.nextDouble() - 0.5) * 0.1;
            } else {
              _saccadeX = 0;
              _saccadeY = 0;
            }
          }

          // Blinking (自然眨眼): 包含双眨眼、长眨眼等模式
          _blinkTimer += 0.016;
          double eyeOpen = 1.0;
          if (_blinkTimer > _nextBlinkTime) {
            final blinkDuration = 0.2;
            final t = (_blinkTimer - _nextBlinkTime) / blinkDuration;
            if (t < 1.0) {
              eyeOpen = 1.0 - math.sin(t * math.pi);
            } else {
              _blinkTimer = 0;
              _nextBlinkTime = 2.0 + random.nextDouble() * 4.0;
              // 10% 概率出现双眨眼
              if (random.nextDouble() < 0.1) _nextBlinkTime = 0.3;
            }
          }

          // --- 3. 情绪参数目标 (Emotion Targets) ---
          // 定义不同情绪下的参数目标值
          final Map<String, double> emotionTargets = {};
          double breathSpeed = 1.0;
          double breathDepth = 1.0;

          switch (widget.emotion) {
            case Live2DEmotion.angry:
              emotionTargets['ParamBrowLForm'] = -0.8;
              emotionTargets['ParamBrowRForm'] = -0.8;
              emotionTargets['ParamBrowLY'] = -0.6;
              emotionTargets['ParamBrowRY'] = -0.6;
              emotionTargets['ParamEyeLOpen'] = 0.8; // 眯眼
              emotionTargets['ParamEyeROpen'] = 0.8;
              emotionTargets['ParamMouthForm'] = -0.8; // 嘴角向下
              emotionTargets['ParamBodyAngleX'] = 0.0; // 身体僵硬
              emotionTargets['ParamBodyAngleY'] = 0.0;
              emotionTargets['ParamBodyAngleZ'] = 0.0;
              breathSpeed = 2.5; // 呼吸急促
              breathDepth = 0.5; // 呼吸浅
              break;
            case Live2DEmotion.happy:
              emotionTargets['ParamBrowLForm'] = 0.5;
              emotionTargets['ParamBrowRForm'] = 0.5;
              emotionTargets['ParamBrowLY'] = 0.3;
              emotionTargets['ParamBrowRY'] = 0.3;
              emotionTargets['ParamMouthForm'] = 1.0; // 微笑
              emotionTargets['ParamCheek'] = 0.5; // 脸红
              emotionTargets['ParamBodyAngleZ'] = 2.0; // 轻微摇摆
              breathSpeed = 1.2;
              breathDepth = 1.1;
              break;
            case Live2DEmotion.sad:
              emotionTargets['ParamBrowLForm'] = -0.3;
              emotionTargets['ParamBrowRForm'] = -0.3;
              emotionTargets['ParamBrowLY'] = 0.2; // 眉毛内侧上扬(八字眉)
              emotionTargets['ParamBrowRY'] = 0.2;
              emotionTargets['ParamEyeLOpen'] = 0.85;
              emotionTargets['ParamEyeROpen'] = 0.85;
              emotionTargets['ParamHeadAngleZ'] = -5.0; // 垂头
              emotionTargets['ParamBodyAngleZ'] = -2.0;
              breathSpeed = 0.6; // 呼吸缓慢
              breathDepth = 0.8;
              break;
            case Live2DEmotion.surprised:
              emotionTargets['ParamBrowLY'] = 0.6;
              emotionTargets['ParamBrowRY'] = 0.6;
              emotionTargets['ParamEyeLOpen'] = 1.5; // 睁大眼
              emotionTargets['ParamEyeROpen'] = 1.5;
              emotionTargets['ParamMouthOpenY'] = 0.5; // 张嘴
              emotionTargets['ParamBodyAngleX'] = -2.0; // 后仰
              breathSpeed = 0.3; // 屏住呼吸
              breathDepth = 0.2;
              break;
            case Live2DEmotion.shy:
              emotionTargets['ParamBrowLY'] = -0.2;
              emotionTargets['ParamBrowRY'] = -0.2;
              emotionTargets['ParamCheek'] = 1.0; // 脸红
              emotionTargets['ParamEyeBallY'] = -0.5; // 视线向下
              emotionTargets['ParamBodyAngleZ'] = 5.0; // 扭捏
              emotionTargets['ParamBodyAngleY'] = 5.0; // 侧身
              breathSpeed = 1.5;
              breathDepth = 0.7;
              break;
            case Live2DEmotion.neutral:
            default:
              emotionTargets['ParamBrowLForm'] = 0.0;
              emotionTargets['ParamBrowRForm'] = 0.0;
              emotionTargets['ParamMouthForm'] = 0.0;
              emotionTargets['ParamCheek'] = 0.0;
              break;
          }

          // --- 4. 参数合成与应用 ---
          try {
            final mgr = Live2DModelManager.instance;

            // 呼吸 (Breathing)
            final breath =
                (math.sin(animationTime * 2.5 * breathSpeed) * 0.5 + 0.5) *
                breathDepth;
            mgr.setParameter('ParamBreath', breath);

            // 头部与身体跟随 (Head & Body Tracking)
            // 愤怒时减少跟随幅度(固执)，开心时增加幅度
            double trackScale = widget.emotion == Live2DEmotion.angry
                ? 0.3
                : 1.0;

            final lookX = (_currentX + _saccadeX) * 30.0 * trackScale;
            final lookY = (_currentY + _saccadeY) * 30.0 * trackScale;

            // 叠加 Idle 噪声 (Perlin noise would be better, but sine sum is okay)
            final idleX = math.sin(animationTime * 0.8) * 1.5;
            final idleY = math.sin(animationTime * 0.6) * 1.5;
            final idleZ = math.sin(animationTime * 0.4) * 1.0;

            mgr.setParameter('ParamAngleX', lookX + idleX);
            mgr.setParameter('ParamAngleY', lookY + idleY);
            mgr.setParameter('ParamAngleZ', (lookX * lookY / 100.0) + idleZ);

            // 眼睛 (Eyes)
            // 混合 眨眼 + 情绪修正
            double targetEyeOpen = emotionTargets['ParamEyeLOpen'] ?? 1.0;
            double finalEyeOpen = math.min(eyeOpen, targetEyeOpen); // 眨眼优先

            mgr.setParameter('ParamEyeLOpen', finalEyeOpen);
            mgr.setParameter('ParamEyeROpen', finalEyeOpen);

            // 眼球位置 (Eye Ball)
            // 害羞时视线强制向下，否则跟随鼠标+扫视
            double eyeBallX = _currentX + _saccadeX;
            double eyeBallY = _currentY + _saccadeY;
            if (widget.emotion == Live2DEmotion.shy) {
              eyeBallY = -0.6 + _saccadeY * 0.2; // 向下看
              eyeBallX = eyeBallX * 0.5; // 减少水平移动
            }
            mgr.setParameter('ParamEyeBallX', eyeBallX);
            mgr.setParameter('ParamEyeBallY', eyeBallY);

            // 眉毛与嘴巴 (Brows & Mouth) - 平滑过渡
            // 我们使用简单的 lerp 来平滑过渡到目标情绪参数
            emotionTargets.forEach((key, target) {
              final current = _currentParams[key] ?? 0.0;
              final next = current + (target - current) * 0.1; // 0.1 的平滑系数
              _currentParams[key] = next;
              mgr.setParameter(key, next);
            });

            // 身体 (Body)
            // 身体跟随头部，但有延迟和衰减
            mgr.setParameter(
              'ParamBodyAngleX',
              lookX * 0.1 + (emotionTargets['ParamBodyAngleX'] ?? 0),
            );
            mgr.setParameter(
              'ParamBodyAngleY',
              lookX * 0.05 + (emotionTargets['ParamBodyAngleY'] ?? 0),
            );
            mgr.setParameter(
              'ParamBodyAngleZ',
              lookX * 0.05 + (emotionTargets['ParamBodyAngleZ'] ?? 0),
            );

            // 头发物理 (Hair Physics)
            final hairPhysics =
                math.sin(animationTime * 3.0 + _currentX * 2.0) * 0.2;
            mgr.setParameter('ParamHairFront', hairPhysics);
            mgr.setParameter('ParamHairSide', -hairPhysics);
            mgr.setParameter('ParamHairBack', hairPhysics * 0.5);
          } catch (e) {
            // 忽略参数设置错误
          }

          Live2DModelManager.instance.update();
          if (mounted) setState(() {});
        } else {
          // 如果模型未加载，不要取消定时器，而是等待下一次检查
          // timer.cancel();
        }
      });

      setState(() => _isLoading = false);

      if (kDebugMode) {
        debugPrint('✓ Live2DViewer: Model loaded');
        final frame = Live2DModelManager.instance.currentFrame;
        if (frame != null) {
          debugPrint('  Drawables: ${frame.drawables.length}');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading model: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('加载模型失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadModel, child: const Text('重试')),
          ],
        ),
      );
    }

    if (!Live2DModelManager.instance.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return MouseRegion(
      onHover: (event) {
        final size = context.size;
        if (size != null) {
          final dx = (event.localPosition.dx / size.width) * 2 - 1;
          final dy = -((event.localPosition.dy / size.height) * 2 - 1);

          setState(() {
            _targetX = dx.clamp(-1.0, 1.0);
            _targetY = dy.clamp(-1.0, 1.0);
          });
        }
      },
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _Live2DPainter(
              textures: Live2DModelManager.instance.textures,
              frame: Live2DModelManager.instance.currentFrame,
              wireframe: widget.wireframe,
              shaderCache: _shaderCache,
            ),
          ),
        ),
      ),
    );
  }
}

class _Live2DPainter extends CustomPainter {
  final List<ui.Image> textures;
  final FrameDto? frame;
  final bool wireframe;
  final Map<ui.Image, ui.ImageShader> shaderCache;

  _Live2DPainter({
    required this.textures,
    required this.frame,
    required this.shaderCache,
    this.wireframe = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || f.drawables.isEmpty || textures.isEmpty) {
      return;
    }

    double? minX, maxX, minY, maxY;
    for (final d in f.drawables) {
      for (int i = 0; i + 1 < d.vertices.length; i += 2) {
        final x = d.vertices[i];
        final y = d.vertices[i + 1];
        minX = minX == null ? x : (x < minX ? x : minX);
        maxX = maxX == null ? x : (x > maxX ? x : maxX);
        minY = minY == null ? y : (y < minY ? y : minY);
        maxY = maxY == null ? y : (y > maxY ? y : maxY);
      }
    }

    final fallbackW = f.canvasWidth > 0 ? f.canvasWidth : 2.0;
    final fallbackH = f.canvasHeight > 0 ? f.canvasHeight : 2.0;

    final modelWidth = (minX != null && maxX != null)
        ? (maxX - minX).abs()
        : fallbackW;
    final modelHeight = (minY != null && maxY != null)
        ? (maxY - minY).abs()
        : fallbackH;

    final safeModelW = modelWidth <= 1e-6 ? fallbackW : modelWidth;
    final safeModelH = modelHeight <= 1e-6 ? fallbackH : modelHeight;

    final sx = size.width / safeModelW;
    final sy = size.height / safeModelH;
    final scale = (sx < sy ? sx : sy) * 1.25;

    // 模型中心，用于平移居中
    final centerModelX = (minX != null && maxX != null)
        ? (minX + maxX) / 2
        : 0.0;
    final centerModelY = (minY != null && maxY != null)
        ? (minY + maxY) / 2
        : 0.0;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.translate(0, size.height * 0.1);
    canvas.scale(scale, -scale);
    canvas.translate(-centerModelX, -centerModelY);

    final sorted = List<DrawableFrameDto>.from(f.drawables)
      ..sort((a, b) => a.drawOrder.compareTo(b.drawOrder));

    for (final d in sorted) {
      // 1. 跳过完全透明的部件
      if (d.opacity <= 0.001) continue;

      // 2. 基础数据校验
      if (d.vertices.length < 4 || d.indices.length < 3) {
        continue;
      }

      // 3. 纹理索引校验
      if (d.textureIndex < 0 || d.textureIndex >= textures.length) {
        continue;
      }

      final image = textures[d.textureIndex];

      // 4. 获取或创建 Shader
      ui.ImageShader? shader = shaderCache[image];
      if (shader == null) {
        // 使用标准 Shader，手动处理 UV 坐标
        shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList([
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        );
        shaderCache[image] = shader;
      }

      // 5. 构造顶点数据
      // 手动转换 UV 坐标以匹配 Flutter 坐标系
      // Live2D UV (0~1, V翻转) -> Flutter Pixel (0~W, 0~H)
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final texCoords = Float32List(d.uvs.length);

      for (int i = 0; i < d.uvs.length; i += 2) {
        texCoords[i] = d.uvs[i] * w;
        texCoords[i + 1] = (1.0 - d.uvs[i + 1]) * h;
      }

      try {
        final vertices = ui.Vertices.raw(
          ui.VertexMode.triangles,
          d.vertices,
          textureCoordinates: texCoords,
          indices: d.indices,
        );

        final paint = Paint()
          ..shader = shader
          ..isAntiAlias = true
          ..filterQuality = FilterQuality
              .medium // 优化：使用 medium 质量以平衡性能和画质
          ..blendMode = BlendMode.srcOver;

        // 应用 Multiply Color 和 Opacity
        // Live2D 的 multiplyColor 通常是 [R, G, B, A]，我们主要使用 RGB 进行乘色
        // Opacity 控制整体透明度
        final alpha = (d.opacity * 255).clamp(0, 255).toInt();
        final r = (d.multiplyColor[0] * 255).clamp(0, 255).toInt();
        final g = (d.multiplyColor[1] * 255).clamp(0, 255).toInt();
        final b = (d.multiplyColor[2] * 255).clamp(0, 255).toInt();

        paint.color = Color.fromARGB(alpha, r, g, b);

        // 使用 modulate 混合模式，这样 paint.color 会与纹理颜色相乘
        // 纹理颜色 * MultiplyColor * Opacity
        canvas.drawVertices(vertices, BlendMode.modulate, paint);
      } catch (e) {
        // debugPrint('Error drawing drawable: $e');
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Live2DPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.textures.length != textures.length;
  }
}

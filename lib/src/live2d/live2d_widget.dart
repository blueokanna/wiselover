import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class Live2DDrawableFrame {
  final int textureIndex;
  final List<double> vertices; // [x0, y0, x1, y1, ...]
  final List<double> uvs; // [u0, v0, u1, v1, ...] 归一化
  final List<int> indices;
  final double opacity;
  final Color multiplyColor;
  final Color screenColor;
  final int drawOrder;

  const Live2DDrawableFrame({
    required this.textureIndex,
    required this.vertices,
    required this.uvs,
    required this.indices,
    required this.opacity,
    required this.multiplyColor,
    required this.screenColor,
    required this.drawOrder,
  });
}

class Live2DFrame {
  final double canvasWidth;
  final double canvasHeight;
  final List<Live2DDrawableFrame> drawables;

  const Live2DFrame({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.drawables,
  });
}

class Live2DWidget extends StatelessWidget {
  final List<ui.Image> textures;
  final Live2DFrame? frame;
  final Color backgroundColor;

  const Live2DWidget({
    super.key,
    required this.textures,
    required this.frame,
    this.backgroundColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Live2DPainter(
        textures: textures,
        frame: frame,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

class _Live2DPainter extends CustomPainter {
  final List<ui.Image> textures;
  final Live2DFrame? frame;
  final Color backgroundColor;
  final Map<ui.Image, ui.ImageShader> _shaderCache = {};

  // 复用 Paint，避免每帧大量分配
  final Paint _paintMultiply = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..blendMode = BlendMode.srcOver;

  final Paint _paintScreen = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..blendMode = BlendMode.screen;

  _Live2DPainter({
    required this.textures,
    required this.frame,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 清背景
    if (backgroundColor.opacity > 0) {
      final paint = Paint()..color = backgroundColor;
      canvas.drawRect(Offset.zero & size, paint);
    }

    final f = frame;
    if (f == null || f.drawables.isEmpty || textures.isEmpty) {
      return;
    }

    // Live2D 坐标系：原点在中心，Y轴向上
    // Flutter 坐标系：原点在左上角，Y轴向下
    final cw = f.canvasWidth > 0 ? f.canvasWidth : size.width;
    final ch = f.canvasHeight > 0 ? f.canvasHeight : size.height;

    // 计算缩放比例
    final sx = size.width / cw;
    final sy = size.height / ch;
    final scale = (sx < sy ? sx : sy) * 0.9;

    // 坐标转换：平移到中心，缩放，翻转Y轴
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale, -scale); // 负号翻转Y轴

    // 按 drawOrder 排序
    final sorted = List<Live2DDrawableFrame>.from(f.drawables)
      ..sort((a, b) => a.drawOrder.compareTo(b.drawOrder));

    // 绘制所有 drawable
    for (final d in sorted) {
      if (d.opacity <= 0.0) continue;
      if (d.vertices.length < 4 || d.indices.length < 3) continue;
      if (d.textureIndex < 0 || d.textureIndex >= textures.length) continue;

      final image = textures[d.textureIndex];
      if (image.width == 0 || image.height == 0) continue;

      // 准备顶点坐标（Live2D坐标系：原点在中心，Y轴向上）
      final positions = <ui.Offset>[];
      for (var i = 0; i + 1 < d.vertices.length; i += 2) {
        positions.add(Offset(d.vertices[i], d.vertices[i + 1]));
      }

      if (positions.isEmpty) continue;

      final texW = image.width.toDouble();
      final texH = image.height.toDouble();
      final texCoords = <ui.Offset>[];
      final uvCount = d.uvs.length ~/ 2;
      final minCount = uvCount < positions.length ? uvCount : positions.length;

      for (var i = 0; i < minCount * 2 && i + 1 < d.uvs.length; i += 2) {
        final u = d.uvs[i].clamp(0.0, 1.0);
        final v = d.uvs[i + 1].clamp(0.0, 1.0);
        texCoords.add(Offset(u * texW, (1.0 - v) * texH));
      }

      while (texCoords.length < positions.length) {
        texCoords.add(
          texCoords.isNotEmpty ? texCoords.first : const Offset(0.0, 0.0),
        );
      }

      // 验证索引有效性
      final validIndicesCount = (d.indices.length ~/ 3) * 3;
      if (validIndicesCount == 0) continue;

      // 过滤无效的索引
      final validIndices = <int>[];
      for (var i = 0; i < validIndicesCount; i++) {
        final idx = d.indices[i];
        if (idx >= 0 && idx < positions.length) {
          validIndices.add(idx);
        }
      }

      if (validIndices.length < 3) continue;

      // 创建顶点数据
      final positionList = Float32List.fromList(
        positions.expand((e) => [e.dx, e.dy]).toList(),
      );
      final texCoordList = Float32List.fromList(
        texCoords.expand((e) => [e.dx, e.dy]).toList(),
      );
      final indexList = Uint16List.fromList(validIndices);

      // 创建/缓存 ImageShader
      ui.ImageShader? shader = _shaderCache[image];
      if (shader == null) {
        try {
          shader = ui.ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            Float64List.fromList([
              1.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
              0.0,
              0.0,
              0.0,
              0.0,
              1.0,
            ]),
          );
          _shaderCache[image] = shader;
        } catch (e) {
          continue;
        }
      }
      // 创建顶点对象
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positionList,
        textureCoordinates: texCoordList,
        indices: indexList,
      );

      // Live2D 标准混合：Multiply + Screen
      final opacity = d.opacity.clamp(0.0, 1.0);
      final alphaValue = (opacity * 255).round().clamp(1, 255);

      // Multiply color: 检查值
      final multiply = d.multiplyColor;
      final mulR = multiply.red;
      final mulG = multiply.green;
      final mulB = multiply.blue;
      // 检查 multiplyColor 是否接近黑色或白色
      final isMultiplyBlack = mulR < 3 && mulG < 3 && mulB < 3;
      final isMultiplyWhite = mulR > 252 && mulG > 252 && mulB > 252;

      _paintMultiply
        ..shader = shader
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high; // 提高过滤质量

      if (isMultiplyBlack || isMultiplyWhite) {
        // 跳过 multiply，直接使用 srcOver 绘制纹理
        _paintMultiply
          ..blendMode = BlendMode.srcOver
          ..color = Color.fromARGB(alphaValue, 255, 255, 255);
      } else {
        // 使用 modulate 应用 multiplyColor
        _paintMultiply
          ..blendMode = BlendMode.modulate
          ..color = Color.fromARGB(alphaValue, mulR, mulG, mulB);
      }
      _paintMultiply.colorFilter = null;

      // Screen pass
      final screen = d.screenColor;
      final screenA = screen.alpha;
      final screenColor = Color.fromARGB(
        (alphaValue * (screenA / 255)).round().clamp(0, 255),
        screen.red,
        screen.green,
        screen.blue,
      );
      _paintScreen
        ..shader = shader
        ..isAntiAlias = true
        ..filterQuality = FilterQuality
            .high // 提高过滤质量
        ..blendMode = BlendMode.screen
        ..color = screenColor
        ..colorFilter = null;

      try {
        canvas.drawVertices(vertices, _paintMultiply.blendMode, _paintMultiply);
        if (screenA > 0) {
          final screenLayerRect = Rect.fromLTWH(
            -size.width * 2,
            -size.height * 2,
            size.width * 4,
            size.height * 4,
          );
          canvas.saveLayer(screenLayerRect, Paint());
          canvas.drawVertices(vertices, BlendMode.screen, _paintScreen);
          canvas.restore();
        }
      } catch (e) {
        // 忽略绘制错误
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Live2DPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.textures != textures ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

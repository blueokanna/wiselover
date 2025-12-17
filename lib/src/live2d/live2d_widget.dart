import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class Live2DDrawableFrame {
  final int textureIndex;
  final List<double> vertices; // [x0, y0, x1, y1, ...]
  final List<double> uvs; // [u0, v0, u1, v1, ...]
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
      // 基本验证
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

      // 准备纹理坐标（归一化坐标 0-1）
      final texCoords = <ui.Offset>[];
      final uvCount = d.uvs.length ~/ 2;
      final minCount = uvCount < positions.length ? uvCount : positions.length;

      for (var i = 0; i < minCount * 2 && i + 1 < d.uvs.length; i += 2) {
        final u = d.uvs[i].clamp(0.0, 1.0);
        final v = d.uvs[i + 1].clamp(0.0, 1.0);
        texCoords.add(Offset(u, v));
      }

      // 如果UV数量不足，用第一个UV或默认值填充
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

      // 创建 ImageShader
      ui.ImageShader? shader;
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
      } catch (e) {
        continue;
      }

      // 创建顶点对象
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        positionList,
        textureCoordinates: texCoordList,
        indices: indexList,
      );

      // 处理 multiply color
      final multiply = d.multiplyColor;
      ColorFilter? colorFilter;
      final r = multiply.red / 255.0;
      final g = multiply.green / 255.0;
      final b = multiply.blue / 255.0;
      final a = multiply.alpha / 255.0;

      if ((r - 1.0).abs() > 0.001 ||
          (g - 1.0).abs() > 0.001 ||
          (b - 1.0).abs() > 0.001 ||
          (a - 1.0).abs() > 0.001) {
        colorFilter = ColorFilter.matrix([
          r,
          0,
          0,
          0,
          0,
          0,
          g,
          0,
          0,
          0,
          0,
          0,
          b,
          0,
          0,
          0,
          0,
          0,
          a,
          0,
        ]);
      }

      // 创建 Paint
      final opacity = d.opacity.clamp(0.0, 1.0);
      final alphaValue = (opacity * 255).round().clamp(1, 255);

      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..shader = shader
        ..color = Color.fromARGB(alphaValue, 255, 255, 255)
        ..blendMode = BlendMode.srcOver
        ..isAntiAlias = true;

      if (colorFilter != null) {
        paint.colorFilter = colorFilter;
      }

      // 绘制
      try {
        canvas.drawVertices(vertices, BlendMode.srcOver, paint);
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

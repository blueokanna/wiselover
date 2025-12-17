import '../frb_generated.dart';
import '../lib.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// 加载一个 moc3 模型，返回句柄
BigInt live2DModelLoad({required List<int> mocBytes}) => RustLib.instance.api
    .crateApiLive2DModelApiLive2DModelLoad(mocBytes: mocBytes);

/// 卸载一个模型
void live2DModelUnload({required BigInt handle}) => RustLib.instance.api
    .crateApiLive2DModelApiLive2DModelUnload(handle: handle);

/// 设置模型参数值（用于动画）
void live2DModelSetParameter({
  required BigInt handle,
  required String parameterId,
  required double value,
}) => RustLib.instance.api.crateApiLive2DModelApiLive2DModelSetParameter(
  handle: handle,
  parameterId: parameterId,
  value: value,
);

/// 生成一帧渲染数据（目前不做参数动画，只是把底层顶点 / 颜色等导出来）
FrameDto live2DModelStep({required BigInt handle}) =>
    RustLib.instance.api.crateApiLive2DModelApiLive2DModelStep(handle: handle);

/// 设置 Part 的不透明度
void live2DModelSetPartOpacity({
  required BigInt handle,
  required String partId,
  required double opacity,
}) => RustLib.instance.api.crateApiLive2DModelApiLive2DModelSetPartOpacity(
  handle: handle,
  partId: partId,
  opacity: opacity,
);

/// 获取所有参数 ID
List<String> live2DModelGetParameterIds({required BigInt handle}) => RustLib
    .instance
    .api
    .crateApiLive2DModelApiLive2DModelGetParameterIds(handle: handle);

/// 获取所有 Part ID
List<String> live2DModelGetPartIds({required BigInt handle}) => RustLib
    .instance
    .api
    .crateApiLive2DModelApiLive2DModelGetPartIds(handle: handle);

/// Dart 侧使用的单个 Drawable 帧数据
class DrawableFrameDto {
  final int textureIndex;

  /// 展平后的顶点坐标数组：[x0, y0, x1, y1, ...]
  final Float32List vertices;

  /// 展平后的纹理坐标数组：[u0, v0, u1, v1, ...]
  final Float32List uvs;

  /// 索引缓冲，指向 `vertices` / `uvs` 中的顶点下标
  final Uint16List indices;
  final double opacity;

  /// 乘色
  final F32Array4 multiplyColor;

  /// 屏幕色
  final F32Array4 screenColor;

  /// 当前渲染顺序（越大越后画）
  final int drawOrder;

  const DrawableFrameDto({
    required this.textureIndex,
    required this.vertices,
    required this.uvs,
    required this.indices,
    required this.opacity,
    required this.multiplyColor,
    required this.screenColor,
    required this.drawOrder,
  });

  @override
  int get hashCode =>
      textureIndex.hashCode ^
      vertices.hashCode ^
      uvs.hashCode ^
      indices.hashCode ^
      opacity.hashCode ^
      multiplyColor.hashCode ^
      screenColor.hashCode ^
      drawOrder.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrawableFrameDto &&
          runtimeType == other.runtimeType &&
          textureIndex == other.textureIndex &&
          vertices == other.vertices &&
          uvs == other.uvs &&
          indices == other.indices &&
          opacity == other.opacity &&
          multiplyColor == other.multiplyColor &&
          screenColor == other.screenColor &&
          drawOrder == other.drawOrder;
}

/// 一帧 Live2D 的整体数据
class FrameDto {
  final double canvasWidth;
  final double canvasHeight;
  final List<DrawableFrameDto> drawables;

  const FrameDto({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.drawables,
  });

  @override
  int get hashCode =>
      canvasWidth.hashCode ^ canvasHeight.hashCode ^ drawables.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameDto &&
          runtimeType == other.runtimeType &&
          canvasWidth == other.canvasWidth &&
          canvasHeight == other.canvasHeight &&
          drawables == other.drawables;
}

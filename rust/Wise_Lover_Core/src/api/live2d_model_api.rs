use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use live2d_core::core::{
    CanvasInfo, Model, Moc, MocError, Vector2, Vector4,
};

/// 内部：一个已加载的 Live2D 模型实例（持有 moc 与 model）
struct Live2dModelInstance {
    #[allow(dead_code)]
    moc: Moc,
    model: Model,
}

fn core() -> &'static live2d_core::core::CubismCore {
    // 复用 wise_lover_boot_api 里已经使用的 CubismCore 初始化逻辑会更好，
    // 这里为了避免循环依赖简单重新实现一份懒加载。
    static CORE: OnceLock<live2d_core::core::CubismCore> = OnceLock::new();
    CORE.get_or_init(|| live2d_core::core::CubismCore::default())
}

fn models() -> &'static Mutex<HashMap<u64, Live2dModelInstance>> {
    static MODELS: OnceLock<Mutex<HashMap<u64, Live2dModelInstance>>> = OnceLock::new();
    MODELS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_handle() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// Dart 侧使用的单个 Drawable 帧数据
#[derive(Debug, Clone)]
pub struct DrawableFrameDto {
    /// 对应原始 drawable 的索引（用于遮罩查找）
    pub index: u32,
    pub texture_index: u32,
    /// 展平后的顶点坐标数组：[x0, y0, x1, y1, ...]
    pub vertices: Vec<f32>,
    /// 展平后的纹理坐标数组：[u0, v0, u1, v1, ...]
    pub uvs: Vec<f32>,
    /// 索引缓冲，指向 `vertices` / `uvs` 中的顶点下标
    pub indices: Vec<u16>,
    /// 遮罩列表，元素为 drawable 索引
    pub masks: Vec<u16>,
    pub opacity: f32,
    /// 乘色
    pub multiply_color: [f32; 4],
    /// 屏幕色
    pub screen_color: [f32; 4],
    /// 当前渲染顺序（越大越后画）
    pub draw_order: i32,
}

/// 一帧 Live2D 的整体数据
#[derive(Debug, Clone)]
pub struct FrameDto {
    pub canvas_width: f32,
    pub canvas_height: f32,
    pub drawables: Vec<DrawableFrameDto>,
}

fn canvas_size(info: CanvasInfo) -> (f32, f32) {
    let (w, h) = info.size_in_pixels;
    (w, h)
}

fn vec2_to_f32(v: &Vector2) -> [f32; 2] {
    [v.x, v.y]
}

fn vec4_to_f32(v: &Vector4) -> [f32; 4] {
    [v.x, v.y, v.z, v.w]
}

/// 加载一个 moc3 模型，返回句柄
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_load(moc_bytes: Vec<u8>) -> Result<u64, String> {
    let core = core();
    let moc = core
        .moc_from_bytes(&moc_bytes)
        .map_err(|e| match e {
            MocError::InvalidMoc => "Invalid moc".to_string(),
            MocError::UnsupportedMocVersion {
                given,
                latest_supported,
            } => format!("Unsupported moc version: {given:?}, latest: {latest_supported:?}"),
        })?;

    let model = Model::from_moc(&moc);
    let handle = next_handle();

    let instance = Live2dModelInstance { moc, model };
    let mut map = models().lock().expect("models mutex poisoned");
    map.insert(handle, instance);

    Ok(handle)
}

/// 卸载一个模型
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_unload(handle: u64) {
    let mut map = models().lock().expect("models mutex poisoned");
    map.remove(&handle);
}

/// 设置模型参数值（用于动画）
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_set_parameter(
    handle: u64,
    parameter_id: String,
    value: f32,
) -> Result<(), String> {
    let map = models().lock().expect("models mutex poisoned");
    let instance = map
        .get(&handle)
        .ok_or_else(|| "live2d_model_set_parameter: invalid handle".to_string())?;

    let model_static = instance.model.get_static();
    let mut dynamic = instance.model.write_dynamic();

    let parameters = model_static.parameters();
    let parameter_values = dynamic.parameter_values_mut();

    // 查找参数索引
    for (i, param) in parameters.iter().enumerate() {
        if param.id() == parameter_id {
            let range = param.value_range();
            let clamped_value = value.clamp(range.0, range.1);
            parameter_values[i] = clamped_value;
            return Ok(());
        }
    }

    // 收集前10个可用参数名用于调试
    let available: Vec<_> = parameters.iter().take(10).map(|p| p.id()).collect();
    Err(format!("Parameter '{}' not found. First 10 available: {:?}", parameter_id, available))
}

/// 生成一帧渲染数据（目前不做参数动画，只是把底层顶点 / 颜色等导出来）
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_step(handle: u64) -> Result<FrameDto, String> {
    let map = models().lock().expect("models mutex poisoned");
    let instance = map
        .get(&handle)
        .ok_or_else(|| "live2d_model_step: invalid handle".to_string())?;

    let model_static = instance.model.get_static();
    let mut dynamic = instance.model.write_dynamic();

    // 一般这里应该做：根据时间、输入参数驱动 parameter_values，然后再 update
    dynamic.update();
    dynamic.reset_drawable_dynamic_flags();

    let canvas = model_static.canvas_info();
    let (canvas_width, canvas_height) = canvas_size(canvas);

    let drawables = model_static.drawables();
    let vertex_positions_containers = dynamic.drawable_vertex_position_containers();
    let draw_orders = dynamic.drawable_draw_orders();
    let opacities = dynamic.drawable_opacities();
    let multiply_colors = dynamic.drawable_multiply_colors();
    let screen_colors = dynamic.drawable_screen_colors();

    // draw_order 升序排序索引
    let mut indices_sorted: Vec<usize> = (0..drawables.len()).collect();
    indices_sorted.sort_by(|&a, &b| {
        let oa = draw_orders[a];
        let ob = draw_orders[b];
        oa.cmp(&ob)
    });

    let mut drawable_frames = Vec::with_capacity(drawables.len());

    for drawable_i in indices_sorted {
        let drawable = &drawables[drawable_i];
        let positions: &[Vector2] = vertex_positions_containers[drawable_i];
        let uvs_src: &[Vector2] = drawable.vertex_uvs();
        let triangles: &[u16] = drawable.triangle_indices();

        // 顶点数量理论上应该与 uv 数量一致，这里简单做一致性检查
        if positions.len() != uvs_src.len() {
            return Err(format!(
                "live2d_model_step: vertex count mismatch (pos={}, uv={})",
                positions.len(),
                uvs_src.len()
            ));
        }

        let mut vertices = Vec::with_capacity(positions.len() * 2);
        let mut uvs = Vec::with_capacity(uvs_src.len() * 2);

        for p in positions {
            let [x, y] = vec2_to_f32(p);
            vertices.push(x);
            vertices.push(y);
        }

        for uv in uvs_src {
            let [u, v] = vec2_to_f32(uv);
            uvs.push(u);
            uvs.push(v);
        }

        let multiply = multiply_colors[drawable_i];
        let screen = screen_colors[drawable_i];

        let frame = DrawableFrameDto {
            index: drawable.index().as_usize() as u32,
            texture_index: drawable.texture_index().as_usize() as u32,
            vertices,
            uvs,
            indices: triangles.to_vec(),
            masks: drawable
                .masks()
                .iter()
                .map(|&m| m as u16)
                .collect(),
            opacity: opacities[drawable_i],
            multiply_color: vec4_to_f32(&multiply),
            screen_color: vec4_to_f32(&screen),
            draw_order: draw_orders[drawable_i],
        };

        drawable_frames.push(frame);
    }

    Ok(FrameDto {
        canvas_width,
        canvas_height,
        drawables: drawable_frames,
    })
}

/// 设置 Part 的不透明度
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_set_part_opacity(
    handle: u64,
    part_id: String,
    opacity: f32,
) -> Result<(), String> {
    let map = models().lock().expect("models mutex poisoned");
    let instance = map
        .get(&handle)
        .ok_or_else(|| "live2d_model_set_part_opacity: invalid handle".to_string())?;

    let model_static = instance.model.get_static();
    let mut dynamic = instance.model.write_dynamic();

    let parts = model_static.parts();
    let part_opacities = dynamic.part_opacities_mut();

    for (i, part) in parts.iter().enumerate() {
        if part.id() == part_id {
            part_opacities[i] = opacity.clamp(0.0, 1.0);
            return Ok(());
        }
    }
    
    let available: Vec<_> = parts.iter().take(10).map(|p| p.id()).collect();
    Err(format!("Part '{}' not found. First 10 available: {:?}", part_id, available))
}

/// 获取所有参数 ID
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_get_parameter_ids(handle: u64) -> Result<Vec<String>, String> {
    let map = models().lock().expect("models mutex poisoned");
    let instance = map
        .get(&handle)
        .ok_or_else(|| "live2d_model_get_parameter_ids: invalid handle".to_string())?;

    let model_static = instance.model.get_static();
    let parameters = model_static.parameters();
    
    Ok(parameters.iter().map(|p| p.id().to_string()).collect())
}

/// 获取所有 Part ID
#[flutter_rust_bridge::frb(sync)]
pub fn live2d_model_get_part_ids(handle: u64) -> Result<Vec<String>, String> {
    let map = models().lock().expect("models mutex poisoned");
    let instance = map
        .get(&handle)
        .ok_or_else(|| "live2d_model_get_part_ids: invalid handle".to_string())?;

    let model_static = instance.model.get_static();
    let parts = model_static.parts();
    
    Ok(parts.iter().map(|p| p.id().to_string()).collect())
}



#![cfg(feature = "core")]

use parking_lot::{RwLock, RwLockReadGuard, RwLockWriteGuard};

pub mod base_types;
pub mod model_types;

pub use base_types::{CubismVersion, MocError, MocVersion};
pub use base_types::{DrawableIndex, TextureIndex};
pub use base_types::{Vector2, Vector4};

pub use model_types::CanvasInfo;
pub use model_types::Part;
pub use model_types::{
    ConstantDrawableFlagSet, ConstantDrawableFlags, Drawable, DynamicDrawableFlagSet,
    DynamicDrawableFlags,
};
pub use model_types::{Parameter, ParameterType};

mod internal;

use internal::platform_impl::{
    PlatformCubismCore, PlatformMoc, PlatformModelDynamic, PlatformModelStatic,
};

#[cfg(not(target_arch = "wasm32"))]
use static_assertions::assert_impl_all;

#[cfg(not(target_arch = "wasm32"))]
assert_impl_all!(CubismCore: Send, Sync);
#[cfg(not(target_arch = "wasm32"))]
assert_impl_all!(Moc: Send, Sync);
#[cfg(not(target_arch = "wasm32"))]
assert_impl_all!(Model: Send, Sync);

use internal::platform_iface::{
    PlatformCubismCoreInterface as _, PlatformMocInterface as _,
    PlatformModelDynamicInterface as _, PlatformModelStaticInterface as _,
};

#[derive(Debug)]
#[cfg_attr(not(target_arch = "wasm32"), derive(Default))]
pub struct CubismCore {
    #[allow(dead_code)]
    inner: PlatformCubismCore,
}

impl CubismCore {
    #[cfg(target_arch = "wasm32")]
    pub async fn new() -> Self {
        let inner = PlatformCubismCore::new().await;
        Self { inner }
    }

    #[cfg(not(target_arch = "wasm32"))]
    pub unsafe fn set_log_function<F>(f: F)
    where
        F: FnMut(&str) + Send + 'static,
    {
        PlatformCubismCore::set_log_function(f)
    }

    pub fn version(&self) -> CubismVersion {
        self.inner.version()
    }
    pub fn latest_supported_moc_version(&self) -> MocVersion {
        self.inner.latest_supported_moc_version()
    }

    pub fn check_moc_consistency(&self, bytes: &[u8]) -> bool {
        self.inner.check_moc_consistency(bytes)
    }

    /// Deserializes a `Moc` from bytes.
    pub fn moc_from_bytes(&self, bytes: &[u8]) -> Result<Moc, MocError> {
        self.inner
            .platform_moc_from_bytes(bytes)
            .map(|(moc_version, platform_moc)| Moc {
                version: moc_version,
                inner: platform_moc,
            })
    }
}

/// Cubism moc.
#[derive(Debug)]
pub struct Moc {
    version: MocVersion,
    inner: PlatformMoc,
}
impl Moc {
    pub fn version(&self) -> MocVersion {
        self.version
    }
}

/// Cubism model.
#[derive(Debug)]
pub struct Model {
    model_static: ModelStatic,
    model_dynamic: RwLock<ModelDynamic>,
}
impl Model {
    pub fn from_moc(moc: &Moc) -> Self {
        let (platform_model_static, platform_model_dynamic) = moc.inner.new_platform_model();

        let model_static = ModelStatic {
            inner: platform_model_static,
        };
        let model_dynamic = ModelDynamic {
            inner: platform_model_dynamic,
        };

        Self {
            model_static,
            model_dynamic: RwLock::new(model_dynamic),
        }
    }

    /// Gets [`ModelStatic`].
    pub fn get_static(&self) -> &ModelStatic {
        &self.model_static
    }

    /// Acquires a read (shared) lock for [`ModelDynamic`].
    pub fn read_dynamic(&self) -> ModelDynamicReadLockGuard<'_> {
        ModelDynamicReadLockGuard {
            inner: self.model_dynamic.read(),
        }
    }
    /// Acquires a write (mutable) lock for [`ModelDynamic`].
    pub fn write_dynamic(&self) -> ModelDynamicWriteLockGuard<'_> {
        ModelDynamicWriteLockGuard {
            inner: self.model_dynamic.write(),
        }
    }
}

#[derive(Debug)]
pub struct ModelStatic {
    inner: PlatformModelStatic,
}
impl ModelStatic {
    pub fn canvas_info(&self) -> CanvasInfo {
        self.inner.canvas_info()
    }
    pub fn parameters(&self) -> &[Parameter] {
        self.inner.parameters()
    }
    pub fn parts(&self) -> &[Part] {
        self.inner.parts()
    }
    pub fn drawables(&self) -> &[Drawable] {
        self.inner.drawables()
    }
    pub fn get_drawable(&self, index: DrawableIndex) -> Option<&Drawable> {
        self.inner.get_drawable(index)
    }
}

/// Dynamic states of a model.
#[derive(Debug)]
pub struct ModelDynamic {
    inner: PlatformModelDynamic,
}
impl ModelDynamic {
    pub fn parameter_values(&self) -> &[f32] {
        self.inner.parameter_values()
    }
    pub fn parameter_values_mut(&mut self) -> &mut [f32] {
        self.inner.parameter_values_mut()
    }
    pub fn part_opacities(&self) -> &[f32] {
        self.inner.part_opacities()
    }
    pub fn part_opacities_mut(&mut self) -> &mut [f32] {
        self.inner.part_opacities_mut()
    }
    pub fn drawable_dynamic_flagsets(&self) -> &[DynamicDrawableFlagSet] {
        self.inner.drawable_dynamic_flagsets()
    }

    pub fn drawable_draw_orders(&self) -> &[i32] {
        self.inner.drawable_draw_orders()
    }
    pub fn drawable_render_orders(&self) -> &[i32] {
        self.inner.drawable_render_orders()
    }
    pub fn drawable_opacities(&self) -> &[f32] {
        self.inner.drawable_opacities()
    }
    pub fn drawable_vertex_position_containers(&self) -> &[&[Vector2]] {
        self.inner.drawable_vertex_position_containers()
    }
    pub fn drawable_multiply_colors(&self) -> &[Vector4] {
        self.inner.drawable_multiply_colors()
    }
    pub fn drawable_screen_colors(&self) -> &[Vector4] {
        self.inner.drawable_screen_colors()
    }

    pub fn update(&mut self) {
        self.inner.update()
    }
    pub fn reset_drawable_dynamic_flags(&mut self) {
        self.inner.reset_drawable_dynamic_flags()
    }
}

#[must_use]
#[derive(Debug)]
pub struct ModelDynamicReadLockGuard<'a> {
    inner: RwLockReadGuard<'a, ModelDynamic>,
}
impl<'a> std::ops::Deref for ModelDynamicReadLockGuard<'a> {
    type Target = ModelDynamic;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}

#[must_use]
#[derive(Debug)]
pub struct ModelDynamicWriteLockGuard<'a> {
    inner: RwLockWriteGuard<'a, ModelDynamic>,
}
impl<'a> std::ops::Deref for ModelDynamicWriteLockGuard<'a> {
    type Target = ModelDynamic;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}
impl<'a> std::ops::DerefMut for ModelDynamicWriteLockGuard<'a> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.inner
    }
}

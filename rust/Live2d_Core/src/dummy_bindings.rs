#[allow(non_upper_case_globals)]
#[allow(non_camel_case_types)]
#[allow(non_snake_case)]
#[allow(dead_code)]

use std::os::raw::{c_char, c_int, c_uint, c_void};

pub type csmVector2 = [f32; 2];
pub type csmVector4 = [f32; 4];

#[repr(C)]
pub struct csmMoc {
    _unused: [u8; 0],
}

#[repr(C)]
pub struct csmModel {
    _unused: [u8; 0],
}

pub const csmAlignofMoc: c_int = 16;
pub const csmAlignofModel: c_int = 16;

extern "C" {
    pub fn csmGetVersion() -> c_uint;
    pub fn csmGetLatestMocVersion() -> c_uint;
    pub fn csmSetLogFunction(func: Option<extern "C" fn(*const c_char)>);
    pub fn csmGetLogFunction() -> Option<extern "C" fn(*const c_char)>;
    pub fn csmGetMocVersion(address: *const c_void, size: c_uint) -> c_uint;
    pub fn csmHasMocConsistency(address: *const c_void, size: c_uint) -> c_int;
    pub fn csmReviveMocInPlace(address: *mut c_void, size: c_uint) -> *mut csmMoc;
    pub fn csmGetSizeofModel(moc: *const csmMoc) -> c_uint;
    pub fn csmInitializeModelInPlace(moc: *const csmMoc, model: *mut c_void, size: c_uint) -> *mut csmModel;
    pub fn csmReadCanvasInfo(model: *const csmModel, size_in_pixels: *mut csmVector2, origin_in_pixels: *mut csmVector2, pixels_per_unit: *mut f32);
    pub fn csmGetParameterCount(model: *const csmModel) -> c_int;
    pub fn csmGetParameterIds(model: *const csmModel) -> *const *const c_char;
    pub fn csmGetParameterTypes(model: *const csmModel) -> *const c_int;
    pub fn csmGetParameterMinimumValues(model: *const csmModel) -> *const f32;
    pub fn csmGetParameterMaximumValues(model: *const csmModel) -> *const f32;
    pub fn csmGetParameterDefaultValues(model: *const csmModel) -> *const f32;
    pub fn csmGetParameterKeyCounts(model: *const csmModel) -> *const c_int;
    pub fn csmGetParameterKeyValues(model: *const csmModel) -> *const *const f32;
    pub fn csmGetParameterValues(model: *mut csmModel) -> *mut f32;
    pub fn csmGetPartCount(model: *const csmModel) -> c_int;
    pub fn csmGetPartIds(model: *const csmModel) -> *const *const c_char;
    pub fn csmGetPartParentPartIndices(model: *const csmModel) -> *const c_int;
    pub fn csmGetPartOpacities(model: *mut csmModel) -> *mut f32;
    pub fn csmGetDrawableCount(model: *const csmModel) -> c_int;
    pub fn csmGetDrawableIds(model: *const csmModel) -> *const *const c_char;
    pub fn csmGetDrawableConstantFlags(model: *const csmModel) -> *const u8;
    pub fn csmGetDrawableDynamicFlags(model: *const csmModel) -> *const u8;
    pub fn csmGetDrawableTextureIndices(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableMaskCounts(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableMasks(model: *const csmModel) -> *const *const c_int;
    pub fn csmGetDrawableVertexCounts(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableVertexUvs(model: *const csmModel) -> *const *const csmVector2;
    pub fn csmGetDrawableVertexPositions(model: *const csmModel) -> *const *const csmVector2;
    pub fn csmGetDrawableIndexCounts(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableIndices(model: *const csmModel) -> *const *const u16;
    pub fn csmGetDrawableParentPartIndices(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableDrawOrders(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableRenderOrders(model: *const csmModel) -> *const c_int;
    pub fn csmGetDrawableOpacities(model: *const csmModel) -> *const f32;
    pub fn csmGetDrawableMultiplyColors(model: *const csmModel) -> *const csmVector4;
    pub fn csmGetDrawableScreenColors(model: *const csmModel) -> *const csmVector4;
    pub fn csmUpdateModel(model: *mut csmModel);
    pub fn csmResetDrawableDynamicFlags(model: *mut csmModel);
}


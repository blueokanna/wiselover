use derive_more::Display;
use num_enum::TryFromPrimitive;
use shrinkwraprs::Shrinkwrap;
use static_assertions::const_assert_eq;
use thiserror::Error;

pub type Vector2 = mint::Vector2<f32>;
pub type Vector4 = mint::Vector4<f32>;

const_assert_eq!(
    std::mem::size_of::<Vector2>(),
    std::mem::size_of::<f32>() * 2
);
const_assert_eq!(
    std::mem::size_of::<Vector4>(),
    std::mem::size_of::<f32>() * 4
);

/// Errors generated when deserializing a moc.
#[derive(Debug, Clone, Error)]
pub enum MocError {
    #[error("Not a valid moc file.")]
    InvalidMoc,
    /// ## Platform-specific
    /// - **Web:** Unsupported.
    #[error("Unsupported moc version. given: \"{given}\" latest supported:\"{latest_supported}\"")]
    UnsupportedMocVersion {
        given: MocVersion,
        latest_supported: MocVersion,
    },
}

/// Cubism version identifier.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Shrinkwrap)]
#[repr(transparent)]
pub struct CubismVersion(pub u32);
impl CubismVersion {
    pub fn raw(&self) -> u32 {
        self.0
    }
    pub fn major(&self) -> u32 {
        (self.0 & 0xFF000000) >> 24
    }
    pub fn minor(&self) -> u32 {
        (self.0 & 0x00FF0000) >> 16
    }
    pub fn patch(&self) -> u32 {
        self.0 & 0x0000FFFF
    }
}
impl std::fmt::Display for CubismVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{:02}.{:02}.{:04} (0x{:08x})",
            self.major(),
            self.minor(),
            self.patch(),
            self.0
        )
    }
}
impl std::fmt::Debug for CubismVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self)
    }
}

#[derive(Debug, Display, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, TryFromPrimitive)]
#[repr(u32)]
pub enum MocVersion {
    #[display(fmt = "30(3.0.00 - 3.2.07)")]
    Moc3_30 = 1,
    #[display(fmt = "33(3.3.00 - 3.3.03)")]
    Moc3_33 = 2,
    #[display(fmt = "40(4.0.00 - 4.1.05)")]
    Moc3_40 = 3,
    #[display(fmt = "42(4.2.00 - 4.2.04)")]
    Moc3_42 = 4,
    #[display(fmt = "50(5.0.00 -)")]
    Moc3_50 = 5,
}

/// Strong-typed index to a texture referenced from a Moc.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Shrinkwrap)]
#[repr(transparent)]
pub struct TextureIndex(pub u64);

impl TextureIndex {
    #[inline]
    pub fn as_usize(&self) -> usize {
        self.0 as usize
    }
}

impl From<usize> for TextureIndex {
    fn from(value: usize) -> Self {
        Self(value as u64)
    }
}

impl std::fmt::Display for TextureIndex {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Strong-typed index to a drawable in a model.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Shrinkwrap)]
#[repr(transparent)]
pub struct DrawableIndex(pub u64);

impl DrawableIndex {
    #[inline]
    pub fn as_usize(&self) -> usize {
        self.0 as usize
    }
}

impl From<usize> for DrawableIndex {
    fn from(value: usize) -> Self {
        Self(value as u64)
    }
}

impl std::fmt::Display for DrawableIndex {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

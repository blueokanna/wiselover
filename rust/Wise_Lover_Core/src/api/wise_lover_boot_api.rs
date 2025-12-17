use live2d_core::core::{CubismCore, MocError};
use std::sync::OnceLock;

fn core() -> &'static CubismCore {
    static CORE: OnceLock<CubismCore> = OnceLock::new();
    CORE.get_or_init(|| {
        CubismCore::default()
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn live2d_core_loader() -> String {
    let core = core();
    format!(
        "Live2D Core v{}, latest moc {:?}",
        core.version(),
        core.latest_supported_moc_version()
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn live2d_core_version() -> String {
    core().version().to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn live2d_core_latest_moc_version() -> String {
    core().latest_supported_moc_version().to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn live2d_core_check_moc_consistency(moc_bytes: Vec<u8>) -> bool {
    core().check_moc_consistency(&moc_bytes)
}

#[flutter_rust_bridge::frb(sync)]
pub fn live2d_core_moc_version(moc_bytes: Vec<u8>) -> Result<String, String> {
    let core = core();
    core.moc_from_bytes(&moc_bytes)
        .map(|moc| moc.version().to_string())
        .map_err(|e| match e {
            MocError::InvalidMoc => "Invalid moc".to_string(),
            MocError::UnsupportedMocVersion { given, latest_supported } => {
                format!("Unsupported moc version: {given:?}, latest: {latest_supported:?}")
            }
        })
}

#[flutter_rust_bridge::frb(init)]
pub fn wise_lover_boot_init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

use std::{env, path::PathBuf};

fn main() {
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    match target_arch.as_str() {
        "wasm32" => handle_target_web(),
        _ => handle_target_native(),
    };
}

fn handle_target_native() {
    let cubism_sdk_dir = if let Some(dir) = get_cubism_sdk_dir_optional() {
        dir
    } else {
        emit_dummy_bindings();
        return;
    };

    let cubism_core_dir = cubism_sdk_dir.join("Core");

    const WRAPPER_HEADER: &str = "src/wrapper.h";

    println!("cargo:rerun-if-changed={}", WRAPPER_HEADER);

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();

    let core_platform_lib_dir_path = calc_lib_dir(&cubism_core_dir, &target_os);
    let core_platform_lib_name = select_lib_name(&target_os);

    println!(
        "cargo:rustc-link-search=native={}",
        core_platform_lib_dir_path.to_str().unwrap()
    );
    println!("cargo:rustc-link-lib=static={}", core_platform_lib_name);

    let core_include_dir_path = PathBuf::from(&cubism_core_dir).join("include");

    let bindings_builder = bindgen::Builder::default()
        .header(WRAPPER_HEADER)
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        .clang_arg(format!("-I{}", core_include_dir_path.to_str().unwrap()));

    let bindings = bindings_builder
        .generate()
        .expect("Unable to generate bindings !");

    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_dir.join("bindings.rs"))
        .expect("Failed to write bindings !");
}

fn handle_target_web() {}

fn emit_dummy_bindings() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let bindings_path = out_dir.join("bindings.rs");
    let dummy_bindings = include_str!("src/dummy_bindings.rs");
    std::fs::write(&bindings_path, dummy_bindings).unwrap();
}

fn calc_lib_dir(cubism_core_dir: &PathBuf, target_os: &str) -> PathBuf {
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();

    let arch_dir_name = match target_os {
        "windows" => target_arch.as_str(),
        "android" => match target_arch.as_str() {
            "aarch64" => "arm64-v8a",
            "arm" => "armeabi-v7a",
            other => other,
        },
        "linux" => target_arch.as_str(),
        other => panic!("Unexpected target_os: {}", other),
    };

    let platform_lib_dir_name = match target_os {
        "windows" => format!("{}/142", arch_dir_name),
        _ => arch_dir_name.to_owned(),
    };

    cubism_core_dir
        .join("lib")
        .join(target_os)
        .join(platform_lib_dir_name)
}

fn select_lib_name(target_os: &str) -> &'static str {
    match target_os {
        "windows" => "Live2DCubismCore_MD",
        _ => "Live2DCubismCore",
    }
}

fn get_cubism_sdk_dir_optional() -> Option<PathBuf> {
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();

    let env_var_name = match target_arch.as_str() {
        "wasm32" => "LIVE2D_CUBISM_SDK_WEB_DIR",
        _ => "LIVE2D_CUBISM_SDK_NATIVE_DIR",
    };

    if let Ok(dir) = env::var(env_var_name) {
        return Some(PathBuf::from(dir));
    }

    #[cfg(windows)]
    {
        let default_path = PathBuf::from(r"D:\CubismSdkForNative5");
        if default_path.join("Core").exists() {
            return Some(default_path);
        }
    }

    None
}

#[allow(dead_code)]
fn get_cubism_sdk_core_dir() -> PathBuf {
    get_cubism_sdk_dir_optional()
        .expect("LIVE2D_CUBISM_SDK_NATIVE_DIR environment variable must be set")
        .join("Core")
}

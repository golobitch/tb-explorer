use std::path::PathBuf;

/// Links the `tb_client` archive vendored for the whole repo in `Vendor/tigerbeetle/lib`.
///
/// One archive per target, because Cargo builds one target at a time: the macOS app links the
/// universal Mach-O in the same directory, the same release, from the same download.
fn main() {
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();

    let slice = match (arch.as_str(), os.as_str()) {
        ("aarch64", "macos") => "aarch64-macos",
        ("x86_64", "macos") => "x86_64-macos",
        ("aarch64", "linux") => "aarch64-linux",
        ("x86_64", "linux") => "x86_64-linux",
        _ => panic!("tb_client is not vendored for {arch}-{os}; see Vendor/tigerbeetle/lib"),
    };

    if os == "linux" && env == "musl" {
        // The vendored Linux archives are the glibc 2.27 builds published by tigerbeetle-go.
        panic!("tb_client is vendored for glibc only; a musl build needs its own archive");
    }

    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../Vendor/tigerbeetle")
        .canonicalize()
        .expect("Vendor/tigerbeetle is missing; run `make vendor`");
    let libdir = root.join("lib").join(slice);
    let lib = libdir.join("libtb_client.a");
    assert!(
        lib.exists(),
        "{} is missing; run `make vendor`",
        lib.display()
    );

    println!("cargo:rustc-link-search=native={}", libdir.display());
    println!("cargo:rustc-link-lib=static=tb_client");
    if os == "linux" {
        // tb_client uses libm symbols without declaring the dependency.
        // https://github.com/tigerbeetle/tigerbeetle/issues/2865
        println!("cargo:rustc-link-lib=m");
    }
    println!("cargo:rerun-if-changed={}", lib.display());
    println!("cargo:rerun-if-changed={}", root.join("VERSION").display());
}

mod api;
mod bridge;
mod decode;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

pub use bridge::*;

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_example_komix_MainActivity_initRustlsPlatformVerifier(
    mut env: jni::JNIEnv<'_>,
    _: jni::objects::JClass<'_>,
    context: jni::objects::JObject<'_>,
) {
    let _ = env.with_env(|env| {
        rustls_platform_verifier::android::init_with_env(env, context)?;
        Ok::<(), jni::errors::Error>(())
    });
}

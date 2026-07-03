use aes::cipher::{BlockDecrypt, KeyInit};
use aes::{Aes256, Block};
use base64::{engine::general_purpose, Engine as _};
use md5::{Digest, Md5};

/// MD5 哈希
pub fn md5_hash(input: &str) -> String {
    let mut hasher = Md5::new();
    hasher.update(input.as_bytes());
    let result = hasher.finalize();
    result.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn normalize_base64(input: &str) -> anyhow::Result<String> {
    let body = input
        .trim()
        .replace(char::is_whitespace, "")
        .replace('-', "+")
        .replace('_', "/")
        .trim_end_matches('=')
        .to_string();

    if body.is_empty() {
        anyhow::bail!("空的加密数据");
    }

    if !body
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || byte == b'+' || byte == b'/')
    {
        anyhow::bail!("加密数据不是有效 Base64");
    }

    match body.len() % 4 {
        0 => Ok(body),
        1 => anyhow::bail!("Base64 长度非法"),
        rem => Ok(format!("{}{}", body, "=".repeat(4 - rem))),
    }
}

fn strip_pkcs7_padding(mut data: Vec<u8>) -> anyhow::Result<Vec<u8>> {
    let padding = *data.last().ok_or_else(|| anyhow::anyhow!("解密结果为空"))? as usize;

    if padding == 0 || padding > 16 || padding > data.len() {
        anyhow::bail!("PKCS7 padding 非法");
    }

    if !data[data.len() - padding..]
        .iter()
        .all(|byte| *byte as usize == padding)
    {
        anyhow::bail!("PKCS7 padding 不匹配");
    }

    data.truncate(data.len() - padding);
    Ok(data)
}

/// AES-256-ECB PKCS7 解密
pub fn aes_decrypt(encrypted_base64: &str, key_str: &str) -> anyhow::Result<String> {
    let clean_base64 = normalize_base64(encrypted_base64)?;
    let encrypted_data = general_purpose::STANDARD.decode(&clean_base64)?;

    if encrypted_data.len() % 16 != 0 {
        anyhow::bail!("AES 密文长度不是 16 字节块的整数倍");
    }

    let mut buffer = encrypted_data;
    let cipher = Aes256::new_from_slice(key_str.as_bytes())
        .map_err(|error| anyhow::anyhow!("AES key 非法: {:?}", error))?;

    for chunk in buffer.chunks_exact_mut(16) {
        let mut block = Block::default();
        block.copy_from_slice(chunk);
        cipher.decrypt_block(&mut block);
        chunk.copy_from_slice(&block);
    }

    let decrypted = strip_pkcs7_padding(buffer)?;
    let result = String::from_utf8(decrypted.to_vec())?;
    Ok(result)
}

/// 尝试用多个种子解密
pub fn try_decrypt_with_seeds(
    encrypted_base64: &str,
    timestamp: &str,
    seeds: &[&str],
) -> Option<String> {
    for seed in seeds {
        let key = md5_hash(&format!("{}{}", timestamp, seed));
        if let Ok(decrypted) = aes_decrypt(encrypted_base64, &key) {
            // 尝试解析 JSON 验证解密是否成功
            if serde_json::from_str::<serde_json::Value>(&decrypted).is_ok() {
                return Some(decrypted);
            }
        }
    }
    None
}

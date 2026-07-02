mod crypto;

use crate::api::http::{HttpClient, HttpRequest};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

const VERSION: &str = "2.0.20";
const JM_SECRET: &str = "185Hcomic3PAPP7R";
const HOST_CONFIG_AES_SEED: &str = "diosfjckwpqpdfjkvnqQjsik";
const AES_SEEDS: &[&str] = &["185Hcomic3PAPP7R", "18comicAPPContent"];
const HOST_CONFIG_URLS: &[&str] = &[
    "https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt",
    "https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt",
];
const FALLBACK_API_BASE: &str = "https://www.cdnhjk.net";
const FALLBACK_IMAGE_BASE: &str = "https://cdn-msp3.jmdanjonproxy.vip";
const USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 13; a1b2c3d4e Build/TQ1A.230305.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/120.0.6099.230 Mobile Safari/537.36";

pub struct JmClient {
    http: HttpClient,
}

#[derive(Debug, Clone)]
struct JmEndpoints {
    api_base_url: String,
    image_base_url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Comic {
    pub id: String,
    pub title: String,
    pub author: Vec<String>,
    pub cover_url: String,
    pub description: String,
    pub tags: Vec<String>,
    pub likes: i64,
    pub views: i64,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chapter {
    pub id: String,
    pub comic_id: String,
    pub name: String,
    pub order: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub items: Vec<Comic>,
    pub total: i64,
    pub page: i32,
    pub has_more: bool,
}

impl JmEndpoints {
    fn fallback() -> Self {
        Self {
            api_base_url: FALLBACK_API_BASE.to_string(),
            image_base_url: FALLBACK_IMAGE_BASE.to_string(),
        }
    }
}

impl JmClient {
    pub fn new() -> Self {
        Self {
            http: HttpClient::new().expect("创建 JM HTTP client 失败"),
        }
    }

    fn timestamp_millis() -> String {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_millis().to_string())
            .unwrap_or_else(|_| "0".to_string())
    }

    fn timestamp_seconds() -> String {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs().to_string())
            .unwrap_or_else(|_| "0".to_string())
    }

    async fn endpoints(&self) -> JmEndpoints {
        if let Some(cached) = endpoint_cache().read().await.clone() {
            return cached;
        }

        match self.resolve_dynamic_endpoints().await {
            Ok(endpoints) => {
                *endpoint_cache().write().await = Some(endpoints.clone());
                endpoints
            }
            Err(_) => JmEndpoints::fallback(),
        }
    }

    async fn refresh_endpoints(&self) -> anyhow::Result<JmEndpoints> {
        let endpoints = self.resolve_dynamic_endpoints().await?;
        *endpoint_cache().write().await = Some(endpoints.clone());
        Ok(endpoints)
    }

    async fn resolve_dynamic_endpoints(&self) -> anyhow::Result<JmEndpoints> {
        let host_pool = self.load_host_pool().await?;
        if host_pool.is_empty() {
            anyhow::bail!("JM host pool 为空");
        }

        let mut picked_api_base = String::new();
        let mut setting = None;

        for domain in &host_pool {
            match self.fetch_setting_from_domain(domain).await {
                Ok(value) => {
                    picked_api_base = normalize_base_url(domain).unwrap_or_default();
                    setting = Some(value);
                    break;
                }
                Err(_) => continue,
            }
        }

        let setting = setting.ok_or_else(|| anyhow::anyhow!("所有 JM setting endpoint 均不可用"))?;
        let image_base_url = setting
            .get("img_host")
            .and_then(parse_string)
            .and_then(|url| normalize_base_url(&url))
            .unwrap_or_else(|| FALLBACK_IMAGE_BASE.to_string());

        let api_base_url = if picked_api_base.is_empty() {
            host_pool
                .iter()
                .find_map(|host| normalize_base_url(host))
                .unwrap_or_else(|| FALLBACK_API_BASE.to_string())
        } else {
            picked_api_base
        };

        Ok(JmEndpoints {
            api_base_url,
            image_base_url,
        })
    }

    async fn load_host_pool(&self) -> anyhow::Result<Vec<String>> {
        let raw = self.fetch_text_from_any(HOST_CONFIG_URLS).await?;
        let encrypted = raw
            .chars()
            .filter(|ch| ch.is_ascii_alphanumeric() || matches!(*ch, '+' | '/' | '='))
            .collect::<String>();
        let key = crypto::md5_hash(HOST_CONFIG_AES_SEED);
        let plain = crypto::aes_decrypt(&encrypted, &key)?;
        let parsed = serde_json::from_str::<Value>(&plain)?;

        let hosts = parsed
            .get("Server")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(parse_string)
                    .filter(|item| !item.is_empty())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        Ok(hosts)
    }

    async fn fetch_text_from_any(&self, urls: &[&str]) -> anyhow::Result<String> {
        let mut last_error = None;

        for url in urls {
            match self
                .http
                .send_text(
                    HttpRequest::get(*url)
                        .header("accept", "text/plain, */*")
                        .header("user-agent", USER_AGENT),
                )
                .await
            {
                Ok(response) if (200..300).contains(&response.status) => return Ok(response.body),
                Ok(response) => {
                    last_error = Some(anyhow::anyhow!(
                        "status={} url={} body={}",
                        response.status,
                        response.final_url,
                        response_preview(&response.body)
                    ));
                }
                Err(error) => last_error = Some(error),
            }
        }

        Err(last_error.unwrap_or_else(|| anyhow::anyhow!("JM host config urls 不可用")))
    }

    async fn fetch_setting_from_domain(&self, domain: &str) -> anyhow::Result<Value> {
        let base_url =
            normalize_base_url(domain).ok_or_else(|| anyhow::anyhow!("JM host 非法: {domain}"))?;
        let ts = Self::timestamp_seconds();
        let token = crypto::md5_hash(&format!("{ts}{JM_SECRET}"));
        let url = format!("{base_url}/setting");

        let response = self
            .http
            .send_text(
                HttpRequest::get(url)
                    .query("app_img_shunt", "1")
                    .query("t", ts.as_str())
                    .header("accept", "application/json, text/plain, */*")
                    .header("Token", token)
                    .header("Tokenparam", format!("{ts},{VERSION}"))
                    .header("user-agent", USER_AGENT),
            )
            .await?;

        if !(200..300).contains(&response.status) {
            anyhow::bail!(
                "JM setting 请求失败: {}. Body starts with: {}",
                response.status,
                response_preview(&response.body)
            );
        }

        let decoded = Self::decode_response_text(&response.body, &ts)?;
        if is_error_response(&decoded) {
            anyhow::bail!(
                "JM setting 响应错误: {}",
                response_preview(&decoded.to_string())
            );
        }

        Ok(decoded)
    }

    async fn request(
        &self,
        path: &str,
        params: &[(&str, String)],
    ) -> anyhow::Result<(Value, JmEndpoints)> {
        let endpoints = self.endpoints().await;

        let value = self.request_once(&endpoints, path, params).await?;
        Ok((value, endpoints))
    }

    async fn request_once(
        &self,
        endpoints: &JmEndpoints,
        path: &str,
        params: &[(&str, String)],
    ) -> anyhow::Result<Value> {
        let ts = Self::timestamp_millis();
        let token = crypto::md5_hash(&format!("{ts}{VERSION}"));
        let url = format!("{}{}", endpoints.api_base_url, path);

        let mut request = HttpRequest::get(url.as_str())
            .header("accept", "application/json, text/plain, */*")
            .header("connection", "Keep-Alive")
            .header("token", token)
            .header("tokenparam", format!("{ts},{VERSION}"))
            .header("user-agent", USER_AGENT);

        if let Some(host) = request_url_host(&url) {
            request = request.header("Host", host);
        }

        for (key, value) in params {
            request = request.query(*key, value.as_str());
        }

        let response = self.http.send_text(request).await?;

        if !(200..300).contains(&response.status) {
            anyhow::bail!(
                "HTTP 请求失败: {}. Body starts with: {}",
                response.status,
                response_preview(&response.body)
            );
        }

        let decoded = Self::decode_response_text(&response.body, &ts)?;
        if is_error_response(&decoded) {
            anyhow::bail!("JM 响应错误: {}", response_preview(&decoded.to_string()));
        }

        Ok(decoded)
    }

    fn decode_response_text(raw: &str, ts: &str) -> anyhow::Result<Value> {
        let raw = raw.trim();
        if raw.is_empty() {
            anyhow::bail!("响应为空");
        }

        let value = serde_json::from_str::<Value>(raw).map_err(|error| {
            anyhow::anyhow!(
                "响应 JSON 解析失败: {error}. Body starts with: {}",
                response_preview(raw)
            )
        })?;

        Self::decode_response_value(value, ts)
    }

    fn decode_response_value(value: Value, ts: &str) -> anyhow::Result<Value> {
        match value {
            Value::String(raw) => {
                let trimmed = raw.trim();
                if trimmed.is_empty() {
                    return Ok(Value::String(String::new()));
                }

                match serde_json::from_str::<Value>(trimmed) {
                    Ok(parsed) => Self::decode_response_value(parsed, ts),
                    Err(_) => Ok(Value::String(raw)),
                }
            }
            Value::Object(map) => {
                if let Some(Value::String(data)) = map.get("data") {
                    let data = data.trim();
                    if !data.is_empty() {
                        if let Some(decrypted) = crypto::try_decrypt_with_seeds(data, ts, AES_SEEDS)
                        {
                            return Self::decode_response_text(&decrypted, ts);
                        }

                        if let Ok(parsed) = serde_json::from_str::<Value>(data) {
                            return Self::decode_response_value(parsed, ts);
                        }
                    }
                }

                Ok(Value::Object(map))
            }
            value => Ok(value),
        }
    }

    pub async fn search(&self, keyword: &str, page: i32) -> anyhow::Result<SearchResult> {
        let (data, endpoints) = self
            .request(
                "/search",
                &[
                    ("search_query", keyword.to_string()),
                    ("page", page.to_string()),
                    ("o", String::new()),
                ],
            )
            .await?;

        self.parse_search_result(data, page, &endpoints.image_base_url)
    }

    pub async fn get_comic_detail(&self, comic_id: &str) -> anyhow::Result<Comic> {
        let (data, endpoints) = self
            .request("/album", &[("id", comic_id.to_string())])
            .await?;

        self.parse_comic(&data, &endpoints.image_base_url)
            .ok_or_else(|| anyhow::anyhow!("解析漫画详情失败"))
    }

    pub async fn get_chapters(&self, comic_id: &str) -> anyhow::Result<Vec<Chapter>> {
        let (data, _) = self
            .request("/album", &[("id", comic_id.to_string())])
            .await?;

        let series = data.get("series").and_then(Value::as_array);

        if series.is_none_or(Vec::is_empty) {
            return Ok(vec![Chapter {
                id: comic_id.to_string(),
                comic_id: comic_id.to_string(),
                name: "第1话".to_string(),
                order: 1,
            }]);
        }

        let chapters = series
            .unwrap()
            .iter()
            .filter(|item| {
                parse_string(item.get("sort").unwrap_or(&Value::Null))
                    .map(|sort| sort != "0")
                    .unwrap_or(true)
                    && parse_i64(item.get("sort").unwrap_or(&Value::Null)) != 0
            })
            .enumerate()
            .map(|(index, item)| {
                let order = (index + 1) as i32;
                Chapter {
                    id: parse_string(item.get("id").unwrap_or(&Value::Null)).unwrap_or_default(),
                    comic_id: comic_id.to_string(),
                    name: format!(
                        "第{}话 {}",
                        order,
                        parse_string(item.get("name").unwrap_or(&Value::Null)).unwrap_or_default()
                    ),
                    order,
                }
            })
            .collect();

        Ok(chapters)
    }

    pub async fn get_chapter_images(&self, chapter_id: &str) -> anyhow::Result<Vec<String>> {
        let (data, endpoints) = self
            .request(
                "/chapter",
                &[("id", chapter_id.to_string()), ("skip", String::new())],
            )
            .await?;

        let images = data
            .get("images")
            .and_then(Value::as_array)
            .ok_or_else(|| anyhow::anyhow!("响应格式错误"))?;

        let urls = images
            .iter()
            .filter_map(parse_string)
            .map(|img| {
                format!(
                    "{}/media/photos/{}/{}",
                    endpoints.image_base_url, chapter_id, img
                )
            })
            .collect();

        Ok(urls)
    }

    pub async fn get_latest(&self, page: i32) -> anyhow::Result<SearchResult> {
        let request_page = std::cmp::max(0, page - 1);
        let (data, endpoints) = self
            .request("/latest", &[("page", request_page.to_string())])
            .await?;

        let items_value = data
            .as_array()
            .cloned()
            .or_else(|| data.get("content").and_then(Value::as_array).cloned())
            .or_else(|| data.get("list").and_then(Value::as_array).cloned())
            .unwrap_or_default();

        let items = items_value
            .iter()
            .filter_map(|item| self.parse_comic(item, &endpoints.image_base_url))
            .collect::<Vec<_>>();

        Ok(SearchResult {
            total: items.len() as i64,
            has_more: items.len() >= 80,
            items,
            page,
        })
    }

    pub async fn get_ranking(
        &self,
        category: &str,
        order: &str,
        page: i32,
    ) -> anyhow::Result<SearchResult> {
        let (data, endpoints) = self
            .request(
                "/categories/filter",
                &[
                    ("page", page.to_string()),
                    ("c", category.to_string()),
                    ("o", order.to_string()),
                ],
            )
            .await?;

        self.parse_search_result(data, page, &endpoints.image_base_url)
    }

    fn parse_search_result(
        &self,
        data: Value,
        page: i32,
        image_base_url: &str,
    ) -> anyhow::Result<SearchResult> {
        let content = data
            .get("content")
            .and_then(Value::as_array)
            .ok_or_else(|| anyhow::anyhow!("响应格式错误"))?;
        let total = parse_i64(data.get("total").unwrap_or(&Value::Null));
        let items = content
            .iter()
            .filter_map(|item| self.parse_comic(item, image_base_url))
            .collect::<Vec<_>>();

        Ok(SearchResult {
            items,
            total,
            page,
            has_more: content.len() >= 80,
        })
    }

    fn parse_comic(&self, data: &Value, image_base_url: &str) -> Option<Comic> {
        Some(Comic {
            id: parse_string(data.get("id")?)?,
            title: parse_string(data.get("name").unwrap_or(&Value::Null))
                .or_else(|| parse_string(data.get("title").unwrap_or(&Value::Null)))
                .unwrap_or_default(),
            author: parse_string_array(data.get("author").unwrap_or(&Value::Null)),
            cover_url: self.build_cover_url(data, image_base_url),
            description: parse_string(data.get("description").unwrap_or(&Value::Null))
                .unwrap_or_default(),
            tags: parse_string_array(data.get("tags").unwrap_or(&Value::Null)),
            likes: parse_i64(data.get("likes").unwrap_or(&Value::Null)),
            views: parse_i64(
                data.get("total_views")
                    .or_else(|| data.get("totalViews"))
                    .unwrap_or(&Value::Null),
            ),
            updated_at: parse_string(
                data.get("update_at")
                    .or_else(|| data.get("addtime"))
                    .unwrap_or(&Value::Null),
            )
            .unwrap_or_default(),
        })
    }

    fn build_cover_url(&self, data: &Value, image_base_url: &str) -> String {
        let image = parse_string(data.get("image").unwrap_or(&Value::Null)).unwrap_or_default();

        if image.starts_with("http://") || image.starts_with("https://") {
            return image;
        }

        if image.starts_with('/') {
            return format!("{}{}", image_base_url, image);
        }

        if image.starts_with("media/") {
            return format!("{}/{}", image_base_url, image);
        }

        if let Some(id) = parse_string(data.get("id").unwrap_or(&Value::Null)) {
            return format!("{}/media/albums/{}_3x4.jpg", image_base_url, id);
        }

        String::new()
    }
}

impl Default for JmClient {
    fn default() -> Self {
        Self::new()
    }
}

fn parse_i64(value: &Value) -> i64 {
    match value {
        Value::Number(number) => number.as_i64().unwrap_or_default(),
        Value::String(text) => text.trim().parse::<i64>().unwrap_or_default(),
        _ => 0,
    }
}

fn parse_string(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => {
            let text = text.trim();
            if text.is_empty() {
                None
            } else {
                Some(text.to_string())
            }
        }
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

fn parse_string_array(value: &Value) -> Vec<String> {
    match value {
        Value::Array(items) => items.iter().filter_map(parse_string).collect(),
        Value::String(text) if !text.trim().is_empty() => vec![text.trim().to_string()],
        _ => vec![],
    }
}

fn is_error_response(value: &Value) -> bool {
    let Some(map) = value.as_object() else {
        return false;
    };
    let code = parse_i64(map.get("code").unwrap_or(&Value::Null));
    code != 0 && code != 200
}

fn endpoint_cache() -> &'static RwLock<Option<JmEndpoints>> {
    static CACHE: OnceLock<RwLock<Option<JmEndpoints>>> = OnceLock::new();
    CACHE.get_or_init(|| RwLock::new(None))
}

fn normalize_base_url(raw: &str) -> Option<String> {
    let value = raw.trim().trim_end_matches('/');
    if value.is_empty() {
        return None;
    }

    if value.starts_with("http://") || value.starts_with("https://") {
        return Some(value.to_string());
    }

    Some(format!("https://{value}"))
}

fn request_url_host(url: &str) -> Option<String> {
    reqwest::Url::parse(url)
        .ok()
        .and_then(|url| url.host_str().map(str::to_string))
        .filter(|host| !host.is_empty())
}

fn response_preview(raw: &str) -> String {
    raw.chars().take(160).collect()
}

mod crypto;

use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::{SystemTime, UNIX_EPOCH};

const VERSION: &str = "2.0.20";
const AES_SEEDS: &[&str] = &["185Hcomic3PAPP7R", "18comicAPPContent"];
const FALLBACK_API_BASE: &str = "https://www.cdnhjk.net";
const FALLBACK_IMAGE_BASE: &str = "https://cdn-msp3.jmdanjonproxy.vip";
const USER_AGENT: &str = "okhttp/3.12.1";

pub struct JmClient {
    client: Client,
    base_url: String,
    image_url: String,
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

impl JmClient {
    pub fn new() -> Self {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .gzip(true)
            .build()
            .unwrap();

        Self {
            client,
            base_url: FALLBACK_API_BASE.to_string(),
            image_url: FALLBACK_IMAGE_BASE.to_string(),
        }
    }

    fn timestamp_millis() -> String {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_millis().to_string())
            .unwrap_or_else(|_| "0".to_string())
    }

    async fn request(&self, path: &str, params: &[(&str, String)]) -> anyhow::Result<Value> {
        let ts = Self::timestamp_millis();
        let token = crypto::md5_hash(&format!("{ts}{VERSION}"));
        let url = format!("{}{}", self.base_url, path);
        let query = params
            .iter()
            .map(|(key, value)| (*key, value.as_str()))
            .collect::<Vec<_>>();

        let mut request = self
            .client
            .get(&url)
            .header("accept", "application/json")
            .header("token", token)
            .header("tokenparam", format!("{ts},{VERSION}"))
            .header("user-agent", USER_AGENT);

        if let Some(host) = request_url_host(&url) {
            request = request.header("Host", host);
        }

        let response = request.query(&query).send().await?;
        let status = response.status();
        let body = response.text().await?;

        if !status.is_success() {
            anyhow::bail!(
                "HTTP 请求失败: {}. Body starts with: {}",
                status,
                response_preview(&body)
            );
        }

        Self::decode_response_text(&body, &ts)
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
        let data = self
            .request(
                "/search",
                &[
                    ("search_query", keyword.to_string()),
                    ("page", page.to_string()),
                    ("o", String::new()),
                ],
            )
            .await?;

        self.parse_search_result(data, page)
    }

    pub async fn get_comic_detail(&self, comic_id: &str) -> anyhow::Result<Comic> {
        let data = self
            .request("/album", &[("id", comic_id.to_string())])
            .await?;

        self.parse_comic(&data)
            .ok_or_else(|| anyhow::anyhow!("解析漫画详情失败"))
    }

    pub async fn get_chapters(&self, comic_id: &str) -> anyhow::Result<Vec<Chapter>> {
        let data = self
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
        let data = self
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
            .map(|img| format!("{}/media/photos/{}/{}", self.image_url, chapter_id, img))
            .collect();

        Ok(urls)
    }

    pub async fn get_latest(&self, page: i32) -> anyhow::Result<SearchResult> {
        let data = self
            .request("/latest", &[("page", page.to_string())])
            .await?;

        let items_value = data
            .as_array()
            .cloned()
            .or_else(|| data.get("content").and_then(Value::as_array).cloned())
            .or_else(|| data.get("list").and_then(Value::as_array).cloned())
            .unwrap_or_default();

        let items = items_value
            .iter()
            .filter_map(|item| self.parse_comic(item))
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
        let data = self
            .request(
                "/categories/filter",
                &[
                    ("page", page.to_string()),
                    ("c", category.to_string()),
                    ("o", order.to_string()),
                ],
            )
            .await?;

        self.parse_search_result(data, page)
    }

    fn parse_search_result(&self, data: Value, page: i32) -> anyhow::Result<SearchResult> {
        let content = data
            .get("content")
            .and_then(Value::as_array)
            .ok_or_else(|| anyhow::anyhow!("响应格式错误"))?;
        let total = parse_i64(data.get("total").unwrap_or(&Value::Null));
        let items = content
            .iter()
            .filter_map(|item| self.parse_comic(item))
            .collect::<Vec<_>>();

        Ok(SearchResult {
            items,
            total,
            page,
            has_more: content.len() >= 80,
        })
    }

    fn parse_comic(&self, data: &Value) -> Option<Comic> {
        Some(Comic {
            id: parse_string(data.get("id")?)?,
            title: parse_string(data.get("name").unwrap_or(&Value::Null))
                .or_else(|| parse_string(data.get("title").unwrap_or(&Value::Null)))
                .unwrap_or_default(),
            author: parse_string_array(data.get("author").unwrap_or(&Value::Null)),
            cover_url: self.build_cover_url(data),
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

    fn build_cover_url(&self, data: &Value) -> String {
        let image = parse_string(data.get("image").unwrap_or(&Value::Null)).unwrap_or_default();

        if image.starts_with("http://") || image.starts_with("https://") {
            return image;
        }

        if image.starts_with('/') {
            return format!("{}{}", self.image_url, image);
        }

        if image.starts_with("media/") {
            return format!("{}/{}", self.image_url, image);
        }

        if let Some(id) = parse_string(data.get("id").unwrap_or(&Value::Null)) {
            return format!("{}/media/albums/{}_3x4.jpg", self.image_url, id);
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

fn request_url_host(url: &str) -> Option<String> {
    reqwest::Url::parse(url)
        .ok()
        .and_then(|url| url.host_str().map(str::to_string))
        .filter(|host| !host.is_empty())
}

fn response_preview(raw: &str) -> String {
    raw.chars().take(160).collect()
}

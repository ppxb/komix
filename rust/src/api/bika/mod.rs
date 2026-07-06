use crate::api::http::{HttpClient, HttpRequest};
use hmac::{Hmac, Mac};
use md5::{Digest, Md5};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::Sha256;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_API_BASE: &str = "https://picaapi.picacomic.com/";
const BACKUP_API_BASE: &str = "https://picaapi.go2778.com/";
const API_KEY: &str = "C69BAF41DA5ABD1FFEDC6D2FEA56B";
const SECRET_KEY: &str =
    "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn";

type HmacSha256 = Hmac<Sha256>;

pub struct BikaClient {
    http: HttpClient,
    api_base: String,
    authorization: String,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PageImage {
    pub id: String,
    pub url: String,
    pub path: String,
    pub original_name: String,
    pub extern: Value,
}

impl BikaClient {
    pub fn new(authorization: impl Into<String>) -> Self {
        Self::with_api_base(DEFAULT_API_BASE, authorization)
    }

    pub fn with_api_base(api_base: impl Into<String>, authorization: impl Into<String>) -> Self {
        Self {
            http: HttpClient::new().expect("创建 Bika HTTP client 失败"),
            api_base: normalize_api_base(&api_base.into()),
            authorization: authorization.into(),
        }
    }

    pub async fn login(email: &str, password: &str) -> anyhow::Result<String> {
        let client = Self::new("");
        let data = client
            .request_json(
                "POST",
                "auth/sign-in",
                Some(json!({"email": email, "password": password})),
            )
            .await?;
        let token = data
            .get("data")
            .and_then(|data| data.get("token"))
            .and_then(parse_string)
            .unwrap_or_default();
        if token.is_empty() {
            anyhow::bail!("哔咔登录失败：响应缺少 token");
        }
        Ok(token)
    }

    pub async fn search(&self, keyword: &str, page: i32) -> anyhow::Result<SearchResult> {
        self.ensure_authorized()?;
        let path = format!("comics/advanced-search?page={}", page.max(1));
        let data = self
            .request_json(
                "POST",
                &path,
                Some(json!({
                    "sort": "dd",
                    "keyword": keyword,
                    "categories": [],
                })),
            )
            .await?;
        self.parse_search_result(&data, page.max(1))
    }

    pub async fn get_latest(&self, page: i32) -> anyhow::Result<SearchResult> {
        self.ensure_authorized()?;
        let page = page.max(1);
        let data = self
            .request_json("GET", &format!("comics?page={page}&s=dd"), None)
            .await?;
        self.parse_search_result(&data, page)
    }

    pub async fn get_ranking(&self, order: &str) -> anyhow::Result<SearchResult> {
        self.ensure_authorized()?;
        let days = match order.trim() {
            "D7" | "H24" | "D30" => order.trim(),
            _ => "H24",
        };
        let data = self
            .request_json(
                "GET",
                &format!("comics/leaderboard?tt={days}&ct=VC"),
                None,
            )
            .await?;
        let comics = data
            .get("data")
            .and_then(|data| data.get("comics"))
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let items = comics
            .iter()
            .filter_map(parse_comic)
            .collect::<Vec<Comic>>();
        Ok(SearchResult {
            total: items.len() as i64,
            page: 1,
            has_more: false,
            items,
        })
    }

    pub async fn get_comic_detail(&self, comic_id: &str) -> anyhow::Result<Comic> {
        self.ensure_authorized()?;
        let data = self
            .request_json("GET", &format!("comics/{comic_id}"), None)
            .await?;
        data.get("data")
            .and_then(|data| data.get("comic"))
            .and_then(parse_comic)
            .ok_or_else(|| anyhow::anyhow!("解析哔咔漫画详情失败"))
    }

    pub async fn get_chapters(&self, comic_id: &str) -> anyhow::Result<Vec<Chapter>> {
        self.ensure_authorized()?;
        let mut page = 1;
        let mut total_pages = 1;
        let mut chapters = Vec::new();

        while page <= total_pages {
            let data = self
                .request_json("GET", &format!("comics/{comic_id}/eps?page={page}"), None)
                .await?;
            let eps = data
                .get("data")
                .and_then(|data| data.get("eps"))
                .cloned()
                .unwrap_or(Value::Null);
            total_pages = parse_i64(eps.get("pages").unwrap_or(&Value::Null)).max(1) as i32;
            let docs = eps
                .get("docs")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();

            for item in docs {
                let order = parse_i64(item.get("order").unwrap_or(&Value::Null)) as i32;
                if order <= 0 {
                    continue;
                }
                let title = parse_string(item.get("title").unwrap_or(&Value::Null))
                    .unwrap_or_else(|| format!("第 {order} 章"));
                chapters.push(Chapter {
                    id: format!("{comic_id}:{order}"),
                    comic_id: comic_id.to_string(),
                    name: title,
                    order,
                });
            }
            page += 1;
        }

        chapters.sort_by_key(|chapter| chapter.order);
        Ok(chapters)
    }

    pub async fn get_chapter_images(
        &self,
        comic_id: &str,
        chapter_order: i32,
    ) -> anyhow::Result<Vec<PageImage>> {
        self.ensure_authorized()?;
        if comic_id.trim().is_empty() || chapter_order <= 0 {
            anyhow::bail!("哔咔章节参数无效");
        }

        let mut page = 1;
        let mut total_pages = 1;
        let mut images = Vec::new();

        while page <= total_pages {
            let data = self
                .request_json(
                    "GET",
                    &format!("comics/{comic_id}/order/{chapter_order}/pages?page={page}"),
                    None,
                )
                .await?;
            let pages = data
                .get("data")
                .and_then(|data| data.get("pages"))
                .cloned()
                .unwrap_or(Value::Null);
            total_pages = parse_i64(pages.get("pages").unwrap_or(&Value::Null)).max(1) as i32;
            let docs = pages
                .get("docs")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();

            for item in docs {
                let media = item.get("media").unwrap_or(&Value::Null);
                let path = parse_string(media.get("path").unwrap_or(&Value::Null))
                    .unwrap_or_default();
                let original_name =
                    parse_string(media.get("originalName").unwrap_or(&Value::Null))
                        .unwrap_or_default();
                let file_server = parse_string(media.get("fileServer").unwrap_or(&Value::Null))
                    .unwrap_or_default();
                let url = build_bika_image_url(&file_server, &path, BikaPictureType::Comic);
                images.push(PageImage {
                    id: parse_string(item.get("id").unwrap_or(&Value::Null))
                        .or_else(|| parse_string(item.get("_id").unwrap_or(&Value::Null)))
                        .unwrap_or_else(|| format!("{}:{}", chapter_order, images.len() + 1)),
                    url,
                    path: sanitize_path(&path),
                    original_name,
                    extern: json!({"pictureType": "page"}),
                });
            }

            page += 1;
        }

        Ok(images)
    }

    fn ensure_authorized(&self) -> anyhow::Result<()> {
        if self.authorization.trim().is_empty() {
            anyhow::bail!("哔咔需要先登录");
        }
        Ok(())
    }

    async fn request_json(
        &self,
        method: &str,
        path: &str,
        body: Option<Value>,
    ) -> anyhow::Result<Value> {
        let method = method.to_uppercase();
        let clean_path = clean_path(path);
        let url = format!("{}{}", self.api_base, clean_path);
        let timestamp = now_seconds();
        let nonce = nonce();
        let signature = create_signature(&clean_path, timestamp, &nonce, &method)?;

        let mut request = match method.as_str() {
            "POST" => HttpRequest::post(url.as_str()),
            _ => HttpRequest::get(url.as_str()),
        }
        .header("api-key", API_KEY)
        .header("accept", "application/vnd.picacomic.com.v1+json")
        .header("app-channel", "3")
        .header("time", timestamp.to_string())
        .header("nonce", nonce)
        .header("signature", signature)
        .header("app-version", "2.2.1.3.3.4")
        .header("app-uuid", "defaultUuid")
        .header("app-platform", "android")
        .header("app-build-version", "45")
        .header("accept-encoding", "gzip")
        .header("user-agent", "okhttp/3.8.1")
        .header("content-type", "application/json; charset=UTF-8")
        .header("image-quality", "original");

        if !self.authorization.trim().is_empty() {
            request = request.header("authorization", self.authorization.trim());
        }

        if let Some(body) = body {
            request = request.body(body.to_string());
        }

        let response = self.http.send_text(request).await?;
        let value = serde_json::from_str::<Value>(&response.body).map_err(|error| {
            anyhow::anyhow!(
                "哔咔响应 JSON 解析失败: {error}. Body starts with: {}",
                response_preview(&response.body)
            )
        })?;

        if response.status == 401 || is_unauthorized(&value) {
            anyhow::bail!("哔咔登录过期，请重新登录");
        }
        if !(200..300).contains(&response.status) || is_error_response(&value) {
            anyhow::bail!("哔咔请求失败: {}", error_message(&value, response.status));
        }

        Ok(value)
    }

    fn parse_search_result(&self, data: &Value, fallback_page: i32) -> anyhow::Result<SearchResult> {
        let comics = data
            .get("data")
            .and_then(|data| data.get("comics"))
            .cloned()
            .unwrap_or(Value::Null);
        let docs = comics
            .get("docs")
            .and_then(Value::as_array)
            .cloned()
            .or_else(|| comics.as_array().cloned())
            .unwrap_or_default();
        let page = parse_i64(comics.get("page").unwrap_or(&Value::Null)) as i32;
        let pages = parse_i64(comics.get("pages").unwrap_or(&Value::Null)) as i32;
        let total = parse_i64(comics.get("total").unwrap_or(&Value::Null));
        let items = docs.iter().filter_map(parse_comic).collect::<Vec<_>>();

        Ok(SearchResult {
            total: if total > 0 { total } else { items.len() as i64 },
            page: if page > 0 { page } else { fallback_page },
            has_more: pages > 0 && page > 0 && page < pages,
            items,
        })
    }
}

impl Default for BikaClient {
    fn default() -> Self {
        Self::new("")
    }
}

#[derive(Clone, Copy)]
enum BikaPictureType {
    Cover,
    Creator,
    Favourite,
    Comic,
    Else,
}

fn parse_comic(data: &Value) -> Option<Comic> {
    let id = parse_string(data.get("_id").unwrap_or(&Value::Null))
        .or_else(|| parse_string(data.get("id").unwrap_or(&Value::Null)))?;
    let thumb = data.get("thumb").unwrap_or(&Value::Null);
    let cover_url = build_bika_image_url(
        &parse_string(thumb.get("fileServer").unwrap_or(&Value::Null)).unwrap_or_default(),
        &parse_string(thumb.get("path").unwrap_or(&Value::Null)).unwrap_or_default(),
        BikaPictureType::Cover,
    );
    let mut tags = parse_string_array(data.get("categories").unwrap_or(&Value::Null));
    tags.extend(parse_string_array(data.get("tags").unwrap_or(&Value::Null)));
    if let Some(team) = parse_string(data.get("chineseTeam").unwrap_or(&Value::Null)) {
        tags.push(team);
    }
    tags.sort();
    tags.dedup();

    Some(Comic {
        id,
        title: parse_string(data.get("title").unwrap_or(&Value::Null)).unwrap_or_default(),
        author: parse_string_array(data.get("author").unwrap_or(&Value::Null)),
        cover_url,
        description: parse_string(data.get("description").unwrap_or(&Value::Null))
            .unwrap_or_default(),
        tags,
        likes: parse_i64(
            data.get("totalLikes")
                .or_else(|| data.get("likesCount"))
                .unwrap_or(&Value::Null),
        ),
        views: parse_i64(data.get("totalViews").unwrap_or(&Value::Null)),
        updated_at: parse_string(data.get("updated_at").unwrap_or(&Value::Null))
            .unwrap_or_default(),
    })
}

fn build_bika_image_url(file_server: &str, path_value: &str, picture_type: BikaPictureType) -> String {
    let mut url = file_server.trim().to_string();
    let mut path = path_value.trim().to_string();

    if url == "https://storage1.picacomic.com" {
        url = match picture_type {
            BikaPictureType::Cover => "https://img.picacomic.com".to_string(),
            BikaPictureType::Creator | BikaPictureType::Favourite => {
                "https://s3.picacomic.com".to_string()
            }
            BikaPictureType::Comic | BikaPictureType::Else => {
                "https://s3.picacomic.com".to_string()
            }
        };
    } else if url == "https://storage-b.picacomic.com" {
        url = match picture_type {
            BikaPictureType::Creator => "https://storage-b.picacomic.com".to_string(),
            BikaPictureType::Cover => "https://img.picacomic.com".to_string(),
            _ => "https://storage-b.diwodiwo.xyz".to_string(),
        };
    }

    if path.contains("picacomic-paint.jpg") || path.contains("picacomic-gift.jpg") {
        url = "https://s3.picacomic.com/static".to_string();
    }

    if path.contains("tobeimg/") {
        path = path.replace("tobeimg/", "");
    } else if path.contains("tobs/") {
        path = format!("static/{}", path.replace("tobs/", ""));
    } else if !path.contains('/') && !url.contains("static") {
        path = format!("static/{path}");
    }

    if url.is_empty() || path.is_empty() {
        return String::new();
    }
    format!("{}/{}", url.trim_end_matches('/'), path.trim_start_matches('/'))
}

fn normalize_api_base(raw: &str) -> String {
    let value = raw.trim();
    let selected = if value == BACKUP_API_BASE {
        BACKUP_API_BASE
    } else {
        DEFAULT_API_BASE
    };
    selected.to_string()
}

fn clean_path(input: &str) -> String {
    let value = input.trim();
    if value.starts_with("http://") || value.starts_with("https://") {
        if let Ok(url) = reqwest::Url::parse(value) {
            let mut path = url.path().trim_start_matches('/').to_string();
            if let Some(query) = url.query() {
                path.push('?');
                path.push_str(query);
            }
            return path;
        }
    }
    value
        .replace(DEFAULT_API_BASE, "")
        .replace(BACKUP_API_BASE, "")
        .trim_start_matches('/')
        .to_string()
}

fn create_signature(
    path: &str,
    timestamp: i64,
    nonce: &str,
    method: &str,
) -> anyhow::Result<String> {
    let raw = format!("{path}{timestamp}{nonce}{method}{API_KEY}").to_lowercase();
    let mut mac = HmacSha256::new_from_slice(SECRET_KEY.as_bytes())
        .map_err(|error| anyhow::anyhow!("HMAC key 非法: {error}"))?;
    mac.update(raw.as_bytes());
    let result = mac.finalize().into_bytes();
    Ok(result.iter().map(|byte| format!("{byte:02x}")).collect())
}

fn nonce() -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    md5_hex(&format!("{nanos}:{counter}"))
}

fn md5_hex(input: &str) -> String {
    let mut hasher = Md5::new();
    hasher.update(input.as_bytes());
    let result = hasher.finalize();
    result.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn now_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or_default()
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

fn sanitize_path(path: &str) -> String {
    let sanitized = path
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '.') {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>();
    if sanitized.is_empty() {
        "_".to_string()
    } else {
        sanitized
    }
}

fn is_unauthorized(value: &Value) -> bool {
    value
        .get("code")
        .and_then(Value::as_i64)
        .is_some_and(|code| code == 401)
        || value
            .get("error")
            .and_then(parse_string)
            .is_some_and(|error| error == "1005")
}

fn is_error_response(value: &Value) -> bool {
    value
        .get("code")
        .and_then(Value::as_i64)
        .is_some_and(|code| code != 200)
}

fn error_message(value: &Value, status: u16) -> String {
    parse_string(value.get("message").unwrap_or(&Value::Null))
        .or_else(|| parse_string(value.get("errorMsg").unwrap_or(&Value::Null)))
        .unwrap_or_else(|| format!("HTTP {status}: {}", response_preview(&value.to_string())))
}

fn response_preview(raw: &str) -> String {
    raw.chars().take(160).collect()
}

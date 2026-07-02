use crate::api::jm::JmClient;

/// 初始化 Rust 核心
pub fn init() -> String {
    "Komix Core Initialized".to_string()
}

/// 搜索漫画 (JM 源)
pub async fn jm_search(keyword: String, page: i32) -> Result<String, String> {
    let client = JmClient::new();
    match client.search(&keyword, page).await {
        Ok(result) => serde_json::to_string(&result).map_err(|e| e.to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// 获取漫画详情 (JM 源)
pub async fn jm_get_comic_detail(comic_id: String) -> Result<String, String> {
    let client = JmClient::new();
    match client.get_comic_detail(&comic_id).await {
        Ok(comic) => serde_json::to_string(&comic).map_err(|e| e.to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// 获取章节列表 (JM 源)
pub async fn jm_get_chapters(comic_id: String) -> Result<String, String> {
    let client = JmClient::new();
    match client.get_chapters(&comic_id).await {
        Ok(chapters) => serde_json::to_string(&chapters).map_err(|e| e.to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// 获取章节图片 (JM 源)
pub async fn jm_get_chapter_images(chapter_id: String) -> Result<String, String> {
    let client = JmClient::new();
    match client.get_chapter_images(&chapter_id).await {
        Ok(images) => serde_json::to_string(&images).map_err(|e| e.to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// 获取最新更新 (JM 源)
pub async fn jm_get_latest(page: i32) -> Result<String, String> {
    let client = JmClient::new();
    match client.get_latest(page).await {
        Ok(result) => serde_json::to_string(&result).map_err(|e| e.to_string()),
        Err(e) => Err(e.to_string()),
    }
}

/// 获取排行榜 (JM 源)
pub async fn jm_get_ranking(category: String, order: String, page: i32) -> Result<String, String> {
    let client = JmClient::new();
    match client.get_ranking(&category, &order, page).await {
        Ok(result) => serde_json::to_string(&result).map_err(|e| e.to_string()),
        Err(e) => Err(e.to_string()),
    }
}

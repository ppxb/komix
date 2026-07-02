use anyhow::{Context, Result};
use reqwest::{Client, Method};
use std::time::Duration;

#[derive(Clone)]
pub struct HttpClient {
    client: Client,
}

pub struct HttpRequest {
    method: Method,
    url: String,
    headers: Vec<(String, String)>,
    query: Vec<(String, String)>,
    body: Option<String>,
}

pub struct HttpResponse {
    pub status: u16,
    pub final_url: String,
    pub body: String,
}

impl HttpClient {
    pub fn new() -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .context("创建 HTTP client 失败")?;

        Ok(Self { client })
    }

    pub async fn send_text(&self, request: HttpRequest) -> Result<HttpResponse> {
        let HttpRequest {
            method,
            url,
            headers,
            query,
            body,
        } = request;

        let mut builder = self.client.request(method, &url);

        if !query.is_empty() {
            builder = builder.query(&query);
        }

        for (name, value) in headers {
            builder = builder.header(name.as_str(), value.as_str());
        }

        if let Some(body) = body {
            builder = builder.body(body);
        }

        let response = builder
            .send()
            .await
            .with_context(|| format!("发送 HTTP 请求失败: {url}"))?;
        let status = response.status().as_u16();
        let final_url = response.url().to_string();
        let body = response
            .text()
            .await
            .with_context(|| format!("读取 HTTP 响应体失败: {final_url}"))?;

        Ok(HttpResponse {
            status,
            final_url,
            body,
        })
    }
}

impl HttpRequest {
    pub fn get(url: impl Into<String>) -> Self {
        Self::new(Method::GET, url)
    }

    pub fn post(url: impl Into<String>) -> Self {
        Self::new(Method::POST, url)
    }

    pub fn new(method: Method, url: impl Into<String>) -> Self {
        Self {
            method,
            url: url.into(),
            headers: Vec::new(),
            query: Vec::new(),
            body: None,
        }
    }

    pub fn header(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers.push((name.into(), value.into()));
        self
    }

    pub fn query(mut self, name: impl Into<String>, value: impl Into<String>) -> Self {
        self.query.push((name.into(), value.into()));
        self
    }

    pub fn body(mut self, body: impl Into<String>) -> Self {
        self.body = Some(body.into());
        self
    }
}

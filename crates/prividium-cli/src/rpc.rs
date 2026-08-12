use std::{
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};

use reqwest::header::{HeaderMap, HeaderValue, ORIGIN};
use secrecy::{ExposeSecret, SecretString};
use serde_json::{Value, json};

use crate::error::{AppError, Result};

#[derive(Debug)]
pub struct EthereumRpc {
    client: reqwest::Client,
    url: SecretString,
    next_id: AtomicU64,
}

impl EthereumRpc {
    pub fn new(url: impl Into<SecretString>, timeout: Duration) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .user_agent("prividium-cli/1")
            .build()
            .map_err(|error| AppError::failed("HTTP_CLIENT_FAILED", error.to_string()))?;
        Ok(Self {
            client,
            url: url.into(),
            next_id: AtomicU64::new(1),
        })
    }

    pub async fn call(&self, method: &str, params: Value) -> Result<Value> {
        self.call_with_headers(method, params, HeaderMap::new())
            .await
            .map(|value| value.0)
    }

    pub async fn call_with_origin(
        &self,
        method: &str,
        params: Value,
        origin: &str,
    ) -> Result<(Value, HeaderMap)> {
        let mut headers = HeaderMap::new();
        headers.insert(
            ORIGIN,
            HeaderValue::from_str(origin).map_err(|_| {
                AppError::failed("INVALID_BROWSER_ORIGIN", "browser origin is invalid")
            })?,
        );
        self.call_with_headers(method, params, headers).await
    }

    async fn call_with_headers(
        &self,
        method: &str,
        params: Value,
        headers: HeaderMap,
    ) -> Result<(Value, HeaderMap)> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let response = self
            .client
            .post(self.url.expose_secret())
            .headers(headers)
            .json(&json!({"jsonrpc":"2.0","id":id,"method":method,"params":params}))
            .send()
            .await
            .map_err(|_| {
                AppError::action(
                    "RPC_UNAVAILABLE",
                    format!("RPC request for {method} failed; the configured URL remains hidden"),
                    None::<String>,
                )
            })?;
        let response_headers = response.headers().clone();
        let status = response.status();
        let document: Value = response.json().await.map_err(|_| {
            AppError::failed(
                "RPC_RESPONSE_INVALID",
                format!("RPC response for {method} is invalid"),
            )
        })?;
        if !status.is_success() {
            return Err(AppError::action(
                "RPC_HTTP_ERROR",
                format!("RPC request for {method} returned HTTP {status}"),
                None::<String>,
            ));
        }
        if document.get("error").is_some_and(|value| !value.is_null()) {
            return Err(AppError::failed(
                "RPC_METHOD_ERROR",
                format!("RPC returned an error for {method}"),
            ));
        }
        Ok((
            document.get("result").cloned().unwrap_or(Value::Null),
            response_headers,
        ))
    }
}

pub fn quantity_u64(value: &Value, label: &str) -> Result<u64> {
    let value = value.as_str().ok_or_else(|| {
        AppError::failed(
            "RPC_QUANTITY_INVALID",
            format!("{label} is not a hexadecimal quantity"),
        )
    })?;
    u64::from_str_radix(value.strip_prefix("0x").unwrap_or_default(), 16).map_err(|_| {
        AppError::failed(
            "RPC_QUANTITY_INVALID",
            format!("{label} is not a hexadecimal quantity"),
        )
    })
}

use std::time::Duration;

use base64::{
    Engine,
    engine::general_purpose::{URL_SAFE, URL_SAFE_NO_PAD},
};
use rand::{RngCore, rngs::OsRng};
use reqwest::{StatusCode, header::LOCATION, redirect::Policy};
use scraper::{Html, Selector};
use secrecy::{ExposeSecret, SecretString};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use url::Url;

use crate::{
    config::RuntimeConfig,
    error::{AppError, Result},
    rpc::quantity_u64,
};

pub struct ProductSession {
    client: reqwest::Client,
    access_token: SecretString,
    rpc_url: String,
    chain_id: u64,
}

impl ProductSession {
    pub async fn login(config: &RuntimeConfig) -> Result<Self> {
        let domain = config.required("SANDBOX_DOMAIN")?;
        let username = config.required("SANDBOX_USER_1_EMAIL")?;
        let password = config.required("SANDBOX_USER_1_PASSWORD")?;
        let chain_id = config.l2_chain_id()?;
        let issuer = format!("https://idp.{domain}/realms/prividium");
        let redirect_uri = format!("https://app.{domain}/callback");
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(20))
            .cookie_store(true)
            .redirect(Policy::none())
            .user_agent("prividium-happy-path/1")
            .build()
            .map_err(|error| AppError::failed("HTTP_CLIENT_FAILED", error.to_string()))?;

        let verifier = random_base64url(48);
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let state = random_base64url(24);
        let nonce = random_base64url(24);
        let mut authorization = Url::parse(&format!("{issuer}/protocol/openid-connect/auth"))
            .map_err(|error| AppError::failed("OIDC_URL_INVALID", error.to_string()))?;
        authorization.query_pairs_mut().extend_pairs([
            ("client_id", "prividium-client"),
            ("redirect_uri", redirect_uri.as_str()),
            ("response_type", "code"),
            ("scope", "openid"),
            ("state", state.as_str()),
            ("nonce", nonce.as_str()),
            ("code_challenge", challenge.as_str()),
            ("code_challenge_method", "S256"),
        ]);
        let response = client.get(authorization).send().await.map_err(|error| {
            AppError::failed(
                "OIDC_AUTHORIZATION_UNAVAILABLE",
                format!("OIDC authorization endpoint is unavailable: {error}"),
            )
        })?;
        if !response.status().is_success() {
            return Err(AppError::failed(
                "OIDC_AUTHORIZATION_UNAVAILABLE",
                format!(
                    "OIDC authorization endpoint returned HTTP {}",
                    response.status()
                ),
            ));
        }
        let login_url = response.url().clone();
        let html = response
            .text()
            .await
            .map_err(|error| AppError::failed("OIDC_LOGIN_FORM_INVALID", error.to_string()))?;
        let (action, mut fields) = parse_login_form(&html, &login_url)?;
        fields.insert("username".to_owned(), username.to_owned());
        fields.insert("password".to_owned(), password.to_owned());
        fields.insert("credentialId".to_owned(), String::new());
        let response = client
            .post(action)
            .form(&fields)
            .send()
            .await
            .map_err(|error| AppError::failed("OIDC_LOGIN_FAILED", error.to_string()))?;
        let callback = follow_to_callback(&client, response, &redirect_uri).await?;
        let values: std::collections::BTreeMap<_, _> =
            callback.query_pairs().into_owned().collect();
        if values.get("state") != Some(&state) {
            return Err(AppError::failed(
                "OIDC_STATE_MISMATCH",
                "OIDC callback state did not match the authorization request",
            ));
        }
        let code = values
            .get("code")
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                AppError::failed(
                    "OIDC_CODE_MISSING",
                    "OIDC callback did not contain an authorization code",
                )
            })?;
        let token: Value = client
            .post(format!("{issuer}/protocol/openid-connect/token"))
            .form(&[
                ("grant_type", "authorization_code"),
                ("client_id", "prividium-client"),
                ("redirect_uri", redirect_uri.as_str()),
                ("code", code.as_str()),
                ("code_verifier", verifier.as_str()),
            ])
            .send()
            .await
            .map_err(|error| AppError::failed("OIDC_TOKEN_EXCHANGE_FAILED", error.to_string()))?
            .error_for_status()
            .map_err(|error| AppError::failed("OIDC_TOKEN_EXCHANGE_FAILED", error.to_string()))?
            .json()
            .await
            .map_err(|error| AppError::failed("OIDC_TOKEN_INVALID", error.to_string()))?;
        let access_token = token
            .get("access_token")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                AppError::failed(
                    "OIDC_TOKEN_MISSING",
                    "token response contained no access token",
                )
            })?;
        validate_claims(access_token, username)?;
        let session = Self {
            client,
            access_token: SecretString::from(access_token.to_owned()),
            rpc_url: format!("https://api.{domain}/rpc"),
            chain_id,
        };
        session.verify_chain().await?;
        Ok(session)
    }

    pub async fn rpc(&self, method: &str, params: Value) -> Result<Value> {
        let response = self
            .client
            .post(&self.rpc_url)
            .bearer_auth(self.access_token.expose_secret())
            .json(&json!({"jsonrpc":"2.0","id":1,"method":method,"params":params}))
            .send()
            .await
            .map_err(|error| {
                AppError::failed(
                    "AUTHENTICATED_RPC_FAILED",
                    format!("protected RPC request for {method} failed: {error}"),
                )
            })?;
        if response.status() == StatusCode::UNAUTHORIZED {
            return Err(AppError::failed(
                "AUTHENTICATED_RPC_UNAUTHORIZED",
                "protected RPC rejected the non-admin access token",
            ));
        }
        let response: Value = response
            .error_for_status()
            .map_err(|error| AppError::failed("AUTHENTICATED_RPC_FAILED", error.to_string()))?
            .json()
            .await
            .map_err(|error| AppError::failed("AUTHENTICATED_RPC_INVALID", error.to_string()))?;
        if response.get("error").is_some_and(|value| !value.is_null()) {
            return Err(AppError::failed(
                "AUTHENTICATED_RPC_ERROR",
                format!("protected RPC returned an error for {method}"),
            ));
        }
        Ok(response.get("result").cloned().unwrap_or(Value::Null))
    }

    async fn verify_chain(&self) -> Result<()> {
        let actual = quantity_u64(
            &self.rpc("eth_chainId", json!([])).await?,
            "protected RPC chain ID",
        )?;
        if actual != self.chain_id {
            return Err(AppError::failed(
                "AUTHENTICATED_RPC_CHAIN_MISMATCH",
                format!(
                    "protected RPC chain ID {actual} does not match {}",
                    self.chain_id
                ),
            ));
        }
        Ok(())
    }
}

fn parse_login_form(
    document: &str,
    base_url: &Url,
) -> Result<(Url, std::collections::BTreeMap<String, String>)> {
    let html = Html::parse_document(document);
    let form_selector = Selector::parse("form")
        .map_err(|error| AppError::failed("OIDC_LOGIN_FORM_INVALID", error.to_string()))?;
    let input_selector = Selector::parse("input")
        .map_err(|error| AppError::failed("OIDC_LOGIN_FORM_INVALID", error.to_string()))?;
    let form = html.select(&form_selector).next().ok_or_else(|| {
        AppError::failed(
            "OIDC_LOGIN_FORM_MISSING",
            "OIDC endpoint returned no login form",
        )
    })?;
    let action = form.value().attr("action").ok_or_else(|| {
        AppError::failed("OIDC_LOGIN_FORM_INVALID", "OIDC login form has no action")
    })?;
    let action = base_url
        .join(action)
        .map_err(|error| AppError::failed("OIDC_LOGIN_FORM_INVALID", error.to_string()))?;
    let fields = form
        .select(&input_selector)
        .filter_map(|input| {
            let name = input.value().attr("name")?;
            Some((
                name.to_owned(),
                input.value().attr("value").unwrap_or_default().to_owned(),
            ))
        })
        .collect();
    Ok((action, fields))
}

async fn follow_to_callback(
    client: &reqwest::Client,
    mut response: reqwest::Response,
    callback_prefix: &str,
) -> Result<Url> {
    for _ in 0..8 {
        let location = response
            .headers()
            .get(LOCATION)
            .and_then(|value| value.to_str().ok())
            .ok_or_else(|| {
                AppError::failed(
                    "OIDC_LOGIN_FAILED",
                    format!(
                        "non-admin OIDC login returned HTTP {} without a redirect",
                        response.status()
                    ),
                )
            })?;
        let target = response
            .url()
            .join(location)
            .map_err(|error| AppError::failed("OIDC_CALLBACK_INVALID", error.to_string()))?;
        if target.as_str().starts_with(callback_prefix) {
            return Ok(target);
        }
        response = client
            .get(target)
            .send()
            .await
            .map_err(|error| AppError::failed("OIDC_LOGIN_FAILED", error.to_string()))?;
    }
    Err(AppError::failed(
        "OIDC_CALLBACK_MISSING",
        "non-admin OIDC login did not reach the approved callback",
    ))
}

fn validate_claims(access_token: &str, username: &str) -> Result<()> {
    let payload = access_token
        .split('.')
        .nth(1)
        .ok_or_else(|| AppError::failed("OIDC_TOKEN_INVALID", "access token is not a JWT"))?;
    let bytes = URL_SAFE_NO_PAD
        .decode(payload)
        .or_else(|_| URL_SAFE.decode(payload))
        .map_err(|_| AppError::failed("OIDC_TOKEN_INVALID", "JWT payload is not base64url"))?;
    let claims: Value = serde_json::from_slice(&bytes)
        .map_err(|error| AppError::failed("OIDC_TOKEN_INVALID", error.to_string()))?;
    let roles = claims
        .pointer("/realm_access/roles")
        .and_then(Value::as_array)
        .ok_or_else(|| AppError::failed("OIDC_ROLE_INVALID", "access token has no realm roles"))?;
    let has_user = roles.iter().any(|value| value.as_str() == Some("user"));
    let has_admin = roles.iter().any(|value| value.as_str() == Some("admin"));
    if !has_user || has_admin {
        return Err(AppError::failed(
            "OIDC_ROLE_INVALID",
            "OIDC smoke identity is not a non-admin user",
        ));
    }
    if claims
        .get("preferred_username")
        .and_then(Value::as_str)
        .is_none_or(|value| !value.eq_ignore_ascii_case(username))
    {
        return Err(AppError::failed(
            "OIDC_IDENTITY_MISMATCH",
            "OIDC access token identifies the wrong evaluation user",
        ));
    }
    Ok(())
}

fn random_base64url(bytes: usize) -> String {
    let mut value = vec![0_u8; bytes];
    OsRng.fill_bytes(&mut value);
    URL_SAFE_NO_PAD.encode(value)
}

use crate::roc;
use bytes::Bytes;
use futures::{Future, FutureExt};
use hyper::header::{HeaderName, HeaderValue};
use roc_std::{RocList, RocStr};
use std::convert::Infallible;
use std::env;
use std::net::SocketAddr;
use std::panic::AssertUnwindSafe;
use std::sync::OnceLock;
use tokio::task::spawn_blocking;

const DEFAULT_PORT: u16 = 8000;
const HOST_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_HOST";
const PORT_ENV_NAME: &str = "ROC_BASIC_WEBSERVER_PORT";

static ROC_MODEL: OnceLock<roc::Model> = OnceLock::new();

pub fn start() -> i32 {
    // Ensure the model is loaded right at startup.
    ROC_MODEL
        .set(roc::call_roc_init())
        .expect("Model is only initialized once at start");

    match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime.block_on(async { run_server().await }),
        Err(err) => {
            eprintln!("Error initializing tokio multithreaded runtime: {}", err); // TODO improve this

            1
        }
    }
}

#[allow(dead_code)]
fn call_roc<'a>(
    method: reqwest::Method,
    url: hyper::Uri,
    headers: impl Iterator<Item = (&'a HeaderName, &'a HeaderValue)>,
    body: Bytes,
) -> hyper::Response<hyper::Body> {
    let headers: RocList<roc_http::Header> = headers
        .map(|(key, value)| roc_http::Header {
            name: key.as_str().into(),
            value: value
                .to_str()
                .expect("valid header value from hyper")
                .into(),
        })
        .collect();

    let (method, method_ext) = {
        match method {
            reqwest::Method::GET => (roc_http::MethodTag::Get, RocStr::empty()),
            reqwest::Method::POST => (roc_http::MethodTag::Post, RocStr::empty()),
            reqwest::Method::PUT => (roc_http::MethodTag::Put, RocStr::empty()),
            reqwest::Method::DELETE => (roc_http::MethodTag::Delete, RocStr::empty()),
            reqwest::Method::HEAD => (roc_http::MethodTag::Head, RocStr::empty()),
            reqwest::Method::OPTIONS => (roc_http::MethodTag::Options, RocStr::empty()),
            reqwest::Method::CONNECT => (roc_http::MethodTag::Connect, RocStr::empty()),
            reqwest::Method::PATCH => (roc_http::MethodTag::Patch, RocStr::empty()),
            reqwest::Method::TRACE => (roc_http::MethodTag::Trace, RocStr::empty()),
            _ => (roc_http::MethodTag::Extension, method.as_str().into()),
        }
    };

    let roc_request = roc_http::RequestToAndFromHost {
        // TODO is this right?? just winging it here
        body: unsafe { RocList::from_raw_parts(body.as_ptr() as *mut u8, body.len(), body.len()) },
        headers,
        method,
        uri: url.to_string().as_str().into(),
        method_ext,
        timeout_ms: 0,
    };

    let roc_response = roc::call_roc_respond(
        roc_request,
        ROC_MODEL.get().expect("Model was initialized at startup"),
    );

    roc_response.into()
}

async fn handle_req(req: hyper::Request<hyper::Body>) -> hyper::Response<hyper::Body> {
    let (parts, body) = req.into_parts();

    #[allow(deprecated)]
    match hyper::body::to_bytes(body).await {
        Ok(body) => {
            spawn_blocking(move || call_roc(parts.method, parts.uri, parts.headers.iter(), body))
                .then(|resp| async {
                    resp.unwrap() // TODO don't unwrap here
                })
                .await
        }
        Err(_) => {
            hyper::Response::builder()
                .status(hyper::StatusCode::BAD_REQUEST)
                .body("Error receiving HTTP request body".into())
                .unwrap() // TODO don't unwrap here
        }
    }
}

/// Translate Rust panics in the given Future into 500 errors
async fn handle_panics(
    fut: impl Future<Output = hyper::Response<hyper::Body>>,
) -> Result<hyper::Response<hyper::Body>, Infallible> {
    match AssertUnwindSafe(fut).catch_unwind().await {
        Ok(response) => Ok(response),
        Err(_panic) => {
            let error = hyper::Response::builder()
                .status(hyper::StatusCode::INTERNAL_SERVER_ERROR)
                .body("Panic detected!".into())
                .unwrap(); // TODO don't unwrap here

            Ok(error)
        }
    }
}

async fn run_server() -> i32 {
    let host = env::var(HOST_ENV_NAME).unwrap_or("127.0.0.1".to_string());
    let port = env::var(PORT_ENV_NAME).unwrap_or(DEFAULT_PORT.to_string());
    let addr = format!("{}:{}", host, port)
        .parse::<SocketAddr>()
        .expect("Failed to parse host and port");
    let server = hyper::Server::bind(&addr).serve(hyper::service::make_service_fn(|_conn| async {
        Ok::<_, Infallible>(hyper::service::service_fn(|req| {
            handle_panics(handle_req(req))
        }))
    }));

    println!("Listening on <http://{host}:{port}>");

    match server.await {
        Ok(_) => 0,
        Err(err) => {
            eprintln!("Error initializing Rust `hyper` server: {}", err); // TODO improve this

            1
        }
    }
}

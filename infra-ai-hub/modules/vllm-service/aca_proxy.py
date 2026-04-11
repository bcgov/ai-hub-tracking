import asyncio
import os
import signal
import subprocess
import sys

import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse
from starlette.background import BackgroundTask


LISTEN_HOST = os.getenv("VLLM_PROXY_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("VLLM_PROXY_PORT", "8000"))
BACKEND_URL = os.getenv("VLLM_BACKEND_URL", "http://127.0.0.1:8001")
FORWARDED_METHODS = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
UPSTREAM_TIMEOUT = httpx.Timeout(connect=1.0, read=None, write=None, pool=None)
EXCLUDED_HEADERS = {
    "connection",
    "content-length",
    "content-encoding",
    "host",
    "keep-alive",
    "transfer-encoding",
}


app = FastAPI()
client = httpx.AsyncClient(base_url=BACKEND_URL, timeout=UPSTREAM_TIMEOUT)
backend_process = None


def backend_exited() -> bool:
    return backend_process is not None and backend_process.poll() is not None


async def backend_ready() -> bool:
    if backend_exited():
        return False

    try:
        response = await client.get("/v1/models")
    except httpx.RequestError:
        return False

    return response.status_code < 500


async def watch_backend() -> None:
    loop = asyncio.get_running_loop()
    exit_code = await loop.run_in_executor(None, backend_process.wait)
    os._exit(exit_code if exit_code != 0 else 0)


@app.on_event("startup")
async def start_backend() -> None:
    global backend_process

    backend_command = [sys.executable, "/usr/local/bin/vllm", "serve", *sys.argv[1:]]
    backend_process = subprocess.Popen(backend_command)
    asyncio.create_task(watch_backend())


@app.on_event("shutdown")
async def stop_backend() -> None:
    if backend_process is None or backend_exited():
        return

    backend_process.send_signal(signal.SIGTERM)

    try:
        await asyncio.get_running_loop().run_in_executor(None, backend_process.wait, 10)
    except subprocess.TimeoutExpired:
        backend_process.kill()

    await client.aclose()


@app.get("/healthz")
async def healthz() -> Response:
    if backend_exited():
        return JSONResponse(
            {"status": "exited", "exit_code": backend_process.returncode},
            status_code=500,
        )

    if await backend_ready():
        return JSONResponse({"status": "ready"})

    return JSONResponse({"status": "warming"}, status_code=503)


@app.api_route("/{path:path}", methods=FORWARDED_METHODS)
async def proxy(path: str, request: Request) -> Response:
    if backend_exited():
        return JSONResponse(
            {"error": "vllm backend exited", "exit_code": backend_process.returncode},
            status_code=500,
        )

    request_headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in EXCLUDED_HEADERS
    }

    upstream_url = httpx.URL(path=f"/{path}", query=request.url.query.encode())
    request_body = await request.body()

    try:
        upstream_request = client.build_request(
            request.method,
            upstream_url,
            headers=request_headers,
            content=request_body,
        )
        upstream_response = await client.send(upstream_request, stream=True)
    except httpx.RequestError:
        return JSONResponse({"error": "vllm backend warming"}, status_code=503)

    response_headers = {
        key: value
        for key, value in upstream_response.headers.items()
        if key.lower() not in EXCLUDED_HEADERS
    }

    return StreamingResponse(
        upstream_response.aiter_raw(),
        status_code=upstream_response.status_code,
        headers=response_headers,
        background=BackgroundTask(upstream_response.aclose),
    )


if __name__ == "__main__":
    uvicorn.run(app, host=LISTEN_HOST, port=LISTEN_PORT, log_level="info")

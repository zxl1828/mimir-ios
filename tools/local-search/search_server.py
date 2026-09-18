#!/usr/bin/env python3
"""
本地搜索服务 —— 给 Mimir 提供联网搜索能力，不需要任何第三方搜索 API。

原理：
    手机 App 把查询发给这台电脑（局域网），电脑用自己已经能上网的环境
    去请求搜索引擎，把结果整理成 JSON 返回。手机不需要自己翻墙。

用法：
    python search_server.py                 # 默认监听 0.0.0.0:8848
    python search_server.py --port 9000
    python search_server.py --host 127.0.0.1

接口：
    GET /search?q=关键词&count=8
    GET /health

返回：
    {"query": "...", "source": "bing", "results": [
        {"title": "...", "url": "...", "snippet": "...", "source": "bing"}]}

数据源（自动降级）：
    1. Bing 的 RSS 输出 —— 结构稳定、不需要解析 HTML
    2. DuckDuckGo 的无脚本页面 —— 作为备选

只用 Python 标准库，不装任何依赖。
"""

from __future__ import annotations

import argparse
import gzip
import html
import io
import json
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)
REQUEST_TIMEOUT = 12


# --------------------------------------------------------------------------
# 抓取与解析
# --------------------------------------------------------------------------


def _fetch(url: str) -> str:
    """抓取一个 URL 并返回文本，自动处理 gzip。"""
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Accept-Encoding": "gzip",
        },
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        raw = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
        charset = response.headers.get_content_charset() or "utf-8"
        return raw.decode(charset, errors="replace")


def _clean(text: str) -> str:
    """去掉标签、压缩空白、还原 HTML 实体。"""
    stripped = re.sub(r"<[^>]+>", "", text or "")
    return html.unescape(re.sub(r"\s+", " ", stripped)).strip()


def search_bing(query: str, count: int) -> list[dict]:
    """Bing 的 RSS 输出，最稳的一条路。"""
    url = "https://www.bing.com/search?" + urllib.parse.urlencode(
        {"q": query, "format": "rss", "count": max(count, 10)}
    )
    xml_text = _fetch(url)
    root = ET.fromstring(xml_text)

    results: list[dict] = []
    for item in root.iter("item"):
        title = _clean(item.findtext("title") or "")
        link = (item.findtext("link") or "").strip()
        snippet = _clean(item.findtext("description") or "")
        if not title or not link:
            continue
        results.append(
            {"title": title, "url": link, "snippet": snippet, "source": "bing"}
        )
        if len(results) >= count:
            break
    return results


_DDG_RESULT = re.compile(
    r'<a[^>]+class="result__a"[^>]+href="(?P<href>[^"]+)"[^>]*>(?P<title>.*?)</a>',
    re.S,
)
_DDG_SNIPPET = re.compile(
    r'<a[^>]+class="result__snippet"[^>]*>(?P<snippet>.*?)</a>', re.S
)


def _unwrap_ddg(href: str) -> str:
    """DuckDuckGo 的结果链接是跳转形式，取其中的真实地址。"""
    if href.startswith("//"):
        href = "https:" + href
    parsed = urllib.parse.urlparse(href)
    params = urllib.parse.parse_qs(parsed.query)
    if "uddg" in params:
        return params["uddg"][0]
    return href


def search_duckduckgo(query: str, count: int) -> list[dict]:
    """DuckDuckGo 无脚本版，作为 Bing 失败时的备选。"""
    url = "https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query})
    page = _fetch(url)

    titles = list(_DDG_RESULT.finditer(page))
    snippets = [_clean(m.group("snippet")) for m in _DDG_SNIPPET.finditer(page)]

    results: list[dict] = []
    for index, match in enumerate(titles):
        title = _clean(match.group("title"))
        link = _unwrap_ddg(match.group("href"))
        if not title or not link:
            continue
        results.append(
            {
                "title": title,
                "url": link,
                "snippet": snippets[index] if index < len(snippets) else "",
                "source": "duckduckgo",
            }
        )
        if len(results) >= count:
            break
    return results


SOURCES = (
    ("duckduckgo", search_duckduckgo),
    ("bing", search_bing),
)


def run_search(query: str, count: int) -> tuple[str, list[dict]]:
    """依次尝试各个数据源，返回第一个有结果的。"""
    errors: list[str] = []
    for name, func in SOURCES:
        try:
            results = func(query, count)
            if results:
                return name, results
            errors.append(f"{name}: 没有结果")
        except Exception as exc:  # noqa: BLE001 - 网络问题种类多，统一记录
            errors.append(f"{name}: {type(exc).__name__} {exc}")
    raise RuntimeError("; ".join(errors) or "所有数据源都不可用")


# --------------------------------------------------------------------------
# HTTP 服务
# --------------------------------------------------------------------------


class SearchHandler(BaseHTTPRequestHandler):
    server_version = "MimirLocalSearch/1.0"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler 的命名约定
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if parsed.path == "/health":
            self._send_json({"status": "ok", "time": time.time()})
            return

        if parsed.path not in ("/search", "/"):
            self._send_json({"error": "未知路径，请使用 /search?q=关键词"}, status=404)
            return

        query = (params.get("q") or [""])[0].strip()
        if not query:
            self._send_json({"error": "缺少查询参数 q"}, status=400)
            return

        try:
            count = min(max(int((params.get("count") or ["8"])[0]), 1), 20)
        except ValueError:
            count = 8

        started = time.time()
        try:
            source, results = run_search(query, count)
        except Exception as exc:  # noqa: BLE001
            print(f"[search] 失败 query={query!r} error={exc}", flush=True)
            self._send_json({"query": query, "error": str(exc), "results": []}, status=502)
            return

        elapsed = time.time() - started
        print(
            f"[search] {query!r} -> {len(results)} 条，来自 {source}，{elapsed:.2f}s",
            flush=True,
        )
        self._send_json(
            {
                "query": query,
                "source": source,
                "elapsed": round(elapsed, 3),
                "results": results,
            }
        )

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._send_cors()
        self.end_headers()

    def _send_cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")

    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._send_cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:  # noqa: A002
        # 默认的逐请求日志太吵，只保留错误。
        if args and str(args[1]).startswith(("4", "5")):
            super().log_message(fmt, *args)


def local_ip() -> str:
    """尽量拿到局域网地址，方便直接告诉用户填进 App。"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def main() -> int:
    parser = argparse.ArgumentParser(description="Mimir 本地搜索服务")
    parser.add_argument("--host", default="0.0.0.0", help="监听地址，默认 0.0.0.0")
    parser.add_argument("--port", type=int, default=8848, help="监听端口，默认 8848")
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), SearchHandler)
    shown = local_ip() if args.host == "0.0.0.0" else args.host
    print("Mimir 本地搜索服务已启动")
    print(f"  本机访问 : http://127.0.0.1:{args.port}/search?q=test")
    print(f"  局域网   : http://{shown}:{args.port}/search?q=test")
    print("  在 App 的「联网搜索」里填入上面这个局域网地址即可")
    print("  按 Ctrl+C 停止")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Mimir Code Bridge —— 把本机项目文件实时喂给手机上的「代码工坊」。

用途：AI（Codex / 其他）在电脑上改这个项目的代码时，iPhone 上的 Mimir
「代码工坊」标签页能实时看到正在编辑的文件内容——文件一变，手机上就刷新。

启动：
    python tools/code_server.py                 # 默认 8849 端口，根目录为仓库根
    python tools/code_server.py --port 8849 --root .

手机端：在 Mimir 的「代码工坊 → 桥接」里填 http://<电脑局域网IP>:8849

接口：
    GET /health          → 服务信息
    GET /status          → 最近被修改的源码文件（AI 正在编辑的那个）
    GET /file?path=...   → 指定文件的内容
    GET /list            → 源码文件列表（按修改时间倒序）
"""

from __future__ import annotations

import argparse
import json
import pathlib
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

# 只暴露源码类文件，避免把二进制资源、构建产物喂给手机
WATCH_SUFFIXES = (".swift", ".yml", ".yaml", ".md", ".sh", ".py", ".json")
SKIP_DIRS = {
    ".git", ".build", ".swiftpm", "build", "Build", "DerivedData",
    "__pycache__", "node_modules", "outputs", "work", ".codex-mobile-tools",
}
MAX_FILES = 400
MAX_BYTES = 200_000  # 单文件读取上限，防止误拉超大文件

ROOT: pathlib.Path = pathlib.Path(".").resolve()


def iter_source_files() -> list[tuple[float, str, int]]:
    """列出项目源码文件，按修改时间倒序。"""
    results: list[tuple[float, str, int]] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in WATCH_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        try:
            stat = path.stat()
        except OSError:
            continue
        results.append((stat.st_mtime, path.relative_to(ROOT).as_posix(), stat.st_size))
    results.sort(reverse=True)
    return results[:MAX_FILES]


def safe_resolve(relative: str) -> pathlib.Path | None:
    """把请求里的相对路径安全映射到项目内文件（拒绝目录穿越）。"""
    if not relative or ".." in relative:
        return None
    candidate = (ROOT / relative).resolve()
    if not str(candidate).startswith(str(ROOT)):
        return None
    return candidate if candidate.is_file() else None


class CodeBridgeHandler(BaseHTTPRequestHandler):

    server_version = "MimirCodeBridge/1.0"

    def _send(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802（标准库命名）
        parsed = urlparse(self.path)
        route = parsed.path
        query = parse_qs(parsed.query)

        if route == "/health":
            self._send({"ok": True, "service": "mimir-code-bridge", "root": str(ROOT)})
            return

        if route == "/status":
            files = iter_source_files()
            if not files:
                self._send({"ok": True, "file": None, "count": 0})
                return
            mtime, rel, size = files[0]
            self._send({
                "ok": True,
                "file": rel,
                "mtime": mtime,
                "size": size,
                "edited_ago": round(time.time() - mtime, 1),
                "count": len(files),
            })
            return

        if route == "/file":
            relative = (query.get("path") or [""])[0]
            target = safe_resolve(relative)
            if target is None:
                self._send({"ok": False, "error": "file not found"}, 404)
                return
            raw = target.read_bytes()[:MAX_BYTES]
            text = raw.decode("utf-8", errors="replace")
            self._send({
                "ok": True,
                "path": relative,
                "mtime": target.stat().st_mtime,
                "lines": text.count("\n") + 1,
                "content": text,
            })
            return

        if route == "/list":
            self._send({
                "ok": True,
                "files": [
                    {"path": rel, "mtime": mtime, "size": size}
                    for mtime, rel, size in iter_source_files()
                ],
            })
            return

        self._send({"ok": False, "error": "unknown route"}, 404)

    def log_message(self, fmt: str, *args) -> None:  # 手机轮询很频繁，保持安静
        return


def main() -> None:
    global ROOT

    parser = argparse.ArgumentParser(description="Mimir Code Bridge")
    parser.add_argument("--port", type=int, default=8849)
    parser.add_argument("--root", default=".", help="项目根目录")
    args = parser.parse_args()

    ROOT = pathlib.Path(args.root).resolve()
    server = ThreadingHTTPServer(("0.0.0.0", args.port), CodeBridgeHandler)

    print(f"Mimir Code Bridge 已就绪：http://0.0.0.0:{args.port}")
    print(f"项目根目录：{ROOT}")
    print(f"监听文件类型：{', '.join(WATCH_SUFFIXES)}")
    print(f"手机端填写：http://<本机局域网IP>:{args.port}")
    print("按 Ctrl+C 停止。")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止。")


if __name__ == "__main__":
    main()

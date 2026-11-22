"""Only serve explicitly published images from a dedicated directory."""
import argparse
import os
import re
import shutil
import stat
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

IMAGE = re.compile(r"/([a-zA-Z0-9_-]{1,128}\.(png|jpg|jpeg|webp|gif))")
TYPES = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
         "webp": "image/webp", "gif": "image/gif"}


def handler(root):
    class Images(BaseHTTPRequestHandler):
        def do_GET(self):
            self.serve_image(True)

        def do_HEAD(self):
            self.serve_image(False)

        def serve_image(self, body):
            if self.path == "/healthz":
                self.send_response(204)
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Phone-Image-Host", "ready")
                self.end_headers()
                return
            match = IMAGE.fullmatch(self.path)
            if not match:
                self.send_error(404)
                return
            name, extension = match.groups()
            try:
                fd = os.open(root / name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            except OSError:
                self.send_error(404)
                return
            with os.fdopen(fd, "rb") as file:
                info = os.fstat(file.fileno())
                if not stat.S_ISREG(info.st_mode):
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", TYPES[extension])
                self.send_header("Content-Length", str(info.st_size))
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                if body:
                    try:
                        shutil.copyfileobj(file, self.wfile)
                    except (BrokenPipeError, ConnectionResetError):
                        pass

        def log_message(self, *args):
            pass

    return Images


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--port", type=int, default=8092)
    args = parser.parse_args()
    root = args.directory.resolve(strict=True)
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler(root)) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()

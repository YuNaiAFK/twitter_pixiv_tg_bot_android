import sys
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import phone_images


class PhoneImagesTests(unittest.TestCase):
    def test_duplicate_and_capacity(self):
        first = b"GIF89a-one"
        second = b"GIF89a-two"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "data" / "public-images"
            root.mkdir(parents=True)
            with (
                patch.dict("os.environ", PHONE_IMAGE_PUBLIC_BASE="https://img.test"),
                patch.dict(sys.modules, fcntl=SimpleNamespace(flock=Mock(), LOCK_EX=1)),
                patch.object(phone_images, "__file__", str(Path(directory) / "bot" / "phone_images.py")),
                patch.object(phone_images, "MAX_STORAGE", len(first)),
                patch.object(phone_images, "DISK_RESERVE", 0),
                patch.object(phone_images.httpx, "get", return_value=SimpleNamespace(
                    status_code=204, headers={"X-Phone-Image-Host": "ready"})),
            ):
                urls = phone_images.store_many([first, first, second], fetch=lambda source: source)
                self.assertEqual(list(urls), [0, 1])
                self.assertEqual(urls[0], urls[1])
                self.assertEqual([p.read_bytes() for p in root.iterdir()], [first])

    def test_wrong_origin_falls_back_before_fetch(self):
        fetch = Mock()
        with (
            patch.dict("os.environ", PHONE_IMAGE_PUBLIC_BASE="https://img.test"),
            patch.object(phone_images.httpx, "get", return_value=SimpleNamespace(status_code=404)),
        ):
            self.assertEqual(phone_images.store_many(["one"], fetch=fetch), {})
        fetch.assert_not_called()


class PhoneProgressTests(unittest.IsolatedAsyncioTestCase):
    async def test_single_message_progress_eta_and_fallback(self):
        edits = []
        observed = threading.Event()

        def worker(urls, *, fetch, stop_event, progress):
            progress(3, 2)
            if not observed.wait(2):
                raise AssertionError("工作尚未完成時沒有更新進度")
            return {0: "a", 1: "b"}

        async def edit(text):
            edits.append(text)
            if "已處理 3/5 張" in text:
                observed.set()

        with patch.object(phone_images, "store_many", side_effect=worker):
            result = await phone_images.store_with_progress(list(range(5)), fetch=None,
                                                            edit=edit, interval=.01)
        self.assertEqual(result, {0: "a", 1: "b"})
        self.assertIn("已處理 0/5 張", edits[0])
        self.assertTrue(any("已存 2 張" in text and "預估剩餘" in text for text in edits))
        self.assertIn("剩餘 3 張交由備援", edits[-1])

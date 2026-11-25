import sys
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import phone_images


class PhoneImagesTests(unittest.TestCase):
    def test_parallel_download_preserves_order_and_cap(self):
        barrier = threading.Barrier(4, timeout=3)
        files = [b"GIF89a-" + bytes([i]) for i in range(4)]

        def fetch(i):
            barrier.wait()
            return files[i]

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "data" / "public-images"
            root.mkdir(parents=True)
            with (
                patch.dict("os.environ", PHONE_IMAGE_PUBLIC_BASE="https://img.test"),
                patch.dict(sys.modules, fcntl=SimpleNamespace(flock=Mock(), LOCK_EX=1)),
                patch.object(phone_images, "__file__", str(Path(directory) / "bot" / "phone_images.py")),
                patch.object(phone_images, "MAX_STORAGE", 2 * len(files[0])),
                patch.object(phone_images, "DISK_RESERVE", 0),
                patch.object(phone_images.httpx, "get", return_value=SimpleNamespace(
                    status_code=204, headers={"X-Phone-Image-Host": "ready"})),
            ):
                urls = phone_images.store_many(list(range(4)), fetch=fetch, workers=4)
                self.assertEqual(list(urls), [0, 1])
                self.assertEqual([(root / u.rsplit("/", 1)[-1]).read_bytes()
                                  for u in urls.values()], files[:2])

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

        def worker(urls, *, fetch, stop_event, progress, workers):
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

class PhoneRecoveryTests(unittest.TestCase):
    def test_restarts_only_tunnel_when_local_origin_is_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            (project / ".phone-image-host.token").touch()
            with (patch.dict("os.environ", PREFIX="/data/data/com.termux/files/usr"),
                  patch.object(phone_images, "_repair_after", 0),
                  patch.object(phone_images.Path, "home", return_value=project),
                  patch.object(phone_images, "_ready", side_effect=[True, False, True]),
                  patch.object(phone_images, "_restart_tunnel") as restart,
                  patch.object(phone_images.subprocess, "run") as start_origin):
                self.assertTrue(phone_images._recover("https://img.test", project, None))
                restart.assert_called_once_with(project)
                start_origin.assert_not_called()

class TunnelDecisionTests(unittest.IsolatedAsyncioTestCase):
    async def test_stop_prevents_storage_and_fallback(self):
        import threading
        from unittest.mock import AsyncMock
        stop = threading.Event()
        decide = AsyncMock(return_value="stop")
        with (patch.object(phone_images, "public_base", return_value="https://img.test"),
              patch.object(phone_images, "_ready", return_value=False),
              patch.object(phone_images, "store_many") as store):
            result = await phone_images.store_with_progress(
                ["one"], fetch=Mock(), edit=AsyncMock(), stop_event=stop, tunnel_decision=decide)
        self.assertEqual(result, {})
        self.assertTrue(stop.is_set())
        decide.assert_awaited_once()
        store.assert_not_called()

import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


with patch('requests.get') as get:
    get.return_value = type('AssetResponse', (), {
        'text': '',
        'content': b'',
    })()
    if 'app.main' in sys.modules:
        del sys.modules['app.main']
    from app import main


class ProxyResponse:
    def __init__(self, body=b'ok', status_code=200, headers=None):
        self.status_code = status_code
        self.headers = headers or {'Content-Type': 'text/plain'}
        self.raw = io.BytesIO(body)
        self._content = body
        self._content_consumed = True


class MainTest(unittest.TestCase):
    def test_normalize_github_file_url(self):
        self.assertEqual(
            main.normalize_github_file_url(
                'https://github.com/user/repo/blob/main/path/file.txt?download=1#part'
            ),
            'https://raw.githubusercontent.com/user/repo/main/path/file.txt?download=1#part',
        )
        self.assertEqual(
            main.normalize_github_file_url(
                'https://github.com/user/repo/raw/main/file.txt'
            ),
            'https://raw.githubusercontent.com/user/repo/main/file.txt',
        )

    def test_normalize_rejects_untrusted_urls(self):
        invalid_urls = (
            'https://github.com.evil.example/user/repo/blob/main/file.txt',
            'https://user:pass@github.com/user/repo/blob/main/file.txt',
            'https://github.com:443/user/repo/blob/main/file.txt',
            'https://raw.githubusercontent.com/user/repo/main/file.txt',
            'https://github.com/user/repo',
        )
        for url in invalid_urls:
            with self.subTest(url=url):
                self.assertIsNone(main.normalize_github_file_url(url))

    @patch.object(main.requests, 'request')
    def test_blob_is_fetched_from_raw_without_redirect(self, request_method):
        request_method.return_value = ProxyResponse(b'MoviePilot')

        with main.app.test_client() as client:
            response = client.get(
                '/https://github.com/user/repo/blob/main/README.md'
            )

        self.assertEqual(response.status_code, 200)
        self.assertNotIn('Location', response.headers)
        self.assertEqual(response.get_data(), b'MoviePilot')
        request_method.assert_called_once()
        self.assertEqual(
            request_method.call_args.kwargs['url'],
            'https://raw.githubusercontent.com/user/repo/main/README.md',
        )

    @patch.object(main.requests, 'request')
    def test_raw_handler_is_fetched_from_raw_host(self, request_method):
        request_method.return_value = ProxyResponse(b'raw')

        with main.app.test_client() as client:
            response = client.get(
                '/https://github.com/user/repo/raw/main/file.txt'
            )

        self.assertEqual(response.status_code, 200)
        self.assertNotIn('Location', response.headers)
        self.assertEqual(response.get_data(), b'raw')
        request_method.assert_called_once()
        self.assertEqual(
            request_method.call_args.kwargs['url'],
            'https://raw.githubusercontent.com/user/repo/main/file.txt',
        )

    @patch.object(main.requests, 'request')
    def test_codeload_path_is_allowed(self, request_method):
        request_method.return_value = ProxyResponse(b'archive')

        with main.app.test_client() as client:
            response = client.get(
                '/https://codeload.github.com/user/repo/zip/refs/heads/main'
                '?download=1'
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_data(), b'archive')
        request_method.assert_called_once()
        self.assertEqual(
            request_method.call_args.kwargs['url'],
            'https://codeload.github.com/user/repo/zip/refs/heads/main?download=1',
        )

    @patch.object(main.requests, 'request')
    def test_codeload_accepts_other_download_paths(self, request_method):
        request_method.return_value = ProxyResponse(b'archive')

        with main.app.test_client() as client:
            response = client.get(
                '/https://codeload.github.com/user/repo/custom/download/path'
            )

        self.assertEqual(response.status_code, 200)
        request_method.assert_called_once()

    def test_codeload_rejects_untrusted_hosts(self):
        invalid_paths = (
            '/https://codeload.github.com.evil.example/user/repo/zip/main',
            '/https://user:pass@codeload.github.com/user/repo/zip/main',
            '/https://codeload.github.com:443/user/repo/zip/main',
            '/https://codeload.github.com',
        )
        with main.app.test_client() as client:
            for path in invalid_paths:
                with self.subTest(path=path):
                    response = client.get(path)
                    self.assertEqual(response.status_code, 403)


if __name__ == '__main__':
    unittest.main()

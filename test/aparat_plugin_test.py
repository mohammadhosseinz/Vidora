"""Run with python3 -m unittest discover -s test -p '*_plugin_test.py'."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

from yt_dlp.utils import ExtractorError

SOURCE = Path(__file__).resolve().parents[1] / (
    'packaging/yt-dlp-plugins/vidora/yt_dlp_plugins/extractor/aparat.py')
spec = importlib.util.spec_from_file_location('vidora_aparat', SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AparatPluginTest(unittest.TestCase):
    def extractor(self, attributes):
        ie = module.AparatVidoraIE()
        ie._download_json = Mock(return_value={'data': {'attributes': attributes}})
        ie._extract_m3u8_formats = Mock(return_value=[{
            'format_id': 'hls-720', 'height': 720,
            'url': 'https://media.example/720.m3u8',
        }])
        return ie

    def test_current_player_formats_metadata_and_mirrors(self):
        ie = self.extractor({
            'title': 'نمونهٔ ویدیو', 'duration': '42',
            'file_link_all': [None, {
                'profile': '360p',
                'urls': ['https://media.example/video.mp4',
                         'https://mirror.example/video.mp4',
                         'https://media.example/video.mp4', 'javascript:alert(1)'],
            }],
            'hls': {'link': 'https://media.example/master.m3u8'},
        })
        result = ie._real_extract('https://www.aparat.com/v/abc123?playlist=1')
        self.assertEqual(result['id'], 'abc123')
        self.assertEqual(result['title'], 'نمونهٔ ویدیو')
        self.assertEqual(result['duration'], 42)
        self.assertEqual([f['format_id'] for f in result['formats']],
                         ['http-360-1-0', 'http-360-1-1', 'hls-720'])
        self.assertEqual(result['formats'][0]['height'], 360)
        self.assertEqual(result['http_headers']['Referer'],
                         'https://www.aparat.com/v/abc123')
        self.assertFalse(ie._extract_m3u8_formats.call_args.kwargs['fatal'])

    def test_single_source_without_quality_or_hls(self):
        ie = self.extractor({'file_link_all': [{
            'profile': '', 'urls': ['https://media.example/video.mp4'],
        }]})
        result = ie._real_extract('https://aparat.com/v/abc123')
        self.assertEqual(len(result['formats']), 1)
        self.assertEqual(result['formats'][0]['format_id'], 'http-source-0-0')
        self.assertIsNone(result['formats'][0]['height'])
        ie._extract_m3u8_formats.assert_not_called()

    def test_unavailable_and_password_protected_videos(self):
        for attributes in ({}, {'deleted': 'yes'}, {'video_pass': 'required'},
                           {'title': 'No playable sources'}):
            with self.subTest(attributes=attributes):
                ie = self.extractor(attributes)
                with self.assertRaises(ExtractorError) as error:
                    ie._real_extract('https://aparat.com/v/abc123')
                self.assertTrue(error.exception.expected)

    def test_watch_mobile_and_embed_urls(self):
        for url in ('https://www.aparat.com/v/abc123',
                    'https://m.aparat.com/v/abc123',
                    'https://www.aparat.com/video/video/embed/videohash/abc123',
                    'https://www.aparat.com/video/video/embed/vt/frame/showvideo/yes/videohash/abc123'):
            self.assertEqual(module.AparatVidoraIE._match_id(url), 'abc123')
        self.assertFalse(module.AparatVidoraIE.suitable('https://evil.example/v/abc123'))


if __name__ == '__main__':
    unittest.main()

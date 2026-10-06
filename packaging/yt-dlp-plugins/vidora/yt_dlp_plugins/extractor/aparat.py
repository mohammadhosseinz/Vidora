"""Read Aparat's current public player API instead of its retired embed page."""
import re

from yt_dlp.extractor.common import InfoExtractor
from yt_dlp.utils import ExtractorError, int_or_none, url_or_none


class AparatVidoraIE(InfoExtractor):
    _VALID_URL = (
        r'https?://(?:(?:www|m)\.)?aparat\.com/'
        r'(?:v/|video/video/embed/(?:[^/?#]+/)*videohash/)(?P<id>[a-zA-Z0-9]+)'
    )

    def _real_extract(self, url):
        video_id = self._match_id(url)
        response = self._download_json(
            f'https://www.aparat.com/api/fa/v1/video/video/show/videohash/{video_id}',
            video_id, 'Downloading player metadata')
        video = (response.get('data') or {}).get('attributes') or {}
        if not video or video.get('deleted') in (True, 'yes'):
            raise ExtractorError('Video unavailable', expected=True)
        if video.get('video_pass'):
            raise ExtractorError('This video is protected by a password', expected=True)

        formats, seen = [], set()
        for index, source in enumerate(video.get('file_link_all') or []):
            if not isinstance(source, dict):
                continue
            profile = str(source.get('profile') or '')
            match = re.search(r'(\d+)', profile)
            height = int_or_none(match.group(1)) if match else None
            for mirror, media_url in enumerate(source.get('urls') or []):
                media_url = url_or_none(media_url)
                if not media_url or media_url in seen:
                    continue
                seen.add(media_url)
                formats.append({
                    'url': media_url,
                    'ext': 'mp4',
                    'format_id': f'http-{height or "source"}-{index}-{mirror}',
                    'height': height,
                })

        hls = video.get('hls') or {}
        hls_url = url_or_none(video.get('hls_link') or hls.get('link'))
        if hls_url:
            formats.extend(self._extract_m3u8_formats(
                hls_url, video_id, 'mp4', entry_protocol='m3u8_native',
                m3u8_id='hls', fatal=False))
        if not formats:
            raise ExtractorError('Video unavailable: no playable formats', expected=True)
        return {
            'id': video_id,
            'title': video.get('title') or video_id,
            'description': video.get('description'),
            'thumbnail': url_or_none(video.get('big_poster')),
            'duration': int_or_none(video.get('duration')),
            'uploader': video.get('owner_username'),
            'formats': formats,
            'http_headers': {'Referer': f'https://www.aparat.com/v/{video_id}'},
        }

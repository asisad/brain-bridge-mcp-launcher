"""Verify offline help assets and fixed destinations without opening a browser."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parents[1]
help_dir = root / 'scripts' / 'help'


class Guide(HTMLParser):
    def __init__(self):
        super().__init__()
        self.images = []
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        assert tag not in {'script', 'iframe', 'form'}, tag
        assert not any(name.startswith('on') for name in attrs), attrs
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        if tag == 'img':
            assert attrs.get('alt'), 'Image requires meaningful alt text'
            self.images.append(attrs['src'])
        if tag == 'a':
            self.links.append(attrs['href'])


guide = Guide()
guide.feed((help_dir / 'index.fa.html').read_text(encoding='utf-8'))
assert len(guide.images) == 3
for image in guide.images:
    assert not urlparse(image).scheme, 'Images must be bundled offline'
    path = (help_dir / image).resolve()
    assert path.is_relative_to(help_dir.resolve()) and path.is_file()
    assert path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
for link in guide.links:
    if link.startswith('#'):
        assert link[1:] in guide.ids
    elif urlparse(link).scheme:
        url = urlparse(link)
        assert url.scheme == 'https' and url.hostname in {'github.com', 'platform.openai.com'}
        assert not url.query and not url.username and not url.password
    else:
        assert (help_dir / link).is_file()
required = {
    'https://github.com/openai/tunnel-client/releases/latest',
    'https://platform.openai.com/settings/organization/tunnels',
    'https://platform.openai.com/settings/organization/api-keys',
}
assert required <= set(guide.links)
helper = (root / 'scripts' / 'BrainBridge.Help.ps1').read_text(encoding='utf-8-sig')
assert all(url in helper for url in required)
assert (help_dir / 'LICENSE-openai-tunnel-client.txt').is_file()
assert (help_dir / 'NOTICE-openai-tunnel-client.txt').is_file()
print('PASS: offline guide, 3 PNG images, attribution, anchors and official link destinations')

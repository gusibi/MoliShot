import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location('package_update', Path(__file__).parents[1] / 'package-update.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class UpdateReleaseTests(unittest.TestCase):
    def test_feed_distinguishes_build_from_display_version_and_keeps_signature(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'MoliShot-v0.8.0.zip'
            archive.write_bytes(b'archive')
            info = {'CFBundleVersion': '16', 'CFBundleShortVersionString': '0.8.0', 'LSMinimumSystemVersion': '14.0'}
            tree = release.build_feed(info, archive, 'signature', 'https://example.org/release', 'https://example.org/update.zip?a=1&b=2')
            item = ET.fromstring(ET.tostring(tree.getroot())).find('channel/item')
            self.assertEqual(item.find(f'{{{release.SPARKLE}}}version').text, '16')
            self.assertEqual(item.find(f'{{{release.SPARKLE}}}shortVersionString').text, '0.8.0')
            self.assertEqual(item.find(f'{{{release.SPARKLE}}}minimumSystemVersion').text, '14.0')
            enclosure = item.find('enclosure')
            self.assertEqual(enclosure.attrib['url'], 'https://example.org/update.zip?a=1&b=2')
            self.assertEqual(enclosure.attrib['length'], '7')
            self.assertEqual(enclosure.attrib[f'{{{release.SPARKLE}}}edSignature'], 'signature')

    def test_rejects_misconfigured_apps_before_signing_or_packaging(self):
        valid = {
            'CFBundleIdentifier': 'com.molishot.app', 'SUPublicEDKey': release.PUBLIC_KEY,
            'SUFeedURL': release.FEED_URL, 'SURequireSignedFeed': True,
            'SUVerifyUpdateBeforeExtraction': True,
        }
        cases = [
            {'CFBundleIdentifier': 'com.example.other'},
            {'SUPublicEDKey': 'different key'},
            {'SUFeedURL': 'http://example.org/untrusted.xml'},
            {'SURequireSignedFeed': False},
            {'SUVerifyUpdateBeforeExtraction': False},
        ]
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'MoliShot.app'
            (app / 'Contents').mkdir(parents=True)
            for changes in cases:
                with self.subTest(changes=changes):
                    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(valid | changes))
                    output = Path(directory) / 'output'
                    with self.assertRaises(ValueError):
                        release.package(app, output, Path('/missing/tools'), Path('/missing/key'))
                    self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()

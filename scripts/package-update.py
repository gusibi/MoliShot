#!/usr/bin/env python3
"""Package a signed app and produce a signed Sparkle feed for GitHub Releases."""
import argparse
import base64
import os
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
FEED_URL = 'https://github.com/gusibi/MoliShot/releases/latest/download/appcast.xml'
PUBLIC_KEY = 'ml8yLk6ziYWICBIyy/74S8pO0aeFDxMQu+3COfHUp28='
ET.register_namespace('sparkle', SPARKLE)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def build_feed(info, archive, signature, release_url, download_url):
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'MoliShot Updates'
    ET.SubElement(channel, 'link').text = 'https://github.com/gusibi/MoliShot/releases'
    ET.SubElement(channel, 'description').text = 'MoliShot updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'MoliShot ' + info['CFBundleShortVersionString']
    ET.SubElement(item, 'link').text = release_url
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = info['CFBundleVersion']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = info['CFBundleShortVersionString']
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
    ET.SubElement(item, 'enclosure', {
        'url': download_url, 'length': str(archive.stat().st_size),
        'type': 'application/octet-stream', f'{{{SPARKLE}}}edSignature': signature,
    })
    return ET.ElementTree(rss)


def package(app, output, tools, key):
    app = app.resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.molishot.app':
        raise ValueError('Unexpected bundle identifier')
    if info.get('SUPublicEDKey') != PUBLIC_KEY or info.get('SUFeedURL') != FEED_URL:
        raise ValueError('App updater configuration does not match the release feed')
    if not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction'):
        raise ValueError('Update verification must be enabled')
    requirement = ('identifier "com.molishot.app" and certificate leaf = H"' +
                   (ROOT / 'Resources/update-signing-certificate.sha1').read_text().strip() + '"')
    run('codesign', '--verify', '--deep', '--strict', '-R', '=' + requirement, str(app))
    version = info['CFBundleShortVersionString']
    if not all(part.isdigit() for part in version.split('.')) or not info['CFBundleVersion'].isdigit():
        raise ValueError('Release version and build must be numeric')
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f'MoliShot-v{version}.zip'
    if archive.exists() or (output / 'appcast.xml').exists():
        raise ValueError('Output already contains an update; use a fresh directory')
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
    sign = str(tools / 'sign_update')
    signature = run(sign, '--ed-key-file', str(key), '-p', str(archive),
                    capture_output=True, text=True).stdout.strip()
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Invalid archive signature')
    # Validate with the PUBLIC key embedded in the app, independent of the signer.
    sdk = os.environ.get('SDKROOT') or run('xcrun', '--sdk', 'macosx', '--show-sdk-path', capture_output=True, text=True).stdout.strip()
    run('swift', '-sdk', sdk,
        str(ROOT / 'scripts/verify-update.swift'), str(archive), PUBLIC_KEY, signature)
    release_url = f'https://github.com/gusibi/MoliShot/releases/tag/v{version}'
    download_url = f'https://github.com/gusibi/MoliShot/releases/download/v{version}/{archive.name}'
    feed = output / 'appcast.xml'
    build_feed(info, archive, signature, release_url, download_url).write(feed, encoding='utf-8', xml_declaration=True)
    run(sign, '--ed-key-file', str(key), str(feed), stdout=subprocess.DEVNULL)
    run(sign, '--verify', '--ed-key-file', str(key), str(feed), stdout=subprocess.DEVNULL)
    print(f'Created update archive and signed feed in {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sparkle-tools', type=Path, required=True, help='Sparkle bin directory')
    parser.add_argument('--key', type=Path, default=Path.home() / 'Library/Application Support/MoliShotSigning/sparkle-private-key.txt')
    args = parser.parse_args()
    package(args.app, args.output.resolve(), args.sparkle_tools.resolve(), args.key)

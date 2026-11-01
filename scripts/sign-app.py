#!/usr/bin/env python3
"""Sign nested code inside out, using a temporary keychain and a pinned identity."""
import argparse
from pathlib import Path
import secrets
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        # security arguments contain passwords: never include them in tracebacks.
        raise RuntimeError(f'{args[0]} failed (exit {result.returncode})')
    return result


def sign_app(app, signing_dir):
    app = app.resolve()
    if app.suffix != '.app' or not (app / 'Contents/Info.plist').is_file():
        raise ValueError('Expected an application bundle')
    expected = (ROOT / 'Resources/update-signing-certificate.sha1').read_text().strip()
    # The P12 is imported only into an isolated, short-lived keychain.
    with tempfile.TemporaryDirectory(prefix='molishot-signing-') as directory:
        keychain = str(Path(directory) / 'release.keychain-db')
        password = secrets.token_urlsafe(32)
        run('security', 'create-keychain', '-p', password, keychain, stdout=subprocess.DEVNULL)
        try:
            run('security', 'unlock-keychain', '-p', password, keychain)
            run('security', 'import', str(signing_dir / 'code-signing.p12'), '-k', keychain,
                '-P', (signing_dir / 'p12-password.txt').read_text().strip(),
                '-T', '/usr/bin/codesign', stdout=subprocess.DEVNULL)
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
                '-s', '-k', password, keychain, stdout=subprocess.DEVNULL)
            identities = run('security', 'find-identity', '-p', 'codesigning', keychain,
                             capture_output=True, text=True).stdout
            if expected not in identities:
                raise ValueError('P12 does not match the pinned release signing identity')
            common = ['codesign', '--force', '--sign', expected, '--keychain', keychain,
                      '--timestamp=none', '--preserve-metadata=identifier,entitlements']
            # Do not use --deep for signing: each nested executable gets a signature.
            targets = []
            magic = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
                     b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                     b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
            for path in app.rglob('*'):
                if path.is_symlink():
                    continue
                if path.is_dir() and path.suffix in ('.app', '.framework', '.xpc'):
                    targets.append(path)
                elif path.is_file():
                    with path.open('rb') as file:
                        if file.read(4) in magic:
                            targets.append(path)
            for target in sorted(targets, key=lambda p: len(p.parts), reverse=True):
                run(*common, str(target), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # Pin the signer, not the cdhash or a forgeable certificate display name.
            requirement = f'designated => identifier "com.molishot.app" and certificate leaf = H"{expected}"'
            run(*common, '--identifier', 'com.molishot.app', '--requirements', '=' + requirement,
                '--entitlements', str(ROOT / 'Resources/MoliShot.entitlements'), str(app))
            run('codesign', '--verify', '--deep', '--strict', str(app))
            run('codesign', '--verify', '-R', '=' + requirement.removeprefix('designated => '), str(app))
        finally:
            run('security', 'delete-keychain', keychain, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--signing-dir', type=Path,
                        default=Path.home() / 'Library/Application Support/MoliShotSigning')
    args = parser.parse_args()
    sign_app(args.app, args.signing_dir)

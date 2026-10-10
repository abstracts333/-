"""Validate prepared localization resources and create a player installer ZIP."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'package'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    manifest = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))
    for entry in manifest['files']:
        path = (PACKAGE / entry['payload']).resolve()
        if not path.is_relative_to(PACKAGE.resolve()):
            raise ValueError('Payload path outside package')
        if sha(path) != entry['payloadHash']:
            raise ValueError('Payload checksum mismatch: ' + entry['payload'])
    paths = sorted(p for p in PACKAGE.rglob('*') if p.is_file() and p.name != 'SHA256SUMS.txt')
    (PACKAGE / 'SHA256SUMS.txt').write_text(''.join(sha(p) + '  ' + p.relative_to(PACKAGE).as_posix() + '\n' for p in paths), encoding='utf-8')
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    name = 'SpaceRangersHD-SimplifiedChinese-' + manifest['version']
    output = dist / ('SpaceRangersHD-SimplifiedChinese-v' + manifest['version'] + '.zip')
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(PACKAGE.rglob('*')):
            if path.is_file():
                archive.write(path, name + '/' + path.relative_to(PACKAGE).as_posix())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP verification failed')
        for path in PACKAGE.rglob('*'):
            if path.is_file() and archive.read(name + '/' + path.relative_to(PACKAGE).as_posix()) != path.read_bytes():
                raise ValueError('Archived content mismatch')
    checksum = sha(output)
    output.with_suffix('.zip.sha256').write_text(checksum + '  ' + output.name + '\n', encoding='utf-8')
    print(f'{output.name}: {output.stat().st_size / 1024 / 1024:.2f} MiB')
    print('SHA256: ' + checksum)

if __name__ == '__main__':
    main()

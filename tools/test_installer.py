"""Test installer on temporary copies of a legally owned clean game."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'package'
MANIFEST = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clean-game', type=Path, required=True)
    parser.add_argument('--temp-root', type=Path, default=Path(tempfile.gettempdir()))
    args = parser.parse_args()
    source = args.clean_game.resolve()
    for entry in MANIFEST['validation']:
        assert sha(source / entry['path']) == entry['hash'], 'Incompatible clean game: ' + entry['path']
    for entry in MANIFEST['files']:
        assert sha(source / entry['path']) == entry['before'], 'Incompatible clean game: ' + entry['path']
    temp_root = args.temp_root.resolve()
    temp_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='srhd-zh-installer-tests-', dir=temp_root) as directory:
        temp = Path(directory).resolve()
        assert temp.parent == temp_root, 'Unexpected cleanup location'
        def fixture(name):
            game = temp / name
            game.mkdir()
            for entry in MANIFEST['files'] + MANIFEST['validation']:
                if entry.get('before', 'validation') is None:
                    continue
                dest = game / entry['path']
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / entry['path'], dest)
            (game / 'Mods/ModCFG.txt').write_bytes(b'CurrentMod=Tweaks\\German, Tweaks\\SR2PQuestStyle\r\nOther=keep\r\n')
            (game / 'save-sentinel.txt').write_text('preserve save', encoding='utf-8')
            return game
        def run(game, mode, expect=0, package=PACKAGE):
            result = subprocess.run(['powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(package / 'Installer.ps1'), '-Mode', mode, '-GamePath', str(game), '-NonInteractive'], capture_output=True)
            assert result.returncode == expect, result.stdout.decode('utf-8', errors='replace') + result.stderr.decode('utf-8', errors='replace')
        def snapshot(game):
            return {e['path']: sha(game / e['path']) for e in MANIFEST['files']}
        game = fixture('中文 游戏目录')
        run(game, 'Verify');run(game, 'Install')
        assert snapshot(game) == {e['path']: e['after'] for e in MANIFEST['files']}
        state = json.loads((game / '.srhd-zh-backup/installation.json').read_bytes())
        run(game, 'Install')
        second = json.loads((game / '.srhd-zh-backup/installation.json').read_bytes())
        assert state['files'] == second['files'] and state['created'] == second['created']
        run(game, 'Uninstall')
        assert snapshot(game) == {e['path']: e['before'] for e in MANIFEST['files']}
        assert (game / 'Mods/ModCFG.txt').read_bytes() == b'CurrentMod=Tweaks\\German, Tweaks\\SR2PQuestStyle\r\nOther=keep\r\n'
        assert (game / 'save-sentinel.txt').read_text() == 'preserve save'
        print('PASS installation hashes, repeated install, uninstall, saves and Unicode directory')
        game = fixture('changed-selection');run(game, 'Install')
        (game / 'Mods/ModCFG.txt').write_bytes('CurrentMod=Tweaks\\Chinese, Tweaks\\SR2LoadingScreen\r\nOther=keep\r\n'.encode('utf-16'))
        run(game, 'Uninstall')
        assert (game / 'Mods/ModCFG.txt').read_bytes().decode('utf-16') == 'CurrentMod=Tweaks\\SR2LoadingScreen\r\nOther=keep\r\n'
        print('PASS changed selection and UTF-16 encoding')
        game = fixture('changed-before-reinstall');run(game, 'Install')
        (game / 'Mods/ModCFG.txt').write_bytes(b'CurrentMod=Tweaks\\SR2LoadingScreen\r\nOther=keep\r\n')
        run(game, 'Install');run(game, 'Uninstall')
        assert (game / 'Mods/ModCFG.txt').read_bytes() == b'CurrentMod=Tweaks\\SR2LoadingScreen\r\nOther=keep\r\n'
        game = fixture('missing-config');(game / 'Mods/ModCFG.txt').unlink();run(game, 'Install');run(game, 'Uninstall')
        assert not (game / 'Mods/ModCFG.txt').exists()
        print('PASS selection changes before reinstall and originally missing configuration')
        game = fixture('wrong-version');(game / 'Rangers.exe').write_bytes(b'incompatible')
        before = snapshot(game);run(game, 'Install', 1);assert snapshot(game) == before
        game = fixture('game-update');run(game, 'Install');(game / 'Rangers.exe').write_bytes(b'new version')
        before = snapshot(game);run(game, 'Uninstall', 1);assert snapshot(game) == before
        print('PASS unknown game versions and game updates reject without writes')
        game = fixture('corrupt-package');bad = temp / 'bad-package';shutil.copytree(PACKAGE, bad)
        (bad / MANIFEST['files'][-1]['payload']).write_bytes(b'corrupt')
        before = snapshot(game);run(game, 'Install', 1, bad);assert snapshot(game) == before
        game = fixture('corrupt-backup');run(game, 'Install')
        state = json.loads((game / '.srhd-zh-backup/installation.json').read_bytes())
        (game / '.srhd-zh-backup' / state['files'][0]['backup']).write_bytes(b'corrupt')
        before = snapshot(game);run(game, 'Uninstall', 1);assert snapshot(game) == before
        print('PASS corrupt payloads and backups reject without writes')
        game = fixture('write-failure');before = snapshot(game)
        def literal(path):
            return "'" + str(path).replace("'", "''") + "'"
        command = '$locked=[IO.File]::Open(' + literal(game / 'steam_ach.dll') + ',[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); try { & ' + literal(PACKAGE / 'Installer.ps1') + ' -Mode Install -GamePath ' + literal(game) + ' -NonInteractive; $result=$LASTEXITCODE } finally {$locked.Dispose()}; exit $result'
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], capture_output=True)
        assert result.returncode == 1 and snapshot(game) == before
        assert not (game / '.srhd-zh-backup/installation.json').exists()
        print('PASS partial installation failure rolls back the executable')
    print('All tests passed; original game directory unmodified.')

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""One-time pre-release bundle migration. Run with both app identities stopped.
Copies only Volant-owned data, never container metadata, symlinks or Keychain secrets.
The old container stays intact. Existing destination data is never overwritten.
"""
import argparse
import json
import plistlib
import shutil
from pathlib import Path

OLD = 'com.mysticcoders.vey'
NEW = 'com.mysticcoders.volant'

def migrate(library):
    source = library / 'Containers' / OLD / 'Data' / 'Library'
    target = library / 'Containers' / NEW / 'Data' / 'Library'
    marker = target / 'volant-identity-migration.json'
    if marker.exists():
        print('Bundle data already migrated; leaving it untouched.')
        return
    support = source / 'Application Support' / 'Vey'
    prefs = source / 'Preferences' / (OLD + '.plist')
    if not support.exists() and not prefs.exists():
        print('No legacy data to migrate.')
        return
    destination = target / 'Application Support' / 'Vey'
    preferences = target / 'Preferences' / (NEW + '.plist')
    if destination.exists() or preferences.exists():
        raise RuntimeError('Destination data already exists; refusing to overwrite. Review both containers manually.')
    # Refuse symlinks anywhere in app-owned data; do not follow outside the source.
    if support.is_symlink() or prefs.is_symlink() or any(p.is_symlink() for p in support.rglob('*')):
        raise RuntimeError('Legacy app data contains symlinks; manual migration required.')
    rewritten = None
    if prefs.exists():
        values = plistlib.loads(prefs.read_bytes())
        old_notes = 'notes.' + str(source / 'Application Support' / 'Vey' / 'Notes')
        new_notes = 'notes.' + str(target / 'Application Support' / 'Vey' / 'Notes')
        rewritten = plistlib.dumps({(new_notes + k[len(old_notes):] if k.startswith(old_notes + '.') else k): v for k, v in values.items()})
    if support.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(support, destination)
    if rewritten is not None:
        preferences.parent.mkdir(parents=True, exist_ok=True)
        preferences.write_bytes(rewritten)
        preferences.chmod(0o600)
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(json.dumps({'source': OLD, 'destination': NEW, 'original_preserved': True}) + '\n')
    print('Copied app data and preferences; original container preserved.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, default=Path.home() / 'Library')
    args = parser.parse_args()
    import subprocess
    for name in ['Volant', 'Vey']:
        status = subprocess.run(['pgrep', '-x', name], stdout=subprocess.DEVNULL).returncode
        if status == 0:
            parser.error('Quit Volant/Vey before migration.')
        if status != 1:
            parser.error('Could not verify that the app is stopped; migration cancelled.')
    migrate(args.library)

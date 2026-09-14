#!/usr/bin/env python3
import sys
sys.dont_write_bytecode = True
import importlib.util
import plistlib
import tempfile
from pathlib import Path
spec = importlib.util.spec_from_file_location('migration', Path(__file__).with_name('migrate-bundle-data.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as directory:
    library = Path(directory) / 'Library'
    old = library / 'Containers' / m.OLD / 'Data' / 'Library'
    new = library / 'Containers' / m.NEW / 'Data' / 'Library'
    support = old / 'Application Support' / 'Vey'
    (support / 'Notes').mkdir(parents=True)
    (support / 'Notes' / 'fixture.md').write_text('Fictional note')
    (support / 'clipboard.sqlite').write_bytes(b'opaque encrypted fixture')
    prefs = old / 'Preferences' / (m.OLD + '.plist')
    prefs.parent.mkdir()
    prefs.write_bytes(plistlib.dumps({'notes.' + str(support / 'Notes') + '.pinned': ['fixture.md'], 'unrelated': 42}))
    m.migrate(library)
    assert (new / 'Application Support/Vey/clipboard.sqlite').read_bytes() == (support / 'clipboard.sqlite').read_bytes()
    migrated = plistlib.loads((new / 'Preferences' / (m.NEW + '.plist')).read_bytes())
    assert migrated['notes.' + str(new / 'Application Support/Vey/Notes') + '.pinned'] == ['fixture.md']
    assert migrated['unrelated'] == 42 and prefs.exists()
    (new / 'Application Support/Vey/Notes/fixture.md').write_text('New edit')
    m.migrate(library)
    assert (new / 'Application Support/Vey/Notes/fixture.md').read_text() == 'New edit'
    (new / 'volant-identity-migration.json').unlink()
    try:
        m.migrate(library)
        raise AssertionError('Must reject existing destination')
    except RuntimeError:
        pass
print('PASS: opaque data copy, preference remapping, original preservation, repeat run, overwrite refusal')

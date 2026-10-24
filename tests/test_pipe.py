"""End-to-end JSONL protocol test; only generated fixtures are used."""
import json
import argparse
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import threading
import time
import uuid
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('app', nargs='?')
parser.add_argument('--audio', action='store_true')
options = parser.parse_args()
APP = Path(options.app) if options.app else Path(json.loads((ROOT / 'build/latest.json').read_text(encoding='utf-8-sig'))['AppRoot'])
CASE = ROOT / 'test-output' / ('pipe-' + uuid.uuid4().hex[:8])
CASE.mkdir(parents=True)

class Client:
    def __init__(self, app, flags=()):
        self.process = subprocess.Popen([str(app / 'QitesXmlLoader.exe'), '--pipe', *flags], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', bufsize=1)
        self.events = queue.Queue()
        self.errors = []
        self.counter = 0
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=lambda: self.errors.extend(self.process.stderr.readlines()), daemon=True).start()
        assert self.next()['type'] == 'ready'

    def read(self):
        for line in self.process.stdout:
            try:
                self.events.put(json.loads(line))
            except Exception as error:
                self.events.put({'type': 'invalid_json', 'raw': line, 'error': str(error)})

    def next(self):
        try:
            event = self.events.get(timeout=20)
        except queue.Empty:
            raise AssertionError(f'Pipe timed out; exit={self.process.poll()}, stderr={self.errors}')
        assert event['type'] != 'invalid_json', event
        return event

    def send(self, command, args=None):
        self.counter += 1
        request = {'id': self.counter, 'command': command, 'args': args or {}}
        self.process.stdin.write(json.dumps(request, ensure_ascii=False) + '\n')
        self.process.stdin.flush()
        return self.counter

    def wait(self, request_id, kind='result'):
        while True:
            event = self.next()
            if event.get('id') == request_id and event['type'] == kind:
                return event['data']

    def call(self, command, args=None, ok=True):
        response = self.wait(self.send(command, args))
        assert response['ok'] is ok, response
        return response.get('value', response)

    def close(self):
        self.call('shutdown')
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0, self.errors
        assert not self.errors, self.errors

folder = CASE / 'music'
(folder / 'nested').mkdir(parents=True)
shutil.copyfile(APP / 'startup.wav', folder / '01 日本語.wav')
shutil.copyfile(APP / 'startup.wav', folder / '02.wav')
shutil.copyfile(APP / 'startup.wav', folder / 'nested' / 'ignored.wav')
client = Client(APP)
assert len(client.call('sources')) == 2
assert len(client.call('formats')) == 10
client.call('not-a-command', ok=False)
client.call('configure', {'SourceLoader': 'single-folder', 'CacheDirectory': str(CASE / 'cache')})
loaded = client.call('load', {'path': str(folder)})
assert loaded['state'] == 'Complete'
lists = client.call('lists')
assert len(lists) == 1 and lists[0]['tracks'] == 2
tracks = client.call('tracks', {'playlistId': lists[0]['id']})
assert tracks['total'] == 2 and '日本語' in tracks['items'][0]['Title']
assert client.call('select', {'all': True})['selected'] == 2
if options.audio:
    assert client.call('devices')
    client.call('audio.play', {'mode': 'random-loop'})
    deadline = time.monotonic() + 10
    while client.call('status')['audioPosition'] < 0.05:
        assert time.monotonic() < deadline
        time.sleep(0.05)
    client.call('audio.pause')
    client.call('audio.seek', {'seconds': 0.5})
    client.call('audio.resume')
    client.call('audio.stop')
    client.call('audio.test')
    client.call('audio.stop')
result = client.call('export', {'destination': str(CASE / 'export'), 'mode': 'Copy', 'target': 'Retone'})
output = Path(result['output'])
assert (output / 'Music' / 'selection.m3u8').is_file()
assert len(list(output.rglob('*.wav'))) == 2
with next(output.rglob('*.wav')).open('rb'):
    client.call('rollback', ok=False)
    assert output.exists()
client.call('rollback')
assert not output.exists()
client.call('configure', {'SourceLoader': 'itunes', 'ResolveLibraryNames': True})
assert client.call('select')['selected'] == 0
actual = folder / '01 日本語.wav'
old = CASE / 'old' / actual.name
good = folder / '02.wav'
xml = CASE / 'fixture.xml'
xml.write_text(f'''<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Tracks</key><dict>
<key>1</key><dict><key>Name</key><string>Moved</string><key>Location</key><string>{escape(old.as_uri())}</string><key>Total Time</key><integer>2000</integer></dict>
<key>2</key><dict><key>Name</key><string>Candidate outside playlists</string><key>Location</key><string>{escape(actual.as_uri())}</string></dict>
<key>3</key><dict><key>Name</key><string>Good</string><key>Location</key><string>{escape(good.as_uri())}</string></dict>
</dict><key>Playlists</key><array><dict><key>Name</key><string>Synthetic</string><key>Playlist Persistent ID</key><string>1111111111111111</string><key>Playlist Items</key><array><dict><key>Track ID</key><integer>1</integer></dict><dict><key>Track ID</key><integer>3</integer></dict></array></dict></array></dict></plist>''', encoding='utf-8')
loaded = client.call('load', {'path': str(xml)})
assert loaded['fileCheck']['resolved'] == 1 and loaded['fileCheck']['unresolved'] == 0, loaded
deep = CASE / 'deep.xml'
deep.write_text('<plist><dict><key>Tracks</key><dict><key>1</key><dict><key>Nested</key>' + '<array>' * 1000 + '<string>x</string>' + '</array>' * 1000 + '</dict></dict><key>Playlists</key><array/></dict></plist>', encoding='utf-8')
client.call('load', {'path': str(deep)}, ok=False)
assert client.call('load', {'path': str(xml)})['state'] == 'Complete'
client.call('configure', {'ResolveLibraryNames': False})
checked = client.call('check')
assert checked['fileCheck']['missing'] == 1
client.call('select', {'all': True})
client.call('export', {'destination': str(CASE / 'stopped')}, ok=False)
assert not (CASE / 'stopped').exists()
client.call('configure', {'MissingPolicy': 'Skip'})
result = client.call('export', {'destination': str(CASE / 'skipped')})
assert len(list(Path(result['output']).rglob('*.wav'))) == 1
assert client.call('issues')['total'] == 1
client.call('rollback')
client.close()
for flag, allowed in [('--ignore-errors', False), ('--approve-errors', True)]:
    policy_client = Client(APP, (flag,))
    configuration = policy_client.call('configure')
    assert configuration['MissingPolicy'] == 'Skip'
    assert configuration['ResolveLibraryNames'] is allowed
    assert configuration['AllowNetworkPaths'] is allowed
    policy_client.close()

# A private test adapter supplies a deterministic long operation. It is never packaged.
test_host = CASE / 'control-host'
shutil.copytree(APP, test_host)
(test_host / 'loaders' / 'delay.json').write_text(json.dumps({'Id': 'delay', 'Names': {'ja': 'Test', 'en': 'Test'}, 'Input': 'folder', 'Script': 'Delay.ps1'}), encoding='utf-8')
(test_host / 'loaders' / 'Delay.ps1').write_text('''param([string]$Path,[QitesXmlLoader.Operation]$Operation)
$Operation.MakeDirectory($Path);$Operation.WriteText((Join-Path $Path 'owned.txt'),'test')
for($i=0;$i -lt 150;$i++){$Operation.Report('Test operation',$i,150,'');$Operation.Check();Start-Sleep -Milliseconds 20}
[pscustomobject]@{Kind='Library';Library=@{Tracks=@{};Playlists=@()}}
''', encoding='utf-8-sig')
client = Client(test_host)
client.call('configure', {'SourceLoader': 'delay', 'CacheDirectory': str(CASE / 'control-cache')})
owned = CASE / 'owned'
load_id = client.send('load', {'path': str(owned)})
client.wait(load_id, 'accepted')
client.call('pause')
deadline = time.monotonic() + 10
while not client.call('status')['paused']:
    assert time.monotonic() < deadline
    time.sleep(0.05)
client.call('resume')
client.call('pause')
client.call('cancel', {'mode': 'rollback'})
cancelled = client.wait(load_id)
assert cancelled['state'] == 'Cancelled', cancelled
assert not owned.exists()
client.close()
(CASE / 'result.json').write_text(json.dumps({'Passed': True, 'SyntheticOnly': True, 'Output': str(CASE)}, indent=2), encoding='utf-8')
print((CASE / 'result.json').read_text(encoding='utf-8'))

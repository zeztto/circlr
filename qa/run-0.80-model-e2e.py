#!/usr/bin/env python3
"""One-turn external Codex -> pinned circlr MCP QA against an already-open QA app.

The caller creates/signs/opens a unique QA app and a disposable .circlr copy first.
This script never launches an app or changes the user's Codex login or audio defaults.
Run prepare, model, verify exactly once, in that order. Evidence stays Git-ignored.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import wave


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_new(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def installed_kit_state(project):
    """Verify every installed managed file against the installer's saved hashes."""
    state_path = project / '.codex/circlr-agent-kit.json'
    require(state_path.is_file() and not state_path.is_symlink(),
            'Installed Codex kit state missing or unsafe')
    state = json.loads(state_path.read_text())
    files = state.get('files')
    require(state.get('schema') == 'circlr-agent-install-v1' and
            isinstance(files, dict) and files, 'Installed Codex kit state invalid')
    for name, expected in files.items():
        relative = Path(name)
        require(not relative.is_absolute() and '..' not in relative.parts and
                isinstance(expected, str) and len(expected) == 64,
                'Installed Codex kit path/hash invalid')
        candidate = project
        for part in relative.parts:
            candidate /= part
            require(not candidate.is_symlink(), 'Installed Codex kit contains a symlink')
        require(candidate.is_file() and digest(candidate) == expected,
                'Installed Codex kit file changed: ' + name)
    return digest(state_path), files


def claim_model_once(plan, fixture, evidence, marker_root=None):
    """Fail closed if any evidence folder already used this QA fixture/project."""
    root = marker_root or Path(__file__).resolve().parent / 'generated'
    require(root.is_dir(), 'QA generated evidence root missing')
    key = hashlib.sha256(json.dumps(
        [str(fixture.resolve()), plan['projectID']],
        ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    marker = root / ('.r80-model-once-' + key + '.json')
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW
    try:
        fd = os.open(marker, flags, 0o600)
    except FileExistsError as error:
        raise RuntimeError('This QA fixture/project already started a model turn; inspect it, never retry') from error
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump({'schema': 'circlr-r80-model-once-v1', 'runID': plan['runID'],
                   'projectID': plan['projectID'], 'fixture': str(fixture),
                   'evidence': str(evidence), 'time': time.time()}, stream,
                  ensure_ascii=False)
        stream.write('\n')
    return marker


class MCP:
    def __init__(self, adapter, fake_home):
        env = os.environ.copy()
        env.pop('CIRCLR_SOCKET', None)
        env['HOME'] = str(fake_home)
        self.child = subprocess.Popen([sys.executable, str(adapter)], stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                      text=True, bufsize=1, env=env)
        self.reader = selectors.DefaultSelector()
        self.reader.register(self.child.stdout, selectors.EVENT_READ)
        self.sequence = 0
        self.message('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {},
                                    'clientInfo': {'name': 'circlr-r80-model-qa', 'version': '1'}})
        self.message('notifications/initialized', notification=True)

    def message(self, method, params=None, notification=False):
        self.sequence += 1
        packet = {'jsonrpc': '2.0', 'method': method}
        if not notification:
            packet['id'] = self.sequence
        if params is not None:
            packet['params'] = params
        self.child.stdin.write(json.dumps(packet, ensure_ascii=False) + '\n')
        self.child.stdin.flush()
        if notification:
            return None
        require(self.reader.select(timeout=30), f'MCP timeout: {method}')
        line = self.child.stdout.readline()
        require(line, f'MCP closed: {method}')
        response = json.loads(line)
        require('error' not in response, f'MCP protocol error: {method}: {response.get("error")}')
        return response['result']

    def call(self, name, arguments=None):
        response = self.message('tools/call', {'name': 'circlr_' + name,
                                               'arguments': arguments or {}})
        packet = response.get('structuredContent') or json.loads(response['content'][0]['text'])
        require(not response.get('isError') and packet.get('ok'),
                f'MCP {name} failed: {packet.get("error", "unknown")}')
        return packet['result']

    def wait_job(self, job, seconds=180):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            status = self.call('job', {'jobID': job['jobID']})['job']
            if status['state'] != 'running':
                require(status['state'] == 'completed', f'Job failed: {status}')
                return status
            time.sleep(0.5)
        raise TimeoutError('Job did not finish')

    def close(self):
        self.reader.close()
        self.child.stdin.close()
        try:
            self.child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.child.terminate()
            self.child.wait(timeout=5)


def paths(options, creating=False):
    # The model subprocess has a private HOME. The QA root still belongs under
    # the logged-in user's real Application Support, independent of that HOME.
    support = (Path(pwd.getpwuid(os.getuid()).pw_dir) /
               'Library/Application Support').resolve()
    qa = options.qa_root.expanduser().resolve(strict=True)
    require(qa.parent == support and qa.name.startswith('circlr-') and qa.name.endswith('-qa'),
            'Only a dedicated circlr-*-qa Application Support root is allowed')
    require(options.bundle_id.startswith('com.circlr.') and options.bundle_id.endswith('qa'),
            'Only a unique com.circlr.*qa bundle ID is allowed')
    fixture = options.project.expanduser().resolve(strict=True)
    require(fixture.is_relative_to(qa / 'fixtures') and fixture.suffix == '.circlr'
            and (fixture / 'manifest.json').is_file(), 'Project must be a QA fixture .circlr')
    app = options.app.expanduser().resolve(strict=True)
    require(app.suffix == '.app' and app != (Path.cwd() / 'dist/써클러.app').resolve(),
            'Pass only the separately signed QA app')
    info = app / 'Contents/Info.plist'
    require(info.is_file(), 'QA app Info.plist missing')
    import plistlib
    plist = plistlib.loads(info.read_bytes())
    require(plist.get('CFBundleIdentifier') == options.bundle_id and
            str(plist.get('CFBundleVersion')) == options.build, 'QA app bundle/build mismatch')
    signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               check=False)
    require(signature.returncode == 0, 'QA app strict deep signature failed')
    adapter = app / 'Contents/Resources/Codex/skills/circlr-studio/scripts/mcp_server.py'
    installer = app / 'Contents/Resources/Codex/install.py'
    require(adapter.is_file() and installer.is_file(), 'QA app Codex kit missing')
    agent = qa / 'Agent'
    manifest = agent / 'selected.json'
    info = os.lstat(manifest)
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and
            stat.S_IMODE(info.st_mode) == 0o600, 'Unsafe QA endpoint manifest')
    endpoint = json.loads(manifest.read_text())
    require(endpoint.get('bundleID') == options.bundle_id and endpoint.get('runID') and
            endpoint.get('schema') == 'circlr-agent-endpoint-v1', 'Wrong selected QA endpoint')
    socket = agent / endpoint['endpoint']
    socket_info = os.lstat(socket)
    require(stat.S_ISSOCK(socket_info.st_mode) and socket_info.st_uid == os.getuid(),
            'Selected QA endpoint is not a same-user socket')
    evidence = options.evidence.expanduser().resolve()
    generated = Path(__file__).resolve().parent / 'generated'
    relative_parts = evidence.relative_to(generated).parts if evidence.is_relative_to(generated) else ()
    require(bool(relative_parts) and relative_parts[0].startswith('r80-model-'),
            'Evidence must be a new ignored qa/generated/r80-model-* path')
    if creating:
        evidence.mkdir(mode=0o700, parents=True, exist_ok=False)
    else:
        require(evidence.is_dir(), 'Evidence directory missing; run prepare first')
    return qa, fixture, app, adapter, installer, endpoint, socket_info, evidence


def fake_home(evidence, agent, creating=False):
    pointer = evidence / 'fake-home-path.json'
    if creating:
        home = Path(tempfile.mkdtemp(prefix='cq80.', dir='/tmp'))
        save_new(pointer, {'path': str(home)})
    else:
        home = Path(json.loads(pointer.read_text())['path'])
    require(home.parent == Path('/tmp') and home.name.startswith('cq80.'),
            'Unexpected MCP child HOME')
    link = home / 'Library/Application Support/circlr/Agent'
    if creating:
        link.parent.mkdir(mode=0o700, parents=True)
        link.symlink_to(agent, target_is_directory=True)
    require(link.is_symlink() and link.resolve() == agent.resolve(), 'QA Agent symlink changed')
    require(stat.S_IMODE(home.stat().st_mode) == 0o700, 'MCP child HOME must be private')
    require(len(os.fsencode(str(link / 'agent.sock'))) < 104,
            'MCP child socket path exceeds conservative AF_UNIX limit')
    return home


def pinned_state(client, options, endpoint, socket_info, fixture):
    state = client.call('snapshot')
    runtime = state.get('runtime', {})
    require(runtime.get('bundleID') == options.bundle_id and
            runtime.get('build') == options.build and
            runtime.get('runID') == endpoint['runID'], 'MCP target app/runtime mismatch')
    require(state.get('path') == str(fixture) and not state.get('dirty'),
            'QA fixture must already be open and saved')
    require(state.get('job') is None or state['job'].get('state') != 'running',
            'QA app has an active job')
    return state


def lanes(section):
    return {item['id']: item for item in section['lanes']}


def prepare(options):
    qa, fixture, app, adapter, installer, endpoint, socket_info, evidence = paths(options, creating=True)
    home = fake_home(evidence, qa / 'Agent', creating=True)
    client_dir = evidence / 'client'
    client_dir.mkdir(mode=0o700)
    subprocess.run([sys.executable, str(installer), '--project', str(client_dir),
                    '--python', sys.executable], check=True, stdout=subprocess.DEVNULL)
    install_state_sha, managed_files = installed_kit_state(client_dir)
    client = MCP(client_dir / '.agents/skills/circlr-studio/scripts/mcp_server.py', home)
    try:
        state = pinned_state(client, options, endpoint, socket_info, fixture)
        context = client.call('context')
        require(context['project']['id'] == state['projectID'] and
                context['project']['revision'] == state['revision'], 'Bounded context mismatch')
        arrangement = state['activeArrangementID']
        use = next(item['id'] for item in next(x for x in state['arrangements']
                                               if x['id'] == arrangement)['uses'])
        section = client.call('inspect', {'arrangementID': arrangement, 'useID': use})
        midi = next((lane for lane in section['lanes'] if isinstance(lane.get('notes'), list)), None)
        require(midi is not None, 'No MIDI lane in first use; select a different QA fixture')
        notes = midi['notes']
        pitch = int(notes[0]['pitch']) if notes else 72
        step = next((i for i in range(16) if not any(n['beat'] == i / 4 and n['pitch'] == pitch
                                                    for n in notes)), None)
        require(step is not None, 'No empty test step in first four beats')
        operation = {'kind': 'set_step', 'arrangementID': arrangement, 'useID': use,
                     'laneID': midi['id'], 'stepIndex': step, 'pitch': pitch,
                     'enabled': True, 'subdivisions': 4, 'velocity': 80, 'gate': 1}
        baseline_events = client.call('events', {'afterSequence': 0})['sequence']
        plan = {'schema': 'circlr-r80-model-e2e-plan-v1', 'build': options.build,
                'bundleID': options.bundle_id, 'runID': endpoint['runID'],
                'socketIdentity': [socket_info.st_dev, socket_info.st_ino, socket_info.st_uid],
                'qaMainSHA256': digest(app / 'Contents/MacOS/circlr'),
                'kitManifestSHA256': digest(app / 'Contents/Resources/Codex/manifest.json'),
                'project': str(fixture), 'projectID': state['projectID'],
                'revision': state['revision'], 'layoutRevision': state['layoutRevision'],
                'manifestSHA256': digest(fixture / 'manifest.json'), 'operation': operation,
                'baselineEventSequence': baseline_events,
                'adapterSHA256': digest(client_dir / '.agents/skills/circlr-studio/scripts/mcp_server.py'),
                'installStateSHA256': install_state_sha, 'installedManagedFiles': managed_files}
        save_new(evidence / 'plan.json', plan)
        save_new(evidence / 'before-inspect.json', section)
        save_new(evidence / 'before-context.json', context)
        print(json.dumps({'status': 'PREPARED', 'evidence': str(evidence),
                          'projectID': state['projectID'], 'revision': state['revision'],
                          'operation': operation}, ensure_ascii=False))
    finally:
        client.close()


def checked_client(options):
    qa, fixture, app, adapter, installer, endpoint, socket_info, evidence = paths(options)
    plan = json.loads((evidence / 'plan.json').read_text())
    require(plan['build'] == options.build and plan['bundleID'] == options.bundle_id and
            plan['project'] == str(fixture), 'Prepared QA candidate differs from requested candidate')
    require(digest(app / 'Contents/MacOS/circlr') == plan['qaMainSHA256'] and
            digest(app / 'Contents/Resources/Codex/manifest.json') == plan['kitManifestSHA256'],
            'QA app or bundled Codex kit changed after prepare')
    require([socket_info.st_dev, socket_info.st_ino, socket_info.st_uid] == plan['socketIdentity']
            and endpoint['runID'] == plan['runID'], 'QA endpoint changed after prepare')
    home = fake_home(evidence, qa / 'Agent')
    installed = evidence / 'client/.agents/skills/circlr-studio/scripts/mcp_server.py'
    require('installStateSHA256' in plan and 'installedManagedFiles' in plan,
            'Prepared plan predates managed kit verification; inspect evidence without rerunning model')
    install_state_sha, managed_files = installed_kit_state(evidence / 'client')
    require(install_state_sha == plan['installStateSHA256'] and
            managed_files == plan['installedManagedFiles'],
            'Installed Codex kit changed after prepare')
    require(digest(installed) == plan['adapterSHA256'] and digest(adapter) == plan['adapterSHA256'],
            'Bundled/installed MCP adapter changed')
    return fixture, evidence, plan, home, installed


def ensure_baseline(client, options, fixture, plan):
    state = client.call('snapshot')
    require(state['runtime']['bundleID'] == options.bundle_id and
            state['runtime']['build'] == options.build and
            state['runtime']['runID'] == plan['runID'] and state['path'] == str(fixture) and
            state['projectID'] == plan['projectID'] and state['revision'] == plan['revision'] and
            not state['dirty'] and digest(fixture / 'manifest.json') == plan['manifestSHA256'],
            'Project changed after prepare')
    require(state['layoutRevision'] == plan['layoutRevision'], 'Project layout changed after prepare')
    return state


class ModelCallGate:
    """Expose only one planned apply after successful, ordered QA reads."""

    def __init__(self, plan, forward, check_write_target):
        self.plan = plan
        self.forward = forward
        self.check_write_target = check_write_target
        self.context_read = False
        self.inspect_read = False
        self.write_attempted = False

    def __call__(self, path, name, arguments, read_only=False):
        if name not in {'circlr_context', 'circlr_inspect', 'circlr_apply'}:
            raise ValueError('QA gateway exposes only context, inspect and one apply')
        if self.write_attempted:
            raise ValueError('QA model write was already attempted; no further tools are allowed')
        if name == 'circlr_context':
            if self.context_read or arguments:
                raise ValueError('QA context must be read once without arguments')
        elif name == 'circlr_inspect':
            expected = {key: self.plan['operation'][key] for key in ('arrangementID', 'useID')}
            if not self.context_read or self.inspect_read or arguments != expected:
                raise ValueError('QA inspect must follow context and use the planned section')
        else:
            expected = {'projectID': self.plan['projectID'],
                        'expectedRevision': self.plan['revision'],
                        'operations': [self.plan['operation']]}
            # Claim before checking or forwarding. An uncertain write is never retried.
            self.write_attempted = True
            if not self.context_read or not self.inspect_read or arguments != expected:
                raise ValueError('QA apply requires completed reads and the exact planned edit')
            self.check_write_target()
        result = self.forward(path, name, arguments, read_only=read_only)
        packet = result.get('structuredContent') or {}
        if result.get('isError') or packet.get('ok') is not True:
            raise ValueError('QA MCP ' + name + ' did not succeed')
        detail = packet.get('result') or {}
        if name == 'circlr_context':
            project = detail.get('project') or {}
            runtime = detail.get('runtime') or {}
            if (project.get('id'), project.get('revision'), runtime.get('build')) != (
                    self.plan['projectID'], self.plan['revision'], self.plan['build']):
                raise ValueError('QA context target differs from the planned project/build')
            self.context_read = True
        elif name == 'circlr_inspect':
            if (detail.get('projectID'), detail.get('revision'),
                    (detail.get('use') or {}).get('id')) != (
                    self.plan['projectID'], self.plan['revision'],
                    self.plan['operation']['useID']):
                raise ValueError('QA inspect target differs from the planned project/use')
            self.inspect_read = True
        return result


def gateway(options):
    """Trusted stdio MCP guard around the app-bundled adapter for one model turn."""
    fixture, evidence, plan, home, installed = checked_client(options)
    spec = importlib.util.spec_from_file_location('circlr_qa_bundled_mcp', installed)
    require(spec and spec.loader, 'Bundled MCP adapter cannot be loaded')
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    resolver = adapter.EndpointResolver(home / 'Library/Application Support/circlr/Agent/agent.sock')

    def check_write_target():
        try:
            current_fixture, _, current_plan, _, current_installed = checked_client(options)
            require(current_fixture == fixture and current_plan == plan and
                    current_installed == installed, 'QA candidate changed before write')
            _, run_id, identity = resolver.resolve()
            require(run_id == plan['runID'] and list(identity) == plan['socketIdentity'],
                    'Pinned QA app socket/run changed before write')
            response = adapter.rpc(resolver, {'id': 'circlr-r80-gateway-prewrite',
                                              'method': 'snapshot', 'arguments': {}})
            require(response.get('ok') is True, 'QA app snapshot failed before write')
            state = response['result']
            runtime = state.get('runtime') or {}
            require((runtime.get('bundleID'), runtime.get('build'), runtime.get('runID')) ==
                    (plan['bundleID'], plan['build'], plan['runID']) and
                    state.get('path') == str(fixture) and
                    state.get('projectID') == plan['projectID'] and
                    state.get('revision') == plan['revision'] and
                    state.get('layoutRevision') == plan['layoutRevision'] and
                    not state.get('dirty') and
                    digest(fixture / 'manifest.json') == plan['manifestSHA256'],
                    'QA app/project changed immediately before write')
        except (OSError, KeyError, RuntimeError, ValueError) as error:
            raise ValueError('target_changed: QA prewrite guard rejected the write; do not retry this fixture') from error

    adapter.TOOLS = [tool for tool in adapter.TOOLS if tool['name'] in
                     {'circlr_context', 'circlr_inspect', 'circlr_apply'}]
    original = adapter.call_tool
    adapter.call_tool = ModelCallGate(plan, original, check_write_target)
    adapter.serve(resolver)


def restricted_codex_environment(home):
    """Keep account auth available while omitting inherited API keys and sockets."""
    codex = shutil.which('codex')
    node = shutil.which('node')
    require(codex and node, 'Codex CLI and Node.js are required')
    real_home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    codex_home = Path(os.environ.get('CODEX_HOME') or real_home / '.codex').resolve(strict=True)
    require(codex_home.is_dir() and codex_home.stat().st_uid == os.getuid(),
            'Codex account home is not a same-user directory')
    scratch = home / 'tmp'
    scratch.mkdir(mode=0o700, exist_ok=True)
    account = pwd.getpwuid(os.getuid()).pw_name
    env = {'HOME': str(home), 'CODEX_HOME': str(codex_home),
           'PATH': str(Path(node).parent) + ':/usr/bin:/bin:/usr/sbin:/sbin',
           'TMPDIR': str(scratch), 'LANG': os.environ.get('LANG', 'en_US.UTF-8'),
           'SHELL': '/bin/zsh', 'USER': account, 'LOGNAME': account}
    if 'LC_ALL' in os.environ:
        env['LC_ALL'] = os.environ['LC_ALL']
    return codex, env


def model(options):
    fixture, evidence, plan, home, installed = checked_client(options)
    client = MCP(installed, home)
    try:
        ensure_baseline(client, options, fixture, plan)
        section = client.call('inspect', {'arrangementID': plan['operation']['arrangementID'],
                                          'useID': plan['operation']['useID']})
        require(section == json.loads((evidence / 'before-inspect.json').read_text()),
                'Target inspect changed after prepare')
    finally:
        client.close()
    codex, env = restricted_codex_environment(home)
    # The marker is exclusive. A failed/uncertain model write must be inspected, never rerun.
    claim_model_once(plan, fixture, evidence)
    save_new(evidence / 'model-started.json', {'status': 'STARTED_ONCE', 'time': time.time()})
    op = plan['operation']
    prompt = ("$circlr-studio를 사용하세요. 지금 열린 QA 프로젝트에 한 번만 MIDI step을 쓰는 검증입니다. "
              "먼저 circlr_context와 대상 circlr_inspect를 읽고 projectID/revision/lane을 확인하세요. "
              "그다음 circlr_apply를 정확히 한 번 호출하세요. 다른 MCP write, shell write, 저장, 다른 곡 열기, "
              "장치 변경, 재생, 녹음은 금지합니다. 실패·승인 거절·target_changed이면 재시도 없이 중단하세요. "
              f"대상 projectID={plan['projectID']}, revision={plan['revision']}; "
              f"apply operations=[{json.dumps(op, ensure_ascii=False)}]. "
              "결과는 확인한 사실과 미확인 항목을 분리해 간단히 보고하세요.")
    (evidence / 'prompt.txt').write_text(prompt + '\n')
    gateway_args = [str(Path(__file__).resolve()), 'gateway', '--qa-root',
                    str(options.qa_root.expanduser().resolve()), '--project',
                    str(fixture), '--app', str(options.app.expanduser().resolve()),
                    '--bundle-id', options.bundle_id,
                    '--build', options.build, '--evidence', str(evidence)]
    config = ('mcp_servers.circlr={command=' + json.dumps(sys.executable) +
              ',args=' + json.dumps(gateway_args) + '}')
    command = [codex, 'exec', '--json', '--ephemeral', '--ignore-user-config',
               '--sandbox', 'read-only', '-C', str(evidence / 'client'),
               '-c', config, '-']
    with (evidence / 'model.jsonl').open('x') as stdout, (evidence / 'model.stderr.log').open('x') as stderr:
        try:
            result = subprocess.run(command, input=prompt, text=True, stdout=stdout,
                                    stderr=stderr, timeout=480, check=False, env=env)
            save_new(evidence / 'model-exit.json', {'exitCode': result.returncode,
                                                      'traceSHA256': digest(evidence / 'model.jsonl')})
            require(result.returncode == 0, 'Model turn failed; inspect state and do not retry this fixture')
        except subprocess.TimeoutExpired:
            save_new(evidence / 'model-exit.json', {'timeout': True,
                                                      'traceSHA256': digest(evidence / 'model.jsonl')})
            raise RuntimeError('Model turn timed out; inspect state and do not retry this fixture')
    print(json.dumps({'status': 'MODEL_TURN_ENDED', 'trace': str(evidence / 'model.jsonl')}))


def model_trace(evidence, plan):
    require((evidence / 'model-exit.json').is_file(), 'Model turn has not completed')
    exit_info = json.loads((evidence / 'model-exit.json').read_text())
    require(exit_info.get('exitCode') == 0 and digest(evidence / 'model.jsonl') == exit_info['traceSHA256'],
            'Model turn was unsuccessful or trace changed')
    # Inspect every lifecycle event, not only completed calls: a failed or pending
    # write can still have reached the app and must never be treated as absent.
    read_tools = {'circlr_context', 'circlr_snapshot', 'circlr_inspect', 'circlr_ports',
                  'circlr_sounds', 'circlr_events', 'circlr_job'}
    reference_command = ('/bin/zsh -lc "sed -n \'1,240p\' '
                         '.agents/skills/circlr-studio/references/session-contract.md && '
                         'sed -n \'1,300p\' '
                         '.agents/skills/circlr-studio/references/circlr-operations.md"')
    pending = {}
    completed = []
    write_starts = []
    command_starts = []
    read_done = {}
    turn_completed = 0
    for number, line in enumerate((evidence / 'model.jsonl').read_text().splitlines(), 1):
        event = json.loads(line)
        event_type = event.get('type')
        require(event_type not in {'turn.failed', 'turn.cancelled'},
                f'Model turn did not complete normally at line {number}')
        if event_type == 'turn.completed':
            require(not pending, 'Model turn completed with unfinished tools')
            turn_completed += 1
        item = event.get('item') or {}
        item_type = item.get('type')
        if item_type == 'file_change':
            raise RuntimeError(f'Model attempted a file change at line {number}')
        if item_type not in {'mcp_tool_call', 'command_execution'}:
            continue
        require(turn_completed == 0, f'Tool event after completed model turn at line {number}')
        require(event_type in {'item.started', 'item.updated', 'item.completed'},
                f'Unexpected tool event at line {number}')
        item_id = item.get('id')
        require(isinstance(item_id, str) and item_id,
                f'Tool event lacks an item ID at line {number}')
        identity = (item_type, item.get('server'), item.get('tool'),
                    item.get('arguments')) if item_type == 'mcp_tool_call' else (
                    item_type, item.get('command'))
        if item_type == 'mcp_tool_call':
            require(item.get('server') == 'circlr',
                    f'Model called an unexpected MCP server at line {number}')
            tool = item.get('tool')
            require(tool in read_tools or tool == 'circlr_apply',
                    f'Model attempted an unexpected MCP write at line {number}')
        else:
            require(item.get('command') == reference_command,
                    f'Model ran an unexpected shell command at line {number}')
        if event_type == 'item.started':
            require(item_id not in pending and all(done['id'] != item_id for done in completed),
                    f'Duplicate tool invocation at line {number}')
            pending[item_id] = identity
            if item_type == 'mcp_tool_call' and item.get('tool') == 'circlr_apply':
                write_starts.append(number)
                require(len(write_starts) == 1 and
                        read_done.get('circlr_context', 0) < number and
                        read_done.get('circlr_inspect', 0) < number and
                        read_done.get('circlr_context', 0) <
                        read_done.get('circlr_inspect', 0),
                        'Expected one write only after completed context and target inspect')
            if item_type == 'command_execution':
                command_starts.append(number)
                require(len(command_starts) == 1,
                        'Expected at most one bundled-reference shell read')
            continue
        require(item_id in pending and pending[item_id] == identity,
                f'Tool lifecycle changed or lacked a start at line {number}')
        if event_type == 'item.updated':
            continue
        require(item.get('status') == 'completed',
                f'Tool did not finish successfully at line {number}')
        if item_type == 'mcp_tool_call':
            require(item.get('error') is None,
                    f'MCP tool returned an error at line {number}')
            if item.get('tool') in {'circlr_context', 'circlr_inspect'}:
                packet = item.get('result', {}).get('structured_content', {})
                require(packet.get('ok') is True,
                        f'Model read failed at line {number}')
                detail = packet.get('result', {})
                if item['tool'] == 'circlr_context':
                    require(detail.get('project', {}).get('id') == plan['projectID'] and
                            detail['project'].get('revision') == plan['revision'],
                            'Model context came from a different project/revision')
                else:
                    require(detail.get('projectID') == plan['projectID'] and
                            detail.get('revision') == plan['revision'] and
                            detail.get('use', {}).get('id') == plan['operation']['useID'],
                            'Model inspect came from a different project/revision/use')
                read_done[item['tool']] = number
        else:
            require(item.get('exit_code') == 0,
                    f'Bundled-reference read failed at line {number}')
        completed.append(item)
        del pending[item_id]
    require(turn_completed == 1 and not pending,
            'Model turn or tool lifecycle is incomplete')
    calls = [item for item in completed if item['type'] == 'mcp_tool_call']
    names = [item['tool'] for item in calls]
    writes = [item for item in calls if item['tool'] not in read_tools]
    require(len(write_starts) == 1 and len(writes) == 1 and
            writes[0]['tool'] == 'circlr_apply',
            'Expected exactly one started and completed model MCP write')
    require(names.count('circlr_context') == 1 and names.count('circlr_inspect') == 1 and
            names.index('circlr_context') < names.index('circlr_inspect') <
            names.index('circlr_apply'),
            'Model did not read bounded context and target before write')
    require(next(item for item in calls if item['tool'] == 'circlr_inspect')['arguments'] ==
            {'arrangementID': plan['operation']['arrangementID'],
             'useID': plan['operation']['useID']}, 'Model inspected a different target')
    args = writes[0].get('arguments', {})
    require(args == {'projectID': plan['projectID'], 'expectedRevision': plan['revision'],
                     'operations': [plan['operation']]}, 'Model applied a different operation')
    result = writes[0].get('result', {}).get('structured_content', {})
    require(result.get('ok') is True and result.get('result', {}).get('revision') == plan['revision'] + 1,
            'Model MCP apply did not succeed')
    return names


def verify(options):
    fixture, evidence, plan, home, installed = checked_client(options)
    names = model_trace(evidence, plan)
    op = plan['operation']
    before = json.loads((evidence / 'before-inspect.json').read_text())
    client = MCP(installed, home)
    try:
        state = client.call('snapshot')
        require(state['runtime']['runID'] == plan['runID'] and state['projectID'] == plan['projectID']
                and state['path'] == str(fixture) and state['revision'] == plan['revision'] + 1,
                'App state does not reflect one model write')
        after = client.call('inspect', {'arrangementID': op['arrangementID'], 'useID': op['useID']})
        previous = lanes(before)
        changed = lanes(after)
        require(previous.keys() == changed.keys(), 'Lane set changed')
        for lane_id in previous:
            if lane_id != op['laneID']:
                require(previous[lane_id] == changed[lane_id], 'Non-target lane changed')
        baseline = previous[op['laneID']]
        edited = changed[op['laneID']]
        require({k: v for k, v in baseline.items() if k != 'notes'} ==
                {k: v for k, v in edited.items() if k != 'notes'}, 'Target lane metadata changed')
        old_by_id = {note['id']: note for note in baseline['notes']}
        new_by_id = {note['id']: note for note in edited['notes']}
        require(all(new_by_id.get(key) == note for key, note in old_by_id.items()) and
                len(new_by_id) == len(old_by_id) + 1, 'Existing notes changed or extra note count wrong')
        added = next(note for key, note in new_by_id.items() if key not in old_by_id)
        require(added['beat'] == op['stepIndex'] / op['subdivisions'] and
                added['pitch'] == op['pitch'] and added['velocity'] == op['velocity'],
                'Model note differs from planned note')
        model_events = client.call('events', {'afterSequence': plan['baselineEventSequence']})
        require(any('실행 · apply' in event.get('message', '') for event in model_events['events']),
                'App activity does not show the model apply')
        save_new(evidence / 'model-edit-inspect.json', after)
        save_new(evidence / 'model-activity.json', model_events)
        undone = client.call('undo', {'projectID': plan['projectID'],
                                      'expectedRevision': state['revision'],
                                      'expectedLayoutRevision': state['layoutRevision']})
        restored = client.call('inspect', {'arrangementID': op['arrangementID'], 'useID': op['useID']})
        require(lanes(restored) == previous and undone['revision'] == plan['revision'] + 2,
                'Undo did not exactly restore MIDI lanes')
        reapplied = client.call('apply', {'projectID': plan['projectID'],
                                          'expectedRevision': undone['revision'],
                                          'operations': [op]})
        final_edit = client.call('inspect', {'arrangementID': op['arrangementID'], 'useID': op['useID']})
        require(len(lanes(final_edit)[op['laneID']]['notes']) == len(baseline['notes']) + 1,
                'QA reapply failed')
        saved = client.call('save', {'projectID': plan['projectID'],
                                     'expectedRevision': reapplied['revision']})
        require(not saved['dirty'] and digest(fixture / 'manifest.json') != plan['manifestSHA256'],
                'Save did not persist edit')
        saved_hash = digest(fixture / 'manifest.json')
        job = client.call('open', {'projectID': plan['projectID'],
                                   'expectedRevision': saved['revision'], 'path': str(fixture)})
        client.wait_job(job, seconds=60)
        reopened = client.call('snapshot')
        reopened_inspect = client.call('inspect', {'arrangementID': op['arrangementID'],
                                                   'useID': op['useID']})
        require(reopened['projectID'] == plan['projectID'] and
                reopened['revision'] == saved['revision'] and not reopened['dirty'] and
                digest(fixture / 'manifest.json') == saved_hash and
                lanes(reopened_inspect) == lanes(final_edit), 'Reopen lost the MIDI edit')
        export = fixture.parent / (fixture.stem + '-r80-model-qa.wav')
        require(not export.exists(), 'QA export already exists; do not overwrite')
        job = client.call('export', {'projectID': plan['projectID'],
                                     'expectedRevision': reopened['revision'], 'path': str(export)})
        client.wait_job(job)
        require(export.is_file(), 'Export job completed without WAV')
        with wave.open(str(export), 'rb') as wav:
            audio = {'channels': wav.getnchannels(), 'sampleRate': wav.getframerate(),
                     'bitsPerSample': wav.getsampwidth() * 8, 'frames': wav.getnframes()}
            nonzero = False
            while frame := wav.readframes(8192):
                nonzero |= any(frame)
        require(audio['channels'] == 2 and audio['sampleRate'] == 48000 and
                audio['bitsPerSample'] == 24 and audio['frames'] > 48000 and nonzero,
                'Exported WAV format/PCM invalid')
        report = {'schema': 'circlr-r80-model-e2e-result-v1', 'status': 'AUTOMATED_PASS',
                  'modelWork': 'one observed MCP apply; QA runtime and fixture matched before and after', 'independentQA':
                  'note diff, Undo, QA reapply, save, reopen, nonzero WAV',
                  'modelToolSequence': names, 'projectID': plan['projectID'],
                  'revisions': [plan['revision'], state['revision'], undone['revision'],
                                reapplied['revision']], 'addedNote': added,
                  'savedManifestSHA256': saved_hash, 'wavSHA256': digest(export),
                  'wavFormat': audio, 'modelTraceSHA256': digest(evidence / 'model.jsonl'),
                  'consolePixelOrAX': 'PENDING independent native UI check'}
        save_new(evidence / 'report.json', report)
        print(json.dumps(report, ensure_ascii=False))
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('prepare', 'model', 'verify', 'gateway'))
    parser.add_argument('--qa-root', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--bundle-id', required=True)
    parser.add_argument('--build', required=True,
                        help='CFBundleVersion of the signed final QA candidate')
    parser.add_argument('--evidence', type=Path, required=True)
    options = parser.parse_args()
    {'prepare': prepare, 'model': model, 'verify': verify, 'gateway': gateway}[options.phase](options)


if __name__ == '__main__':
    require(sys.version_info >= (3, 11), 'Python 3.11+ required for bundled Codex installer')
    main()

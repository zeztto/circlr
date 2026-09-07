#!/usr/bin/env python3
"""Install the bundled circlr skill and agents in one project. Python 3.11+."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import tomllib

STATE = Path('.codex/circlr-agent-kit.json')
CONFIG = Path('.codex/config.toml')
SKILL = Path('.agents/skills/circlr-studio')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, relative):
    rel = Path(relative)
    if rel.is_absolute() or '..' in rel.parts or not rel.parts:
        raise ValueError('Invalid installation path: ' + str(relative))
    path = root
    for part in rel.parts:
        path /= part
        if path.is_symlink():
            raise ValueError('Refusing symlink in installation path: ' + str(path))
    return path


def managed_path(relative):
    p = Path(relative)
    return (p == CONFIG or p.is_relative_to(SKILL) or
            (p.parent == Path('.codex/agents') and p.name.startswith('circlr-') and p.suffix == '.toml'))


def load_kit(kit):
    manifest = json.loads((kit / 'manifest.json').read_text())
    if manifest.get('schema') != 'circlr-agent-kit-v1':
        raise ValueError('Unsupported kit manifest')
    for name, sha in manifest['files'].items():
        source = safe_path(kit, name)
        if not source.is_file() or digest(source.read_bytes()) != sha:
            raise ValueError('Kit integrity mismatch: ' + name)
    return manifest


def replace_file(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.circlr-install-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def _install(kit, project, python, dry_run=False):
    kit = kit.resolve(strict=True)
    project = project.resolve(strict=True)
    if not project.is_dir():
        raise ValueError('Project must be an existing directory')
    python = str(Path(python).resolve(strict=True))
    if not os.access(python, os.X_OK):
        raise ValueError('Python must be executable')
    manifest = load_kit(kit)
    state_path = safe_path(project, STATE)
    state = json.loads(state_path.read_text()) if state_path.exists() else None
    previous = state.get('files', {}) if state else {}
    if state and state.get('schema') != 'circlr-agent-install-v1':
        raise ValueError('Unknown installation state')
    for name, sha in previous.items():
        if not managed_path(name):
            raise ValueError('Unexpected managed path: ' + name)
        p = safe_path(project, name)
        if not p.is_file() or digest(p.read_bytes()) != sha:
            raise ValueError('Locally modified or missing file; no files changed: ' + str(p))
    desired = {}
    for name in manifest['files']:
        rel = Path(name)
        if rel.is_relative_to(Path('skills/circlr-studio')):
            desired[str(SKILL / rel.relative_to('skills/circlr-studio'))] = (kit / rel).read_bytes()
    skill_path = str(project / SKILL)
    mcp_path = str(project / SKILL / 'scripts/mcp_server.py')
    agents = []
    for name in manifest['files']:
        rel = Path(name)
        if rel.parent != Path('agents') or rel.suffix != '.toml':
            continue
        data = tomllib.loads((kit / rel).read_text())
        instructions = data['developer_instructions'].replace('__SKILL_PATH__', skill_path)
        # Serialize all substituted values as TOML strings, including spaces and quotes.
        rendered = '\n'.join([
            'name = ' + json.dumps(data['name']),
            'description = ' + json.dumps(data['description']),
            'sandbox_mode = "read-only"',
            'developer_instructions = ' + json.dumps(instructions, ensure_ascii=False),
            '', '[mcp_servers.circlr]',
            'command = ' + json.dumps(python),
            'args = ' + json.dumps([mcp_path, '--read-only']), '',
        ]).encode()
        tomllib.loads(rendered.decode())
        desired[str(Path('.codex/agents') / rel.name)] = rendered
        agents.append(data['name'])
    if not agents or not desired:
        raise ValueError('Empty kit')
    config_path = safe_path(project, CONFIG)
    existing = config_path.read_bytes() if config_path.exists() else b''
    config = tomllib.loads(existing.decode())
    connection = {'command': python, 'args': [mcp_path]}
    configured = config.get('mcp_servers', {}).get('circlr')
    if configured is not None and configured != connection:
        raise ValueError('Existing mcp_servers.circlr differs; no files changed: ' + str(config_path))
    if configured is None:
        block = '\n# Managed circlr music-agent connection. User model and concurrency are inherited.\n[mcp_servers.circlr]\ncommand = ' + json.dumps(python) + '\nargs = ' + json.dumps([mcp_path]) + '\n'
        desired[str(CONFIG)] = existing + block.encode()
    else:
        desired[str(CONFIG)] = existing
    tomllib.loads(desired[str(CONFIG)].decode())
    for name, data in desired.items():
        p = safe_path(project, name)
        if p.exists() and name not in previous and (not p.is_file() or p.read_bytes() != data):
            # A user's existing config can be extended only on first install, after parsing.
            if name != str(CONFIG) or configured is not None:
                raise ValueError('Unmanaged file conflict; no files changed: ' + str(p))
    new_state = {'schema': 'circlr-agent-install-v1', 'version': manifest['version'],
                 'files': {name: digest(data) for name, data in sorted(desired.items())}}
    desired[str(STATE)] = (json.dumps(new_state, indent=2) + '\n').encode()
    deleted = set(previous) - set(desired)
    changed = {name: data for name, data in desired.items()
               if not safe_path(project, name).is_file() or safe_path(project, name).read_bytes() != data}
    result = {'schema': 'circlr-agent-install-result-v1', 'version': manifest['version'],
              'project': str(project), 'dryRun': dry_run, 'changedFiles': sorted(changed),
              'removedFiles': sorted(deleted), 'agents': sorted(agents),
              'skill': str(project / SKILL / 'SKILL.md')}
    if dry_run or not (changed or deleted):
        return result
    backups = {}
    try:
        for name in list(changed) + list(deleted):
            p = safe_path(project, name)
            backups[name] = p.read_bytes() if p.exists() else None
        # Reject edits that happened between planning and lock acquisition.
        for name, sha in previous.items():
            if digest(safe_path(project, name).read_bytes()) != sha:
                raise ValueError('Installation changed while preparing: ' + name)
        for name, data in changed.items():
            replace_file(safe_path(project, name), data)
        for name in deleted:
            safe_path(project, name).unlink()
    except Exception:
        for name, data in backups.items():
            p = safe_path(project, name)
            if data is None:
                p.unlink(missing_ok=True)
            else:
                replace_file(p, data)
        raise
    return result


def install(kit, project, python, dry_run=False):
    project = project.resolve(strict=True)
    if dry_run:
        return _install(kit, project, python, True)
    # Serialize planning as well as writes; never overwrite another installer run.
    lock = safe_path(project, '.circlr-agent-install.lock')
    fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    try:
        return _install(kit, project, python, False)
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True, type=Path, help='Existing project directory; no global configuration is changed.')
    parser.add_argument('--python', default=sys.executable, help='Python interpreter used by the installed stdio MCP.')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(install(Path(__file__).parent, args.project, args.python, args.dry_run), ensure_ascii=False, indent=2))
    except (OSError, ValueError, KeyError) as e:
        parser.exit(1, 'circlr install: ' + str(e) + '\n')


if __name__ == '__main__':
    main()

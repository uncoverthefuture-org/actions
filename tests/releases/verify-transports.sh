#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
# Exercise the action bodies without credentials or cloud calls.
python3 <<'PY'
import json, os, pathlib, re, shlex, subprocess, tempfile
root = pathlib.Path(os.environ['REPO_ROOT'])
app = root / '.github/actions/app'
names = ['ssh-container-deploy', 'doctl-container-deploy', 'aws-ssm-container-deploy']
options = ['deployment_strategy', 'readiness_path', 'release_snapshots', 'rollback_version', 'quadlet_enabled']
dispatch = (app / 'dispatch/action.yml').read_text()
for name in names:
    action = (app / name / 'action.yml').read_text()
    assert 'uses: ./.github/actions/app/common/release-options' in action
    block = dispatch.split('      uses: ./.github/actions/app/' + name + '\n', 1)[1].split('    - name:', 1)[0]
    for option in options:
        assert re.search(r'^  ' + option + ':', action, re.M), (name, option)
        assert re.search(r'^        ' + option + ':', block, re.M), (name, option)

# Wrappers run before script installation; check their path expansion too.
for name in names[:2]:
    action = (app / name / 'action.yml').read_text()
    case = re.search(r'case "\$DEPLOYMENT_ROOT" in.*?esac', action, re.S).group()
    for base, expected in [('~/deployments', '/tmp/release-home/deployments'),
                           ('/home/runner/custom', '/tmp/release-home/custom'),
                           ('/opt/custom deployments', '/opt/custom deployments')]:
        result = subprocess.run(['bash', '-c', case + '\nprintf "%s" "$DEPLOYMENT_ROOT"'],
            env=dict(os.environ, HOME='/tmp/release-home', DEPLOYMENT_ROOT=base),
            check=True, capture_output=True, text=True)
        assert result.stdout == expected, (name, base, result.stdout)

aws = (app / names[2] / 'action.yml').read_text()
body = aws.split('    - name: Deploy container via AWS SSM\n', 1)[1].split('      run: |\n', 1)[1]
body = '\n'.join(line[8:] for line in body.splitlines())
body = body.split('echo "Sending SSM command', 1)[0]
# Read the exact JSON sent to SSM before the action's EXIT trap removes it.
body += '\ncat ssm-commands.json\n'
with tempfile.TemporaryDirectory() as temp:
    temp = pathlib.Path(temp)
    env = dict(os.environ)
    for variable in re.findall(r'\$\{([A-Z_][A-Z0-9_]*)', body):
        env[variable] = ''
    payload = "value with 'quotes' \"double\"\n$(touch should-not-exist); `touch should-not-exist`"
    env.update(S3_URI='s3://bucket/scripts.tgz', GITHUB_SHA='abc123',
               DEPLOYMENT_STRATEGY='blue-green', READINESS_PATH='/health/ready',
               RELEASE_SNAPSHOTS='true', ROLLBACK_VERSION='v1.2.3', QUADLET_ENABLED='false',
               ENV_CONTENT_VAL=payload, REGISTRY_TOKEN_VAL=payload)
    result = subprocess.run(['bash', '-c', body], cwd=temp, env=env, check=True, capture_output=True, text=True)
    commands = json.loads(result.stdout)
    assert commands['executionTimeout'] == ['3600']
    # Execute the actual shell/JSON round trip, stopping before host installation.
    argv = shlex.split(commands['commands'][0])
    assert argv[:2] == ['bash', '-c']
    argv[2] = argv[2].split("echo '================================================================'", 1)[0] + 'env -0'
    remote = subprocess.run(['sh', '-c', shlex.join(argv)],
        cwd=temp, env=dict(os.environ, HOME=str(temp/'remote-home')), check=True, capture_output=True).stdout
    values = dict(item.split(b'=', 1) for item in remote.split(b'\0') if b'=' in item)
    for key in ['DEPLOYMENT_STRATEGY', 'READINESS_PATH', 'RELEASE_SNAPSHOTS', 'ROLLBACK_VERSION', 'QUADLET_ENABLED']:
        assert values[key.encode()].decode() == env[key], key
    assert values[b'ENV_CONTENT'].decode() == payload
    assert values[b'REGISTRY_TOKEN'].decode() == payload
    assert values[b'HOME'].decode() == str(temp/'remote-home')
    assert not (temp/'should-not-exist').exists()

# Validate the actual doctl remote export block after GitHub expression evaluation.
doctl = (app / names[1] / 'action.yml').read_text()
exports = doctl.split("        export DEPLOYMENT_STRATEGY=", 1)[1].split('        # Ports & runtime', 1)[0]
exports = 'export DEPLOYMENT_STRATEGY=' + exports
outputs = {'strategy':'blue-green', 'readiness':'/health/ready', 'enabled':'true', 'rollback':'v1.2.3'}
exports = re.sub(r'\$\{\{ steps.release-options.outputs.(\w+) }}', lambda m: outputs[m[1]], exports)
exports = exports.replace('${{ inputs.quadlet_enabled }}', 'false')
result = subprocess.run(['bash', '-c', exports + '\nenv -0'], check=True, capture_output=True).stdout
values = dict(item.split(b'=', 1) for item in result.split(b'\0') if b'=' in item)
assert values[b'DEPLOYMENT_STRATEGY'] == b'blue-green'
assert values[b'ROLLBACK_VERSION'] == b'v1.2.3'
assert values[b'READINESS_PATH'] == b'/health/ready'
assert values[b'RELEASE_SNAPSHOTS'] == b'true'
assert values[b'QUADLET_ENABLED'] == b'false'
print('Shared input wiring, DigitalOcean exports, and AWS SSM command serialization passed')
PY

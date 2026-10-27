"""Offline bootstrap integration tests. All privileged/network commands are fakes."""
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = '/bin/bash'
REAL_GIT = shutil.which('git')


def isolated_source(source):
    # Host installations must not affect the mocked platform/tool inventory.
    source = source.replace('/usr/share/omarchy', '$HOME/mock-system/omarchy')
    return source.replace('have() { command -v "$1" >/dev/null 2>&1; }',
                          'have() { case "$1" in tldr|lazygit) [[ -x "$MOCK_BIN/$1" ]] ;; '
                          '*) command -v "$1" >/dev/null 2>&1 ;; esac; }')


LIBRARY = isolated_source((ROOT / 'bootstrap.sh').read_text()).rsplit('\nmain "$@"', 1)[0]

MOCK = r'''#!PYTHON
import hashlib, json, os, pathlib, re, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['AUDIT'], 'a') as out:
    out.write(json.dumps([name, args]) + '\n')
home = pathlib.Path(os.environ['HOME'])
bin_dir = pathlib.Path(os.environ['MOCK_BIN'])
if name == 'uname':
    print(os.environ.get('MOCK_OS', 'Darwin') if args == ['-s'] else os.environ.get('MOCK_ARCH', 'arm64'))
elif name == 'id':
    print('1000' if args == ['-u'] else 'tester')
elif name == 'pacman' and args[:1] == ['-Q']:
    sys.exit(0 if os.environ.get('MOCK_OMARCHY') == '1' else 1)
elif name == 'sudo':
    if args == ['-v']:
        assert sys.stdin.isatty(), 'sudo authentication must read the terminal'
    elif args[0] in ('pmset', 'systemsetup', 'rm', 'touch', 'chflags'):
        raise AssertionError('Unexpected inherited macOS setting: ' + str(args))
    else:
        sys.exit(subprocess.call(args))
elif name == 'git':
    if args[:2] == ['init', '-q'] and '.dogfiles-source-' in args[-1]:
        (pathlib.Path(args[-1]) / '.git').mkdir()
        (pathlib.Path(args[-1]) / '.mock-source').touch()
    elif args[0] == '-C' and (pathlib.Path(args[1]) / '.mock-source').exists():
        dest = pathlib.Path(args[1])
        op = args[2:]
        if op[:3] == ['remote', 'add', 'origin']:
            (dest / '.mock-url').write_text(op[3])
        elif op[:1] == ['fetch']:
            if os.environ.get('MOCK_FETCH_FAIL') == '1': sys.exit(1)
            (dest / '.mock-revision').write_text(op[-1])
        elif op == ['rev-parse', 'HEAD']:
            print('0' * 40 if os.environ.get('MOCK_WRONG_REVISION') == '1' else (dest / '.mock-revision').read_text())
        elif 'checkout' in op and (dest / '.mock-url').exists():
            url = (dest / '.mock-url').read_text()
            if 'ohmyzsh' in url:
                (dest / 'tools').mkdir(exist_ok=True)
                (dest / 'tools/install.sh').write_text("""
test "$1" = --unattended && test "$2" = --keep-zshrc || exit 1
test "$BRANCH" = dogfiles-pinned || exit 1
mkdir -p "$ZSH/.git"
cp "${REMOTE#file://}/.mock-revision" "$ZSH/.mock-revision"
touch "$ZSH/.mock-source"
printf 'true\\n' > "$ZSH/oh-my-zsh.sh"
""")
            elif 'nvm-sh' in url:
                (dest / 'nvm.sh').write_text('true\n')
            elif 'alacritty' in url:
                (dest / 'extra').mkdir(exist_ok=True)
                (dest / 'extra/alacritty.info').write_text('mock terminfo')
    elif args[0] == 'clone':
        dest = pathlib.Path(args[-1])
        if 'panacotar/dogfiles' in args[-2]:
            shutil.copytree(os.environ['TEMPLATE'], dest)
            subprocess.check_call([os.environ['REAL_GIT'], 'init', '-q', str(dest)])
            subprocess.check_call([os.environ['REAL_GIT'], '-C', str(dest), 'remote', 'add', 'origin', args[-2]])
        else:
            (dest / '.git').mkdir(parents=True)
    else:
        sys.exit(subprocess.call([os.environ['REAL_GIT']] + args))
elif name == 'brew':
    if args == ['shellenv']:
        print('export PATH="' + str(bin_dir) + ':$PATH"')
    elif args[:1] == ['list']:
        sys.exit(int(os.environ.get('MOCK_BREW_MISSING', '0')))
    elif args[:1] == ['install'] and os.environ.get('MOCK_BREW_FAIL'):
        print('mock package stdout diagnostic')
        print('mock package stderr diagnostic', file=sys.stderr)
        sys.exit(int(os.environ['MOCK_BREW_FAIL']))
elif name == 'xcode-select':
    if args == ['-p']: sys.exit(int(os.environ.get('MOCK_NO_CLT', '0')))
elif name == 'ssh-keygen':
    assert sys.stdin.isatty(), 'key generation must read the terminal'
    dest = pathlib.Path(args[args.index('-f') + 1])
    dest.write_text('private-test-key')
    dest.with_suffix('.pub').write_text('ssh-ed25519 public-test-key\n')
elif name == 'ssh-add':
    loaded = bin_dir / 'agent-loaded'
    if args == ['-l']: sys.exit(int(os.environ.get('MOCK_AGENT_STATUS',
        ('0' if loaded.exists() else '1') if os.environ.get('SSH_AUTH_SOCK') else '2')))
    if args[:1] == ['-T']: sys.exit(0 if loaded.exists() else 1)
    assert sys.stdin.isatty(), 'ssh-add must read the terminal'
    loaded.touch()
elif name == 'ssh-agent':
    print('export SSH_AUTH_SOCK=/tmp/mock-dogfiles-agent;')
elif name == 'dscl':
    print('UserShell: ' + str(bin_dir / 'zsh'))
elif name == 'getent':
    print('tester:x:1000:1000::' + str(home) + ':' + os.environ.get('MOCK_LOGIN_SHELL', str(bin_dir / 'zsh')))
elif name == 'apt-cache':
    sys.exit(1)
elif name == 'dpkg-query':
    if os.environ.get('MOCK_PACKAGES_INSTALLED') == '1': print('install ok installed')
    else: sys.exit(1)
elif name == 'tmux' and args == ['has-session']:
    sys.exit(0 if os.environ.get('MOCK_TMUX_RUNNING') == '1' else 1)
elif name == 'chsh':
    sys.exit(int(os.environ.get('MOCK_CHSH_BLOCKED', '0')))
elif name == 'defaults' and os.environ.get('MOCK_MACOS_FAIL') == 'defaults':
    print('mock macOS stdout diagnostic')
    print('mock macOS stderr diagnostic', file=sys.stderr)
    sys.exit(1)
elif name == 'curl':
    url = next(a for a in args if a.startswith('https://'))
    if 'api.github.com' in url:
        print('{"tag_name":"v1.2.3"}')
    else:
        output = pathlib.Path(args[args.index('-o') + 1])
        if 'ohmyzsh' in url:
            output.write_text('mkdir -p "$ZSH"\nprintf "true\\n" > "$ZSH/oh-my-zsh.sh"\n')
        elif url.endswith('checksums.txt'):
            asset = 'lazygit_1.2.3_linux_' + ('arm64' if os.environ.get('MOCK_ARCH', 'arm64') in ('arm64', 'aarch64') else 'x86_64') + '.tar.gz'
            digest = hashlib.sha256(pathlib.Path(os.environ['TARBALL']).read_bytes()).hexdigest()
            if os.environ.get('BAD_CHECKSUM') == '1': digest = '0' * 64
            output.write_text(digest + '  ' + asset + '\n')
        elif url.endswith('.tar.gz'):
            shutil.copyfile(os.environ['TARBALL'], output)
        elif 'Homebrew/install/' in url:
            output.write_text('printf "installer executed\\n" > "$HOME/homebrew-installer-ran"\n')
        else: raise AssertionError('Unexpected download: ' + url)
elif name == 'jq':
    print(json.load(sys.stdin)['tag_name'])
elif name == 'shasum':
    print(hashlib.sha256(pathlib.Path(args[-1]).read_bytes()).hexdigest() + '  ' + args[-1])
elif name == 'sha256sum':
    source = (pathlib.Path(os.environ['TEMPLATE']) / 'bootstrap.sh').read_text()
    arch = 'ARM64' if os.environ.get('MOCK_ARCH', 'arm64') in ('arm64', 'aarch64') else 'X86_64'
    digest = re.search(r'readonly LAZYGIT_' + arch + r'_SHA256=([a-f0-9]+)', source)[1]
    if os.environ.get('BAD_CHECKSUM') == '1': digest = '0' * 64
    print(digest + '  ' + args[0])
elif name == 'install':
    assert args[-1] == '/usr/local/bin/lazygit'
    (bin_dir / 'lazygit').symlink_to(bin_dir / 'dispatcher')
elif name == 'grep' and os.environ.get('MOCK_GREP_SHELLS') == '1' and args[-1] == '/etc/shells':
    sys.exit(0)
elif name == 'grep':
    sys.exit(subprocess.call(['/usr/bin/grep'] + args))
'''


def snapshot(root):
    result = {}
    for path in sorted(root.rglob('*')):
        relative = str(path.relative_to(root))
        if path.is_symlink(): result[relative] = ('link', str(path.readlink()))
        elif path.is_file(): result[relative] = ('file', path.read_bytes(), path.stat().st_mode)
        else: result[relative] = ('dir', path.stat().st_mode)
    return result


class BootstrapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='dogfiles-test-')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name).resolve()
        self.home = self.work / 'home with spaces'
        self.home.mkdir()
        self.bin = self.work / 'bin'
        self.bin.mkdir()
        self.audit = self.work / 'audit'
        self.template = self.work / 'template'
        self.template.mkdir()
        for name in ('bootstrap.sh', 'install.sh'):
            (self.template / name).write_text(isolated_source((ROOT / name).read_text()))
        for name in ('conf', 'omarchy', 'scripts'):
            shutil.copytree(ROOT / name, self.template / name)
        dispatcher = self.bin / 'dispatcher'
        dispatcher.write_text(MOCK.replace('PYTHON', sys.executable, 1))
        dispatcher.chmod(0o755)
        for command in ('uname', 'id', 'pacman', 'sudo', 'git', 'brew', 'xcode-select',
                        'ssh-keygen', 'ssh-agent', 'ssh-add', 'dscl', 'getent', 'apt-cache',
                        'apt-get', 'dpkg-query', 'curl', 'jq', 'sha256sum', 'shasum', 'install', 'grep', 'zsh',
                        'tldr', 'lazygit', 'tmux', 'gpg', 'tig', 'tree', 'htop',
                        'sqlite3', 'exiftool', 'pkg-config', 'gh', 'chsh', 'wget',
                        'defaults', 'osascript', 'gem', 'go', 'tic'):
            (self.bin / command).symlink_to(dispatcher)
        tarball = self.work / 'lazygit.tar.gz'
        with tarfile.open(tarball, 'w:gz') as archive:
            data = b'#!/bin/sh\necho lazygit\n'
            entry = tarfile.TarInfo('lazygit')
            entry.size = len(data)
            entry.mode = 0o755
            archive.addfile(entry, io.BytesIO(data))
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ':/usr/bin:/bin',
                        AUDIT=str(self.audit), MOCK_BIN=str(self.bin), TEMPLATE=str(self.template),
                        REAL_GIT=REAL_GIT, TARBALL=str(tarball), GIT_CONFIG_NOSYSTEM='1',
                        GIT_CONFIG_GLOBAL='/dev/null', SHELL=str(self.bin / 'zsh'))
        for key in ('XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'DISPLAY', 'WAYLAND_DISPLAY', 'BASH_ENV', 'ZDOTDIR'):
            self.env.pop(key, None)

    def run_script(self, body, tty=False, env=None, tty_input=None):
        script = self.work / 'test.sh'
        script.write_text(body)
        run_env = dict(self.env, **(env or {}))
        if not tty:
            return subprocess.run([BASH, str(script)], env=run_env, capture_output=True, text=True)
        pid, fd = pty.fork()
        if pid == 0:
            os.execve(BASH, [BASH, str(script)], run_env)
        if tty_input is not None:
            os.write(fd, tty_input.encode())
        output = bytearray()
        deadline = time.monotonic() + 20
        status = None
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError:
                        break
                    if not chunk: break
                    output.extend(chunk)
            else:
                os.kill(pid, 9)
                self.fail('Bootstrap hung waiting for input')
        finally:
            os.close(fd)
            _, status = os.waitpid(pid, 0)
        return subprocess.CompletedProcess([], os.waitstatus_to_exitcode(status), output.decode(), '')

    def run_main(self, args='', platform='macos', tty=False):
        override = '\ndetect_platform() { platform=' + platform + '; say "Platform: $platform"; }\n'
        override += 'apple_ssh_add() { ssh-add --apple-use-keychain "$@"; }\n'
        return self.run_script(LIBRARY + override + '\nmain ' + args + '\n', tty=tty)

    def checkout(self):
        repo = self.home / 'code/darius/dogfiles'
        shutil.copytree(self.template, repo)
        subprocess.run([REAL_GIT, 'init', '-q', str(repo)], check=True)
        subprocess.run([REAL_GIT, '-C', str(repo), 'remote', 'add', 'origin',
                        'git@github.com:panacotar/dogfiles.git'], check=True)
        return repo

    def calls(self):
        return [json.loads(line) for line in self.audit.read_text().splitlines()] if self.audit.exists() else []

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_no_mutations(self, allow_brew_shellenv=False):
        banned = {'sudo', 'curl', 'ssh-keygen', 'ssh-agent', 'ssh-add', 'brew', 'chsh', 'apt-get', 'install', 'defaults', 'osascript'}
        for command, args in self.calls():
            if allow_brew_shellenv and command == 'brew' and args == ['shellenv']:
                continue
            self.assertNotIn(command, banned, (command, args))
            if command == 'git': self.assertNotIn('clone', args)
            if command == 'pacman': self.assertEqual(args[:1], ['-Q'])

    def test_platform_routing(self):
        fixture = self.work / 'os-release'
        for contents, expected in [('ID=linuxmint\nID_LIKE="ubuntu debian"\n', 'debian'),
                                   ('ID=debian\n', 'debian'), ('ID=fedora\n', None)]:
            fixture.write_text(contents)
            result = self.run_script(LIBRARY + '\ndetect_platform "$RELEASE"\n',
                                     env={'MOCK_OS': 'Linux', 'RELEASE': str(fixture)})
            if expected:
                self.assert_success(result)
                self.assertIn(expected, result.stdout)
            else: self.assertNotEqual(result.returncode, 0)
        result = self.run_script(LIBRARY + '\ndetect_platform\n', env={'MOCK_OS': 'Linux', 'MOCK_OMARCHY': '1'})
        self.assert_success(result)
        self.assertIn('omarchy', result.stdout)
        result = self.run_script(LIBRARY + '\ndetect_platform\n', env={'MOCK_OS': 'FreeBSD'})
        self.assertNotEqual(result.returncode, 0)

    def test_missing_checkout_dry_run_all_platforms(self):
        before = snapshot(self.home)
        for platform in ('macos', 'debian', 'omarchy'):
            result = self.run_main('--dry-run', platform)
            self.assert_success(result)
            self.assertIn('pending', result.stdout)
            self.assertIn('Would generate', result.stdout)
            self.assertIn('Would install TPM', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_existing_checkout_dry_run_and_key_skip(self):
        repo = self.checkout()
        (self.home / '.vimrc').write_text('original')
        (self.home / '.aliases').symlink_to('/missing/config')
        (self.home / '.ssh').mkdir()
        (self.home / '.ssh/github_id_ed25519').write_text('existing-key')
        before = snapshot(self.home)
        result = self.run_main('--dry-run')
        self.assert_success(result)
        self.assertIn('Would back up:', result.stdout)
        self.assertIn('Preserve existing SSH key', result.stdout)
        self.assertIn('Would reuse/start an SSH agent', result.stdout)
        self.assertIn(str(repo / 'conf/zshrc'), result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_existing_key_loads_into_reachable_agent_and_preserves_ssh_config(self):
        ssh = self.home / '.ssh'
        ssh.mkdir()
        (ssh / 'github_id_ed25519').write_text('existing private key')
        (ssh / 'github_id_ed25519.pub').write_text('existing public key')
        (ssh / 'config').write_text('Host personal\n  User custom\n')
        code = LIBRARY + '\nplatform=omarchy; dry_run=false; setup_ssh\n'
        self.assert_success(self.run_script(code, tty=True,
                            env={'MOCK_AGENT_STATUS': '1', 'SSH_AUTH_SOCK': '/tmp/existing-agent'}))
        calls = self.calls()
        self.assertFalse(any(name in ('ssh-agent', 'ssh-keygen') for name, _ in calls))
        self.assertIn(['ssh-add', [str(ssh / 'github_id_ed25519')]], calls)
        self.assertEqual((ssh / 'config').read_text(), 'Host personal\n  User custom\n')
        self.assertEqual((ssh / 'github_id_ed25519').read_text(), 'existing private key')
        cache = next(ssh.glob('environment-*'))
        self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
        self.assertIn('/tmp/existing-agent', cache.read_text())
        self.audit.unlink()
        # A later piped bootstrap recovers the cached agent without inherited variables.
        self.assert_success(self.run_script(code, tty=True))
        calls = self.calls()
        self.assertFalse(any(name == 'ssh-agent' for name, _ in calls))
        self.assertFalse(any(name == 'ssh-add' and args == [str(ssh / 'github_id_ed25519')]
                             for name, args in calls))

    def test_stale_cached_agent_is_replaced_and_key_loaded(self):
        ssh = self.home / '.ssh'
        ssh.mkdir()
        (ssh / 'github_id_ed25519').write_text('existing key')
        host = subprocess.check_output(['hostname', '-s'], text=True).strip()
        cache = ssh / ('environment-' + host)
        cache.write_text('export SSH_AUTH_SOCK=/tmp/stale-agent\n')
        code = LIBRARY + '\nplatform=omarchy; dry_run=false; setup_ssh\n'
        self.assert_success(self.run_script(code, tty=True))
        self.assertIn(['ssh-agent', ['-s']], self.calls())
        self.assertIn('/tmp/mock-dogfiles-agent', cache.read_text())

    def test_dry_run_with_missing_prerequisites(self):
        self.checkout()
        before = snapshot(self.home)
        code = LIBRARY + '''
detect_platform() { platform=macos; }
have() {
  case "$1" in git|brew|curl|tldr|ssh) return 1;; esac
  command -v "$1" >/dev/null 2>&1
}
main --dry-run
'''
        result = self.run_script(code)
        self.assert_success(result)
        self.assertIn('identity validation is pending', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_config_only_backups_xdg_and_rerun(self):
        repo = self.checkout()
        (self.home / '.vimrc').write_text('original vim')
        (self.home / '.aliases').symlink_to('/missing/aliases')
        self.env['XDG_CONFIG_HOME'] = str(self.home / 'custom config')
        self.env['XDG_STATE_HOME'] = str(self.home / 'custom state')
        command = 'bash "$CHECKOUT/bootstrap.sh" --configs-only'
        self.env['CHECKOUT'] = str(repo)
        result = self.run_script(command)
        self.assert_success(result)
        self.assertEqual((self.home / '.vimrc').readlink(), repo / 'conf/vimrc')
        self.assertTrue((self.home / 'custom config/alacritty/alacritty.toml').is_symlink())
        backups = list((self.home / 'custom state/dogfiles/backups').glob('bootstrap-*'))
        self.assertEqual(len(backups), 1)
        saved = backups[0] / str(self.home).lstrip('/')
        self.assertEqual((saved / '.vimrc').read_text(), 'original vim')
        self.assertEqual((saved / '.aliases').readlink(), Path('/missing/aliases'))
        before = snapshot(self.home)
        self.assert_success(self.run_script(command))
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_config_only_dry_run_and_relative_correct_link(self):
        repo = self.checkout()
        (self.home / '.vimrc').symlink_to('code/darius/dogfiles/conf/vimrc')
        before = snapshot(self.home)
        result = self.run_script('bash "$CHECKOUT/bootstrap.sh" --configs-only --dry-run',
                                 env={'CHECKOUT': str(repo)})
        self.assert_success(result)
        self.assertIn('Already linked: ' + str(self.home / '.vimrc'), result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_ssh_preflight_and_existing_config_backup(self):
        ssh = self.home / '.ssh'
        ssh.mkdir()
        public = ssh / 'github_id_ed25519.pub'
        public.write_text('orphan')
        result = self.run_main('--dry-run')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(public.read_text(), 'orphan')
        public.unlink()
        original = self.home / 'original ssh config'
        original.write_text('Host private-host\n  User example\n')
        (ssh / 'config').symlink_to(original)
        self.assert_success(self.run_main(platform='debian', tty=True))
        self.assertIn('Host private-host', (ssh / 'config').read_text())
        saved = list((self.home / '.local/state/dogfiles/backups').glob('ssh-*/config'))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].readlink(), original)
        self.assertEqual(original.read_text(), 'Host private-host\n  User example\n')

    def test_installed_debian_packages_are_not_upgraded(self):
        code = LIBRARY + '\nplatform=debian; dry_run=false; install_packages\n'
        self.assert_success(self.run_script(code, tty=True, env={'MOCK_PACKAGES_INSTALLED': '1'}))
        self.assertFalse(any(name == 'apt-get' and 'install' in args for name, args in self.calls()))

    def test_blocked_shell_change_prints_manual_command(self):
        (self.home / '.zshrc').write_text('true\n')
        self.env['MOCK_GREP_SHELLS'] = '1'
        self.env['MOCK_CHSH_BLOCKED'] = '1'
        code = LIBRARY + '''
platform=debian; dry_run=false
getent() { printf 'tester:x:1000:1000::%s:/bin/bash\\n' "$HOME"; }
setup_login_shell
'''
        result = self.run_script(code, tty=True)
        self.assert_success(result)
        self.assertIn('change the login shell manually', result.stdout)

    def test_conflicting_checkout_and_config_parent(self):
        repo = self.home / 'code/darius/dogfiles'
        repo.mkdir(parents=True)
        (repo / 'unrelated').write_text('keep')
        before = snapshot(self.home)
        self.assertNotEqual(self.run_main('--dry-run').returncode, 0)
        self.assertEqual(snapshot(self.home), before)
        shutil.rmtree(repo)
        repo = self.checkout()
        subprocess.run([REAL_GIT, '-C', str(repo), 'remote', 'set-url', 'origin', 'https://example.com/other.git'], check=True)
        self.assertNotEqual(self.run_main('--dry-run').returncode, 0)
        (self.home / '.config').write_text('parent is file')
        result = self.run_script('bash "$CHECKOUT/bootstrap.sh" --configs-only', env={'CHECKOUT': str(repo)})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / '.gitconfig').exists(), 'preflight must finish before linking')

    def test_omarchy_personal_configs_take_priority_and_monitor_opt_in(self):
        repo = self.checkout()
        (self.home / '.bashrc').write_text('Omarchy shell')
        (self.home / '.zshrc').write_text('keep zsh')
        self.env['MOCK_OS'] = 'Linux'
        self.env['MOCK_OMARCHY'] = '1'
        self.env['CHECKOUT'] = str(repo)
        self.env['XDG_CONFIG_HOME'] = str(self.home / 'custom config')
        config = self.home / 'custom config'
        (config / 'tmux').mkdir(parents=True)
        (config / 'tmux/tmux.conf').write_text('old tmux')
        (config / 'alacritty').mkdir()
        (config / 'alacritty/alacritty.toml').symlink_to(repo / 'omarchy/config/alacritty/alacritty.toml')
        command = 'bash "$CHECKOUT/bootstrap.sh" --configs-only'
        before = snapshot(self.home)
        preview = self.run_script(command + ' --dry-run')
        self.assert_success(preview)
        self.assertIn('Skip monitor settings', preview.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_success(self.run_script(command))
        self.assertEqual((self.home / '.bashrc').read_text(), 'Omarchy shell')
        self.assertEqual((self.home / '.zshrc').readlink(), repo / 'conf/zshrc')
        self.assertEqual((self.home / '.aliases').readlink(), repo / 'conf/aliases')
        self.assertFalse((config / 'hypr/monitors.lua').exists())
        self.assertEqual((config / 'alacritty/alacritty.toml').readlink(), repo / 'conf/alacritty.toml')
        for target in (self.home / '.tmux.conf', config / 'tmux/tmux.conf'):
            self.assertEqual(target.readlink(), repo / 'conf/tmux.conf')
        saved = next((self.home / '.local/state/dogfiles/backups').glob('bootstrap-*'))
        self.assertEqual((saved / str(self.home).lstrip('/') / '.zshrc').read_text(), 'keep zsh')
        self.assertEqual((saved / str(config).lstrip('/') / 'tmux/tmux.conf').read_text(), 'old tmux')
        self.assertEqual((saved / str(config).lstrip('/') / 'alacritty/alacritty.toml').readlink(),
                         repo / 'omarchy/config/alacritty/alacritty.toml')
        before = snapshot(self.home)
        self.assert_success(self.run_script(command))
        self.assertEqual(snapshot(self.home), before)
        self.assert_success(self.run_script(command + ' --include-monitors'))
        self.assertTrue((config / 'hypr/monitors.lua').is_symlink())
        self.assert_no_mutations()

    def test_omarchy_full_setup_installs_and_validates_zsh(self):
        self.env.update(MOCK_LOGIN_SHELL='/usr/bin/bash', MOCK_GREP_SHELLS='1')
        result = self.run_main(platform='omarchy', tty=True)
        self.assert_success(result)
        self.assertTrue((self.home / '.zshrc').is_symlink())
        self.assertTrue((self.home / '.oh-my-zsh/oh-my-zsh.sh').is_file())
        for plugin in ('zsh-autosuggestions', 'zsh-syntax-highlighting'):
            self.assertTrue((self.home / '.oh-my-zsh/custom/plugins' / plugin / '.git').is_dir())
        calls = self.calls()
        syntax = ['zsh', ['-n', str(self.home / '.zshrc')]]
        startup = ['zsh', ['-ic', 'exit']]
        change = ['chsh', ['-s', str(self.bin / 'zsh')]]
        for call in (syntax, startup, change):
            self.assertIn(call, calls)
        self.assertLess(calls.index(syntax), calls.index(startup))
        self.assertLess(calls.index(startup), calls.index(change))

    def test_existing_tmux_shell_is_updated_even_when_login_shell_is_zsh(self):
        self.env['MOCK_TMUX_RUNNING'] = '1'
        self.assert_success(self.run_main(platform='omarchy', tty=True))
        calls = self.calls()
        self.assertIn(['tmux', ['set-option', '-g', 'default-shell', str(self.bin / 'zsh')]], calls)
        self.assertIn(['tmux', ['set-environment', '-g', 'SHELL', str(self.bin / 'zsh')]], calls)
        self.assertFalse(any(name == 'chsh' for name, _ in calls))
        self.assertFalse(any(name == 'tmux' and args[0] in ('send-keys', 'kill-server', 'new-session')
                             for name, args in calls))

    def test_tmux_shell_setup_without_server_or_dry_run_does_not_mutate(self):
        code = LIBRARY + '\ndry_run=false; setup_tmux_shell\n'
        self.assert_success(self.run_script(code))
        self.assertEqual([args for name, args in self.calls() if name == 'tmux'], [['has-session']])
        self.audit.unlink()
        self.assert_success(self.run_script(LIBRARY + '\ndry_run=true; setup_tmux_shell\n',
                                            env={'MOCK_TMUX_RUNNING': '1'}))
        self.assertFalse(any(name == 'tmux' for name, _ in self.calls()))

    def test_omarchy_exclusions_skip_sources_and_are_repeatable(self):
        # Exclusions are processed before validating source files.
        for relative in ('alacritty/alacritty.toml', 'kitty/kitty.conf'):
            (self.template / 'omarchy/config' / relative).unlink()
        command = ('bash "$TEMPLATE/omarchy/install.sh" --exclude-config alacritty/alacritty.toml '
                   '--exclude-config kitty/kitty.conf')
        before = snapshot(self.home)
        self.assert_success(self.run_script(command + ' --dry-run'))
        self.assertEqual(snapshot(self.home), before)
        self.assert_success(self.run_script(command))
        self.assertFalse((self.home / '.config/alacritty/alacritty.toml').exists())
        self.assertFalse((self.home / '.config/kitty/kitty.conf').exists())
        self.assertTrue((self.home / '.config/hypr/hyprland.lua').is_symlink())
        for args in ('--exclude-config', '--exclude-config ../outside', '--exclude-config /absolute',
                     '--exclude-config --dry-run'):
            before = snapshot(self.home)
            self.assertNotEqual(self.run_script('bash "$TEMPLATE/omarchy/install.sh" ' + args).returncode, 0)
            self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_full_macos_setup_and_rerun(self):
        result = self.run_main(tty=True)
        self.assert_success(result)
        repo = self.home / 'code/darius/dogfiles'
        self.assertEqual((self.home / '.ssh/github_id_ed25519').read_text(), 'private-test-key')
        self.assertTrue((self.home / '.zshrc').is_symlink())
        self.assertTrue((self.home / '.tmux/plugins/tmux-continuum/.git').is_dir())
        self.assertIn('UseKeychain yes', (self.home / '.ssh/config').read_text())
        calls_before = len(self.calls())
        self.assert_success(self.run_main(tty=True))
        calls = self.calls()[calls_before:]
        self.assertFalse(any(command in ('ssh-keygen', 'ssh-agent') for command, _ in calls))
        self.assertFalse(any(command == 'ssh-add' and args not in (['-l'], ['-T', str(self.home / '.ssh/github_id_ed25519.pub')])
                             for command, args in calls))
        self.assertFalse(any(command == 'git' and 'clone' in args for command, args in calls))
        remote = subprocess.check_output([REAL_GIT, '-C', str(repo), 'remote', 'get-url', 'origin'], text=True)
        self.assertEqual(remote.strip(), 'git@github.com:panacotar/dogfiles.git')

    def test_full_debian_setup_existing_key_and_omarchy_setup(self):
        for platform in ('debian', 'omarchy'):
            with self.subTest(platform=platform):
                (self.home / '.ssh').mkdir(exist_ok=True)
                (self.home / '.ssh/github_id_ed25519').write_text('original')
                (self.home / '.bashrc').write_text('keep bash')
                self.assert_success(self.run_main(platform=platform, tty=True))
                self.assertEqual((self.home / '.ssh/github_id_ed25519').read_text(), 'original')
                self.assertEqual((self.home / '.bashrc').read_text(), 'keep bash')
        calls = self.calls()
        self.assertIn(['apt-get', ['update']], calls)
        pacman_args = [args for command, args in calls if command == 'pacman' and args[0] != '-Q']
        self.assertTrue(pacman_args)
        self.assertEqual(pacman_args[0][:3], ['-S', '--needed', '--noconfirm'])
        self.assertFalse(any(command == 'ssh-keygen' for command, _ in calls))
        self.assertTrue(any(command == 'ssh-add' and args == [str(self.home / '.ssh/github_id_ed25519')]
                            for command, args in calls))

    def test_lazygit_checksum_and_architecture(self):
        (self.bin / 'lazygit').unlink()
        code = LIBRARY + '\nplatform=debian; temp_dir=; install_lazygit_binary\n'
        failed = self.run_script(code, tty=True, env={'BAD_CHECKSUM': '1', 'MOCK_ARCH': 'aarch64'})
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('checksum verification failed', failed.stdout)
        self.assertFalse(any(command == 'install' for command, _ in self.calls()))
        self.assert_success(self.run_script(code, tty=True, env={'MOCK_ARCH': 'aarch64'}))
        self.assertTrue(any('lazygit_0.66.2_linux_arm64.tar.gz' in arg for _, args in self.calls() for arg in args))
        downloads = [arg for name, args in self.calls() if name == 'curl' for arg in args if arg.startswith('https://')]
        self.assertTrue(all('/v0.66.2/' in url and url.endswith('.tar.gz') for url in downloads))

    def test_homebrew_checksum_rejects_download_before_execution(self):
        code = LIBRARY + '''
platform=macos; dry_run=false; temp_dir=
find_brew() { brew_bin=; }
install_packages
'''
        result = self.run_script(code, tty=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Homebrew installer checksum verification failed', result.stdout)
        self.assertFalse((self.home / 'homebrew-installer-ran').exists())
        urls = [arg for name, args in self.calls() if name == 'curl' for arg in args if arg.startswith('https://')]
        self.assertEqual(len(urls), 1)
        self.assertRegex(urls[0], r'/Homebrew/install/[0-9a-f]{40}/install.sh$')

    def test_homebrew_checksum_accepts_only_matching_content(self):
        payload = 'printf "installer executed\\n" > "$HOME/homebrew-installer-ran"\n'
        digest = hashlib.sha256(payload.encode()).hexdigest()
        code = LIBRARY.replace('5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148', digest)
        code += '''
platform=macos; dry_run=false; temp_dir=
find_brew() {
  brew_bin=
  if [[ -f "$HOME/homebrew-installer-ran" ]]; then brew_bin=$(command -v brew); fi
}
install_packages
'''
        result = self.run_script(code, tty=True)
        self.assert_success(result)
        self.assertTrue((self.home / 'homebrew-installer-ran').exists())

    def test_wrong_fetched_commit_is_rejected_and_staging_removed(self):
        code = 'source "$TEMPLATE/scripts/sources.sh"\nclone_pinned https://github.com/nvm-sh/nvm.git "$HOME/plugin" "$NVM_REVISION"\n'
        for failure in ('MOCK_WRONG_REVISION', 'MOCK_FETCH_FAIL'):
            with self.subTest(failure=failure):
                result = self.run_script(code, env={failure: '1'})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.home / 'plugin').exists())
                self.assertFalse(list(self.home.glob('.dogfiles-source-*')))

    def test_bootstrap_fetches_only_full_commit_pins_for_plugins(self):
        self.assert_success(self.run_main(tty=True))
        fetches = [args for name, args in self.calls() if name == 'git' and 'fetch' in args]
        self.assertEqual(len(fetches), 7)  # Oh My Zsh, two Zsh plugins, four tmux plugins.
        for args in fetches:
            self.assertRegex(args[-1], r'^[0-9a-f]{40}$')

    def test_optional_runtime_and_security_sources_are_pinned(self):
        self.prepare_linux_post_installer()
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='1 3 4 5 11\n\n')
        self.assert_success(result)
        calls = self.calls()
        self.assertTrue((self.home / '.nvm/nvm.sh').exists())
        fetches = [args for name, args in calls if name == 'git' and 'fetch' in args]
        self.assertEqual(len(fetches), 7)
        for args in fetches:
            self.assertRegex(args[-1], r'^[0-9a-f]{40}$')
        self.assertIn(['go', ['install', 'github.com/OJ/gobuster/v3@v3.8.2']], calls)
        self.assertIn(['gem', ['install', 'wpscan', '--version', '4.1.0']], calls)
        self.assertFalse(any(name == 'curl' for name, _ in calls))

    def test_existing_nvm_is_preserved_and_reports_pin_mismatch(self):
        nvm = self.home / '.nvm'
        (nvm / '.git').mkdir(parents=True)
        (nvm / '.mock-source').touch()
        (nvm / '.mock-revision').write_text('1' * 40)
        (nvm / 'nvm.sh').write_text('local customization\n')
        before = snapshot(self.home)
        self.prepare_linux_post_installer()
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='4\n\n')
        self.assert_success(result)
        self.assertIn('preserving existing checkout', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assertFalse(any(name == 'git' and 'fetch' in args for name, args in self.calls()))

    def test_piped_help_and_dry_run(self):
        command = 'cat "$TEMPLATE/bootstrap.sh" | bash -s -- '
        before = snapshot(self.home)
        self.assert_success(self.run_script(command + '--help'))
        self.assert_success(self.run_script(command + '--dry-run'))
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_standalone_dry_run_announces_stages_without_shared_file(self):
        shutil.rmtree(self.template / 'scripts')
        before = snapshot(self.home)
        result = self.run_script('cd /; cat "$TEMPLATE/bootstrap.sh" | bash -s -- --dry-run')
        self.assert_success(result)
        stages = [
            'Dogfiles setup: macos',
            'Installing common CLI tools...',
            'Setting up GitHub SSH access...',
            'Preparing the dogfiles checkout...',
            'Installing shell and tmux plugins...',
            'Linking configuration files...',
            'Checking the login shell...',
            'Verifying common CLI commands...',
            'Setup preview complete',
        ]
        locations = [result.stdout.index(stage) for stage in stages]
        self.assertEqual(locations, sorted(locations))
        self.assertIn('DRY RUN: no changes will be made.', result.stdout)
        self.assertIn('#################################', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_bootstrap_loads_shared_announcements_after_cloning(self):
        helper = self.template / 'scripts/output.sh'
        with helper.open('a') as out:
            out.write('\ntrumpet() { printf "SHARED:%s\\n" "$1"; }\n')
        result = self.run_main(tty=True)
        self.assert_success(result)
        self.assertNotIn('SHARED:Installing common CLI tools...', result.stdout)
        self.assertIn('SHARED:Installing shell and tmux plugins...', result.stdout)
        self.assertIn('SHARED:Linking configuration files...', result.stdout)
        self.assertIn('SHARED:Dogfiles setup complete', result.stdout)

    def test_shared_announcements_work_without_terminal_capabilities(self):
        result = self.run_script('source "$TEMPLATE/scripts/output.sh"\n'
                                 'init_output true\ntrumpet "A stage"\nprogress_comm "A step"\n',
                                 env={'TERM': 'dumb'})
        self.assert_success(result)
        self.assertIn('#################################\n A stage', result.stdout)
        self.assertIn('-----> A step', result.stdout)
        self.assertNotIn('\033', result.stdout)

    def test_piped_real_entry_point_uses_terminal_for_key(self):
        result = self.run_script('cat "$TEMPLATE/bootstrap.sh" | bash', tty=True,
                                 env={'MOCK_OS': 'Linux', 'MOCK_OMARCHY': '1'})
        self.assert_success(result)
        self.assertTrue((self.home / '.ssh/github_id_ed25519').exists())

    def test_invalid_flags_and_relative_xdg(self):
        self.assertNotEqual(self.run_main('--unknown').returncode, 0)
        self.assertNotEqual(self.run_main('--include-monitors --dry-run').returncode, 0)
        self.env['XDG_CONFIG_HOME'] = 'relative'
        self.assertNotEqual(self.run_main('--dry-run').returncode, 0)
        self.assert_no_mutations()

    def test_post_install_no_packages_still_applies_all_macos_settings(self):
        before = snapshot(self.home)
        result = self.run_script('cd /; bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='\n')
        self.assert_success(result)
        self.assertIn('Applying macOS settings from conf/macos', result.stdout)
        self.assertNotIn('Keyboard repeat instead of', result.stdout)
        self.assertIn('macOS settings applied.', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        calls = self.calls()
        defaults = [args for name, args in calls if name == 'defaults']
        # The user can extend conf/macos with more personal preferences.
        self.assertIn(['write', '-g', 'ApplePressAndHoldEnabled', '-bool', 'false'], defaults)
        self.assertFalse(any(name in ('osascript', 'pmset', 'systemsetup', 'chflags')
                             for name, _ in calls))
        self.assertFalse(any(name == 'brew' and args != ['shellenv'] for name, args in calls))

    def test_macos_settings_reports_failure(self):
        result = self.run_script('bash "$TEMPLATE/conf/macos"',
                                 env={'MOCK_MACOS_FAIL': 'defaults'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('macOS setting failed at line', result.stderr)
        self.assertNotIn('macOS settings applied.', result.stdout)

    def test_macos_settings_apply_user_preferences_without_terminal(self):
        result = self.run_script('bash "$TEMPLATE/conf/macos"')
        self.assert_success(result)
        mutations = [[name, args] for name, args in self.calls() if name not in ('uname', 'id')]
        self.assertIn(['defaults', ['write', '-g', 'ApplePressAndHoldEnabled', '-bool', 'false']], mutations)
        self.assertTrue(all(name in ('defaults', 'sudo') for name, _ in mutations))

    def test_macos_settings_reject_linux_without_applying_anything(self):
        result = self.run_script('bash "$TEMPLATE/conf/macos"', env={'MOCK_OS': 'Linux'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('These settings require macOS', result.stderr)
        self.assert_no_mutations()

    def test_post_install_checkboxes_toggle_before_installation(self):
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='2,6\n2\n\n')
        self.assert_success(result)
        self.assertIn('Installing Mac', result.stdout)
        self.assertIn('Installing DBeaver...', result.stdout)
        self.assertNotIn('Installing Go...', result.stdout)
        installed = [args for name, args in self.calls() if name == 'brew' and args != ['shellenv']]
        self.assertEqual(installed, [['install', '--cask', 'dbeaver-community']])
        self.assertEqual(result.stdout.count('Press Enter to install the selected items:'), 3)
        last_prompt = result.stdout.index('Press Enter to install the selected items:')
        self.assertLess(last_prompt, result.stdout.index('Selection complete. Installing selected options...'))
        self.assertLess(last_prompt, result.stdout.index('Installing DBeaver...'))

    def test_post_install_failure_logs_stdout_stderr_and_final_path(self):
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='\n', env={'MOCK_MACOS_FAIL': 'defaults'})
        self.assertEqual(result.returncode, 1)
        logs = list((self.template / 'logs').glob('install-*/output.log'))
        self.assertEqual(len(logs), 1)
        contents = logs[0].read_text()
        for expected in ('mock macOS stdout diagnostic', 'mock macOS stderr diagnostic',
                         'macOS setting failed at line',
                         'Command failed (status 1)',
                         'fix the reported issue and rerun. Logged in ' + str(logs[0])):
            self.assertIn(expected, contents)
            self.assertIn(expected, result.stdout)

    def test_post_install_package_failure_preserves_exit_code_and_flushes_log(self):
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='2\n\n', env={'MOCK_BREW_FAIL': '23'})
        self.assertEqual(result.returncode, 23)
        log = next((self.template / 'logs').glob('install-*/output.log'))
        contents = log.read_text()
        self.assertIn('mock package stdout diagnostic', contents)
        self.assertIn('mock package stderr diagnostic', contents)
        self.assertIn('Command failed (status 23)', contents)
        self.assertTrue(contents.endswith('Logged in ' + str(log) + '\n'))
        self.assertNotIn('Applying macOS settings', contents)

    def test_post_install_early_exit_is_logged(self):
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 env={'MOCK_OS': 'FreeBSD'})
        self.assertNotEqual(result.returncode, 0)
        log = next((self.template / 'logs').glob('install-*/output.log'))
        self.assertIn('Unsupported operating system.', log.read_text())
        self.assertIn('Logged in ' + str(log), result.stdout)

    def test_post_install_logs_are_unique_private_and_include_success(self):
        for _ in range(2):
            self.assert_success(self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                                tty_input='q\n'))
        logs = list((self.template / 'logs').glob('install-*/output.log'))
        self.assertEqual(len(logs), 2)
        for log in logs:
            self.assertEqual(log.stat().st_mode & 0o077, 0)
            self.assertEqual(log.parent.stat().st_mode & 0o077, 0)
            contents = log.read_text()
            self.assertIn('Selection cancelled.', contents)
            self.assertIn('Logged in ' + str(log), contents)

    def test_post_install_help_does_not_create_logs(self):
        self.assert_success(self.run_script('bash "$TEMPLATE/install.sh" --help'))
        self.assertFalse((self.template / 'logs').exists())

    def test_install_logs_are_gitignored(self):
        result = subprocess.run([REAL_GIT, 'check-ignore', '--no-index',
                                 'logs/install-example/output.log'],
                                cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_post_install_none_proceeds_without_second_confirmation(self):
        before = snapshot(self.home)
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='n\n', env={'TERM': 'xterm-256color'})
        self.assert_success(result)
        self.assertEqual(result.stdout.count('Choose optional installations and settings:'), 1)
        self.assertEqual(result.stdout.count('Press Enter to install the selected items:'), 1)
        self.assertIn('No optional items selected. Continuing...', result.stdout)
        self.assertIn('Applying macOS settings from conf/macos', result.stdout)
        self.assertNotIn('\033[J', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assertFalse(any(name == 'brew' and args != ['shellenv'] for name, args in self.calls()))

    def test_checkbox_selection_waits_for_enter_except_none(self):
        # Exercise selection without running all optional installer tasks.
        source = (self.template / 'install.sh').read_text()
        function = source[source.index('collect_choices() {'):source.index('\nselected() {')]
        for selection, expected in [('a\n\n', '1 1 1 1 1 1 1 1'), ('4 5 8\n\n', '0 0 0 1 1 0 0 1'), ('a\nn\n', '0 0 0 0 0 0 0 0')]:
            with self.subTest(selection=selection):
                result = self.run_script('BOLD=; NORMAL=; os=macos; exec 3</dev/tty\n' + function +
                                         '\ncollect_choices\nprintf "CHOICES:%s\\n" "${choices[*]}"\n',
                                         tty=True, tty_input=selection)
                self.assert_success(result)
                self.assertIn('CHOICES:' + expected, result.stdout)
                self.assertEqual(result.stdout.count('Press Enter to install the selected items:'), 2)
        self.assert_no_mutations()

    def test_checkbox_redraw_then_none_clears_selection_and_continues(self):
        before = snapshot(self.home)
        result = self.run_script('stty rows 24 cols 80 </dev/tty\nbash "$TEMPLATE/install.sh"',
                                 tty=True, tty_input='2\nn\n', env={'TERM': 'xterm-256color'})
        self.assert_success(result)
        self.assertIn('[x]  2. Go', result.stdout)
        self.assertEqual(result.stdout.count('Choose optional installations and settings:'), 2)
        self.assertEqual(result.stdout.count('Press Enter to install the selected items:'), 2)
        self.assertEqual(result.stdout.count('\033[15A\033[J'), 1)
        after_none = result.stdout.split('No optional items selected. Continuing...')[-1]
        self.assertNotIn('Choose optional installations', after_none)
        self.assertIn('Applying macOS settings from conf/macos', after_none)
        self.assertNotIn('Installing Go...', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assertFalse(any(name == 'brew' and args != ['shellenv'] for name, args in self.calls()))

    def test_linux_none_proceeds_without_packages(self):
        self.prepare_linux_post_installer()
        before = snapshot(self.home)
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True, tty_input='n\n')
        self.assert_success(result)
        self.assertIn('No options selected. Nothing to install.', result.stdout)
        self.assertEqual(result.stdout.count('Press Enter to install the selected items:'), 1)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_post_install_invalid_selection_does_not_partially_select(self):
        before = snapshot(self.home)
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='2 nope\nq\n')
        self.assert_success(result)
        self.assertIn('Choose numbers between 1 and 8', result.stdout)
        self.assertEqual(result.stdout.count('Choose optional installations and settings:'), 1)
        self.assertEqual(result.stdout.count('Press Enter to install the selected items:'), 2)
        self.assertIn('Selection cancelled.', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations(allow_brew_shellenv=True)

    def prepare_linux_post_installer(self):
        # Substitute only the trusted OS metadata file, so these Linux flows can
        # also be exercised on the macOS development host.
        release = self.work / 'os-release'
        release.write_text('ID=linuxmint\nID_LIKE="ubuntu debian"\n')
        script = self.template / 'install.sh'
        script.write_text(script.read_text().replace('. /etc/os-release', '. "$TEST_OS_RELEASE"'))
        self.env.update(MOCK_OS='Linux', MOCK_OMARCHY='0', TEST_OS_RELEASE=str(release))

    def test_linux_post_install_cancel_does_not_refresh_apt(self):
        self.prepare_linux_post_installer()
        before = snapshot(self.home)
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True, tty_input='q\n')
        self.assert_success(result)
        self.assertIn('Installing Linux', result.stdout)
        self.assertIn('Desktop/hardware extras', result.stdout)
        self.assertNotIn('StripMe Finder service', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_linux_post_install_collects_choices_before_apt_and_tasks(self):
        self.prepare_linux_post_installer()
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True, tty_input='2\n\n')
        self.assert_success(result)
        apt_calls = [args for name, args in self.calls() if name == 'apt-get']
        self.assertEqual(apt_calls, [['update'], ['install', '-y', 'golang-go']])
        selection_end = result.stdout.index('Selection complete. Installing selected options...')
        self.assertLess(selection_end, result.stdout.index('Updating the local package index...'))
        self.assertLess(selection_end, result.stdout.index('Installing Go...'))
        self.assertNotIn('Press Enter to install the selected items:', result.stdout[selection_end:])

    def test_post_install_rejects_omarchy(self):
        before = snapshot(self.home)
        result = self.run_script('bash "$TEMPLATE/install.sh"', tty=True,
                                 env={'MOCK_OS': 'Linux', 'MOCK_OMARCHY': '1'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('On Omarchy, use bootstrap.sh', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

    def test_package_names_and_existing_tldr(self):
        for platform, expected in [('macos', 'gnupg'), ('debian', 'openssh-client'), ('omarchy', 'github-cli')]:
            result = self.run_script(LIBRARY + '\nplatform=' + platform + '; package_list; printf "%s\\n" "${packages[@]}"\n')
            self.assert_success(result)
            self.assertIn(expected, result.stdout)
            self.assertNotIn('tealdeer', result.stdout)
        (self.bin / 'tldr').unlink()
        result = self.run_script(LIBRARY + '\nplatform=macos; package_list; printf "%s\\n" "${packages[@]}"\n')
        self.assertIn('tealdeer', result.stdout)

    def test_package_constants_preserve_platform_package_sets(self):
        (self.bin / 'tldr').unlink()
        expected = {
            'macos': 'git curl wget unzip zsh vim tealdeer lazygit tmux gnupg tig tree htop sqlite exiftool pkgconf gh jq ca-certificates',
            'debian': 'git curl wget unzip zsh vim tealdeer tmux gnupg tig tree htop sqlite3 libimage-exiftool-perl pkg-config gh jq openssh-client ca-certificates',
            'omarchy': 'git curl wget unzip zsh vim tealdeer lazygit tmux gnupg tig tree htop sqlite perl-image-exiftool pkgconf github-cli jq openssh ca-certificates',
        }
        for platform, packages in expected.items():
            result = self.run_script(LIBRARY + '\nplatform=' + platform + '; package_list; printf "%s\\n" "${packages[@]}"\n')
            self.assert_success(result)
            self.assertCountEqual(result.stdout.splitlines(), packages.split())
        code = LIBRARY + '\nplatform=debian; package_list; printf "%s\\n" "${packages[@]}"\n'
        x11 = self.run_script(code, env={'DISPLAY': ':0'})
        self.assert_success(x11)
        self.assertCountEqual(x11.stdout.splitlines(), expected['debian'].split() + ['xclip'])
        wayland = self.run_script(code, env={'DISPLAY': ':0', 'WAYLAND_DISPLAY': 'wayland-0'})
        self.assert_success(wayland)
        self.assertCountEqual(wayland.stdout.splitlines(), expected['debian'].split())

    @unittest.skipUnless(shutil.which('zsh'), 'Zsh is not available')
    def test_fresh_zsh_startup_without_optional_integrations(self):
        for name in ('zshrc', 'aliases', 'custom_commands.sh'):
            (self.home / ('.' + name)).symlink_to(self.template / 'conf' / name)
        self.env['ZDOTDIR'] = str(self.home)
        self.env['SHELL'] = '/bin/bash'
        result = subprocess.run([shutil.which('zsh'), '-ic', 'print -r -- "$path[1]"; print -r -- "SHELL=$SHELL"; alias ll'],
                                env=self.env, text=True, capture_output=True)
        self.assert_success(result)
        self.assertIn('SHELL=' + str(self.bin / 'zsh'), result.stdout)
        self.assertIn("ll='ls -alh'", result.stdout)
        self.assertNotIn('no such file', result.stderr)
        self.assertNotIn('not found', result.stderr)


if __name__ == '__main__':
    unittest.main()

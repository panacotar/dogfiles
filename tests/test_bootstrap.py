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
LIBRARY = (ROOT / 'bootstrap.sh').read_text().rsplit('\nmain "$@"', 1)[0]

MOCK = r'''#!PYTHON
import hashlib, json, os, pathlib, shutil, subprocess, sys
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
    else:
        sys.exit(subprocess.call(args))
elif name == 'git':
    if args[0] == 'clone':
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
elif name == 'xcode-select':
    if args == ['-p']: sys.exit(int(os.environ.get('MOCK_NO_CLT', '0')))
elif name == 'ssh-keygen':
    assert sys.stdin.isatty(), 'key generation must read the terminal'
    dest = pathlib.Path(args[args.index('-f') + 1])
    dest.write_text('private-test-key')
    dest.with_suffix('.pub').write_text('ssh-ed25519 public-test-key\n')
elif name == 'ssh-add':
    if args == ['-l']: sys.exit(int(os.environ.get('MOCK_AGENT_STATUS', '2')))
    assert sys.stdin.isatty(), 'ssh-add must read the terminal'
elif name == 'ssh-agent':
    print('export SSH_AUTH_SOCK=/tmp/mock-dogfiles-agent;')
elif name == 'dscl':
    print('UserShell: ' + str(bin_dir / 'zsh'))
elif name == 'getent':
    print('tester:x:1000:1000::' + str(home) + ':' + str(bin_dir / 'zsh'))
elif name == 'apt-cache':
    sys.exit(1)
elif name == 'dpkg-query':
    if os.environ.get('MOCK_PACKAGES_INSTALLED') == '1': print('install ok installed')
    else: sys.exit(1)
elif name == 'chsh':
    sys.exit(int(os.environ.get('MOCK_CHSH_BLOCKED', '0')))
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
        else: raise AssertionError('Unexpected download: ' + url)
elif name == 'jq':
    print(json.load(sys.stdin)['tag_name'])
elif name == 'sha256sum':
    print(hashlib.sha256(pathlib.Path(args[0]).read_bytes()).hexdigest() + '  ' + args[0])
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
            shutil.copy(ROOT / name, self.template / name)
        for name in ('conf', 'omarchy'):
            shutil.copytree(ROOT / name, self.template / name)
        dispatcher = self.bin / 'dispatcher'
        dispatcher.write_text(MOCK.replace('PYTHON', sys.executable, 1))
        dispatcher.chmod(0o755)
        for command in ('uname', 'id', 'pacman', 'sudo', 'git', 'brew', 'xcode-select',
                        'ssh-keygen', 'ssh-agent', 'ssh-add', 'dscl', 'getent', 'apt-cache',
                        'apt-get', 'dpkg-query', 'curl', 'jq', 'sha256sum', 'install', 'grep', 'zsh',
                        'tldr', 'lazygit', 'tmux', 'gpg', 'tig', 'tree', 'htop',
                        'sqlite3', 'exiftool', 'pkg-config', 'gh', 'chsh', 'wget'):
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

    def assert_no_mutations(self):
        banned = {'sudo', 'curl', 'ssh-keygen', 'ssh-agent', 'ssh-add', 'brew', 'chsh', 'apt-get', 'install'}
        for command, args in self.calls():
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
        self.assertIn('Skip SSH setup', result.stdout)
        self.assertIn(str(repo / 'conf/zshrc'), result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

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

    def test_omarchy_config_only_preserves_shell_and_monitor_opt_in(self):
        repo = self.checkout()
        (self.home / '.bashrc').write_text('Omarchy shell')
        (self.home / '.zshrc').write_text('keep zsh')
        self.env['MOCK_OS'] = 'Linux'
        self.env['MOCK_OMARCHY'] = '1'
        self.env['CHECKOUT'] = str(repo)
        command = 'bash "$CHECKOUT/bootstrap.sh" --configs-only'
        before = snapshot(self.home)
        preview = self.run_script(command + ' --dry-run')
        self.assert_success(preview)
        self.assertIn('Skip monitor settings', preview.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_success(self.run_script(command))
        self.assertEqual((self.home / '.bashrc').read_text(), 'Omarchy shell')
        self.assertEqual((self.home / '.zshrc').read_text(), 'keep zsh')
        self.assertFalse((self.home / '.config/hypr/monitors.lua').exists())
        self.assertTrue((self.home / '.config/alacritty/alacritty.toml').readlink().is_relative_to(repo / 'omarchy'))
        self.assert_success(self.run_script(command + ' --include-monitors'))
        self.assertTrue((self.home / '.config/hypr/monitors.lua').is_symlink())
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
        self.assertFalse(any(command in ('ssh-keygen', 'ssh-add', 'ssh-agent') for command, _ in calls))
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
        self.assertFalse(any(command.startswith('ssh-') for command, _ in calls))

    def test_lazygit_checksum_and_architecture(self):
        (self.bin / 'lazygit').unlink()
        code = LIBRARY + '\nplatform=debian; temp_dir=; install_lazygit_binary\n'
        failed = self.run_script(code, tty=True, env={'BAD_CHECKSUM': '1', 'MOCK_ARCH': 'aarch64'})
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn('checksum verification failed', failed.stdout)
        self.assertFalse(any(command == 'install' for command, _ in self.calls()))
        self.assert_success(self.run_script(code, tty=True, env={'MOCK_ARCH': 'aarch64'}))
        self.assertTrue(any('lazygit_1.2.3_linux_arm64.tar.gz' in arg for _, args in self.calls() for arg in args))

    def test_piped_help_and_dry_run(self):
        command = 'cat "$TEMPLATE/bootstrap.sh" | bash -s -- '
        before = snapshot(self.home)
        self.assert_success(self.run_script(command + '--help'))
        self.assert_success(self.run_script(command + '--dry-run'))
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

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

    def test_post_install_defaults_to_no_without_touching_configs(self):
        before = snapshot(self.home)
        result = self.run_script('cd /; bash "$TEMPLATE/install.sh"', tty=True,
                                 tty_input='n\n' * 20)
        self.assert_success(result)
        self.assertIn('Post-installation complete', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.assert_no_mutations()

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

    @unittest.skipUnless(shutil.which('zsh'), 'Zsh is not available')
    def test_fresh_zsh_startup_without_optional_integrations(self):
        for name in ('zshrc', 'aliases', 'custom_commands.sh'):
            (self.home / ('.' + name)).symlink_to(self.template / 'conf' / name)
        self.env['ZDOTDIR'] = str(self.home)
        result = subprocess.run([shutil.which('zsh'), '-ic', 'print -r -- "$path[1]"'],
                                env=self.env, text=True, capture_output=True)
        self.assert_success(result)
        self.assertNotIn('no such file', result.stderr)
        self.assertNotIn('not found', result.stderr)


if __name__ == '__main__':
    unittest.main()

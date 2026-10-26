"""Security regressions using temporary homes and local Git repositories only."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GIT = shutil.which('git')
ZSH = shutil.which('zsh')


class SecurityTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='dogfiles-security-')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name).resolve()
        self.home = self.work / 'home with spaces'
        self.home.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH='/usr/bin:/bin',
                        GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                        GIT_AUTHOR_NAME='Test', GIT_COMMITTER_NAME='Test',
                        GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_EMAIL='test@example.invalid')
        for key in ('BASH_ENV', 'ZDOTDIR', 'GIT_DIR', 'GIT_WORK_TREE'):
            self.env.pop(key, None)

    def git(self, *args):
        return subprocess.check_output([GIT, *args], env=self.env, text=True).strip()

    def clone(self, origin, destination, revision):
        return subprocess.run(['/bin/bash', '-eu', '-c',
                               'source "$1"; clone_pinned "$2" "$3" "$4"',
                               'test', str(ROOT / 'scripts/sources.sh'),
                               str(origin), str(destination), revision],
                              env=self.env, capture_output=True, text=True)

    def origin(self):
        origin = self.work / 'origin'
        self.git('init', '-q', str(origin))
        (origin / 'payload').write_text('pinned content')
        self.git('-C', str(origin), 'add', 'payload')
        self.git('-C', str(origin), 'commit', '-qm', 'selected revision')
        pin = self.git('-C', str(origin), 'rev-parse', 'HEAD')
        (origin / 'payload').write_text('new unselected content')
        self.git('-C', str(origin), 'commit', '-qam', 'moving branch')
        return origin, pin

    def test_pinned_clone_uses_selected_commit_and_preserves_local_edits(self):
        origin, pin = self.origin()
        destination = self.home / 'plugin with spaces'
        result = self.clone(origin, destination, pin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((destination / 'payload').read_text(), 'pinned content')
        self.assertEqual(self.git('-C', str(destination), 'rev-parse', 'HEAD'), pin)
        detached = subprocess.run([GIT, '-C', str(destination), 'symbolic-ref', '-q', 'HEAD'],
                                  env=self.env, capture_output=True)
        self.assertNotEqual(detached.returncode, 0)
        (destination / 'payload').write_text('local edits')
        latest = self.git('-C', str(origin), 'rev-parse', 'HEAD')
        rerun = self.clone(origin, destination, latest)
        self.assertEqual(rerun.returncode, 0, rerun.stderr)
        self.assertIn('preserving existing checkout', rerun.stderr)
        self.assertEqual((destination / 'payload').read_text(), 'local edits')
        self.assertEqual(self.git('-C', str(destination), 'rev-parse', 'HEAD'), pin)

    def test_unavailable_or_invalid_pin_never_publishes_a_checkout(self):
        origin, _ = self.origin()
        destination = self.home / 'plugin'
        for revision in ('0' * 40, 'master', '--help'):
            with self.subTest(revision=revision):
                result = self.clone(origin, destination, revision)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(destination.exists())
                self.assertFalse(list(self.home.glob('.dogfiles-source-*')))

    def test_pinned_clone_rejects_destination_conflicts(self):
        origin, pin = self.origin()
        destination = self.home / 'plugin'
        destination.symlink_to(origin, target_is_directory=True)
        # An existing checkout symlink is preserved, including its target.
        result = self.clone(origin, destination, pin)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(destination.is_symlink())
        destination.unlink()
        destination.write_text('keep this')
        result = self.clone(origin, destination, pin)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(destination.read_text(), 'keep this')

    @unittest.skipUnless(ZSH, 'Zsh is unavailable')
    def test_shell_startup_rejects_project_executables_and_old_relative_path(self):
        project = self.work / 'untrusted project'
        project.mkdir()
        marker = self.work / 'untrusted-code-ran'
        trusted = self.home / '.local/bin'
        trusted.mkdir(parents=True)
        for directory in (project / 'bin', project / 'node_modules/.bin', project):
            directory.mkdir(parents=True, exist_ok=True)
            for name in ('rbenv', 'pyenv', 'brew', 'uname'):
                executable = directory / name
                executable.write_text('#!/bin/sh\nprintf ran >> "$MARKER"\n')
                executable.chmod(0o755)
        for name in ('rbenv', 'pyenv'):
            executable = trusted / name
            executable.write_text('#!/bin/sh\nprintf "true\\n"\n')
            executable.chmod(0o755)
        # Do not consult the development host's Homebrew installation.
        source = (ROOT / 'conf/zshrc').read_text()
        for prefix in ('/opt/homebrew/bin/brew', '/usr/local/bin/brew'):
            source = source.replace(prefix, str(self.work / 'absent-brew'))
        zshrc = self.work / 'zshrc'
        zshrc.write_text(source)
        omz = self.home / '.oh-my-zsh'
        omz.mkdir()
        (omz / 'oh-my-zsh.sh').write_text('''
[[ ${ZSH_DISABLE_COMPFIX:-} != true ]] || exit 17
zstyle -s ':omz:update' mode update_mode
[[ $update_mode == disabled ]] || exit 18
''')
        env = dict(self.env, PATH='./bin:./node_modules/.bin:.:relative::/usr/bin:/bin',
                   MARKER=str(marker), ZSH_DISABLE_COMPFIX='true')
        result = subprocess.run([ZSH, '-dfc', 'source "$1"; print -rl -- $path',
                                 'test', str(zshrc)], cwd=project, env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists(), result.stdout + result.stderr)
        self.assertTrue(all(part.startswith('/') for part in result.stdout.splitlines()))
        self.assertIn(str(trusted), result.stdout)

    def test_terminal_configs_disallow_clipboard_reads(self):
        import tomllib
        for relative in ('conf/alacritty.toml', 'omarchy/config/alacritty/alacritty.toml'):
            with self.subTest(config=relative):
                settings = tomllib.loads((ROOT / relative).read_text())
                self.assertEqual(settings['terminal']['osc52'], 'OnlyCopy')

    def test_all_tmux_plugins_have_full_commit_pins(self):
        entries = re.findall(r"^set -g @plugin '([^']+)'", (ROOT / 'conf/tmux.conf').read_text(), re.M)
        self.assertTrue(entries)
        for entry in entries:
            self.assertRegex(entry, r'^[\w.-]+/[\w.-]+#[0-9a-f]{40}$')


if __name__ == '__main__':
    unittest.main()

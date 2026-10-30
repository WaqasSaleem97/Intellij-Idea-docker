import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copyfile(REPO / 'resources.sh', self.root / 'resources.sh')
        self.original = ('PUID=1000\nWEBTOP_USER=admin\nWEBTOP_PASSWORD=DemoPassword123\n'
                         'IDEA_HEAP_MB=1536\nIDEA_CPU_LIMIT=3.60\n'
                         'IDEA_MEMORY_LIMIT=21574m\nIDEA_MEMORY_SWAP_LIMIT=21574m\n')
        (self.root / '.env').write_text(self.original)
        binary = self.root / 'bin'
        binary.mkdir()
        docker = binary / 'docker'
        docker.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['MOCK_CALLS'], 'a') as output:
    output.write(json.dumps(args)+'\\n')
if args[0]=='info':
    print(os.environ.get('MOCK_RESOURCES','4 25165824000 linux'))
elif args[0]=='update' and os.environ.get('MOCK_UPDATE_FAIL')=='1':
    raise SystemExit(1)
elif args[0]=='compose' and 'ps' in args:
    print(os.environ.get('MOCK_CONTAINER','container123'))
''')
        docker.chmod(0o755)
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'],
                        MOCK_CALLS=str(self.root / 'calls.jsonl'))

    def run_script(self, *args, **environment):
        return subprocess.run(['bash', 'resources.sh', *args], cwd=self.root,
                              env=dict(self.env, **environment), capture_output=True, text=True)

    def values(self):
        return dict(line.split('=', 1) for line in (self.root / '.env').read_text().splitlines())

    def test_default_ninety_percent_and_credentials(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        values = self.values()
        self.assertEqual(values['IDEA_CPU_LIMIT'], '3.60')
        self.assertEqual(values['IDEA_MEMORY_LIMIT'], '21600m')
        self.assertEqual(values['IDEA_MEMORY_SWAP_LIMIT'], '21600m')
        self.assertEqual(values['WEBTOP_PASSWORD'], 'DemoPassword123')
        self.assertEqual(values['IDEA_HEAP_MB'], '1536')
        self.assertEqual((self.root / '.env').stat().st_mode & 0o777, 0o600)
        self.assertNotIn('DemoPassword123', result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.root / 'calls.jsonl').read_text().splitlines()]
        self.assertIn(['update', '--cpus', '3.60', '--memory', '21600m',
                       '--memory-swap', '21600m', 'container123'], calls)
        self.assertFalse(any('up' in call or 'restart' in call for call in calls))

    def test_small_host_also_uses_ninety_percent(self):
        result = self.run_script('--configure-only', MOCK_RESOURCES='2 4294967296 linux')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.values()['IDEA_CPU_LIMIT'], '1.80')
        self.assertEqual(self.values()['IDEA_MEMORY_LIMIT'], '3686m')
        self.assertNotIn('update', (self.root / 'calls.jsonl').read_text())

    def test_performance_alias_keeps_ninety_percent(self):
        result = self.run_script('--performance', '--configure-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.values()['IDEA_CPU_LIMIT'], '3.60')
        self.assertEqual(self.values()['IDEA_MEMORY_LIMIT'], '21600m')

    def test_failed_update_preserves_env(self):
        result = self.run_script(MOCK_UPDATE_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / '.env').read_text(), self.original)

    def test_invalid_totals_and_removed_light_flag_preserve_env(self):
        for arguments, environment in [((), {'MOCK_RESOURCES': '2 1048576 linux'}),
                                       (('--light',), {})]:
            result = self.run_script(*arguments, **environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((self.root / '.env').read_text(), self.original)

    def test_repeat_update_is_idempotent(self):
        self.assertEqual(self.run_script('--configure-only').returncode, 0)
        first = (self.root / '.env').read_text()
        self.assertEqual(self.run_script('--configure-only').returncode, 0)
        self.assertEqual((self.root / '.env').read_text(), first)


    def test_setup_migrates_the_old_light_configuration(self):
        # Run the unmodified setup logic in a disposable directory. Only bypass
        # its normal-user guard in this copy when the test runner itself is root.
        setup = (REPO / 'setup.sh').read_text()
        if os.geteuid() == 0:
            setup = setup.replace('if (( EUID == 0 )); then', 'if false; then', 1)
        (self.root / 'setup.sh').write_text(setup)
        (self.root / '.env').write_text(self.original.replace('IDEA_CPU_LIMIT=3.60', 'IDEA_CPU_LIMIT=2.00')
                                      .replace('21574m', '4096m') + 'IDEA_RESOURCE_PROFILE=light\n')
        result = subprocess.run(['bash', 'setup.sh'], cwd=self.root, env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        values = self.values()
        self.assertEqual(values['IDEA_CPU_LIMIT'], '3.60')
        self.assertEqual(values['IDEA_MEMORY_LIMIT'], '21600m')
        self.assertEqual(values['IDEA_RESOURCE_PROFILE'], 'performance')
        self.assertEqual(values['WEBTOP_PASSWORD'], 'DemoPassword123')
        self.assertEqual(values['IDEA_HEAP_MB'], '1536')
        self.assertNotIn('DemoPassword123', result.stdout + result.stderr)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin_dir = self.root / 'ide/bin'
        self.bin_dir.mkdir(parents=True)
        self.vendor_options = '-Xms1024m\n-Xmx2048m\n-Dvendor.option=true\n'
        (self.bin_dir / 'idea64.vmoptions').write_text(self.vendor_options)
        executable = self.bin_dir / 'idea.sh'
        executable.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
custom=os.environ.get('IDEA_VM_OPTIONS')
options=Path(custom) if custom else Path(__file__).with_name('idea64.vmoptions')
Path(os.environ['MOCK_LAUNCH_FILE']).write_text(json.dumps({
    'options':options.read_text(),'args':sys.argv[1:],'custom':bool(custom)}))
''')
        executable.chmod(0o755)
        self.env = dict(os.environ, IDEA_INSTALL_DIR=str(self.root / 'ide'),
                        XDG_CACHE_HOME=str(self.root / 'cache'),
                        MOCK_LAUNCH_FILE=str(self.root / 'launch.json'))
        self.env.pop('IDEA_VM_OPTIONS', None)
        self.env.pop('IDEA_HEAP_MB', None)

    def run_launcher(self, **environment):
        return subprocess.run(['bash', str(REPO / 'idea-launcher.sh'), 'project with spaces'],
                              env=dict(self.env, **environment), capture_output=True, text=True)

    def test_default_keeps_vendor_options_even_with_old_managed_cache(self):
        cache = self.root / 'cache/intellij-docker/idea64.vmoptions'
        cache.parent.mkdir(parents=True)
        cache.write_text('-Xmx1024m\n')
        for environment in [{}, {'IDEA_HEAP_MB': ''}]:
            result = self.run_launcher(**environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            launch = json.loads((self.root / 'launch.json').read_text())
            self.assertEqual(launch['args'], ['project with spaces'])
            self.assertEqual(launch['options'], self.vendor_options)
            self.assertFalse(launch['custom'])
        self.assertEqual((self.bin_dir / 'idea64.vmoptions').read_text(), self.vendor_options)

    def test_custom_heap_and_explicit_options(self):
        self.assertEqual(self.run_launcher(IDEA_HEAP_MB='1536').returncode, 0)
        launch = json.loads((self.root / 'launch.json').read_text())
        self.assertIn('-Xmx1536m\n', launch['options'])
        self.assertIn('-Dvendor.option=true\n', launch['options'])
        self.assertTrue(launch['custom'])
        options = self.root / 'custom.vmoptions'
        options.write_text('-Xmx1700m\n')
        self.assertEqual(self.run_launcher(IDEA_VM_OPTIONS=str(options)).returncode, 0)
        self.assertEqual(json.loads((self.root / 'launch.json').read_text())['options'], '-Xmx1700m\n')

    def test_invalid_heap_is_rejected(self):
        result = self.run_launcher(IDEA_HEAP_MB='1024;echo BAD')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'launch.json').exists())


if __name__ == '__main__':
    unittest.main()

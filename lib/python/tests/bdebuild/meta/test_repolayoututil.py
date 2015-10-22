import unittest
import json
import os

try:
    from cStringIO import StringIO
except:
    from io import StringIO

from bdebuild.meta import repolayout
from bdebuild.meta import repolayoututil


class TestRepoLayout(unittest.TestCase):

    def setUp(self):
        self.repo_root_one = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), 'repos', 'one')
        self.repo_root_two = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), 'repos', 'two')

    def test_get_repo_layout(self):
        value, config_path = repolayoututil.get_repo_layout(self.repo_root_one)
        exp_value = repolayout.RepoLayout()
        exp_value.group_dirs = ['groups', 'enterprise', 'wrappers']
        exp_value.app_package_dirs = ['applications']
        exp_value.stand_alone_package_dirs = ['adapters', 'standalones']
        exp_value.third_party_package_dirs = ['thirdparty', 'third-party']
        exp_value.group_abs_dirs = []
        self.assertEqual(value, exp_value)
        self.assertEqual(config_path, None)

        value, config_path = repolayoututil.get_repo_layout(self.repo_root_two)
        exp_value = repolayout.RepoLayout()
        exp_value.group_dirs = ['groups1']
        exp_value.app_package_dirs = ['apps1']
        exp_value.stand_alone_package_dirs = ['sap1', 'sap2']
        exp_value.third_party_package_dirs = []
        exp_value.group_abs_dirs = ['groupabs1']
        self.assertEqual(value, exp_value)
        self.assertEqual(config_path,
                         os.path.join(self.repo_root_two, '.bdelayoutconfig'))

    def test_write_repo_layout_to_json(self):
        out = StringIO()
        repo_layout = repolayout.RepoLayout()
        repo_layout.group_dirs = ['groups1', 'groups2']
        repo_layout.app_package_dirs = ['apps1', 'apps2']
        repo_layout.stand_alone_package_dirs = ['sap1', 'sap2']
        repo_layout.third_party_package_dirs = ['tpp1', 'tpp2']
        repo_layout.group_abs_dirs = ['groupabs1', 'groupabs2']

        repolayoututil.write_repo_layout_to_json(out, repo_layout)

        exp_value = {
            'group_dirs': ['groups1', 'groups2'],
            'app_package_dirs': ['apps1', 'apps2'],
            'stand_alone_package_dirs': ['sap1', 'sap2'],
            'third_party_package_dirs': ['tpp1', 'tpp2'],
            'group_abs_dirs': ['groupabs1', 'groupabs2']
        }

        self.assertEqual(json.dumps(exp_value), out.getvalue())

    def test_parse_repo_layout_from_json(self):

        exp_value = {
            'group_dirs': ['groups1', 'groups2'],
            'app_package_dirs': ['apps1', 'apps2'],
            'stand_alone_package_dirs': ['sap1', 'sap2'],
            'third_party_package_dirs': ['tpp1', 'tpp2'],
            'group_abs_dirs': ['groupabs1', 'groupabs2']
        }
        test_input = StringIO(json.dumps(exp_value))

        value = repolayoututil.parse_repo_layout_from_json(test_input)

        exp_value = repolayout.RepoLayout()
        exp_value.group_dirs = ['groups1', 'groups2']
        exp_value.app_package_dirs = ['apps1', 'apps2']
        exp_value.stand_alone_package_dirs = ['sap1', 'sap2']
        exp_value.third_party_package_dirs = ['tpp1', 'tpp2']
        exp_value.group_abs_dirs = ['groupabs1', 'groupabs2']

        self.assertEqual(value, exp_value)


if __name__ == '__main__':
    unittest.main()

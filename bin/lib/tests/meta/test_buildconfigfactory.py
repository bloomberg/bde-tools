import os
import unittest

from bdebld.meta import buildconfigfactory
from bdebld.meta import buildflagsparser
from bdebld.meta import options
from bdebld.meta import optionsparser
from bdebld.meta import repocontextloader


class TestBuildConfig(unittest.TestCase):
    def setUp(self):
        repos_path = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), 'repos')
        self.repo_root = os.path.join(repos_path, 'one')

        self.cap_repo_root = os.path.join(repos_path, 'two')

        self.flags_parser = buildflagsparser.BuildFlagsParser(
            '-Wl,-Bdynamic', '-Wl,-Bstatic', '-l([^ =]+)', '-L([^ =]+)',
            '-I([^ =]+)', '-D')

        default_rules_path = os.path.join(repos_path, 'repo_test_def.opts')
        with open(default_rules_path) as f:
            parser = optionsparser.OptionsParser(f)
            parser.parse()
            self.default_rules = parser.option_rules

    def test_cap(self):
        loader = repocontextloader.RepoContextLoader(self.cap_repo_root)
        loader.load()
        repo_context = loader.repo_context

        build_config = buildconfigfactory.make_build_config(
            repo_context,
            self.flags_parser,
            options.Uplid.from_str('unix-linux-x86_64-3.2.0-gcc-4.7.2'),
            options.Ufid.from_str('dbg_mt_exc'), self.default_rules)

        self.assertEqual(set(p for p in build_config.normal_packages),
                         set(['gr1p1']))

        self.assertEqual(set(g for g in build_config.package_groups),
                         set(['gr1']))

    def test_make_repo_build_config(self):
        loader = repocontextloader.RepoContextLoader(self.repo_root)
        loader.load()
        repo_context = loader.repo_context

        buildconfigfactory.make_build_config(
            repo_context,
            self.flags_parser,
            options.Uplid.from_str('unix-linux-x86_64-3.2.0-gcc-4.7.2'),
            options.Ufid.from_str('dbg_mt_exc'), self.default_rules)


if __name__ == '__main__':
    unittest.main()

# -----------------------------------------------------------------------------
# Copyright 2015 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE -----------------------------------

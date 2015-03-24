import unittest

from bdebld.meta import options
from bdebld.meta import optionsutil


class TestOptionsUtil(unittest.TestCase):

    def test_get_default_option_rules(self):
        rules = optionsutil.get_default_option_rules()

        # We care that the function was able to load the file, not that that
        # the parser correctly loaded the file, which is tested
        # elsewhere. Therefore, we just verify that the list contains one known
        # rule.
        has_flag = False
        for rule in rules:
            if rule.key == 'COMPONENT_BDEBUILD_CXXFLAGS':
                has_flag = True

        self.assertTrue(has_flag)

    def test_match_ufid(self):
        # format:
        # { configure ufid: ((matched masks), (unmatched masks)) }
        ufid_masks = {
            'dbg_mt_exc': (('dbg', '_', 'mt', 'dbg_mt', 'dbg_mt_exc'),
                           ('opt', 'opt_mt', 'opt_mt_exc')),
            'opt_mt_safe': (('opt', '_', 'mt', 'opt_mt_safe'),
                            ('opt_mt_exc', 'safe2')),
        }

        for ufid_str in ufid_masks:
            masks = ufid_masks[ufid_str]
            matched_masks = masks[0]
            unmatched_masks = masks[1]

            ufid = options.Ufid.from_str(ufid_str)
            for mask_str in matched_masks:
                mask = options.Ufid.from_str(mask_str)
                self.assertTrue(optionsutil.match_ufid(ufid, mask),
                                'ufid: %s mask: %s' % (ufid, mask))

            for mask_str in unmatched_masks:
                mask = options.Ufid.from_str(mask_str)
                self.assertFalse(optionsutil.match_ufid(ufid, mask),
                                 'ufid: %s mask: %s' % (ufid, mask))

    def test_match_uplid(self):
        # format:
        # { configure uplid: ((matched masks), (unmatched masks)) }
        uplid_masks = {
            'unix-linux-x86-3.2.0-gcc-4.7.2':
            (('unix',
              'unix-',
              'unix-*-x86',
              'unix-linux-x86-3.2.0',
              'unix-linux-x86-3.1.9',
              'unix-linux-x86-2.9.9',
              'unix-linux-x86-3.2.0-gcc',
              'unix-linux-x86-3.2.0-gcc-4.7.2',
              'unix-linux-x86-3.2.0-gcc-4.7.1',
              'unix-linux-x86-3.2.0-gcc-4.6.2',
              'unix-linux-x86-3.2.0-gcc-3.7.2'),
             ('windows',
              'unix-sunos',
              'unix-linux-pcc',
              'unix-linux-x86-3.2.1',
              'unix-linux-x86-3.3.0',
              'unix-linux-x86-4.0.0',
              'unix-linux-x86-3.2.0-clang',
              'unix-linux-x86-3.2.0-gcc-4.7.3',
              'unix-linux-x86-3.2.0-gcc-4.10.1',
              'unix-linux-x86-3.2.0-gcc-4.7.2.3',
              'unix-linux-x86-3.2.0-gcc-5.1.9')),
            'unix-linux-x86-3.2.0-gcc-clang':
            (('unix',
              'unix-*-x86',
              'unix-linux-x86-3.2.0',
              'unix-linux-x86-3.2.0-gcc-clang'),
             ('windows',
              'unix-linux-x86-3.2.0-gcc-5.1.9'))
        }

        for uplid_str in uplid_masks:
            masks = uplid_masks[uplid_str]
            matched_masks = masks[0]
            unmatched_masks = masks[1]

            uplid = options.Uplid.from_str(uplid_str)
            for mask_str in matched_masks:
                mask = options.Uplid.from_str(mask_str)
                self.assertTrue(optionsutil.match_uplid(uplid, mask),
                                'uplid: %s mask: %s' % (uplid, mask))

            for mask_str in unmatched_masks:
                mask = options.Uplid.from_str(mask_str)
                self.assertFalse(optionsutil.match_uplid(uplid, mask),
                                 'uplid: %s mask: %s' % (uplid, mask))

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

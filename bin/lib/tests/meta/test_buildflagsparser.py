import unittest

from bdebld.meta import buildflagsparser


class TestBuildFlagsParser(unittest.TestCase):
    def setUp(self):
        self.parser = buildflagsparser.BuildFlagsParser('-Wl,-Bdynamic',
                                                        '-Wl,-Bstatic',
                                                        '-l([^ =]+)',
                                                        '-L([^ =]+)',
                                                        '-I([^ =]+)', '-D')

    def test_get_export_cflags(self):
        cflags = [
            '-DBDE_BUILD_TARGET_DBG',
            '-DBDE_BUILD_TARGET_EXC',
            '-DBDE_BUILD_TARGET_MT',
            '-I/test/bsl-oss/groups/bsl/bsl+stdhdrs',
            '-I/test/bsl-oss/groups/extras',
            '-pipe', '--param',
            '-D_REENTRANT'
        ]
        exp_export_cflags = [
            '-DBDE_BUILD_TARGET_DBG',
            '-DBDE_BUILD_TARGET_EXC',
            '-DBDE_BUILD_TARGET_MT',
            '-D_REENTRANT'
        ]

        export_cflags = self.parser.get_export_cflags(cflags)
        self.assertEqual(export_cflags, exp_export_cflags)

    def test_partition_cflags(self):
        cflags = [
            '-DBDE_BUILD_TARGET_DBG',
            '-DBDE_BUILD_TARGET_EXC',
            '-DBDE_BUILD_TARGET_MT',
            '-I/home/test/bsl-oss/groups/bsl/bsl+stdhdrs',
            '-pipe', '--param',
            '-I/home/test/extras',
            '-D_REENTRANT'
        ]
        exp_include_paths = [
            '/home/test/bsl-oss/groups/bsl/bsl+stdhdrs',
            '/home/test/extras'
        ]
        exp_flags = [
            '-DBDE_BUILD_TARGET_DBG',
            '-DBDE_BUILD_TARGET_EXC',
            '-DBDE_BUILD_TARGET_MT',
            '-pipe', '--param',
            '-D_REENTRANT'
        ]
        include_paths, flags = self.parser.partition_cflags(cflags)
        self.assertEqual(exp_include_paths, include_paths)
        self.assertEqual(exp_flags, flags)

    def test_partition_linkflags(self):
        linkflags = [
            '-m64',
            '-mtune=opteron',
            '-fPIC',
            '-L/bbsrc/bde/registry/lroot/lib/',
            '-lpthread',
            '-lrt',
            '-Wl,-rpath',
            '-Wl,/opt/swt/install/gcc-4.7.2/lib64',
            '-Wl,-Bstatic',
            '-lbde'
        ]
        exp_stlibs = ['bde']
        exp_libs = ['pthread', 'rt']
        exp_lib_paths = ['/bbsrc/bde/registry/lroot/lib/']
        exp_flags = [
            '-m64',
            '-mtune=opteron',
            '-fPIC',
            '-Wl,-rpath',
            '-Wl,/opt/swt/install/gcc-4.7.2/lib64'
        ]
        stlibs, libs, lib_paths, flags = self.parser.partition_linkflags(
            linkflags)

        self.assertEqual(exp_stlibs, stlibs)
        self.assertEqual(exp_libs, libs)
        self.assertEqual(exp_lib_paths, lib_paths)
        self.assertEqual(exp_flags, flags)


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

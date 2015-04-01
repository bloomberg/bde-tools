import unittest

try:
    from cStringIO import StringIO
except:
    from io import StringIO

from bdebld.meta import optiontypes
from bdebld.setenv import compilerinfo


class TestRepoLayout(unittest.TestCase):

    def setUp(self):
        self.config_str = """
[
    {
        "hostname": "m2",
        "uplid": "unix-linux-",
        "compilers": [
            {
                "type": "gcc",
                "c_path": "/usr/bin/gcc",
                "cxx_path": "/usr/bin/g++",
                "version": "4.1.2"
            }
        ]
    },
    {
        "hostname": ".*",
        "uplid": "unix-linux-",
        "compilers": [
            {
                "type": "gcc",
                "c_path": "/opt/swt/install/gcc-4.9.2/bin/gcc",
                "cxx_path": "/opt/swt/install/gcc-4.9.2/bin/g++",
                "version": "4.9.2"
            },
            {
                "type": "gcc",
                "c_path": "/opt/swt/install/gcc-4.3.5/bin/gcc",
                "cxx_path": "/opt/swt/install/gcc-4.3.5/bin/g++",
                "version": "4.3.5"
            },
            {
                "type": "gcc",
                "c_path": "/usr/bin/gcc",
                "cxx_path": "/usr/bin/g++",
                "version": "4.1.2"
            }
        ]
    },
    {
        "hostname": ".*",
        "uplid": "unix-aix-",
        "compilers": [
            {
                "type": "xlc",
                "version": "11.1",
                "c_path": "/a/b/c/xlc_r-11.1",
                "cxx_path": "/d/e/f/xlC_r-11.1"
            },
            {
                "type": "xlc",
                "version": "12.1",
                "c_path": "/a/b/c/xlc_r-12.1",
                "cxx_path": "/d/e/f/xlC_r-12.1"
            },
            {
                "type": "xlc",
                "version": "12.2",
                "flags": "-qpath=/test/test",
                "c_path": "/a/b/c/xlc_r-12.2",
                "cxx_path": "/d/e/f/xlC_r-12.2"
            }
        ]
    }
]
        """
        self.config_file = StringIO(self.config_str)

    def test_get_compilerinfos1(self):

        uplid = optiontypes.Uplid('unix', 'linux', '*', '*', '*', '*')
        infos = compilerinfo.get_compilerinfos('m2', uplid,
                                               self.config_file)

        exp_infos = [
            compilerinfo.CompilerInfo('gcc', '4.1.2',
                                      '/usr/bin/gcc',
                                      '/usr/bin/g++')
        ]

        self.assertEqual(infos, exp_infos)

    def test_get_compilerinfos2(self):

        uplid = optiontypes.Uplid('unix', 'linux', '*', '*', '*', '*')
        infos = compilerinfo.get_compilerinfos('m1', uplid,
                                               self.config_file)

        exp_infos = [
            compilerinfo.CompilerInfo('gcc', '4.9.2',
                                      '/opt/swt/install/gcc-4.9.2/bin/gcc',
                                      '/opt/swt/install/gcc-4.9.2/bin/g++'),
            compilerinfo.CompilerInfo('gcc', '4.3.5',
                                      '/opt/swt/install/gcc-4.3.5/bin/gcc',
                                      '/opt/swt/install/gcc-4.3.5/bin/g++'),
            compilerinfo.CompilerInfo('gcc', '4.1.2',
                                      '/usr/bin/gcc',
                                      '/usr/bin/g++')
        ]

        self.assertEqual(infos, exp_infos)

    def test_get_compilerinfos3(self):

        uplid = optiontypes.Uplid('unix', 'aix', '*', '*', '*', '*')
        infos = compilerinfo.get_compilerinfos('blahblah', uplid,
                                               self.config_file)

        exp_infos = [
            compilerinfo.CompilerInfo('xlc', '11.1',
                                      '/a/b/c/xlc_r-11.1',
                                      '/d/e/f/xlC_r-11.1'),
            compilerinfo.CompilerInfo('xlc', '12.1',
                                      '/a/b/c/xlc_r-12.1',
                                      '/d/e/f/xlC_r-12.1'),
            compilerinfo.CompilerInfo('xlc', '12.2',
                                      '/a/b/c/xlc_r-12.2',
                                      '/d/e/f/xlC_r-12.2',
                                      '-qpath=/test/test')
        ]

        self.assertEqual(infos, exp_infos)

    def test_get_compilerinfo4(self):
        uplid = optiontypes.Uplid('unix', 'windows', '*', '*', '*', '*')
        infos = compilerinfo.get_compilerinfos('blahblah', uplid,
                                               self.config_file)
        self.assertEqual(infos, None)

    def test_compile_info(self):
        info = compilerinfo.CompilerInfo('gcc', '4.1.2',
                                         '/usr/bin/gcc',
                                         '/usr/bin/g++')

        self.assertEqual(info.key(), 'gcc-4.1.2')
        self.assertEqual(info.description(), 'gcc-4.1.2')


if __name__ == '__main__':
    unittest.main()

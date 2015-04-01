pykg-config
==============================================================================

A pkg-config replacement.

pykg-config is an input- and output-compatible implementation of pkg-config
written in Python for greater ease of portability. It is designed to be a
drop-in replacement: command lines that work for pkg-config should produce
identical output from pykg-config.


Requirements
------------

pykg-config uses the new string formatting operations that were introduced in
Python 2.6. It will not function with an earlier version of Python. It has been
been tested with Python 2.6, 2.7, 3.1, 3.2, 3.3, and 3.4.


Installation
------------

There are several methods of installation available:

1. Download the source (either from the repository or a source archive),
extract it somewhere, and run pykg-config from that directory.

2. Download the source (either from the repository or a source archive),
extract it somewhere, and use distutils to install it into your Python
distribution:

 a. Extract the source, e.g. to a directory C:\pykg-config\
 b. Run setup.py to install pykg-config to your default Python installation:

    C:\pykg-config\> python setup.py install

 c. If necessary, set environment variables. These should be set by default,
    but if not you will need to set them yourself. On Windows, you will need to
    ensure that your Python site-packages directory is in the PYTHONPATH
    variable and the Python scripts directory is in the PATH variable.
    Typically, these will be something like C:\Python26\Lib\site-packages\
    and C:\Python26\Scripts\, respectively (assuming Python 2.6 installed in
    C:\Python26\).

3. Use the Windows installer. This will perform the same job as running
setup.py (see #2), but saves opening a command prompt. You may still need to
add paths to your environment variables

Under Unix-like operating systems, if you do not already have the original
pkg-config available, you should create a symbolic link to pykg-config. This
allows build system scripts that look for pkg-config to find pykg-config
without modification. Place this link somewhere in your path. For example,
assuming pykg-config was installed to /usr/local:

$ ln -s /usr/local/bin/pykg-config.py /usr/local/bin/pkg-config

On Windows, a batch file, pkg-config.bat, is installed along with pykg-config
into the Scripts directory. This should function as a drop-in replacement for
pkg-config in build system scripts, such as CMake's UsePkgConfig.cmake module,
provided that this directory is in your PATH environment variable.


Package paths
-------------

Paths are searched in this order:

1. All paths listed in the PKG_CONFIG_PATH environment variable.
2. All paths listed in the PKG_CONFIG_LIBDIR environment variable, if set.
3. (Windows only) The registry keys
   HKEY_CURRENT_USER\Software\pkg-config\PKG_CONFIG_PATH and
   HKEY_LOCAL_MACHINE\Software\pkg-config\PKG_CONFIG_PATH. For both of these,
   paths should be set as values of the key. The value name has no meaning to
   pkg-config; use it for your own reference. The value type must be REG_SZ (a
   string), and the data should be a single path.
4. All paths listed in the --with-pc-path option when setup.py is executed, if
   set. Otherwise, all paths in ${prefix}/lib[64]/pkgconfig/ and
   ${prefix}/share/pkgconfig/, where ${prefix} is a system prefix (typically
   this will be /usr/).

If you are using Windows, I recommend you add paths to PKG_CONFIG_PATH. This is
the easiest place to add paths to and the easiest to check for errors. Google
can tell you how to add an environment variable in Windows. Unfortunately,
because Windows does not have a centralised directory structure, you will
probably have to add every package you install to this variable. If you are
lucky, some nice packages will do it when they are installed, but I haven't
yet seen one that does this.


Hard-coded package path
-----------------------

It is possible, when installing using setup.py, to specify a hard-coded list of
paths to be searched for .pc files. Use the following setup.py command to do
so:

  python setup.py build_py --with-pc-path=<desired paths here> install

The list of paths should be specified as a single string, with the paths
separated by a semi-colon (';') on Windows or a colon (':') on other platforms.


pkg-config (.pc) file things-to-watch-out-for
---------------------------------------------

The pkg-config format does not deal with spaces in values very well. If you
have an include or lib path with a space in it (common on Windows), pkg-config
will cheerfully treat up to the first space as an include or lib path, and
then ignore all remaining words. This is despite correctly parsing the file
with escaped spaces (the final value processing step is where it drops the
rest).

By contrast, pykg-config uses Python's shlex module to split values,
preserving things like escaped spaces. This is an advantage on Windows
(provided your .pc files properly escape their spaces), but does mean output
is incompatible with pkg-config.

In the interest of user-friendliness, on Windows, full compatibility is
_disabled_ by default (i.e. paths with escaped spaces are handled correctly).
On other platforms, full compatibility is _enabled_ by default. You can
manually turn it on or off using the --full-compatibility and
--less-compatibility switches.

The standard Windows path format (using \) does not play well with some build
systems, such as CMake. Fortunately, CMake correctly handles paths specified
using Unix-style separators (/), so if your .pc files specify their paths using
that format you shouldn't have any problems.

Miscellaneous notes
-------------------

1. Default target compiler

The CMake pkg-config module does not handle Microsoft Visual C++ style libdir
specifications (/libpath:). For this reason, even on Windows, the output
defaults to the standard non-MSVC-compatible format. You can change which style
is used with the --msvc-syntax and --no-msvc-syntax options.

2. Testing compatibility

The test script, test_compatibility.py, performs a set of unit tests in an
attempt to maintain compatibility with the version of pkg-config mentioned in
CORRESPONDING_VERSION in pykg-config.py. Executing it will run through all the
tests. If they all pass, pykg-config.py is producing the same output as the
pkg-config installed on your system.

3. Search prefix and system directories

pkg-config searchers in directories below a prefix that is defined at compile
time. Typically, this prefix will be /usr/lib/ or /usr/lib64/, depending on the
toolchain used to compile pkg-config. This path is then hard-coded into the
binary and cannot be changed at run-time. The only way to change it is by
recompiling pkg-config and forcing a different value for the system libpath
onto it.

This presents a problem for pykg-config. Checking the Python system prefix (via
sys.prefix) is not a guaranteed solution, as it is often different from the
libpath used by the compiler that builds pkg-config. While not much of a
problem for pykg-config's main target (Windows), in order to ensure
compatiblity it is best to try and meet this problem.

A nasty hack is used to try and fix this in the majority of cases. At startup,
pykg-config looks at the value of sys.path. It finds the first entry containing
'pythonxy.zip' (where x and y are the major and minor version numbers). If the
end of the containing directory name is '64', it assumes that the system is
running 64-bit libraries as the primary toolchain. This will cause paths such
as /usr/lib/ (which are created from the sys.prefix value) to turn into
/usr/lib64/.

You can test if the result is accurate for your system by ensuring that the
'test_print_errors_with_error' test will have an error caused by a package in
/usr/lib64 (see the comments for that test), then running
test_compatibility.py. If the error messages are the same (i.e. the test
passes), then the hack has worked.

5. Why?

Because building pkg-config for Windows in an easy-to-distribute, easy-to-use
way is a pain. The core functionality of pkg-config is simple and easy to
provide using Python (which provides several modules useful for such things as
parsing text files, which is what .pc files are).

It was also fun.


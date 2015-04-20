"""Utilities to load parts of a repository.
"""

import glob
import os
import re

from bdebld.common import blderror
from bdebld.common import sysutil
from bdebld.meta import repounits
from bdebld.meta import optionsparser


def load_package_group(path):
    """Load a package group.

    Args:
        path (str): Path to the root of the package group.

    Returns:
        PackageGroup
    """
    package_group = repounits.PackageGroup(path)
    package_group.mem = set(_load_lsv(
        os.path.join(package_group.path, 'group',
                     package_group.name + '.mem')))
    package_group.dep = set(_load_lsv(
        os.path.join(package_group.path, 'group',
                     package_group.name + '.dep')))

    package_group.opts = _load_opts(os.path.join(package_group.path, 'group',
                                                 package_group.name + '.opts'))
    package_group.defs = _load_opts(os.path.join(package_group.path, 'group',
                                                 package_group.name + '.defs'))
    package_group.cap = _load_opts(os.path.join(package_group.path, 'group',
                                                package_group.name + '.cap'))

    return package_group


def load_package(path, package_type):
    """Load a package.

    Args:
        path (str): Path to the root of the package.
        type_ (PackageType): The package type.

    Returns:
        A type derived from PackageBase
    """

    package = repounits.Package(path, package_type)
    package.mem = set(_load_lsv(
        os.path.join(package.path, 'package',
                     package.name + '.mem')))
    package.pub = set(_load_lsv(
        os.path.join(package.path, 'package',
                     package.name + '.pub')))
    package.dep = set(_load_lsv(
        os.path.join(package.path, 'package',
                     package.name + '.dep')))

    package.opts = _load_opts(os.path.join(package.path, 'package',
                                           package.name + '.opts'))
    package.defs = _load_opts(os.path.join(package.path, 'package',
                                           package.name + '.defs'))
    package.cap = _load_opts(os.path.join(package.path, 'package',
                                          package.name + '.cap'))

    dums_path = os.path.join(package.path, 'package', package.name + '.dums')
    package.has_dums = os.path.isfile(dums_path)

    if package.type_ == repounits.PackageType.PACKAGE_PLUS:
        package.pt_extras = _load_plus_package_extras(package)
    else:
        for component_name in sorted(package.mem):
            component = load_component(component_name, package.path)
            package.components.append(component)

    return package


def _load_plus_package_extras(package):
    """Load metadata of a "+" package.

    Args:
        package (Package): The plus package.

    Returns:
        PlusPackageExtras
    """

    def rps(l):
        return set([os.path.relpath(path, package.path) for path in l])

    extras = repounits.PlusPackageExtras()
    if len(package.pub) > 0:
        extras.headers = package.pub
    else:
        headers = glob.glob(os.path.join(package.path, '*.h'))
        headers.extend(glob.glob(os.path.join(package.path, '*.SUNWCCh')))
        headers.extend(glob.glob(os.path.join(package.path, '*/*.h')))
        headers.extend(glob.glob(os.path.join(package.path, '*/*.SUNWCCh')))

        extras.headers = rps(headers)

    extras.cpp_sources = rps(glob.glob(os.path.join(package.path, '*.cpp')))
    extras.cpp_tests = rps(glob.glob(os.path.join(package.path,
                                                  'test', '*.cpp')))
    extras.c_tests = rps(glob.glob(os.path.join(package.path, 'test', '*.c')))
    return extras


def load_component(name, package_path):
    """Load a component.

    Args:
        name (str): The name of the component.
        package_path (str): The path to the package containing the component.

    Returns:
        None
    """
    component = repounits.Component(name)
    base_path = os.path.join(package_path, component.name)
    header_path = base_path + '.h'
    cxx_path = base_path + '.cpp'
    c_path = base_path + '.c'

    if not os.path.isfile(header_path):
        raise blderror.MemError('%s does not exist' % header_path)

    if os.path.isfile(cxx_path):
        component.type_ = repounits.ComponentType.CXX
        test_path = base_path + '.t.cpp'
    elif os.path.isfile(c_path):
        component.type_ = repounits.ComponentType.C
        test_path = base_path + '.t.c'
    else:
        raise blderror.MemError('%s source file found for ' % header_path)

    component.has_test_driver = os.path.isfile(test_path)
    return component


def is_package_group_path(path):
    """Determine whether a path is the root of a package group.
    """
    group_name = os.path.basename(path)
    return os.path.isfile(os.path.join(path, 'group', group_name + '.mem'))


def is_package_path(path):
    """Determine whether a path is the root of a package.
    """
    package_name = os.path.basename(path)
    return os.path.isfile(os.path.join(path, 'package', package_name + '.mem'))


def is_third_party_path(path):
    """Determine whether a path is the root of a third party directory.
    """
    return os.path.isfile(os.path.join(path, 'wscript'))


def is_bde_repo_path(path):
    """Determine whether a path is the root of a BDE-style repo.
    """
    basename = os.path.basename(path)
    return basename not in ('build', '_build')


def _load_opts(path):
    """Load option rules from a file.
    """
    if os.path.isfile(path):
        return optionsparser.parse_option_rules_file(path)
    else:
        return []


REMOVE_COMMENT_RE = re.compile(r'^([^#]*)(#.*)?$')


def _load_lsv(path):
    """Load values from line separated file.

    Return the contents of the line separated file from the specified path.  If
    the path does not exist, return an empty array.
    """

    try:
        with open(path) as f:
            lines = f.readlines()
    except IOError:
        return []

    entries = []
    for line in lines:
        line = line.rstrip('\n')
        # Lines after "#LEGACY" are ignored and used for compatibility with
        # other internal legacy tools.
        if line == '#LEGACY':
            break
        entries.extend(REMOVE_COMMENT_RE.match(line).group(1).split())
    return entries


def get_uor_doc(uor):
    """Parse the mnemonic and description of a UOR from its doc file.

    Args:
        uor (Package or PackageGroup): The unit of release.

    Returns:
        UorDoc
    """
    name = uor.name
    doc_path = os.path.join(uor.path, 'doc', name + '.txt')

    try:
        with open(doc_path) as f:
            purpose = None
            mnemonic = None
            for line in f:
                if line.startswith('@PURPOSE'):
                    purpose = line.split(':')[1].strip()

                elif line.startswith('@MNEMONIC'):
                    mnemonic = line.split(':')[1].strip()

                if purpose and mnemonic:
                    return repounits.UorDoc(mnemonic, purpose)
    except:
        pass

    return repounits.UorDoc(name, 'N/A')


UOR_VERSIONS_CACHE = {}


def get_uor_version(uor, uors_map):
    """Try to get the version number of a UOR.

    Args:
        uor (Package or PackageGroup): The unit of release.
        uors_map (dict of str to uor): Map of name to uors in the repo.

    Returns:
        UorVersion
    """

    def _is_valid(version):
        return (sysutil.is_int_string(version.major) and
                sysutil.is_int_string(version.minor) and
                sysutil.is_int_string(version.patch))

    global UOR_VERSIONS_CACHE
    if uor.name in UOR_VERSIONS_CACHE:
        return UOR_VERSIONS_CACHE[uor.name]

    try:
        version = _get_uor_version_impl(uor)
        if _is_valid(version):
            UOR_VERSIONS_CACHE[uor.name] = version
            return version
    except:
        UOR_VERSIONS_CACHE[uor.name] = None
        return None

    ref_name = version.major.split('_')[0].lower()
    if uor.name != ref_name:
        if ref_name not in UOR_VERSIONS_CACHE:
            ref_version = _get_uor_version_impl(uors_map[ref_name])
            ref_version = ref_version if _is_valid(ref_version) else None
            UOR_VERSIONS_CACHE[ref_name] = ref_version

        version = UOR_VERSIONS_CACHE[ref_name]
    else:
        version = None

    UOR_VERSIONS_CACHE[uor.name] = version
    return version


def _get_uor_version_impl(uor):
    is_group = getattr(uor, 'components', None) is None

    if is_group:
        scm_path = os.path.join(uor.path, '%sscm' % uor.name)
        versiontag_path = os.path.join(scm_path,
                                       '%sscm_versiontag.h' % uor.name)
        if uor.name in ('bde', 'bsl'):
            version_path = os.path.join(scm_path,
                                        '%sscm_patchversion.h' % uor.name)
        else:
            version_path = os.path.join(scm_path,
                                        '%sscm_version.cpp' % uor.name)
    else:
        versiontag_path = os.path.join(uor.path, '%s_versiontag.h' % uor.name)
        version_path = os.path.join(uor.path, '%s_version.cpp' % uor.name)

    with open(versiontag_path) as f:
        versiontag_source = f.read()

    with open(version_path) as f:
        version_source = f.read()

    major_ver_re = re.compile(
        r'''^\s*#define\s+%s_VERSION_MAJOR\s+(\S+)\s*$''' %
        uor.name.upper(), re.MULTILINE)

    minor_ver_re = \
        re.compile(r'''^\s*#define\s+%s_VERSION_MINOR\s+(\S+)\s*$''' %
                   uor.name.upper(), re.MULTILINE)

    if uor.name in ('bde', 'bsl'):
        patch_ver_re = re.compile(
            r'''^\s*#define\s+%sSCM_PATCHVERSION_PATCH\s+(\S+)\s*$''' %
            uor.name.upper(), re.MULTILINE)
    else:
        patch_ver_re = re.compile(
            r'''^\s*#define\s+%s_VERSION_PATCH\s+(\S+)\s*$''' %
            uor.name.upper(), re.MULTILINE)

    major_ver = None
    minor_ver = None
    patch_ver = None

    m = major_ver_re.search(versiontag_source)
    if m:
        major_ver = m.group(1)

    m = minor_ver_re.search(versiontag_source)
    if m:
        minor_ver = m.group(1)

    m = patch_ver_re.search(version_source)
    if m:
        patch_ver = m.group(1)

    return repounits.UorVersion(major_ver, minor_ver, patch_ver)

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

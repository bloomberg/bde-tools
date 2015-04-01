"""Structures to describe a BDE-style repository.

This module defines types that represent the various structures along with
their associated meta data that compose a BDE-style respository.
"""

import os
import collections

from bdebld.common import mixins

UorDoc = collections.namedtuple('UorDoc', ['mnemonic', 'description'])

UorVersion = collections.namedtuple('UorVersion', ['major', 'minor', 'patch'])


class ComponentType(object):
    """This class enumerates over types of component.

    Enumerators:
       CXX: A C++ component.
       C: A C component.
    """
    CXX = 0,
    C = 1


class Component(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """This class represents a BDE-style component.

    Attributes:
        name (str): Name of the component.
        type_ (ComponentType): Type of this component (C or C++).
        has_test_driver (bool): Whether this component has a test driver.
    """

    def __init__(self, name):
        self.name = name
        self.type_ = ComponentType.CXX
        self.has_test_driver = True

    def header(self):
        return self.name + '.h'

    def source(self):
        if self.type_ == ComponentType.CXX:
            ext = '.cpp'
        else:
            ext = '.c'
        return self.name + ext

    def test_driver(self):
        if self.type_ == ComponentType.CXX:
            ext = '.t.cpp'
        else:
            ext = '.t.c'
        return self.name + ext


class PackageType(object):
    """This class enumerates over the types of packages.

    Enumerators:
        NORMAL: A regular package.
        PLUS: A special package that doesn't contain BDE-Style components.
        STAND_ALONE: A package that does not belong to a package group.
        APPLICATION: A stand-alone package that contains an application.
    """
    NORMAL = 0
    PLUS = 1
    STAND_ALONE = 2
    APPLICATION = 3


class Package(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """This class represents a BDE-style package.

    Attributes:
        name (str): Name of the package.
        path (str): Path to the root of the package.
        type_ (PackageType): Type of the package.
        doc (UorDoc): Relevant documentation.
        version (UorVersion): Version of the package.
        mem (set of str): Members of this package.
        dep (set of str): Dependencies of this package.
        opts (list of OptionRule): List of option rules representing build
            options.
        cap (list of OptionRule): List of option rules representing
            capabilities.
        has_dums (bool): Whether a dums file (containing symbols to dummy out)
            exists.
        components (set of Component): Components in this Package.
        pt_extras (PlusPackageExtras): Extra information for \
            "+" packages.
    """

    def __init__(self, path, type_):
        self.name = os.path.basename(path)
        self.path = path
        self.type_ = type_
        self.doc = None
        self.version = None
        self.mem = set()
        self.dep = set()
        self.pub = set()
        self.opts = []
        self.defs = []
        self.cap = []
        self.has_dums = False
        self.components = []
        self.pt_extras = None

    def is_stand_alone(self):
        return (self.type_ == PackageType.APPLICATION or
                self.type_ == PackageType.STAND_ALONE)


class PlusPackageExtras(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """This class represents the extra metadata of a plus package.

    Plus packages are packages having a name containing a '+'.  These packages
    do not behave like regular BDE packages in that they do not contain
    BDE-style components.

    The build behavior for these packages is that all source files in the root
    directory of the package are built into a library.  If a <package>.pub file
    exist, all files listed in the pub file are installed; otherwise, all .h
    and .SUNWCCh files in directories other than 'test' are installed.

    The test drivers for these packages are contained in the 'test' directory.
    They are ran a only a single time unlike BDE-style test drivers which gets
    run repeatedly with increasing test numbers.

    Attributes:
       headers (set of str): Header files that are exported.
       cpp_sources (set of str): C++ source files.
       cpp_tests (set of str): C++ test driver source files.
       c_tests (set of str): C test driver source files.
    """
    def __init__(self):
        self.headers = set()
        self.cpp_sources = set()
        self.cpp_tests = set()
        self.c_tests = set()


class ThirdPartyPackage(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """This class represents a third-party package.
    """
    def __init__(self, path):
        self.name = os.path.basename(path)
        self.path = path


class PackageGroup(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """This class represents a BDE-style package group.

    Attributes:
        name (str): Name of the package group.
        path (str): Path to the root of the package group.
        doc (UorDoc): Relevant documentation of the package group.
        version (UorVersion): Version of the package group.
        mem (set of str): List of packages belonging to this package group.
        dep (set of str): Dependencies of this package.
        opts (list of OptionRule): List of option rules representing build
            options.
        defs (list of OptionRule): List of option rules representing exported
            build options.
        cap (list of OptionRule): List of option rules representing
            capabilities.
    """

    def __init__(self, path):
        self.name = os.path.basename(path)
        self.path = path
        self.doc = None
        self.version = None
        self.mem = set()
        self.dep = set()
        self.opts = []
        self.defs = []
        self.cap = []

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

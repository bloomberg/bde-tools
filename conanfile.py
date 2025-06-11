# ***************************************************************
# This is an internal Bloomberg Conan recipe.                   *
# This recipe does not work outside of Bloomberg infrastructure *
# ***************************************************************

import os
from conan import ConanFile

from conan.tools.cmake import CMake

class Package(ConanFile):
    python_requires = "conan-dpkg-recipe/[>=0.22]@test/unstable"
    python_requires_extend = "conan-dpkg-recipe.CMakeModule"

    skip_unit_tests = True

    def init(self):
        super().init()
        self.dependency_ignore.append('python3.8')
        self.dependency_ignore.append('python3.12')

    def get_build_target(self) -> str | None:
        return None

    def get_install_components(self) -> list[str] | None:
        return [self.name]

    def package_info(self):
        if "bbs-cmake-module" == self.name:
            super().package_info()

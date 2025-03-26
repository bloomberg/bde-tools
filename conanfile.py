# ***************************************************************
# This is an internal Bloomberg Conan recipe.                   *
# This recipe does not work outside of Bloomberg infrastructure *
# ***************************************************************

import os
from conan import ConanFile

from conan.tools.cmake import CMake

class Package(ConanFile):
    python_requires = "conan-dpkg-recipe/[>=0.16]@test/unstable"
    python_requires_extend = "conan-dpkg-recipe.DPKGConan"

    def init(self):
        super().init()
        self.dependency_ignore.append('cmake')
        self.dependency_ignore.append('python3.8')
        self.dependency_ignore.append('python3.12')

    def build(self):
        cmake = CMake(self)
        cmake.configure()
        cmake.build()

    def package(self):
        cmake = CMake(self)
        cmake.install(component=self.name)

    def package_info(self):
        if "bbs-cmake-module" == self.name:
            bbs_module_path=os.path.join(self.package_folder, "share", "cmake", "BdeBuildSystem")
            self.buildenv_info.append_path("BdeBuildSystem_DIR", bbs_module_path)
            self.runenv_info.append_path("BdeBuildSystem_DIR", bbs_module_path)

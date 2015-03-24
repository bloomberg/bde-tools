"""Error types.

Note that most of these types are currently not used. They serve as
placeholders for supported error conditions in the future.
"""


class RepoError(Exception):
    pass


class LsfNotSorted(RepoError):
    pass


class LsfDupLine(RepoError):
    pass


class MemError(RepoError):
    # missing or extra in mem files
    pass


class PackageDepError(RepoError):
    # Missing package referenced in dep
    pass


class PackageCycle(RepoError):
    pass


class PackageGroupCycle(RepoError):
    pass


class ComponentCycle(RepoError):
    pass

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

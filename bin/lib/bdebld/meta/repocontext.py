"""Aggregate Repository structure and metadata
"""

from bdebld.common import blderror


class RepoContext(object):
    """This class represents the structure of a repository.

    Attributes:
        units (dict of str to Unit): Map of names to unit.
    """

    def __init__(self):
        self.root_path = None
        self.units = {}

    def add_unit(self, unit):
        if unit.name in self.units:
            msg = '"%s" is redefined at %s. Previously defined at %s' % (
                unit.name, unit.path, self.units[unit.name].path)
            raise blderror.DuplicateUnitError(msg)

        self.units[unit.name] = unit


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

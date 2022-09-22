"""Error types.

Note that some of these types may not currently be used -- they serve as
placeholders for error conditions in the future.
"""


class BldError(Exception):
    pass


class DuplicateUnitError(BldError):
    pass


class InvalidOptionRuleError(BldError):
    def __init__(self, line_num, rule, message):
        self.line_num = line_num
        self.rule = rule
        self.message = message


class InvalidOptionFileError(BldError):
    def __init__(self, file_path, invalid_rule_error):
        self.file_path = file_path
        self.rule_error = invalid_rule_error

    def __str__(self):
        return 'Invalid option rule in %s at line %s (%s):\n "%s"' % (
            self.file_path,
            self.rule_error.line_num,
            self.rule_error.message,
            self.rule_error.rule,
        )


class CycleError(BldError):
    pass


class InvalidInstallTargetError(BldError):
    pass


class MissingFileError(BldError):
    pass


class InvalidUfidError(BldError):
    pass


class InvalidUplidError(BldError):
    pass


class UnsupportedPlatformError(BldError):
    pass


class InvalidConfigFileError(BldError):
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

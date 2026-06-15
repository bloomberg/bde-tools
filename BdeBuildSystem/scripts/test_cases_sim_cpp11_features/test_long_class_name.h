// test_long_class_name.h                                             -*-C++-*-
#ifndef INCLUDED_TEST_LONG_CLASS_NAME
#define INCLUDED_TEST_LONG_CLASS_NAME

#include <bsls_compilerfeatures.h>

// Test case from Perl: Very long template parameter names that force wrapping
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class T,
          class U,
          class... X>
class ShortNames {
};

template <class A_very_long_template_parameter_name_that_will_force_wrapping,
          class T,
          class... X>
class LongNames {
};

template <class... VeryLongTypeParameterNameForTestingLineWrappingBehavior>
void functionWithVeryLongParameterNames(
    VeryLongTypeParameterNameForTestingLineWrappingBehavior&&... args);

#endif

#endif

// ----------------------------------------------------------------------------
// Copyright 2020 Bloomberg Finance L.P.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ----------------------------- END-OF-FILE ----------------------------------

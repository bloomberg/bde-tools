// test_forward_extra_args.h                                          -*-C++-*-
#ifndef INCLUDED_TEST_FORWARD_EXTRA_ARGS
#define INCLUDED_TEST_FORWARD_EXTRA_ARGS

#include <bsls_compilerfeatures.h>

// Test case from Perl: forward with extra template arguments
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <typename... A>
void forwardWithExtraArg(const vector<A>&... a) {
    if (q()) {
        xyz(forward<A, int>(a)...
            );
    }
}

template <class... ARGS>
void multipleTemplateArgs(ARGS&&... args) {
    helper<ARGS, default_type, int>(args...);
}

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

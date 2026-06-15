// test_local_var_args.h                                              -*-C++-*-
#ifndef INCLUDED_TEST_LOCAL_VAR_ARGS
#define INCLUDED_TEST_LOCAL_VAR_ARGS

#include <bsls_compilerfeatures.h>

// Test case from Perl: $local-var-args directive
template <class T>
class NonVariadicClassWithVariadicMember {
  public:
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $local-var-args=4

    template <class... U>
    NonVariadicClassWithVariadicMember(const U&... u);

    template <class... ARGS>
    void process(ARGS&&... args);

#endif
};

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $local-var-args=4

template <class T>
    template <class... U>
NonVariadicClassWithVariadicMember<T>::
    NonVariadicClassWithVariadicMember(const U&... u) {
}

template <class T>
    template <class... ARGS>
void NonVariadicClassWithVariadicMember<T>::process(ARGS&&... args) {
    impl(std::forward<ARGS>(args)...);
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

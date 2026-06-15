// test_bsl_forward.h                                                 -*-C++-*-
#ifndef INCLUDED_TEST_BSL_FORWARD
#define INCLUDED_TEST_BSL_FORWARD

#include <bsls_compilerfeatures.h>

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class... ARGS>
void useBslForward(ARGS&&... args) {
    process(bsl::forward<ARGS>(args)...);
}

template <class T>
void useBslSingle(T&& value) {
    handle(bsl::forward<T>(value));
}

template <class T, class... U>
void mixedNamespaces(T&& first, U&&... rest) {
    process(std::forward<T>(first), bsl::forward<U>(rest)...);
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

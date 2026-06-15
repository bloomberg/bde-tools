// test_const_ref.h                                                   -*-C++-*-
#ifndef INCLUDED_TEST_CONST_REF
#define INCLUDED_TEST_CONST_REF

#include <bsls_compilerfeatures.h>

// Edge case: Variadic with const references (not forwarding references)
#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class... TYPES>
void constRefPack(const TYPES&... values) {
    process(values...);
}

template <class... TYPES>
class ConstRefClass {
  public:
    void method(const TYPES&... args);
    void constMethod(const TYPES&... args) const;
};

template <class... TYPES>
void ConstRefClass<TYPES...>::method(const TYPES&... args) {
    handle(args...);
}

template <class... TYPES>
void ConstRefClass<TYPES...>::constMethod(const TYPES&... args) const {
    handle(args...);
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

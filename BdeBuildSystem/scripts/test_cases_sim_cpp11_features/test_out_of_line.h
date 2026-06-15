// test_out_of_line.h                                                 -*-C++-*-
#ifndef INCLUDED_TEST_OUT_OF_LINE
#define INCLUDED_TEST_OUT_OF_LINE

#include <bsls_compilerfeatures.h>

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class... TYPES>
class OutOfLine {
  public:
    void method(TYPES&&... args);
    static void staticMethod(const TYPES&... values);
};

template <class... TYPES>
void OutOfLine<TYPES...>::method(TYPES&&... args) {
    process(std::forward<TYPES>(args)...);
}

template <class... TYPES>
void OutOfLine<TYPES...>::staticMethod(const TYPES&... values) {
    handle(values...);
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

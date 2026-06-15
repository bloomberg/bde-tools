// test_constructor.h                                                 -*-C++-*-
#ifndef INCLUDED_TEST_CONSTRUCTOR
#define INCLUDED_TEST_CONSTRUCTOR

#include <bsls_compilerfeatures.h>

#if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES // $var-args=3

template <class... ARGS>
class ConstructorTest {
    int d_value;
  public:
    ConstructorTest(ARGS&&... args);
};

template <class... ARGS>
ConstructorTest<ARGS...>::ConstructorTest(ARGS&&... args)
: d_value(init(std::forward<ARGS>(args)...))
{
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

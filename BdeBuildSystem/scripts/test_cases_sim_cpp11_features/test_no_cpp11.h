// test_no_cpp11.h                                                    -*-C++-*-
#ifndef INCLUDED_TEST_NO_CPP11
#define INCLUDED_TEST_NO_CPP11

// File with no C++11 simulation regions

template <class T>
void normalTemplate(const T& value) {
    process(value);
}

class NormalClass {
  public:
    void method();
};

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

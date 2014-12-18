// csabbg_midreturn.t.cpp                                             -*-C++-*-
// ----------------------------------------------------------------------------

#include "csabbg_midreturn.t.hpp"
#include <bdes_ident.h>

namespace bde_verify
{
    namespace csabbg
    {
        int f()
        {
            struct x {
                static bool test() {
                    volatile bool b = true;
                    if (!b) {
                        return false;
                    }
                    return b;
                }
            };
            if (x::test()) {
                return 1;
            }
            if (x::test()) {
                return 2;                                            // RETURN
            }
            if (x::test()) {
                return 3;
            }
            if (f()) {
                return 4;                                             // RETURN
            }
            return 0;
        }

        template <class X>
        int g()
        {
            struct x {
                static bool test() {
                    volatile bool b = true;
                    if (!b) {
                        return false;
                    }
                    return b;
                }
            };
            if (x::test()) {
                return 1;
            }
            if (x::test()) {
                return 2;                                            // RETURN
            }
            if (x::test()) {
                return 3;
            }
            if (f()) {
                return 4;                                             // RETURN
            }
            return 0;
        }

        int h()
        {
            return g<char>() + g<double>();
        }

        int i()
        {
            if (i()) {
                return 5;          // Comment                        // RETURN
            }
            if (i()) {
                return 6;          // Comment                         // RETURN
            }
            if (i()) {
                return 7;          // Comment                          // RETURN
            }
            return 0;
        }

        struct y {
            y()
            {
                if (f()) {
                    return;
                }
                if (f()) {
                    return;                                          // RETURN
                }
                if (f()) {
                    return;
                }
                if (f()) {
                    return;                                           // RETURN
                }
                return;
            }
        };

        template <class X>
        struct z {
            z()
            {
                if (f()) {
                    return;
                }
                if (f()) {
                    return;                                          // RETURN
                }
                if (f()) {
                    return;
                }
                if (f()) {
                    return;                                           // RETURN
                }
                return;
            }
        };

        void w()
        {
            z<char> z1;
            z<int> z2;
        }

        int l()
        {
            if (f()) return                                                    1;
            if (f()) return                                                   1;
            if (f()) return                                                  1;
            if (f()) return                                                 1;
            if (f()) return                                                1;
            if (f()) return                                               1;
            if (f()) return                                              1;
            if (f()) return                                             1;
            if (f()) return                                            1;
            if (f()) return                                           1;
            if (f()) return                                          1;
            if (f()) return                                         1;
            if (f()) return                                        1;
            return 0;
        }

        int m()
        {
            if (f()) return                                                    1;
                                                                      // RETURN
            if (f()) return                                                   1;
                                                                      // RETURN
            if (f()) return                                                  1;
                                                                      // RETURN
            if (f()) return                                                 1;
                                                                      // RETURN
            if (f()) return                                                1;
                                                                      // RETURN
            if (f()) return                                               1;
                                                                      // RETURN
            if (f()) return                                              1;
                                                                      // RETURN
            if (f()) return                                             1;
                                                                      // RETURN
            if (f()) return                                            1;
                                                                      // RETURN
            if (f()) return                                           1;
                                                                      // RETURN
            if (f()) return                                          1;
                                                                      // RETURN
            if (f()) return                                         1;
                                                                      // RETURN
            if (f()) return                                        1; // RETURN
            return 0;
        }
    }
}

#include <stdio.h>

namespace bde_verify
{
    namespace csabbg
    {
        void *n()
        {
            if (f()) {
                return NULL;
            }
            if (f()) {
                return NULL;  // RETURN
            }
            if (f()) {
                return NULL;                                          // RETURN
            }
            return NULL;
        }

        int f(int n)
        {
            switch (n) {
              case 1:
                return 7;
              default:
                ++n;
                return n;
              case 2:
                return 8;
            }
        }

        int g(int n)
        {
            switch (n) {
              case 1:
                return 7;
              default:
                return 0;
              case 2:
                return 8;
            }
        }

        int h(int n)
        {
            switch (n) {
              default:
                return 7;
              case 1:
                ++n;
                return n;
              case 2:
                return 8;                                             // RETURN
            }
        }

        int i(int n)
        {
            switch (n) {
              case 1:
                switch (n) {
                  case 1:
                    return 7;
                }
              default:
                return n;
            }
        }
    }
}

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------

// csamisc_stringadd.t.cpp                                            -*-C++-*-

namespace bde_verify
{
    namespace csamisc
    {
        template <class T>
        static void use(T const&)
        {
        }

        namespace
        {
            struct string
            {
            };
            
            string operator+(string const& s, char const*)
            {
                return s;
            }
            string operator+(char const*, string const& s)
            {
                return s;
            }

            string operator-(string const& s, char const*)
            {
                return s;
            }
            string operator-(char const*, string const& s)
            {
                return s;
            }
        }
    }
}

int main(int ac, char*[])
{
    bde_verify::csamisc::string str;
    char const* lit("0123");

    bde_verify::csamisc::use("0123" + ac);
    bde_verify::csamisc::use("0123" + str);
    bde_verify::csamisc::use(lit + ac);

    bde_verify::csamisc::use(ac + "0123");
    bde_verify::csamisc::use(str + "0123");
    bde_verify::csamisc::use(ac + lit);

    bde_verify::csamisc::use("0123" - ac);
    bde_verify::csamisc::use("0123" - str);
    bde_verify::csamisc::use(lit - ac);

    bde_verify::csamisc::use(str - "0123");

    bde_verify::csamisc::use("0123" + -1);
    bde_verify::csamisc::use("0123" + 0);
    bde_verify::csamisc::use("0123" + 1);
    bde_verify::csamisc::use("0123" + 2);
    bde_verify::csamisc::use("0123" + 3);
    bde_verify::csamisc::use("0123" + 4);
    bde_verify::csamisc::use("0123" + 5);

    bde_verify::csamisc::use("0123" - 1);
    bde_verify::csamisc::use("0123" - 0);
    bde_verify::csamisc::use("0123" - -1);
    bde_verify::csamisc::use("0123" - -2);
    bde_verify::csamisc::use("0123" - -3);
    bde_verify::csamisc::use("0123" - -4);
    bde_verify::csamisc::use("0123" - -5);
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

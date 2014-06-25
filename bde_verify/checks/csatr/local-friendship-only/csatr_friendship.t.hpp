// csatr_friendship.t.hpp                                             -*-C++-*-

#ifndef INCLUDED_CSATR_FRIENDSHIP
#define INCLUDED_CSATR_FRIENDSHIP

#if !defined(INCLUDED_BDES_IDENT)
#  include <bdes_ident.h>
#endif
#ifndef INCLUDED_CSASCM_VERSION
#  include <csascm_version.h>
#endif

#ifndef INCLUDED_CSATR_EXTERNFRIENDSHIP
#include "csatr_externfriendship.t.hpp"
#endif

namespace bde_verify
{
    namespace csamisc
    {
        class BadGroup;
    }

    namespace csatr
    {
        class BadPackage;
        template <class> class friendship_GoodTemplate;
        class friendship_GoodDeclared;
        void operator+ (friendship_GoodDeclared const&);
        template <class T>
        void operator+ (friendship_GoodDeclared const&, T);

        class friendship_Component
        {
        public:
            friend class bde_verify::csamisc::BadGroup;
            friend class bde_verify::csatr::BadPackage;
            friend class bde_verify::csatr::BadExtern;
            friend void bde_verify::csatr::BadExtern::f() const;
            friend class bde_verify::csatr::BadExtern::Nested;
            friend class bde_verify::csatr::friendship_GoodDeclared;
            friend class GoodLocal;
            template <class T> friend class BadPackageTemplate;
            template <class T> friend class GoodTemplate;
            friend void bde_verify::csatr::operator+ (BadExtern const&);
            template <class T>
            friend void bde_verify::csatr::operator+ (BadExtern const&, T);

            friend void bde_verify::csatr::operator+ (friendship_GoodDeclared const&);
            template <class T>
            friend void bde_verify::csatr::operator+ (friendship_GoodDeclared const&, T);

            template <class T>
            friend void BadExtern::g(T);
        };

        template <class T>
        class friendship_GoodTemplate
        {
        };

        class friendship_GoodDeclared
        {
        public:
            void f() const;
            class Nested;
            template <class T> void g(T);
        };

        class friendship_GoodLocal
        {
            friend void friendship_GoodDeclared::f() const;
            friend class friendship_GoodDeclared::Nested;
            template <class T>
            friend void friendship_GoodDeclared::g(T);
        };

        class FriendshipLocal
        {
        private:
            struct PImpl;
            friend struct PImpl;
        };

        template <class T>
        struct friendship_GoodTemplateDeclared;

        template <class T>
        struct FriendlyToDeclared
        {
            friend struct friendship_GoodTemplateDeclared<T>;
        };

        template <class T>
        struct friendship_GoodTemplateDeclared
        {
        };
    }
}

#endif

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

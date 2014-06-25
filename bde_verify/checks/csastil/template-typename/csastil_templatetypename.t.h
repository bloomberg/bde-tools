// csastil_templatetypename.t.h                                       -*-C++-*-

#if !defined(INCLUDED_CSASTIL_TEMPLATETYPENAME)
#define INCLUDED_CSASTIL_TEMPLATETYPENAME
#if !defined(INCLUDED_BDES_IDENT)
#  include <bdes_ident.h>
#endif
#ifndef INCLUDED_CSASCM_VERSION
#  include <csascm_version.h>
#endif

namespace bde_verify
{
    namespace csastil
    {
        template <typename T>
        struct TemplateTypenameBad
        {
        public:
            template <typename S> TemplateTypenameBad();
            template <typename SS> void foo();
        };

        struct TemplateTypenameMember
        {
        public:
            template <typename SS> TemplateTypenameMember();
            template <typename S> void foo();
        };

        template <typename T>
        void swap(TemplateTypenameBad<T>&, TemplateTypenameBad<T>&);

        template <class TT>
        class TemplateTypenameGood
        {
        public:
            template <class S> TemplateTypenameGood();
            template <class SS> void foo();
        };

        template <class TT>
        void swap(TemplateTypenameGood<TT>&, TemplateTypenameGood<TT>&);
    }
}

template <typename TT>
inline void
bde_verify::csastil::swap(TemplateTypenameBad<TT>&, TemplateTypenameBad<TT>&)
{
}

namespace bde_verify
{
    namespace csastil
    {
        template <typename AA, class BB, typename CC> void foo();
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

// csatr_componentprefix.v.hpp                                        -*-C++-*-

#ifndef INCLUDED_CSATR_COMPONENTPREFIX
#define INCLUDED_CSATR_COMPONENTPREFIX 1

#if !defined(INCLUDED_BDES_IDENT)
#  include <bdes_ident.h>
#endif
#ifndef INCLUDED_CSASCM_VERSION
#  include <csascm_version.h>
#endif

// ----------------------------------------------------------------------------

namespace bde_verify
{
    namespace csatr
    {
        enum BadEnum
        {
            badBadEnumTag
        };

        typedef BadEnum BadTypedef;

        struct BadStruct
        {
            enum GoodEnum
            {
                goodGoodEnumTag
            };
            int member;
            int method();
        };

        typedef struct BadStruct1
        {
            int member;
            int method();
        } BadStruct2;

        typedef struct
        {
            int member;
            int method();
        } BadStruct3;

        class BadClass
        {
        public:
            int member;
            int method();
        };

        template <class>
        class BadTemplate
        {
        public:
            int member;
            int method();
        };

        template <class>
        int badTemplate()
        {
            int goodBadTemplateVariable;
            return goodBadTemplateVariable;
        }

        int badFunction()
        {
            int goodBadFunctionVariable = badTemplate<int>();
            return goodBadFunctionVariable;
        }

        int badVariable(0);

        enum ComponentPrefixGoodEnum
        {
            badGoodEnumTag,
            componentPrefixGoodEnumTag
        };

        typedef BadEnum ComponentPrefixGoodTypedef;

        struct ComponentPrefixGoodStruct
        {
            enum GoodEnum
            {
                goodGoodEnumTag
            };
            int member;
            int method();
        };

        class ComponentPrefixGoodClass
        {
        public:
            int member;
            int method();
        };

        void swap(ComponentPrefixGoodClass&, ComponentPrefixGoodClass&);

        template <class>
        class ComponentPrefixGoodTemplate
        {
        public:
            int member;
            int method();
        };

        template <class T>
        void swap(ComponentPrefixGoodTemplate<T>&,
                  ComponentPrefixGoodTemplate<T>&);

        template <class>
        int componentPrefixGoodTemplate()
        {
            int goodGoodTemplateVariable;
            return goodGoodTemplateVariable;
        }

        int componentPrefixGoodFunction()
        {
            int goodGoodFunctionVariable = componentPrefixGoodTemplate<int>();
            return goodGoodFunctionVariable;
        }

        int componentPrefixGoodVariable(0);

        class GoodDeclaration;
    }
}

// ----------------------------------------------------------------------------

inline void
bde_verify::csatr::swap(bde_verify::csatr::ComponentPrefixGoodClass&,
                  bde_verify::csatr::ComponentPrefixGoodClass&)
{
    extern int someVariable;
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

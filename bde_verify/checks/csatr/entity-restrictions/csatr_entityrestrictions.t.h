// csatr_entityrestrictions.t.h                                       -*-C++-*-

#ifndef INCLUDED_CSATR_ENTITYRESTRICTIONS
#define INCLUDED_CSATR_ENTITYRESTRICTIONS

#if !defined(INCLUDED_BDES_IDENT)
#  include <bdes_ident.h>
#endif
#ifndef INCLUDED_CSASCM_VERSION
#  include <csascm_version.h>
#endif

namespace bde_verify
{
    namespace csatr
    {
        struct EntityRestrictions
        {
            enum LegalEnum {};
            typedef LegalEnum LegalTypedef;
            static int legalVar;
            int legalMember;
            void legalFunction();
        };
        struct EntityRestrictionsAux
        {
        };

        void swap(EntityRestrictions&);
        void swap(EntityRestrictions&, EntityRestrictions&, EntityRestrictions&);
        void swap(EntityRestrictions&, EntityRestrictionsAux&);
        void swap(EntityRestrictions, EntityRestrictions);
        void swap(EntityRestrictions const&, EntityRestrictions const&);
        void swap(EntityRestrictions&, EntityRestrictions&);

        void operator+(EntityRestrictions);

        extern int entityRestrictionsVar;
        void entityRestrictionsFunction();

        typedef EntityRestrictions EntityRestrictionsTypedef;
        enum EntityRestrictionsEnum {};
        struct EntityRestrictionsStruct {};
        class EntityRestrictionsClass {};
        union EntityRestrictionsUnion {};
    }

    struct csatr_EntityRestrictions
    {
    };

    void swap(csatr_EntityRestrictions&, csatr_EntityRestrictions&);
    bool operator== (const csatr_EntityRestrictions&,
                    const  csatr_EntityRestrictions&);
    bool operator!= (const csatr_EntityRestrictions&,
                    const  csatr_EntityRestrictions&);
}

inline void bde_verify::csatr::EntityRestrictions::legalFunction()
{
}

// BDE_VERIFY pragma: set global_names x y z w
int x;
void y() { }
typedef int z;
enum w { v };

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

// csabbg_enumvalue.t.cpp                                             -*-C++-*-
// -----------------------------------------------------------------------------
// Copyright 2013 Hyman Rosen (hrosen4@bloomberg.net)
// Distributed under the Boost Software License, Version 1.0. (See file  
// LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt).     
// -----------------------------------------------------------------------------

enum NotValue {          Za = 0 };
enum    Value { Nb = -1, Zb = 0 };

struct X {
    enum NotValue {          Za = 0 };
    enum    Value { Nb = -1, Zb = 0 };
};

template <class T>
struct Y {
    enum NotValue {          Za = 0 };
    enum    Value { Nb = -1, Zb = 0 };
};

namespace bde_verify
{
    enum NotValue {          Za = 0 };
    enum    Value { Nb = -1, Zb = 0 };

    struct X {
        enum NotValue {          Za = 0 };
        enum    Value { Nb = -1, Zb = 0 };
    };

    template <class T>
    struct Y {
        enum NotValue {          Za = 0 };
        enum    Value { Nb = -1, Zb = 0 };
    };

    namespace csabbg
    {
        enum NotValue {          Za = 0 };
        enum    Value { Nb = -1, Zb = 0 };

        struct X {
            enum NotValue {          Za = 0 };
            enum    Value { Nb = -1, Zb = 0 };
        };

        template <class T>
        struct Y {
            enum NotValue {          Za = 0 };
            enum    Value { Nb = -1, Zb = 0 };
        };

        namespace
        {
            enum NotValue {          Za = 0 };
            enum    Value { Nb = -1, Zb = 0 };

            struct X {
                enum NotValue {          Za = 0 };
                enum    Value { Nb = -1, Zb = 0 };
            };

            template <class T>
            struct Y {
                enum NotValue {          Za = 0 };
                enum    Value { Nb = -1, Zb = 0 };
            };
        }
    }
}

// csafmt_comments.t.cpp                                              -*-C++-*-

// @DESCRIPTION: this is a fully value-semantic type, don't you know.

// @DESCRIPTION: this is just a value-semantic type.

//     ( Base_Class )
//           |
//           |   Show inheritance relationship
//           |
//           V
//    ( Derived_Class )
//           |
//           |   Show inheritance relationship
//           |
//           V
// ( Derived_Derived_Class )

//        ( Base_Class )
//              |
//             |   Show inheritance relationship
//            |
//           V
//    ( Derived_Class )

//     ,-----------.
//    (  Base_Class )
//     `-----------'
//           |
//           |   Show inheritance relationship
//           |
//           V
//    ,--------------.
//   (  Derived_Class )
//    `--------------'
//           |
//           |   Show inheritance relationship
//           |
//           V
//  ,----------------------.
// (  Derived_Derived_Class )
//  `----------------------'

        // ====================
        // This can be
        // wrapped.
        // ====================

        // ========================
        // This cannnot be.
        // Wrapped
        // ========================

// Hello,
// world! This can wrap.

// This can't wrap.                                                   Hello
// world! This can't wrap. 

// This can wrap.  S'Ok!                                         Hello
// 'world!' This can wrap.

// This can't wrap.                                                 Hello
// world! This can't wrap. 

// This can wrap.  S'Ok!                                       Hello.
// "world!" This can wrap.

// This can't wrap.                                               Hello.
// world! This can't wrap. 

//@PURPOSE: None. Why even go on?
//@PURPOSE: Lots! Tell you later.
// @ Purpose :Too much space, too many dots...

// Pure procedure? My god! It's full of pure procedures!

#pragma bde_verify push
// BDE_VERIFY pragma: set wrap_slack 1
// ============================================================================
// y                                                                        x
// a b c d
// ============================================================================
#pragma bde_verify pop

//@CLASSES:
//    a::b : first class
//    c_d: not so first class
//
//@DESCRIPTION: flak

// This is a modifiable reference, while this other one contains non-modifiable
// references.

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

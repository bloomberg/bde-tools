// bdeflag_ut.h                                                       -*-C++-*-

#ifndef INCLUDED_BDEFLAG_UT
#define INCLUDED_BDEFLAG_UT

#ifndef INCLUDED_BSLS_IDENT
#include <bsls_ident.h>
#endif
BSLS_IDENT("$Id: $")

//@PURPOSE: Provide low-level utilities for bdeflag program.
//
//@CLASSES:
//    Ut: low-level utilities for bdeflag program
//
//@AUTHOR: Bill Chapman
//
//@DESCRIPTION: This component defines a class that is mostly a namespace
// for a collection of static functions, most of which operate on bsl::strings.

#ifndef INCLUDED_BSL_IOSTREAM
#include <bsl_iostream.h>
#endif

#ifndef INCLUDED_BSL_SET
#include <bsl_set.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#endif

#ifndef INCLUDED_BSL_VECTOR
#include <bsl_vector.h>
#endif

#ifndef INCLUDED_CTYPE
#include <ctype.h>
#define INCLUDED_CTYPE
#endif

namespace BloombergLP {
namespace bdeflag {

struct Ut {
    // Objects of this class are never created, this class is just a namespace
    // for various utility types and functions.

    typedef bsl::vector<bsl::string>  LineVec;
    typedef LineVec::iterator         LineVecIt;
    typedef LineVec::const_iterator   LineVecCIt;

    typedef bsl::set<int>             LineNumSet;
    typedef LineNumSet::iterator      LineNumSetIt;

    struct AlphaNumOrColon {
        // This struct enables a quick boolean lookup where 'd_stateRef[c]' is
        // 'true' if char 'c' can be in a C++ identifier and 'false' otherwise.
        // Note that ':', '_', '~' are considered valid identifier chars.

        bool  d_state[256];
        bool *d_stateRef;

        // CREATORS
        AlphaNumOrColon();
            // Initialize the 'd_state' array, and point 'd_stateRef' to the
            // beginning or middle of the array, depending on whether the type
            // 'char' is signed.
    };

    static AlphaNumOrColon  s_alphaNumOrColon;

    // CLASS METHODS
    static
    bool alphaNumOrColon(char c);
        // Return 'true' if char 'c' can be in a C++ identifier and 'false'
        // otherwise.  Note that ':', '_', '~' are considered valid identifier
        // chars.

    static
    char blockOutQuotes(bsl::string *line, char startsQuoted = 0);
        // Modify the specified string 'line' with all strings quoted with '"'
        // or '\'' replaced with same length strings of 'X'.  The specified
        // 'startsQuoted' indicates the line is started in a quoted string.
        // Return true if the quotes are unterminated and the line ends in a
        // '\'.  Note that this method understands '\\' escapes.
        //
        // DEPRECATED: No longer used as blocking out quotes was not readily
        // separable from processing comments, so functionality was blended in
        // in 'bdeflag_lines.cpp'.

    static
    char charAtOrBefore(const bsl::string& s, int col, int *atCol = 0);
        // Return the first char at or preceding s[col] that is not whitespace
        // and set the specified '*atCol' to its index.  If no nonwhite
        // chars exist in the line before 'col', return 0 and leave '*startPos'
        // garbage.  Note it is alright in 'col' is negative or after the end
        // of the string.

    static
    bool charInString(char c, const char *str);
        // Return 'true' if the specified char 'c' is in the string 'str' and
        // 'false' otherwise.  Note that if 'c' is 0, this always returns
        // 'false'.

    static
    char firstCharOf(const bsl::string& s);
        // Return the first non-space char of this line, and 0 if the line is
        // all spaces or blank.

    static
    bool frontMatches(const bsl::string& s,
                      const bsl::string& pattern);
    static
    bool frontMatches(const bsl::string& s,
                      const bsl::string& pattern,
                      int                pos);
        // Return 'true' if the specified string 's' starting at position 'pos'
        // matches the specified 'pattern' and 'false' otherwise.  The behavior
        // is undefined if 'pos > s.length()', or if 'pos' is unspecified and
        // 'pattern' begins with spaces.  Note it is alright if 'pos' is
        // greater than the length of 's'.  If 'pos' is unspecified, match to
        // the first nonwhite sequence in 's'.  Note it is alright if 'pattern'
        // begins with spaces, so long is 'pos' is specified.

    static
    bool isUpperCaseString(const bsl::string& s);
        // Return 'true' if every alpha char in the specified string 's' is
        // upper case.

    static
    char lastCharOf(const bsl::string& s);
        // Return the last char of this line, if the line is blank or comment,
        // return 0.

    static
    size_t npos();
        // return bsl::string::npos

    static
    bsl::string nthString(int n);
        // return "first" for 1, "second" for 2, etc

    static
    bool p(const char *name, const char *value);
        // used by P macros in other components

    static
    bool p(const char *name, char value);
        // used by P macros in other components

    static
    bool p(const char *name, double value);
        // used by P macros in other components

    static
    bool p(const char *name, const bsl::string& value);
        // used by P macros in other components

    static
    bsl::string removeTemplateAngleBrackets(const bsl::string& s);
        // Given a templated name 's', remove all the '<*>' (possibly nested)
        // from it.  If the '<>'s in 's' are unbalanced (meaning it's not
        // a template expression) return "<>".

    static
    bsl::string spacesOut(bsl::string s);
        // Return the specified 's' with all spaces removed.

    static
    void trim(bsl::string *string);
        // Trim trailing whitespace from string.

    static bsl::string wordAfter(const bsl::string&  s,
                                 int                 startPos,
                                 int                *end = 0);
        // Return the next C++ identifier that occurs at or after the specified
        // 'startPos' in the string s.  If the optional 'end' is specified, set
        // it to the postion of the last char in the identifier, or the first
        // char endcountered if a non-identifier char is encountered before any
        // identifier-appropriate chars.  Return 'end == -1' if the string is 0
        // length or contains only whitespace at or after 'startPos'.

    static bsl::string wordBefore(const bsl::string&  s,
                                  int                 end,
                                  int                *start = 0);
        // Return the word preceding or ending with 's[end]' consisting of
        // alphanums or ':'s, and set the optionally specified '*start' to the
        // index of the beginning of the found word.  If no word is found but a
        // nonspace char is found, "" is returned and 'start' points to the
        // found char.  If there are nothing but spaces from s[end] to the
        // start of the line, "" is returned and 'start' is -1..  The behavior
        // is undefined if 'end' is not in the range '0 <= end < s.length()'.
};

// FREE OPERATORS
bsl::ostream& operator<<(bsl::ostream& stream, const Ut::LineNumSet& set);
    // Output, in sequence, the line numbers in the given set, with ','s in
    // between them, and return the stream passed.

//=============================================================================
//                       INLINE FUNCTION DEFINITIONS
//=============================================================================

// CLASS METHODS
inline
bool Ut::alphaNumOrColon(char c)
{
    return s_alphaNumOrColon.d_stateRef[c];
}

inline
char Ut::firstCharOf(const bsl::string& s)
{
    size_t pos = s.find_first_not_of(' ');
    return npos() == pos ? 0 : s[pos];
}

inline
bool Ut::frontMatches(const bsl::string& s,
                      const bsl::string& pattern)
{
    BSLS_ASSERT_OPT(pattern.length() > 0);
    BSLS_ASSERT_OPT(' ' != pattern[0]);

    size_t pos = s.find_first_not_of(' ');
    if (npos() == pos) {
        return false;                                                 // RETURN
    }

    return frontMatches(s, pattern, pos);
}

inline
bool Ut::isUpperCaseString(const bsl::string& s)
{
    const char *pc           = s.data();
    const char * const pcEnd = pc + s.length();
    for (; pc < pcEnd; ++pc) {
        if (isalpha(*pc) && !isupper(*pc)) {
            return false;                                             // RETURN
        }
    }

    return true;
}

inline
char Ut::lastCharOf(const bsl::string& s)
{
    if ("" == s) {
        return 0;                                                     // RETURN
    }

    return s[s.length() - 1];
}

inline
size_t Ut::npos()
        // return bsl::string::npos
{
    return bsl::string::npos;
}

}  // close namespace bdeflag
}  // close namespace BloombergLP

#endif

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------

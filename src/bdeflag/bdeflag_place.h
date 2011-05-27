// bdeflag_place.h                                                    -*-C++-*-

#ifndef INCLUDED_BDEFLAG_PLACE
#define INCLUDED_BDEFLAG_PLACE

#ifndef INCLUDED_BSLS_IDENT
#include <bsls_ident.h>
#endif
BSLS_IDENT("$Id: $")

//@PURPOSE: Provide a class representing a position.
//
//@CLASSES:
//    Place: representation of a position as a (line number, col) coord pair
//
//@AUTHOR: Bill Chapman
//
//@DESCRIPTION: An object of type 'Place' represents a position in a source
// file as a (line number, column) coordinate pair.  Special positions 'end()'
// and 'rEnd()' are provided as static functions, representing after the end
// of all source and before the start of all source.  Operations '++', '--',
// '(Place + int)' and '(Place - int)' are provided, where incrementing a
// Place moves it to the next nonwhite position in the file, adding to 'end()'
// or decrementing from 'rEnd()' has no effect.  Other utilities are also
// provided.

#ifndef INCLUDED_BDEFLAG_LINES
#include <bdeflag_lines.h>
#endif

#ifndef INCLUDED_BDEFLAG_UT
#include <bdeflag_ut.h>
#endif

#ifndef INCLUDED_BSL_LIST
#include <bsl_vector.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#endif

#ifndef INCLUDED_BSL_UTILITY
#include <bsl_utility.h>
#endif

namespace BloombergLP {

namespace bdeFlag {

class Place {
    // CLASS DATA
    static Place        s_rEnd;     // before the first
    static Place        s_end;

    // DATA
    int                 d_lineNum;
    int                 d_col;

  public:
    // CREATORS
    Place() : d_lineNum(0), d_col(0) {}
        // Construct a place at 'rEnd()'.

    Place(int line, int col) : d_lineNum(line), d_col(col) {}
        // Construct a place at the specified '(line number, column)' position.

    // CLASS METHODS
    static
    const Place& rEnd();
        // The place at '(0, 0)' before the first char of source in the file.

    static
    const Place& end();
        // The place at '(Lines::lineCount(), 0)' after the last char of source
        // in the file.

    static
    void setEnds();
        // Set the static data 's_end' and 's_rEnd' according to the
        // information in Lines.

    // MANIPULATORS
    Place& operator++();
        // Skip to the next position of a valid char in the file.  The behavior
        // is undefined unless the starting position is a (0, 0), end(), or a
        // position with valid data at it, that is, not past the last line,
        // before the first line, or after the end of the line it is on.  Note
        // that given 'end', we position ourselves to the first valid char of
        // the file.

    Place& operator--();
        // Move this Place to the previous char of the file at which a char is
        // stored.  If we go off the front of the file, we set this object to
        // 'end()'.  The behavior is undefined unless the starting position is
        // either 'end()' or a position in the file with a valid char at it.
        // Note that given 'end', we position ourselves to the last valid char
        // of the file.

    Place& nextLine();
        // Go to the first nonwhite position at or after the beginning of the
        // next line.  Return 'end()' if reach EOF.

    // ACCESSORS
    char operator*() const;
        // Return the char at the current location.  If we are at 'end()

    int col() const;
        // Column of this 'Place'.

    bsl::ostream& error() const;
        // Start an error message indicating the filename and place.  Errors
        // are things that should never happen if the source file is a
        // correctly compiling C++ file.

    Place findFirstOf(const char *target,
                      bool        of = true) const;
    Place findFirstOf(const char  *target,
                      bool         of,
                      const Place& endPlace) const;
        // Find the next occurance of any char in the specfied 'target',
        // starting at the current position, and before the optionally
        // specified 'endPlace', returning the position of the found char or
        // 'endPlace' if it is not found.  If 'of' is passed 'false', we
        // instead search for the first occurance of any char NOT in 'target'.
        // The behavior is undefined unless the current position is either at a
        // valid location or at 'end()'.  Note that if 'endPlace' is not
        // specified, it is as those 'endPlace == end()' were specified.

#if 0
    // not tested, will probably not be needed

    Place findLastOf(const char *target, bool of = true) const;
        // Find the last occurance of any char in the specfied 'target',
        // starting at the current position.  If 'of' is passed 'false', we
        // instead search for the first occurance of any char NOT in 'target'.
        // The behavior is undefined unless the current position is either at a
        // valid location or at 'end()'.  Note that starting at 'end()' is
        // effectively starting from the last char of the file.
#endif

    Place findStatementStart() const;
        // Find the position of the start of the current statement.  Note that
        // prefixes like 'static', 'inline', or 'template' will be ignored.

    int lineNum() const;
        // The line number of this Place object.

    bsl::string nameAfter(Place *end = 0, bool known = true) const;
        // Return the identifier or template at or after the current position.
        // 'known' indicates that we know we are expecting a template.

    bsl::string templateNameAfter(Place *end = 0,
                                        bool known = true) const;
        // Return the template name at or after the current position.  If only
        // only an identifier and no template is found, return the empty
        // string.  'known' means we know we are getting a template.

    bsl::string templateNameBefore(Place *start = 0) const;
        // Return the template name preceding or ending with '**this'
        // consisting of alphanums and ':'s, and set the optionally specified
        // '*start' to the location of the beginning of the found word.  If
        // nothing but whitespace exists before the beginning of the file, ""
        // is returned and 'start' is set to 'end()'.  If a char that is
        // neither an alphanum nor a ':' is found, "" is returned and 'start'
        // is set to the index of that char.  The behavior is undefined unless
        // the current location is either a valid location or 'end()', if
        // 'end()', the search begins at the last char of hte file.

    bsl::string twoPointsString(const Place& endPlace) const;
        // Return a string composed of everything from '*this' to 'endPlace'.
        // Newlines are represented as space, all strings of space are reduced
        // to single spaces.

    bsl::ostream& warning() const;
        // Begin a warning message about the current position.  Warnings are
        // issued where something is not an error, meaning the file can
        // containcompiling C, but the warning is something this tool is meant
        // to warn about.

    bool whiteAfter() const;
        // Return 'true' if the char after the current Place is white
        // (including newline) and 'false' otherwise.

    bsl::string wordAfter(Place *end = 0) const;
        // Return the C++ identifier at or after the current position, setting
        // the optionally specified 'end' to the last char of the word.  If a
        // non-identifier char is encountered before an identifier is
        // encountered, 'end' is pointed to that char and "" is returned.

    bsl::string wordBefore(Place *start = 0) const;
        // Return the word preceding or ending with '**this' consisting of
        // alphanums and ':'s, and set the optionally specified '*start' to the
        // location of the beginning of the found word.  If nothing but
        // whitespace exists before the beginning of the file, "" is returned
        // and 'start' is set to 'end()'.  If a char that is neither an
        // alphanum nor a ':' is found, "" is returned and 'start' is set to
        // the index of that char.  The behavior is undefined unless the
        // current location is either a valid location or 'end()', if 'end()',
        // the search begins at the last char of hte file.
};

//=============================================================================
//                          INLINE FUNCTION DEFINTIONS
//=============================================================================

// FREE OPERATORS
inline
bool operator==(const Place& lhs, const Place& rhs)
    // Return 'true' if the two places are at the same position and 'false'
    // otherwise.
{
    return lhs.lineNum() == rhs.lineNum() && lhs.col() == rhs.col();
}

inline
bool operator<(const Place& lhs, const Place& rhs)
    // Return 'true' if the specified 'lhs' is before the specified 'rhs' and
    // 'false' otherwise.
{
    if      (lhs.lineNum() < rhs.lineNum()) {
        return true;                                                  // RETURN
    }
    else if (lhs.lineNum() > rhs.lineNum()) {
        return false;                                                 // RETURN
    }
    else {
        return lhs.col() < rhs.col();                                 // RETURN
    }
}

inline
bool operator>(const Place& lhs, const Place& rhs)
    // Return 'true' if the specified 'lhs' is after the specified 'rhs' and
    // 'false' otherwise.
{
    if      (lhs.lineNum() > rhs.lineNum()) {
        return true;                                                  // RETURN
    }
    else if (lhs.lineNum() < rhs.lineNum()) {
        return false;                                                 // RETURN
    }
    else {
        return lhs.col() > rhs.col();                                 // RETURN
    }
}

inline
bool operator!=(const Place& lhs, const Place& rhs)
    // Return 'true' if the two places are not at the same position and 'false'
    // otherwise.
{
    return !(lhs == rhs);
}

inline
bool operator<=(const Place& lhs, const Place& rhs)
    // Return 'true' if the specified 'lhs' is at or before the specified 'rhs'
    // and 'false' otherwise.
{
    return !(lhs > rhs);
}

inline
bool operator>=(const Place& lhs, const Place& rhs)
    // Return 'true' if the specified 'lhs' is at or after the specified 'rhs'
    // and 'false' otherwise.
{
    return !(lhs < rhs);
}

Place operator+(Place lhs, int rhs);
    // Return the specified 'lhs' after incrementing it the specified 'rhs'
    // times.  Note 'rhs' may be negative.

Place operator-(Place lhs, int rhs);
    // Return the specified 'lhs' after decrementing it the specified 'rhs'
    // times.  Note 'rhs' may be negative.

inline
bsl::ostream& operator<<(bsl::ostream& stream, const Place& place)
    // Output the specified 'place' to the specified 'stream', then return
    // 'stream'.
{
    stream << "(" << place.lineNum() << ", " << place.col() << ")";

    return stream;
}

// CLASS METHODS
inline
const Place& Place::rEnd()
{
    return s_rEnd;
}

inline
const Place& Place::end()
{
    return s_end;
}

// ACCESSORS
inline
char Place::operator*() const
{
    if (d_lineNum >= Lines::lineCount() || d_lineNum < 0 ||
                                       d_col >= Lines::lineLength(d_lineNum)) {
        return 0;                                                     // RETURN
    }

    return Lines::line(d_lineNum)[d_col];
}

inline
int Place::col() const
{
    return d_col;
}

inline
Place Place::findFirstOf(const char *target,
                         bool        of) const
{
    return findFirstOf(target, of, end());
}

inline
int Place::lineNum() const
{
    return d_lineNum;
}

}  // close namespace bdeFlag
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

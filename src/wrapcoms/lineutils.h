// lineutils.h                                                        -*-C++-*-
#ifndef INCLUDED_LINEUTILS
#define INCLUDED_LINEUTILS

//@PURPOSE: Provide a namespace for 'BDE' comment identification utilities.
//
//@CLASSES:
//  LineUtils: namespace for a suite of 'BDE' comment identification functions
//
//@SEE_ALSO: commentparagraph.h
//
//@AUTHOR: tmarshall
//
//@DESCRIPTION: This component provides a namespace for a set of comment-line
// utility functions to classify comment line text consistent with 'BDE' canon
// conventions for C++ header files.  The Primary Utilities efficiently provide
// all of the functionality needed to re-format a 'BDE' C++ header file.  The
// Helper Utilities are used by the Primary Utilities, but are also publicly
// available for general use.
//
// The only whitespace character recognized by this component is the space
// character (' ') itself, so it is the user's responsibility to remove, e.g.,
// tab ('\t') characters before using the utilities in this component.
//
//
///SYNOPSIS
///--------
//..
//  PRIMARY UTILITIES:
//  int findCommentIndex          (const vector<char>& line);
//  int isBlankComment            (const vector<char>& line, int commentIndex);
//  int isBlankListMarker         (const vector<char>& line, int commentIndex);
//  int isClassOrSeeAlsoComment   (const vector<char>& line);
//  int isCommentedDeclaration    (const vector<char>& line, int commentIndex);
//  int isCopyrightNotice         (const vector<char>& line);
//  int isListBlock               (const vector<char>& line, int commentIndex);
//  int isListBlockItem           (const vector<char>& line, int commentIndex);
//  int isNoFillToggle            (const vector<char>& line, int commentIndex);
//
//  HELPER UTILITIES
//  int hasComment                (const vector<char>& line);
//  int isBannerLine              (const vector<char>& line, int commentIndex);
//  int isHeadingComment          (const vector<char>& line, int commentIndex);
//  int isInlineBanner            (const vector<char>& line, int commentIndex);
//..
///USAGE
///-----
// Referring to the Synopsis above, all of the functions that require a
// 'commentIndex' parameter (i.e., all of the the "is" functions EXCEPT
// 'isClassOrSeeAlsoComment') will return zero ("false") if 'commentIndex' is
// negative.  This behavior allows these functions to be (correctly) called on
// lines that are not comments.
//
// A full, buildable program in the USAGE section of the 'commentparagraph'
// component illustrates the usage and behavior of the Primary Utilities in
// filling comment paragraphs in a 'BDE' canon header file.

#ifndef INCLUDED_VECTOR
#include <vector>
#define INCLUDED_VECTOR
#endif

                            // ===============
                            // class LineUtils
                            // ===============
struct LineUtils {
    // Namespace for a set of comment-line formatting utility functions.  Note
    // that a set of "Helper Utilities" have been made 'public' for the
    // convenience of the user, but are not explicitly needed (by the user) to
    // perform comment-paragraph formatting on 'BDE' C++ header files.  See the
    // USAGE section of the 'commentparagraph' component for a formatting
    // application that (explicitly) uses only the "Primary Utilities".

    // PRIMARY UTILITIES
    static int findCommentIndex(const std::vector<char>& line);
        // Return the start index of the first occurrance of the sequence "//"
        // in the specified 'line' if that line is a pure, non-blank comment
        // (i.e., there is no text before the "//" and at least one
        // non-whitespace character after the "//") without any of the 'BDE'
        // special tokens (i.e., "//@", "///", "// ===", // ---", or "// - -"),
        // and a negative value otherwise.
        //
        // Note that the return value of this function encodes all of the
        // information needed to make single-line decisions on 'BDE' canon
        // header text.  The remaining Primary Utilities are needed to make
        // appropriate multi-line decisions.  See the USAGE section of the
        // 'commentparagraph' component for examples.

    static int isBlankComment(const std::vector<char>& line, int commentIndex);
        // Return zero if, in the specified 'line' with the specified
        // 'commentIndex', any character beyond the position commentIndex + 1
        // is a non-whitespace character, and a non-zero value otherwise.  See
        // the USAGE section for additional documentation of behavior.

    static int isBlankListMarker(const std::vector<char>& line,
                                 int                      commentIndex);
        // Return a non-zero value if the string of length three within the
        // specified 'line', beginning at the specified 'commentIndex', exists
        // and is "//:" and there are no other non-whitespace characters in
        // 'line', and zero otherwise.  See the USAGE section for additional
        // documentation of behavior.

    static int isClassOrSeeAlsoComment(const std::vector<char>& line);
        // Return a positive value if the first six characters of the specified
        // 'line' match those of one of the 'BDE' tokens
        //..
        //  //@CLASSES:
        //  //@SEE_ALSO:
        //  //@AUTHOR:
        //  //@DEPRECATED:
        //..
        // and zero otherwise.  See the USAGE section for additional
        // documentation of behavior.

    static int isCommentedDeclaration(const std::vector<char>& line,
                                      int                      commentIndex);
        // Return a positive value if the first three characters starting at
        // the specified 'commentIndex' in the specified 'line' match the
        // string "//!", and zero otherwise.  See the USAGE section for
        // additional documentation of behavior.

    static int isCopyrightNotice(const std::vector<char>& line);
        // Return a positive value if the first ten characters of the
        // specified 'line' match the string "// NOTICE:", and
        // zero otherwise.  See the USAGE section for
        // additional documentation of behavior.

    static int isListBlock(const std::vector<char>& line, int commentIndex);
        // Return a non-zero value if the string of length three within the
        // specified 'line', beginning at the specified 'commentIndex', exists
        // and is "//:", and zero otherwise.  See the USAGE section for
        // additional documentation of behavior.

    static int isListBlockItem(const std::vector<char>& line,
                               int                      commentIndex);
        // Return the (positive) level value 'N' if the string within the
        // specified 'line', beginning at the specified 'commentIndex', matches
        // the pattern "//: (  )*(o |[1-9][0-9] " (where 'N = n / 2' and 'n' is
        // the total number of spaces within the matched pattern "(  )*"), 
        // and zero otherwise.  See the USAGE section for additional
        // documentation of behavior.

    static int isNoFillToggle(const std::vector<char>& line, int commentIndex);
        // Return a non-zero value if the string of length four within the
        // specified 'line', beginning at the specified 'commentIndex', exists
        // and is "//..", and zero otherwise.  See the USAGE section for
        // additional documentation of behavior.

    // HELPER UTILITIES
    static int hasComment(const std::vector<char>& line);
        // Return the start index of the first occurrance of the sequence "//"
        // in the specified 'line' if there are no non-space characters before
        // that "//", or a negative value otherwise.

    static int isBannerLine(const std::vector<char>& line, int commentIndex);
        // Examine the specified 'line', beginning at the specified
        // 'commentIndex'.  Return a non-zero value if the first six characters
        // of the comment comment match any of the 'BDE' banner line sequences
        // (i.e., "//====", "// ===", "//----", "// ---", "// - -", or
        // "//- - "), and zero otherwise.  See the USAGE section for additional
        // documentation of behavior.

    static int isHeadingComment(const std::vector<char>& line,
                                int                      commentIndex);
        // Examine the specified 'line', beginning at the specified
        // 'commentIndex'.  Return a non-zero value if the comment matches
        // either of the 'BDE' heading tokens (i.e., "//@" or "///") but DOES
        // NOT match "//@D", and zero otherwise.  See the USAGE section for
        // additional documentation of
        // behavior.

    static int isInlineBanner(const std::vector<char>& line, int commentIndex);
        // Return a non-zero value if the first word within the comment in the
        // specified 'line', having the specified 'commentIndex' (i.e., the
        // first set of non-space characters after line[commentIndex + 1])
        // matches "INLINE" or "TEMPLATE", and zero otherwise.  See the USAGE
        // section for additional documentation of behavior.
};

// ============================================================================
//                      INLINE FUNCTION DEFINITIONS
// ============================================================================

                        // - - - - - - - -
                        // HELPER UTILITIES
                        // - - - - - - - -
inline
int LineUtils::isBannerLine(const std::vector<char>& line, int commentIndex)
{
    return commentIndex >= 0 && line.size() > commentIndex + 6
        && ('=' == line[commentIndex + 3] && '=' == line[commentIndex + 5] ||
            '-' == line[commentIndex + 2] && '-' == line[commentIndex + 4] ||
            '-' == line[commentIndex + 3] && '-' == line[commentIndex + 5]);
}

inline
int LineUtils::isHeadingComment(const std::vector<char>& line,
                                int                      commentIndex)
{
    return  commentIndex >= 0 && line.size() > commentIndex + 4
         && ('@' == line[commentIndex + 2] && 'D' != line[commentIndex + 3] ||
             '/' == line[commentIndex + 2] ||
             '#' == line[commentIndex + 2]);  // This traps commented #include
}

                        // - - - - - - - - -
                        // PRIMARY UTILITIES
                        // - - - - - - - - -
inline
int LineUtils::findCommentIndex(const std::vector<char>& line)
{
    int commentIndex = hasComment(line);

    if (commentIndex < 0 || isHeadingComment(line, commentIndex)
                         || isBannerLine(line, commentIndex)
                         || isBlankComment(line, commentIndex)
                         || isInlineBanner(line, commentIndex)) {
        return -1;
    }

    return commentIndex;
}

inline
int LineUtils::isBlankListMarker(const std::vector<char>& line,
                                 int                      commentIndex)
{
    return line.size() == commentIndex + 4        &&
           ':'         == line[commentIndex + 2]  &&
           '\n'        == line[commentIndex + 3];
}

inline
int LineUtils::isClassOrSeeAlsoComment(const std::vector<char>& line)
{
    return line.size() > 6 &&  '/' == line[0] && '/' == line[1]
                           &&  '@' == line[2]
                           && ('C' == line[3] && 'L' == line[4] &&
                               'A' == line[5])
                           || ('S' == line[3] && 'E' == line[4] &&
                               'E' == line[5])
                           || ('A' == line[3] && 'U' == line[4] &&
                               'T' == line[5])
                           || ('D' == line[3] && 'E' == line[4] &&
                               'P' == line[5]);
}

inline
int LineUtils::isCommentedDeclaration(const std::vector<char>& line,
                                      int                      commentIndex)
{
    return commentIndex >= 0                      &&
           line.size()  >  commentIndex + 3       &&
           '!'          == line[commentIndex + 2];
}

inline
int LineUtils::isCopyrightNotice(const std::vector<char>& line)
{
    return line.size() > 9 &&
           '/' == line[0] && '/' == line[1] && ' ' == line[2] &&
           'N' == line[3] && 'O' == line[4] && 'T' == line[5] &&
           'I' == line[6] && 'C' == line[7] && 'E' == line[8] &&
           ':' == line[9];
}

inline
int LineUtils::isListBlock(const std::vector<char>& line, int commentIndex)
{
    return line.size() > commentIndex + 3 && ':' == line[commentIndex + 2];
}

inline
int LineUtils::isNoFillToggle(const std::vector<char>& line, int commentIndex)
{
    return line.size() > commentIndex + 4 && '.' == line[commentIndex + 2]
                                          && '.' == line[commentIndex + 3];
}

#endif

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//------------------------------ END OF FILE ----------------------------------

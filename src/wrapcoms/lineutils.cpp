// lineutils.cpp                                                      -*-C++-*-
#include <lineutils.h>
#include <ctype.h>

using namespace std;

                            // -----------------------
                            // static helper functions
                            // -----------------------

static
int isBulletToken(const vector<char>& line, int i)
    // Return a non-zero value if the string in the specified 'line', starting
    // at the specified index 'i' matches "o " and zero otherwise.  The
    // behavior is undefined unless 'i >= 0'.
{
    return line.size() >= i + 1        &&
           'o'         == line[i]      &&
           ' '         == line[i + 1];
}

static
int isNumberToken(const vector<char>& line, int i)
    // Return a non-zero value if the string in the specified 'line', starting
    // at the specified index 'i' matches the pattern '([1-9] |[1-9][0-9] )'
    // and zero otherwise.  The behavior is undefined unless 'i >= 0'.
{
    int length = line.size();
    return
        i + 1 <= length                       && // enough room for 2       and
        '0' != line[i] && isdigit(line[i])    && // 1st char is [1-9]       and
          (' ' == line[i + 1]               ||   //   2nd char is ' '      or
           i + 1 <= length                &&     //     room for 3        and
           isdigit(line[i + 1])           &&     //     2nd char is [0-9] and
           ' ' == line[i + 2]                 ); //     3rd char is ' '
}

    
static
int skipWhitespace(const vector<char>& line, int startIndex)
    // Return the index of the first non-space (' ') character in the specified
    // 'line' occuring at or after the specified 'startIndex'.  The behavior is
    // undefined unless 'startIndex < line.size()'.
{
    int i = startIndex;
    while (' ' == line[i]) {
        ++i;
    }
    return i;
}

static
int spacesToLevel(int numSpaces)
    // Return the level 'N' corresponding to the specified 'numSpaces', where
    // where 'N' is defined by
    //..
    //  numSpaces == 2 * N - 1
    //..
    // if 'N' is an integer, and '-numSpaces' otherwise.
{
    if ((numSpaces + 1) % 2 != 0) {
        return -1 * numSpaces;                                        // RETURN
    }
    else {
        return (numSpaces + 1) / 2;                                   // RETURN
    }
}

                            // ---------------
                            // class LineUtils
                            // ---------------

// CLASS METHODS
int LineUtils::hasComment(const vector<char>& line)
{
    int i = skipWhitespace(line, 0);

    if (line.size() < i + 3) {          // too short to be comment
        return -1;                                                    // RETURN
    }

    return '/' == line[i] && '/' == line[i + 1] ? i : -1;
}

int LineUtils::isBlankComment(const vector<char>& line, int commentIndex)
{
    if (commentIndex < 0) {
        return 0;                                                     // RETURN
    }

    return '\n' == line[skipWhitespace(line, commentIndex + 2)];
}

int LineUtils::isInlineBanner(const vector<char>& line, int commentIndex)
{
    int lineLength = line.size();
    if (commentIndex < 0 || commentIndex + 3 > lineLength) {
        return 0;                                                     // RETURN
    }

    int i = skipWhitespace(line, commentIndex + 2);
    return lineLength >= i + 7                    &&
           (! strncmp(&line[i], "INLINE",   6) ||        // logical-not strncmp
            ! strncmp(&line[i], "TEMPLATE", 9)       );  // logical-not strncmp

}

int LineUtils::isListBlockItem(const vector<char>& line, int commentIndex)
{
    if (!isListBlock(line, commentIndex)) {      // not a List Block
        return 0;                                                     // RETURN
    }
    int tokenIndex = skipWhitespace(line, commentIndex + 3);
    if (tokenIndex + 1 >= line.size()) {         // too few characters
        return 0;                                                     // RETURN
    }
    int level      = spacesToLevel(tokenIndex - (commentIndex + 3));
    if (level <= 0) {                            // invalid level
        return 0;                                                     // RETURN
    }
    if (isBulletToken(line, tokenIndex) || isNumberToken(line, tokenIndex)) {
        return level;                                                 // RETURN
    }
    else {
        return 0;
    }
}

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//--------------------------- END OF FILE -------------------------------------

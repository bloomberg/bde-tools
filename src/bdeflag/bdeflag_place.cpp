// bdeflag_place.cpp                                                  -*-C++-*-

#include <bdeflag_place.h>

#include <bdeflag_lines.h>
#include <bdeflag_ut.h>

#include <bsls_assert.h>

#include <bsl_string.h>

#define P(x)          Ut::p(#x, (x))

namespace BloombergLP {

namespace bdeFlag {

// FREE OPERATORS
Place operator+(Place lhs, int rhs)
{
    if (rhs >= 0) {
        for (int j = 0; j < rhs; ++j) {
            ++lhs;
        }
    }
    else {
        for (int j = 0; j > rhs; --j) {
            --lhs;
        }
    }

    return lhs;
}

Place operator-(Place lhs, int rhs)
{
    if (rhs >= 0) {
        for (int j = 0; j < rhs; ++j) {
            --lhs;
        }
    }
    else {
        for (int j = 0; j > rhs; --j) {
            ++lhs;
        }
    }

    return lhs;
}

// CLASS DATA
Place Place::s_rEnd;
Place Place::s_end;

// CLASS MANIPULATORS
void Place::setEnds()
{
    s_rEnd = Place(0, 0);
    s_end  = Place(Lines::lineCount(), 0);
}

// MANIPULATORS
Place& Place::operator++()
{
    size_t pos;

    if (d_lineNum >= Lines::lineCount()) {
        *this = end();
        return *this;                                                 // RETURN
    }
    else if (d_lineNum < 0) {
        *this = rEnd();                                               // RETURN
    }

    ++d_col;
    if (d_col < Lines::lineLength(d_lineNum)) {
        pos = Lines::line(d_lineNum).find_first_not_of(' ', d_col);
        if (Ut::npos() != pos) {
            d_col = pos;
            return *this;                                             // RETURN
        }
        else {
            d_col = Lines::lineLength(d_lineNum);
        }
    }

    if (d_col >= Lines::lineLength(d_lineNum)) {
        while (true) {
            if (++d_lineNum >= Lines::lineCount()) {
                d_col = 0;
                BSLS_ASSERT_OPT(end() == *this);
                break;
            }
            pos = Lines::line(d_lineNum).find_first_not_of(' ');
            if (Ut::npos() != pos) {
                d_col = pos;
                break;
            }
        }
    }

    return *this;
}

Place& Place::operator--()
{
    size_t pos;

    if (d_lineNum >= Lines::lineCount()) {
        *this = end();
    }
    else if (d_lineNum < 0) {
        *this = rEnd();
        return *this;                                                 // RETURN
    }

    --d_col;
    if (d_col >= 0 && d_lineNum < Lines::lineCount()) {
        pos = Lines::line(d_lineNum).find_last_not_of(' ', d_col);
        if (Ut::npos() != pos) {
            d_col = pos;
        }
        else {
            d_col = -1;
        }
    }

    while (d_col < 0) {
        if (--d_lineNum <= 0) {
            *this = rEnd();
            break;
        }
        pos = Lines::line(d_lineNum).find_last_not_of(' ');
        if (Ut::npos() != pos) {
            d_col = pos;
            break;
        }
    }

    return *this;
}

Place& Place::nextLine()
{
    d_col = 0;
    ++d_lineNum;

    if (0 == Lines::lineLength(d_lineNum) || ' ' == **this) {
        ++*this;
    }

    return *this;
}

// ACCESSORS
bsl::ostream& Place::error() const
{
    return bsl::cerr << "Error: " << Lines::fileName() << ":" << *this << ": ";
}

Place Place::findFirstOf(const char *target,
                         bool of,
                         const Place& endPlace) const
{
    Place cursor = *this;
    if (cursor <= rEnd() || 0 == *cursor) {
        ++cursor;
    }

    int lastLine = bsl::min(endPlace.d_lineNum, Lines::lineCount() - 1);

    if (cursor.d_lineNum <= lastLine) {
        const bsl::string& curLine = Lines::line(cursor.d_lineNum);
        size_t pos = of
                   ? curLine.find_first_of(    target, cursor.d_col)
                   : curLine.find_first_not_of(target, cursor.d_col); // not of
        if (Ut::npos() != pos) {

            return bsl::min(Place(cursor.d_lineNum, pos), endPlace);  // RETURN
        }
        cursor.d_col = Lines::lineLength(cursor.d_lineNum) - 1;
        ++cursor;
    }

    while (cursor.d_lineNum <= lastLine) {
        const bsl::string& curLine = Lines::line(cursor.d_lineNum);

        size_t pos = of ? curLine.find_first_of(    target)
                        : curLine.find_first_not_of(target); // "not of"
        if (Ut::npos() != pos) {
            return bsl::min(Place(cursor.d_lineNum, pos), endPlace);  // RETURN
        }
        cursor.d_col = Lines::lineLength(cursor.d_lineNum) - 1;
        ++cursor;
    };

    return endPlace;
}

#if 0
// not tested, will probably not be needed
Place Place::findLastOf(const char *target, bool of) const
{
    Place cursor = *this;
    if (cursor.d_lineNum >= Lines::lineCount()) {
        // get cursor back to a valid position
        cursor = end();
        --cursor;
    }

    while (true) {
        if (rEnd() == cursor) {
            return rEnd();                                            // RETURN
        }
        const bsl::string& curLine = Lines::line(cursor.d_lineNum);
        size_t pos = of
                   ? curLine.find_last_of(    target, cursor.d_col)
                   : curLine.find_last_not_of(target, cursor.d_col); // not of
        if (Ut::npos() != pos) {
            return Place(cursor.d_lineNum, pos);
        }
        cursor.d_col = 0;
        --cursor;
    }
}
#endif

Place Place::findStatementStart() const
{
    // go back and find the end of the statement before this one, or rEnd

    int cli = d_lineNum;
    int li = Lines::lineBefore(&cli);
    if (0 == cli) {
        return rEnd();                                                // RETURN
    }

    for (++li; li < cli; ++li) {
        if (Lines::BDEFLAG_S_BLANKLINE != Lines::statement(li) &&
                                                !Lines::isProtectionLine(li)) {
            break;
        }
    }

    int col = Lines::lineIndent(li);
    while (li < cli) {
        int li2 = li + 1;
        if (Lines::lineIndent(li2) != col || 0 != strchr("{:",
                                                      Lines::line(li2)[col])) {
            break;
        }
        ++li;
    }

    return Place(li, col);
}

bsl::string Place::nameAfter(Place *end, bool known) const
{
    Place retEnd;
    if (0 == end) {
        end = &retEnd;
    }

    bsl::string ret = wordAfter(&retEnd);
    if ("" == ret) {
        if ('<' == *retEnd) {
            return retEnd.templateNameAfter(end, known);              // RETURN
        }

        *end = retEnd;
        return "";                                                    // RETURN
    }

    if ('<' == *(retEnd + 1)) {
        Place tempEnd;
        bsl::string tempRet = templateNameAfter(&tempEnd, known);
        if ("" != tempRet) {
            *end = tempEnd;
            return tempRet;                                           // RETURN
        }
    }

    *end = retEnd;
    return ret;
}

bsl::string Place::templateNameAfter(Place *endName, bool known) const
{
    bool unknown = !known;
    Place defaultEnd;
    if (!endName) {
        endName = &defaultEnd;
    }

    Place start = *this;
    {
        char c;
        if (start.lineNum() <= 0) {
            start = rEnd() + 1;
        }
        else if (c = *start, ' ' == c || 0 == c) {
            ++start;
        }
        if (Lines::lineCount() <= start.lineNum()) {
            *endName = end();
            return "";                                                // RETURN
        }
    }

    {
        char c = *start;
        if ('<' != c && !Ut::alphaNumOrColon(c)) {
            *endName = start;
            return "";                                                // RETURN
        }
    }

    Place oab(start);    // Open Angle Bracket
    {
        const bsl::string& curLine = Lines::line(oab.d_lineNum);
        Ut::wordAfter(curLine, oab.d_col, &oab.d_col);
        if ('<' != *oab &&
                          static_cast<int>(curLine.length()) > oab.d_col + 1) {
            ++oab.d_col;
        }
    }
    if ('<' != *oab) {
        // not a template name

        *endName = start;
        return "";                                                    // RETURN
    }

    int li  = oab.d_lineNum;
    int col = oab.d_col;

    bsl::string searchString = known
                             ? "abcdefghijklmnopqrstuvwxyz"
                               "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                               "1234567890:*&_(),=|?/^%!~+.[] "
                             : "abcdefghijklmnopqrstuvwxyz"
                               "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                               "1234567890:*&_(),=. ";

    int angleDepth = 1;
    int parenDepth = 0;
    int boundaryLi = known ? Lines::lineCount() : bsl::min(Lines::lineCount(),
                                                           li + 8);
    bool notTemplate = false;
    const bsl::string *pCurLine = &Lines::line(li);
    int len = pCurLine->length();
    while (angleDepth > 0 && li < boundaryLi) {
        ++col;
        while (col >= len) {
            ++li;
            pCurLine = &Lines::line(li);
            len = pCurLine->length();
            col = 0;
        }

        char c = pCurLine->operator[](col);
        char c2 = col < len - 1 ? pCurLine->operator[](col + 1) : 0;

        if        ('<' == c) {
            if (known) {
                if (0 == parenDepth) {
                    ++angleDepth;
                }
            }
            else {
                if ('<' == c2) {
                    notTemplate = true;
                    break;
                }
                ++angleDepth;
            }
        } else if ('>' == c) {
            if (unknown) {
                if ('>' == c2) {
                    notTemplate = true;
                    break;
                }
                --angleDepth;
                if (0 == angleDepth) {
                    break;
                }
            }
            else if (0 == parenDepth) {
                --angleDepth;
                if (0 == angleDepth) {
                    break;
                }
            }
        } else if ('(' == c) {
            ++parenDepth;
        } else if (')' == c) {
            --parenDepth;
            if (parenDepth < 0) {
                notTemplate = true;
                break;
            }
        } else if ('&' == c) {
            if (unknown && '&' == c2) {
                notTemplate = true;
                break;
            }
        } else if (Ut::npos() == searchString.find(c)) {
            notTemplate = true;
            break;
        }
    }

    if (notTemplate || 0 != angleDepth || 0 != parenDepth) {
        // it's not a template

        *endName = start;
        return "";                                                    // RETURN
    }
    BSLS_ASSERT_OPT(0 == angleDepth);

    // it's a template!!

    *endName = Place(li, col);

    bsl::string ret;
    col = start.col();
    for (li = start.lineNum(); li < endName->lineNum(); ) {
        ret += Lines::line(li).substr(col);
        col = 0;
        ++li;
    }
    ret += Lines::line(li).substr(col, endName->col() + 1 - col);

    return ret;
}

bsl::string Place::templateNameBefore(Place *start) const
{
    Place defaultStart;
    if (!start) {
        start = &defaultStart;
    }

    Place back = *this;
    if (rEnd() >= *this) {
        *start = rEnd();
        return "";                                                    // RETURN
    }
    else if (end().lineNum() <= lineNum()) {
        back = end() - 1;
    }

    {
        char c = *back;
        if (!c || ' ' == c) {
            --back;
            if (rEnd() == back) {
                *start = rEnd();
                return "";                                            // RETURN
            }
        }
    }

    if ('>' != *back) {
        *start = back;
        return "";                                                    // RETURN
    }

    int li  = back.d_lineNum;
    int col = back.d_col;

    const char *searchConstChar = "abcdefghijklmnopqrstuvwxyz"
                                  "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                                  "1234567890:*&_(),=. ";
    bsl::string searchString = searchConstChar;

    int angleDepth = 1;
    int parenDepth = 0;
    int boundaryLi = bsl::max(0, li - 8);
    bool notTemplate = false;
    const bsl::string *pCurLine = &Lines::line(li);
    while (angleDepth > 0 && li > boundaryLi) {
        --col;
        if (col < 0) {
            --li;
            pCurLine = &Lines::line(li);
            int len = pCurLine->length();
            if (0 == len) {
                notTemplate = true;
                break;
            }
            col = len - 1;
        }

        char c = pCurLine->operator[](col);
        char c2 = col > 0 ? pCurLine->operator[](col - 1) : 0;

        if        ('>' == c) {
            ++angleDepth;
            if ('>' == c2) {
                notTemplate = true;
                break;
            }
        } else if ('<' == c) {
            if ('<' == c2) {
                notTemplate = true;
                break;
            }
            --angleDepth;
            if (0 == angleDepth) {
                break;
            }
        } else if (')' == c) {
            ++parenDepth;
        } else if ('(' == c) {
            --parenDepth;
            if (parenDepth < 0) {
                notTemplate = true;
                break;
            }
        } else if ('&' == c) {
            if ('&' == c2) {
                notTemplate = true;
                break;
            }
        } else if (Ut::npos() == searchString.find(c)) {
            notTemplate = true;
            break;
        }
    }

    if (notTemplate || 0 != parenDepth || 0 != angleDepth || 0 == col) {
        // it's not a template

        *start = back;
        return "";                                                    // RETURN
    }

    Place cursor(li, col);
    --cursor;
    char c = *cursor;

    bsl::string wordBefore = cursor.wordBefore(start);

    if ("" == wordBefore) {
        *start = back;
        return "";                                                    // RETURN
    }

    // it's a template!!!

    if ("template" == wordBefore) {
        *start = cursor + 1;
    }

    return (*start).twoPointsString(back);
}

bsl::string Place::twoPointsString(const Place& endPlace) const
{
    bsl::string ret;
    ret.reserve(80);

    for (Place cursor = *this; cursor <= endPlace; ++cursor) {
        if (0 != *cursor) {
            ret += *cursor;
            if (cursor.whiteAfter()) {
                ret += ' ';
            }
        }
    }

    Ut::trim(&ret);
    return ret;
}

bsl::ostream& Place::warning() const
{
    return bsl::cerr << "Warning: " << Lines::fileName() << ": " << *this <<
                                                                          ": ";
}

bool Place::whiteAfter() const
{
    const int li = lineNum();

    if (li >= Lines::lineCount()) {
        return false;                                                 // RETURN
    }

    const int colPlusOne = col() + 1;
    const bsl::string& curLine = Lines::line(li);
    if (colPlusOne >= static_cast<int>(curLine.length())) {
        return true;                                                  // RETURN
    }

    return ' ' == curLine[colPlusOne];
}

bsl::string Place::wordAfter(Place *endName) const
{
    Place defaultEnd;
    if (!endName) {
        endName = &defaultEnd;
    }

    Place cursor = *this;
    if (cursor.lineNum() >= Lines::lineCount()) {
        *endName = end();
        return "";                                                    // RETURN
    }
    else if (cursor.lineNum() <= 0 ||
                                    0 == Lines::lineLength(cursor.lineNum())) {
        ++cursor;
    }

    while (end() > cursor) {
        const bsl::string& curLine = Lines::line(cursor.d_lineNum);

        BSLS_ASSERT_OPT(curLine.length() > 0);

        int startCol, endCol;
        bsl::string ret = Ut::wordAfter(curLine, cursor.d_col, &endCol);
        if (-1 != endCol) {
            // note we might have found "" and endCol points to char we
            // found

            endName->d_lineNum = cursor.d_lineNum;
            endName->d_col     = endCol;
            return ret;                                               // RETURN
        }

        cursor.nextLine();
    }

    *endName = end();
    return "";
}

bsl::string Place::wordBefore(Place *start) const
{
    Place defaultStart;
    if (!start) {
        start = &defaultStart;
    }

    Place cursor = *this;
    if (cursor.lineNum() >= Lines::lineCount()) {
        cursor = end() - 1;
    }
    else if (cursor.lineNum() <= 0) {
        *start = rEnd();
        return "";                                                    // RETURN
    }
    else if (0 == Lines::lineLength(cursor.lineNum())) {
        --cursor;
    }

    while (rEnd() != cursor) {
        const bsl::string& curLine = Lines::line(cursor.d_lineNum);

        BSLS_ASSERT_OPT(curLine.length() > 0);

        int startCol;
        bsl::string ret = Ut::wordBefore(curLine, cursor.d_col, &startCol);
        if (-1 != startCol) {
            // note we might have found "" and startCol points to char we
            // found

            cursor.d_col = startCol;
            *start = cursor;
            return ret;                                               // RETURN
        }
        cursor.d_col = 0;
        --cursor;
    }

    *start = rEnd();
    return "";
}

}  // close namespace bdeFlag
}  // close namespace BloombergLP

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------

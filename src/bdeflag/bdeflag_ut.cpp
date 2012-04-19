// bdeflag_ut.cpp                                                     -*-C++-*-

#include <bdeflag_ut.h>

#include <bsl_string.h>

#include <bsl_cstdlib.h>
#include <bsl_cstring.h>
#include <bsl_fstream.h>
#include <bsl_iostream.h>
#include <bsl_sstream.h>

#define P(x)            Ut::p(#x, (x))

namespace BloombergLP {

namespace bdeflag {

Ut::AlphaNumOrColon  Ut::s_alphaNumOrColon;

Ut::AlphaNumOrColon::AlphaNumOrColon()
{
    char tokenChar = 0;
    --tokenChar;
    d_stateRef = tokenChar < 0 ? &d_state[128] : &d_state[0];

    bsl::memset(d_state, 0, sizeof(d_state));

    int begin = d_state - d_stateRef;
    int end   = d_state + 256 - d_stateRef;
    for (int c = begin; c < end; ++c) {
        char cc = c;
        d_stateRef[cc] = isalnum(cc) || ':' == cc || '_' == cc || '~' == cc;
    }
}

char Ut::blockOutQuotes(bsl::string *line, char startsQuoted)
    // Note this may be called before parsing out comments, so there may be
    // mangled and incomplete quoted strings in the line, don't get upset in
    // that case.
{
    char ret = startsQuoted;
    const int len = line->length();

    size_t pos = 0;
    while (ret || npos() != (pos = line->find_first_of("\"'", pos))) {
        size_t endPos = pos;
        const char startChar = ret ? ret : (*line)[pos];
        const char *endStr = '"' == startChar ? "\\\"" : "\\'";
        while (npos() != (endPos = line->find_first_of(endStr, endPos + 1))) {
            if ('\\' == (*line)[endPos]) {
                if (line->length() > endPos + 1) {
                    ++endPos;
                }
                else {
                    ret = startChar;
                }
            }
            else {
                ret = 0;
                break;
            }
        }
        if (npos() == endPos) {
            endPos = line->length();
        }
        else {
            ++endPos;
        }
        const bsl::string& endLine = line->substr(endPos);
        line->resize(pos);
        line->insert(pos, endPos - pos, startChar);
        *line += endLine;
        pos = endPos;

        if (ret && line->length() == endPos) {
            return ret;                                               // RETURN
        }
    }

    return 0;
}

char Ut::charAtOrBefore(const bsl::string& s, int col, int *atCol)
{
    int defaultAtCol;
    if (0 == atCol) {
        atCol = &defaultAtCol;
    }

    col = bsl::min(col, static_cast<int>(s.length()) - 1);
    if (col < 0) {
        return 0;                                                     // RETURN
    }

    size_t pos = s.find_last_not_of(' ', col);
    if (npos() == pos) {
        return 0;                                                     // RETURN
    }
    else {
        *atCol = pos;
        return s[pos];                                                // RETURN
    }
}

bool Ut::charInString(char c, const char *str)
{
    for (const char *pc = str; *pc; ++pc) {
        if (*pc == c) {
            return true;                                              // RETURN
        }
    }

    return false;
}

bool Ut::frontMatches(const bsl::string& s,
                      const bsl::string& pattern,
                      int                pos)
{
    if (s.length() < pattern.length() + pos) {
        return false;                                                 // RETURN
    }

    const char *ps = s.data() + pos;
    const char *pp = pattern.data();
    const char *ppEnd = pattern.end();
    for (; pp < ppEnd; ++pp, ++ps) {
        if (*ps != *pp) {
            return false;                                             // RETURN
        }
    }

    return true;
}

bsl::string Ut::nthString(int n)
{
    switch (n) {
      case 1: {
        return "first";                                               // RETURN
      } break;
      case 2: {
        return "second";                                              // RETURN
      } break;
      case 3: {
        return "third";                                               // RETURN
      } break;
      case 4: {
        return "fourth";                                              // RETURN
      } break;
      case 5: {
        return "fifth";                                               // RETURN
      } break;
      case 6: {
        return "sixth";                                               // RETURN
      } break;
      default: {
        bsl::stringstream ss;
        ss << '\'' << n << "'th";
        return ss.str();                                              // RETURN
      }
    }
}

bool Ut::p(const char *name, const char *value)
{
    bsl::cerr << name << " = " << value << bsl::endl;
    return false;
}

bool Ut::p(const char *name, char value)
{
    bsl::cerr << name << " = " << value << bsl::endl;
    return false;
}

bool Ut::p(const char *name, double value)
{
    bsl::cerr << name << " = " << value << bsl::endl;
    return false;
}

bool Ut::p(const char *name, const bsl::string& value)
{
    bsl::cerr << name << " = " << value << bsl::endl;
    return false;
}

bsl::string Ut::removeTemplateAngleBrackets(const bsl::string& s)
{
    bsl::string ret = s;
    const bsl::string angles = "<>";

    while (true) {
        bsl::size_t u = ret.find_first_of(angles);
        if (npos() == u) {
            return ret;                                               // RETURN
        }
        if ('>' == ret[u]) {
            // not a template -- give up

            return angles;                                            // RETURN
        }
        while (true) {
            bsl::size_t v = ret.find_first_of(angles, u + 1);
            if (npos() == v) {
                // not a template -- give up

                return angles;                                        // RETURN
            }
            if ('>' == ret[v]) {
                ret = ret.substr(0, u) + ret.substr(v + 1);
                break;
            }
            else {
                BSLS_ASSERT('<' == ret[v]);
                u = v;
            }
        }
    }
}

bsl::string Ut::spacesOut(bsl::string s)
{
    bsl::string ret = s;

    int out = 0, in = 0, len = s.length();
    for ( ; in < len; ++in) {
        if (' ' != s[in]) {
            if (out != in) {
                ret[out] = s[in];
            }
            ++out;
        }
    }

    ret.resize(out);
    return ret;
}

void Ut::trim(bsl::string *string)
{
    size_t col = string->find_last_not_of(" \r");
    if (Ut::npos() == col) {
        col = 0;
    }
    else {
        ++col;
    }
    if (col < string->length()) {
        string->resize(col);
    }
}

bsl::string Ut::wordAfter(const bsl::string&  s,
                          int                 startPos,
                          int                *end)
{
    int defaultEnd;
    if (0 == end) {
        end = &defaultEnd;
    }

    int len = s.length();
    BSLS_ASSERT_OPT(startPos < len);

    size_t pos = s.find_first_not_of(' ', startPos);
    if (npos() == pos) {
        *end = -1;
        return "";                                                    // RETURN
    }

    startPos = pos;

    if (!alphaNumOrColon(s[startPos])) {
        *end = startPos;
        return "";                                                    // RETURN
    }

    // we've found something

    int endPos = startPos;
    int lenMinus = len - 1;
    while (endPos < lenMinus && alphaNumOrColon(s[endPos + 1])) {
        ++endPos;
    }

    BSLS_ASSERT_OPT(endPos < len);
    BSLS_ASSERT_OPT(alphaNumOrColon(s[endPos]));

    *end = endPos;
    return s.substr(startPos, endPos + 1 - startPos);
}

bsl::string Ut::wordBefore(const bsl::string&  s,
                           int                 end,
                           int                *start)
{
    int defaultStart;
    if (0 == start) {
        start = &defaultStart;
    }
    *start = -1;

    BSLS_ASSERT_OPT(end < static_cast<int>(s.length()));
    size_t pos = s.find_last_not_of(' ', end);
    if (npos() == pos) {
        *start = -1;
        return "";                                                    // RETURN
    }

    *start = pos;

    if (!alphaNumOrColon(s[pos])) {
        return "";                                                    // RETURN
    }

    // we've found something

    while (*start > 0 && alphaNumOrColon(s[*start - 1])) {
        --*start;
    }

    BSLS_ASSERT_OPT(*start >= 0);
    BSLS_ASSERT_OPT(alphaNumOrColon(s[*start]));

    return s.substr(*start, pos + 1 - *start);
}

bsl::ostream& operator<<(bsl::ostream& stream, const Ut::LineNumSet& set)
{
    const Ut::LineNumSetIt begin = set.begin(), end = set.end();

    bool first_time = true;
    for (Ut::LineNumSetIt it = begin; end != it; ++it) {
        if (first_time) {
            first_time = false;
        }
        else {
            stream << ", ";
        }
        stream << *it;
    }

    return stream;
}

}  // close namespace bdeflag

}  // close namespace BloombergLP

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------

// bdeflag_lines.cpp                                                  -*-C++-*-

#include <bdeflag_lines.h>

#include <bdeu_string.h>

#include <bslma_allocator.h>
#include <bslma_default.h>

#include <bsls_assert.h>

#include <bsl_cstring.h>
#include <bsl_map.h>
#include <bsl_string.h>

#include <bsl_cstdlib.h>
#include <bsl_cstring.h>
#include <bsl_fstream.h>
#include <bsl_iostream.h>

#include <ctype.h>
#include <sys/types.h>
#include <sys/stat.h>

#define P(x)            Ut::p(#x, (x))

namespace BloombergLP {
namespace bdeflag {

struct Lines_StartProgram {
    // Object to be created at program start to initialize 's_crsOK' variable
    // with 'getenv'.

    // PUBLIC CLASS DATA
    static bool s_crsOK;

    // CREATOR
    Lines_StartProgram();
        // Initialize things at program start that don't have to be
        // reinitialized for each file.
} lines_startProgram;
bool Lines_StartProgram::s_crsOK;

Lines_StartProgram::Lines_StartProgram()
{
    s_crsOK = !!bsl::getenv("BDEFLAG_TOLERATE_CARRIAGE_RETURNS");
}

using bsl::cout;
using bsl::cerr;
using bsl::endl;

bsl::string               Lines::s_fileName;
Lines::FileType           Lines::s_fileType;
Lines::LineVec            Lines::s_lines;
Lines::CommentVec         Lines::s_comments;
Lines::IndentVec          Lines::s_commentIndents;
Lines::IndentVec          Lines::s_lineIndents;
Lines::StatementVec       Lines::s_statements;
bsl::vector<bool>         Lines::s_statementEnds;
int                       Lines::s_lineCount;
Ut::LineNumSet            Lines::s_longLines;
Ut::LineNumSet            Lines::s_cStyleComments;
Ut::LineNumSet            Lines::s_inlinesNotAlone;
Ut::LineNumSet            Lines::s_badlyAlignedImplicits;
Ut::LineNumSet            Lines::s_badlyAlignedReturns;
Ut::LineNumSet            Lines::s_tbds;
Ut::LineNumSet            Lines::s_contComments;
Lines::State              Lines::s_state = BDEFLAG_EMPTY;
int                       Lines::s_purposeFlags;
Lines::ComponentPrefix    Lines::s_componentPrefix;
bool                      Lines::s_hasTabs;
bool                      Lines::s_hasCrs;
bool                      Lines::s_hasTrailingBlanks;
bool                      Lines::s_includesAssertH;
bool                      Lines::s_includesCassert;
bool                      Lines::s_includesDoubleQuotes;
bool                      Lines::s_assertFound;
bool                      Lines::s_includesComponentDotH;
bool                      Lines::s_couldntOpenFile;
Ut::LineNumSet            Lines::s_nonAsciiLines;

// LOCAL FUNCTIONS

static
bsl::string componentInclude()
    // for a .cpp file, determine the appropriate component #include clause
{
    bsl::string s = Lines::fileName();
    size_t slashPos = s.find_last_of('/');
    if (Ut::npos() != slashPos) {
        s = s.substr(slashPos + 1);
    }
    size_t clip;
    switch (Lines::fileType()) {
      case Lines::BDEFLAG_DOT_CPP: {
        bsl::size_t idx = s.rfind('.');
        clip = Ut::npos() == idx ? 0  : s.length() - idx;
      }  break;
      case Lines::BDEFLAG_DOT_T_DOT_CPP: {
        clip = 6;
      }  break;
      default: {
        BSLS_ASSERT_OPT(0);    // should never happen
        return "";                                                    // RETURN
      }  break;
    }
    BSLS_ASSERT_OPT(s.length() >= clip);

    s = s.substr(0, s.length() - clip);

    return "<" + s + ".h>";
}

static inline
int nextLiveChar(const bsl::string& s, int pos)
    // skip to next possibly relevant char in 'killQuotesComments'
{
    size_t ret = s.find_first_of("/*\"'", pos);
    return Ut::npos() == ret ? s.length() : ret;
}

// PRIVATE MANIPULATORS
void Lines::checkForAssert()
{
    s_assertFound = false;

    if (BDEFLAG_DOT_H != fileType()) {
        return;                                                       // RETURN
    }

    const char *ASSERT = "ASSERT";
    int lineCount = Lines::lineCount();
    for (int li = 1; li < lineCount; ++li) {
        const char *pc;
        bool commentFound = false;
        for (pc = s_lines[li].c_str(); *pc; ++pc) {
            if ('/' == *pc && '/' == pc[1]) {
                commentFound = true;
                break;
            }
        }
        if (!commentFound) {
            continue;
        }
        for (pc = pc + 2; *pc; ++pc) {
            if (isalnum(*pc) || '_' == *pc) {
                const char *pcB;
                for (pcB = pc + 1; *pcB && (isalnum(*pcB) || '_' == *pcB); ) {
                    ++pcB;
                }
                if ('(' == *pcB && 6 == pcB - pc && !strncmp(pc, ASSERT, 6)) {
                    s_assertFound = true;
                    return;                                           // RETURN
                }
                pc = pcB - 1;    // note *pcB might be 0, and we will ++ next
            }
        }
    }
}

void Lines::checkIncludes()
{
    BSLS_ASSERT_OPT(BDEFLAG_INCLUDES_CHECKED >= s_state);

    BSLS_ASSERT_OPT(lineCount() >= 1);
    BSLS_ASSERT_OPT(0 == line(0).length());

    s_includesAssertH = false;
    s_includesCassert = false;
    s_includesDoubleQuotes = false;

    bool firstInclude = true;

    for (int li = 1; li < lineCount(); ++li) {
        const bsl::string& curLine = line(li);

        size_t pos = curLine.find_first_not_of(' ');
        if (Ut::npos() != pos && '#' == curLine[pos]) {
            pos = curLine.find_first_not_of(' ', pos + 1);
            if (Ut::npos() != pos && Ut::frontMatches(curLine,
                                                      "include",
                                                      pos)) {
                pos = curLine.find_first_not_of(' ', pos + 7);

                if (Ut::npos() != pos) {
                    if (firstInclude) {
                        firstInclude = false;

                        if (BDEFLAG_DOT_H != s_fileType) {
                            if (Ut::frontMatches(curLine,
                                                 componentInclude(),
                                                 pos)) {
                                s_includesComponentDotH = true;
                            }
                        }
                    }

                    if ('"' == curLine[pos]) {
                        s_includesDoubleQuotes = true;
                    }
                    else if (Ut::frontMatches(curLine, "<assert.h>", pos)) {
                        s_includesAssertH = true;
                    }
                    else if (Ut::frontMatches(curLine, "<cassert>",  pos)) {
                        s_includesCassert = true;
                    }
                }
            }
        }
    }

    s_state = BDEFLAG_INCLUDES_CHECKED;

    return;
}

void Lines::checkPurpose()
{
    if (BDEFLAG_DOT_H != s_fileType) {
        return;                                                       // RETURN
    }

    const bsl::string purpose = "//@PURPOSE:";
    const bsl::string provide = "Provide";
    const bsl::string lcProvide = "provide";

    int lineCount = Lines::lineCount();
    for (int li = 1; li < lineCount; ++li) {
        const bsl::string& curLine = s_lines[li];
        if (!Ut::frontMatches(curLine, purpose, 0)) {
            continue;
        }

#if 0
        if (curLine.length() < 12) {
            s_purposeFlags |= (BDEFLAG_PURPOSE_LACKS_PROVIDE |
                               BDEFLAG_PURPOSE_LACKS_PERIOD);
            return;                                                   // RETURN
        }

        const bsl::string& firstPurposeWord = Ut::wordAfter(curLine, 11);
        if (provide != firstPurposeWord && lcProvide != firstPurposeWord) {
            s_purposeFlags |= BDEFLAG_PURPOSE_LACKS_PROVIDE;
        }

        if ('.' != curLine[curLine.length() - 1]) {
            s_purposeFlags |= BDEFLAG_PURPOSE_LACKS_PERIOD;
        }
#endif

        return;                                                       // RETURN
    }

    s_purposeFlags |= BDEFLAG_NO_PURPOSE;
}

void Lines::firstDetect()
{
    BSLS_ASSERT_OPT(BDEFLAG_FIRST_DETECTED >= s_state || P((double) s_state));

    s_longLines.clear();

    s_hasTabs = false;
    s_hasCrs  = false;
    s_nonAsciiLines.clear();
    for (int li = 0; li < s_lineCount; ++li) {
        bsl::string& curLine = s_lines[li];

        if (curLine.length() > 79) {
            s_longLines.insert(li);
        }

        for (const unsigned char *pc = (unsigned char *) curLine.c_str();
                                                                   *pc; ++pc) {
            if (0x80 & *pc) {
                s_nonAsciiLines.insert(li);
                break;
            }
        }

        if (Ut::npos() != curLine.find_first_of("\r\t")) {
            s_hasTabs |= Ut::npos() != curLine.find('\t');

            bool hasCr = Ut::npos() != curLine.find('\r');
            s_hasCrs |= hasCr;
            if (hasCr) {
                bsl::size_t crPos;
                while (Ut::npos() != (crPos = curLine.find('\r'))) {
                    if (curLine.length() - 1 == crPos) {
                        curLine.resize(crPos);
                        break;
                    }
                    else {
                        curLine[crPos] = ' ';
                    }
                }
            }
        }

        if (curLine.length() > 0 && ' ' == curLine[curLine.length() - 1]) {
            s_hasTrailingBlanks = true;
        }
    }

    s_state = BDEFLAG_FIRST_DETECTED;
}

void Lines::identifyInlinesNotAlone()
{
    BSLS_ASSERT_OPT(BDEFLAG_STATEMENTS_IDENTIFIED <= s_state);

    int end = lineCount();
    for (int li = 1; li < end; ++li) {
        if (BDEFLAG_S_INLINE == statement(li)) {
            const bsl::string& curLine = Lines::line(li);
            int col = Lines::lineIndent(li);
            if (static_cast<int>(curLine.length()) != col + 6 &&
                                      "inline static" != curLine.substr(col)) {
                s_inlinesNotAlone.insert(li);
            }
        }
    }

    s_state = BDEFLAG_INLINES_NOT_ALONE;
}

void Lines::identifyStatements()
{
    BSLS_ASSERT_OPT(BDEFLAG_QUOTES_COMMENTS_KILLED <= s_state);
    BSLS_ASSERT_OPT(BDEFLAG_STATEMENTS_IDENTIFIED  >= s_state);

    static const struct {
        const char    *d_str;
        StatementType  d_statementType;
    } recStmts[] = {                            // RECognized STateMents
        { "private:",         BDEFLAG_S_PRIVATE },
        { "protected:",       BDEFLAG_S_PROTECTED },
        { "public:",          BDEFLAG_S_PUBLIC },
        { "class",            BDEFLAG_S_CLASS_STRUCT_UNION },
        { "struct",           BDEFLAG_S_CLASS_STRUCT_UNION },
        { "union",            BDEFLAG_S_CLASS_STRUCT_UNION },
        { "template",         BDEFLAG_S_TEMPLATE },
        { "return",           BDEFLAG_S_RETURN },
        { "if",               BDEFLAG_S_IF_WHILE_FOR },
        { "while",            BDEFLAG_S_IF_WHILE_FOR },
        { "for",              BDEFLAG_S_IF_WHILE_FOR },
        { "do",               BDEFLAG_S_DO },
        { "else",             BDEFLAG_S_ELSE },
        { "try",              BDEFLAG_S_TRY },
        { "BSLS_TRY",         BDEFLAG_S_TRY },
        { "__try",            BDEFLAG_S_TRY },
        { "namespace",        BDEFLAG_S_NAMESPACE },
        { "switch",           BDEFLAG_S_SWITCH },
        { "case",             BDEFLAG_S_CASE },
        { "default:",         BDEFLAG_S_DEFAULT },
        { "enum",             BDEFLAG_S_ENUM },
        { "BSLS_ASSERT",      BDEFLAG_S_ASSERT },
        { "BSLS_ASSERT_SAFE", BDEFLAG_S_ASSERT },
        { "BSLS_ASSERT_OPT",  BDEFLAG_S_ASSERT },
        { "friend",           BDEFLAG_S_FRIEND },
        { "inline",           BDEFLAG_S_INLINE },
        { "static",           BDEFLAG_S_STATIC },
        { "extern",           BDEFLAG_S_EXTERN },
        { "typedef",          BDEFLAG_S_TYPEDEF } };

    enum { NUM_REC_STMTS = sizeof recStmts / sizeof *recStmts };

    typedef bsl::map<bsl::string, StatementType>                 StmtMap;
    typedef bsl::map<bsl::string, StatementType>::const_iterator StmtMapCIt;
    StmtMap stmtMap;
    for (int i = 0; i < NUM_REC_STMTS; ++i) {
        stmtMap[recStmts[i].d_str] = recStmts[i].d_statementType;
    }
    const StmtMapCIt stmtMapEnd = stmtMap.end();

    s_statements.clear();
    s_statements.insert(s_statements.begin(),
                        s_comments.size(),
                        BDEFLAG_S_NONE);

    int lc = lineCount();
    for (int li = 0; li <= lc; ++li) {      // also do line 'lineCount'
        const bsl::string curLine = line(li);
        if (0 == curLine.length()) {
            s_statements[li] = BDEFLAG_S_BLANKLINE;
        }
        else {
            const bsl::string first = Ut::wordAfter(curLine, 0);
            StmtMapCIt it = stmtMap.find(first);
            if (stmtMapEnd != it) {
                s_statements[li] = it->second;
            }
        }
    }

    s_state = BDEFLAG_STATEMENTS_IDENTIFIED;
}

void Lines::identifyStatementEnds()
{
    BSLS_ASSERT_OPT(s_state >= BDEFLAG_STATEMENTS_IDENTIFIED);
    BSLS_ASSERT_OPT(s_state >= BDEFLAG_LINE_INDENTS_CALCULATED);

    const int lineCount = Lines::lineCount();

    BSLS_ASSERT_OPT(s_statementEnds.size() == s_lines.size());

    for (int li = 0; li < lineCount; ++li) {
        const bsl::string& curLine = line(li);

        const int cLength = curLine.length();
        if (0 == cLength) {
            s_statementEnds[li] = true;
            continue;
        }

        const char lastChar = curLine[cLength - 1];
        switch (lastChar) {
          case ';':
          case '{':
          case '}': {
            s_statementEnds[li] = true;
          }  break;
          case ':': {
            switch (Lines::statement(li)) {
              case Lines::BDEFLAG_S_SWITCH:
              case Lines::BDEFLAG_S_CASE:
              case Lines::BDEFLAG_S_DEFAULT:
              case Lines::BDEFLAG_S_PRIVATE:
              case Lines::BDEFLAG_S_PUBLIC:
              case Lines::BDEFLAG_S_PROTECTED: {
                s_statementEnds[li] = true;
              }  break;
              default: {
                ; // do nothing
              }
            }
          }  break;
          case ')': {
            // see if it's in a c'tor init list

            const int indentLevel = Lines::lineIndent(li);
            const char startChar = curLine[indentLevel];
            if (((':' == startChar) | (',' == startChar)) &&
                                                   cLength > indentLevel + 4 &&
                                         (('_' == curLine[indentLevel + 3]) &
                                          ('d' == curLine[indentLevel + 2]))) {
                s_statementEnds[li] = true;
            }
          }  break;
          default: {
            ; // do nothing
          }
        }
    }

    s_state = BDEFLAG_STATEMENTS_IDENTIFIED;
}

void Lines::killQuotesComments()
{
    BSLS_ASSERT_OPT(BDEFLAG_QUOTES_COMMENTS_KILLED >= s_state);

    static const struct {
        const char  *d_str;
        CommentType  d_commentType;
    } legalComments[] = {
        { " RETURN",                  BDEFLAG_RETURN },
        { "RETURN",                   BDEFLAG_RETURN },

        { " IMPLICIT",                BDEFLAG_IMPLICIT },
        { "IMPLICIT",                 BDEFLAG_IMPLICIT },

        { " PUBLIC TYPE",             BDEFLAG_TYPE },
        { " PRIVATE TYPE",            BDEFLAG_TYPE },
        { " PROTECTED TYPE",          BDEFLAG_TYPE },
        { " TYPE",                    BDEFLAG_TYPE },

        { " PRIVATE CLASS DATA",      BDEFLAG_CLASS_DATA },
        { " PUBLIC CLASS DATA",       BDEFLAG_CLASS_DATA },
        { " PROTECTED CLASS DATA",    BDEFLAG_CLASS_DATA },
        { " CLASS DATA",              BDEFLAG_CLASS_DATA },

        { " PRIVATE DATA",            BDEFLAG_DATA },
        { " PUBLIC DATA",             BDEFLAG_DATA },
        { " PROTECTED DATA",          BDEFLAG_DATA },
        { " DATA",                    BDEFLAG_DATA },
        { " CONSTANT",                BDEFLAG_DATA },
        { " INSTANCE DATA",           BDEFLAG_DATA },

        { " FRIEND",                  BDEFLAG_FRIEND },

        { " TRAITS",                  BDEFLAG_TRAITS },

        { " INVARIANTS",              BDEFLAG_INVARIANTS },

        { " PRIVATE CLASS METHOD",    BDEFLAG_CLASS_METHOD },
        { " PUBLIC CLASS METHOD",     BDEFLAG_CLASS_METHOD },
        { " PROTECTED CLASS METHOD",  BDEFLAG_CLASS_METHOD },
        { " CLASS METHOD",            BDEFLAG_CLASS_METHOD },

        { " PRIVATE CREATOR",         BDEFLAG_CREATOR },
        { " PUBLIC CREATOR",          BDEFLAG_CREATOR },
        { " PROTECTED CREATOR",       BDEFLAG_CREATOR },
        { " CREATOR",                 BDEFLAG_CREATOR },

        { " PRIVATE MANIPULATOR",     BDEFLAG_MANIPULATOR },
        { " PUBLIC MANIPULATOR",      BDEFLAG_MANIPULATOR },
        { " PROTECTED MANIPULATOR",   BDEFLAG_MANIPULATOR },
        { " MANIPULATOR",             BDEFLAG_MANIPULATOR },

        { " PRIVATE ACCESSOR",        BDEFLAG_ACCESSOR },
        { " PUBLIC ACCESSOR",         BDEFLAG_ACCESSOR },
        { " PROTECTED ACCESSOR",      BDEFLAG_ACCESSOR },
        { " ACCESSOR",                BDEFLAG_ACCESSOR },

        { " FREE OPERATOR",           BDEFLAG_FREE_OPERATOR },

        { " NOT IMPLEMENTED",         BDEFLAG_NOT_IMPLEMENTED },

        { " close namespace",         BDEFLAG_CLOSE_NAMESPACE },
        { " close unnamed namespace", BDEFLAG_CLOSE_UNNAMED_NAMESPACE },
        { " close enterprise namespace",
                                      BDEFLAG_CLOSE_ENTERPRISE_NAMESPACE },
        { " close package namespace", BDEFLAG_CLOSE_PACKAGE_NAMESPACE },
        { "! ",                       BDEFLAG_BANG },
        { " CLASS INVARIANT",         BDEFLAG_IGNORED },
        { " STANDARD TYPEDEF",        BDEFLAG_IGNORED } };

    enum { NUM_LEGAL_COMMENTS = sizeof legalComments / sizeof *legalComments };

    typedef bsl::map<bsl::string, CommentType>                 CommentMap;
    typedef bsl::map<bsl::string, CommentType>::const_iterator CommentMapCIt;
    CommentMap commentMap;
    for (int i = 0; i < NUM_LEGAL_COMMENTS; ++i) {
        commentMap[legalComments[i].d_str] = legalComments[i].d_commentType;
    }
    const CommentMapCIt commentMapBegin = commentMap.begin();

    s_cStyleComments.clear();

    char quote = 0;    // 0: not in quoted str, ':in quoted char, ": in q str
    const int lineCount = s_lineCount;
    bool inCStyleComment = false;
    for (int li = 0; li < s_lineCount; ++li) {
        bsl::string& curLine = s_lines[li];
        const int len = curLine.length();

        bool slash    = false;
        bool asterisk = false;
        for (int col = 0; col < len; col = (slash | asterisk | inCStyleComment)
                                         ? col + 1
                                         : nextLiveChar(curLine, col + 1)) {
            char& c = curLine[col];

            if (!inCStyleComment) {
                BSLS_ASSERT_OPT(!asterisk);

                // Handle quoted strings

                if (quote | ('"' == c) | ('\'' == c)) {
                    BSLS_ASSERT_OPT(!quote || 0 == col);
                    slash = false;

                    const char startChar  = quote ? quote : c;
                    size_t       endPos   = quote ? -1 : col;
                    const char *endStr = '"' == startChar ? "\\\"" : "\\'";
                    while (Ut::npos() !=
                        (endPos = curLine.find_first_of(endStr, endPos + 1))) {
                        if ('\\' == curLine[endPos]) {
                            if (curLine.length() > endPos + 1) {
                                ++endPos;    // skip the quoted char
                            }
                            else {
                                quote = startChar;    // string goes off line
                            }
                        }
                        else {
                            quote = 0;    // string ended
                            break;
                        }
                    }
                    if (Ut::npos() == endPos) {
                        endPos = curLine.length();
                    }
                    else {
                        BSLS_ASSERT_OPT(startChar == curLine[endPos]);

                        ++endPos;
                    }
                    const bsl::string& endLine = curLine.substr(endPos);

                    // Note the following manipulation of 'curLine' may
                    // invalidate reference 'c'.

                    curLine.resize(col);
                    curLine.append(endPos - col, startChar);
                    curLine += endLine;

                    BSLS_ASSERT_OPT(curLine.length() == len);
                    BSLS_ASSERT_OPT(endPos >= 1);
                    BSLS_ASSERT_OPT(!quote || len == endPos);

                    col = endPos - 1;

                    continue;    // on to next char
                }

                if (slash) {
                    slash = false;

                    if ('/' == c) {
                        // C++ comment

                        ++col;
                        CommentType& cmtRef = s_comments[li];
                        cmtRef = BDEFLAG_UNRECOGNIZED;
                        s_commentIndents[li] = col - 2;
                        bsl::string comment = curLine.substr(col);

                        if (bdeu_String::strstrCaseless(comment.c_str(),
                                                        comment.length(),
                                                        "tbd",
                                                        3)) {
                            s_tbds.insert(li);
                        }

                        CommentMapCIt it = commentMap.upper_bound(comment);

                        // 'it' now points to the lowest key > comment

                        if (commentMapBegin != it &&
                             (--it, Ut::frontMatches(comment, it->first, 0))) {
                            cmtRef = it->second;
                        }
                        else if     (comment.length() >= 6) {
                            if (!bsl::strcmp(
                                         comment.data() + comment.length() - 6,
                                         "RETURN")) {
                                cmtRef = BDEFLAG_RETURN;
                            }
                            else if (comment.length() >= 8 &&
                                    !bsl::strcmp(
                                         comment.data() + comment.length() - 8,
                                         "IMPLICIT")) {
                                cmtRef = BDEFLAG_IMPLICIT;
                            }
                        }
                        if (79 != curLine.length()) {
                            if      (BDEFLAG_IMPLICIT == cmtRef) {
                                s_badlyAlignedImplicits.insert(li);
                            }
                            else if (BDEFLAG_RETURN   == cmtRef) {
                                s_badlyAlignedReturns.  insert(li);
                            }
                        }

                        // Wipe out the comment.  Preserve '\' in case we're
                        // in a macro, so the macro will be properly wiped
                        // out.

                        bool lastSlash = '\\' == curLine[curLine.length() - 1];

                        curLine.resize(col-2);
                        if (lastSlash) {
                            curLine += " \\";
                            if (li + 1 >= s_lineCount) {
                                s_contComments.insert(li);
                            }
                            else {
                                const bsl::string& nextLine = s_lines[li + 1];
                                bsl::size_t firstNonBlank =
                                               nextLine.find_first_not_of(' ');
                                if (Ut::npos() == firstNonBlank
                                   || firstNonBlank + 2 > nextLine.size()
                                   || '/' != nextLine[firstNonBlank]
                                   || '/' != nextLine[firstNonBlank + 1]) {
                                    s_contComments.insert(li);
                                }
                            }
                        }
                        break;
                    }
                    else if ('*' == c) {
                        inCStyleComment = true;
                        s_cStyleComments.insert(li);
                        curLine[col - 1] = ' ';
                        c = ' ';
                    }
                }
                else {
                    if ('/' == c) {
                        slash = true;
                    }
                }
            }
            else {
                // in C-style Comment

                BSLS_ASSERT_OPT(!quote);
                BSLS_ASSERT_OPT(!slash);

                if ('\\' != c || col != curLine.length() - 1) {
                    if (asterisk) {
                        asterisk = false;

                        if ('/' == c) {
                            inCStyleComment = false;
                        }
                    }
                    if ('*' == c) {
                        asterisk = true;
                    }
                    c = ' ';
                }
                else {
                    asterisk = false;
                }
            }
        }
    }

    s_state = BDEFLAG_QUOTES_COMMENTS_KILLED;
}

void Lines::setLineIndents()
{
    BSLS_ASSERT_OPT(s_state <= BDEFLAG_LINE_INDENTS_CALCULATED);

    int lineCount = s_lineCount;
    for (int i = 0; i < lineCount; ++i) {
        size_t pos = line(i).find_first_not_of(' ');
        s_lineIndents[i] = Ut::npos() == pos ? 0 : pos;
    }

    s_state = BDEFLAG_LINE_INDENTS_CALCULATED;
}

void Lines::trimTrailingWhite()
{
    int lineCount = Lines::lineCount();
    for (int li = 0; li < lineCount; ++li) {
        Ut::trim(&s_lines[li]);
    }
}

void Lines::untabify()
{
    int lineCount = Lines::lineCount();
    for (int li = 0; li < lineCount; ++li) {
        bsl::string& curLine = s_lines[li];
        int len = curLine.length();

        for (int col = 0; col < len; ++col) {
            if ('\t' == curLine[col]) {
                curLine[col] = ' ';
                const int charAfter = ((col + 8) / 8) * 8;
                ++col;
                const int toInsert = charAfter - col;
                BSLS_ASSERT_OPT(toInsert >= 0);  BSLS_ASSERT_OPT(toInsert < 8);

                curLine.insert(col, toInsert, ' ');
                len += toInsert;
                BSLS_ASSERT_OPT(curLine.length() == len);
                col = charAfter - 1;
            }
        }
    }
}

void Lines::wipeOutMacros()
{
    // Two passes -- first pass take of '#if 0' blocks, second take out all
    // other macros.

    BSLS_ASSERT_OPT(BDEFLAG_MACROS_WIPED_OUT >= s_state);

    const bsl::string S_IF = "if";
    const bsl::string S_ELSE = "else";
    const bsl::string S_ELIF = "elif";
    const bsl::string S_ENDIF = "endif";

    int startIf = -1;
    int lineCount = this->lineCount();
    for (int li = 1; li < lineCount; ++li) {
        bsl::string& curLine = s_lines[li];

        int end;
        int col = Lines::lineIndent(li);
        if ('#' == curLine[col]) {
            if ((int) curLine.length() <= col + 1) {
                curLine.resize(col);
                continue;
            }
            const bsl::string& wa = Ut::wordAfter(curLine, col + 1, &end);
            if (S_ELSE == wa || S_ELIF == wa ||
                      (S_IF == wa && "0" == Ut::wordAfter(curLine, end + 1))) {
                int depth = 1;
                int li2;
                for (li2 = li + 1; li2 < lineCount; ++li2) {
                    bsl::string& curLine2 = s_lines[li2];

                    if (curLine.length() > 0) {
                        col = Lines::lineIndent(li2);
                        if ('#' == curLine2[col]) {
                            col = curLine2.find_first_not_of(' ', col + 1);
                            if (Ut::frontMatches(curLine2, S_IF, col)) {
                                ++depth;
                            }
                            else if (S_ENDIF == Ut::wordAfter(curLine2, col)) {
                                --depth;
                                if (0 == depth) {
                                    for (int j = li; j <= li2; ++j) {
                                        s_lines[j] = "";
                                        s_lineIndents[j] = 0;
                                        s_comments[j] = BDEFLAG_NONE;
                                        s_commentIndents[j] = 0;
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
                if (lineCount == li2 && depth > 0) {
                    cerr << "Error: " << fileName() << ": unmatched '#if' or"
                                                 " '#ifdef' at " << li << endl;
                    break;
                }
            }
        }
    }

    bool inMacro = false;
    for (int li = 1; li < lineCount; ++li) {
        bsl::string& curLine = s_lines[li];

        inMacro = inMacro || '#' == Ut::firstCharOf(curLine);

        if (inMacro) {
            bool lastCharContinues = '\\' == Ut::lastCharOf(curLine);

            curLine = "";
            s_comments[li] = BDEFLAG_NONE;
            s_commentIndents[li] = 0;

            if (!lastCharContinues) {
                inMacro = false;
            }
        }
    }

    // Remove any residual trailing slashes that might have been left over
    // after comments (comments ending with '\' were preserved as just the
    // the '\' in case they were within macros.

    for (int li = 1; li < lineCount; ++li) {
        bsl::string& curLine = s_lines[li];

        while ('\\' == Ut::lastCharOf(curLine)) {
            curLine.resize(curLine.length() - 1);
        }
    }

    s_state = BDEFLAG_MACROS_WIPED_OUT;
}

// CLASS METHODS
void Lines::braceReport()
{
    cout << "<line#> <curly-brace-depth> <paren-depth> <source-line>\n\n";

    int curly = 0, paren = 0;

    for (int li = 1; li <= s_lineCount; ++li) {
        const char *pc = li < s_lineCount ? s_lines[li].c_str() : "";

        cout.width(3);
        cout << li;
        cout.width(0);
        cout << ' ' << curly << ' ' << paren << ' ' << pc << endl;

        for (; *pc; ++pc) {
            switch (*pc) {
              case ('{'): {
                ++curly;
              } break;
              case ('}'): {
                --curly;
              } break;
              case ('('): {
                ++paren;
              } break;
              case (')'): {
                --paren;
              } break;
            }
        }
    }
}

bsl::string Lines::commentAsString(CommentType comment)
{
    switch (comment) {
      case BDEFLAG_NONE:                    return "NONE";
      case BDEFLAG_RETURN:                  return "RETURN";
      case BDEFLAG_TYPE:                    return "TYPE";
      case BDEFLAG_CLASS_DATA:              return "CLASS DATA";
      case BDEFLAG_DATA:                    return "DATA";
      case BDEFLAG_FRIEND:                  return "FRIEND";
      case BDEFLAG_TRAITS:                  return "TRAITS";
      case BDEFLAG_INVARIANTS:              return "INVARIANTS";
      case BDEFLAG_CLASS_METHOD:            return "CLASS METHOD";
      case BDEFLAG_NOT_IMPLEMENTED:         return "NOT IMPLEMENTED";
      case BDEFLAG_CREATOR:                 return "CREATOR";
      case BDEFLAG_MANIPULATOR:             return "MANIPULATOR";
      case BDEFLAG_ACCESSOR:                return "ACCESSOR";
      case BDEFLAG_FREE_OPERATOR:           return "FREE OPERATOR";
      case BDEFLAG_CLOSE_NAMESPACE:         return "close namespace";
      case BDEFLAG_CLOSE_UNNAMED_NAMESPACE: return "close unnamed namespace";
      case BDEFLAG_UNRECOGNIZED:            return "<unrecognized>";
      default:                              return "<strange>";
    }
}

int Lines::lineBefore(int *cli_p)
{
    if (*cli_p < 1) {
        *cli_p = 0;
        return 0;                                                     // RETURN
    }
    else {
        if (*cli_p >= Lines::lineCount()) {
            *cli_p = Lines::lineCount() - 1;
        }
    }
    int li = *cli_p - 1;

    // the 0th line is 0 length

    for (; true; --li) {
        if (s_statementEnds[li]) {
            return li;                                                // RETURN
        }
    }
}

// CREATORS
Lines::Lines(const char *fileName)
{
    s_state = BDEFLAG_EMPTY;

    s_fileName = fileName;
    s_lineCount = 0;

    s_lines.clear();
    s_badlyAlignedImplicits.clear();
    s_badlyAlignedReturns.clear();
    s_comments.clear();
    s_longLines.clear();
    s_cStyleComments.clear();
    s_tbds.clear();
    s_contComments.clear();
    s_purposeFlags = 0;
    s_hasTabs = false;
    s_hasCrs = false;
    s_hasTrailingBlanks = false;
    s_includesAssertH = false;
    s_includesCassert = false;
    s_includesDoubleQuotes = false;
    s_assertFound = false;
    s_includesComponentDotH = false;
    s_couldntOpenFile = false;
    s_componentPrefix = BDEFLAG_CP_UNRECOGNIZED;

    s_fileType = BDEFLAG_DOT_CPP;
    if (s_fileName.length() >= 2) {
        if (s_fileName.substr(s_fileName.length() - 2) == ".h") {
            s_fileType = BDEFLAG_DOT_H;
        } else if (s_fileName.length() >= 6) {
            const bsl::string& suffix =
                                    s_fileName.substr(s_fileName.length() - 6);
            if (suffix == ".t.cpp" || suffix == ".m.cpp") {
                s_fileType = BDEFLAG_DOT_T_DOT_CPP;
            }
        }
    }

    {
        int matchIdx = Ut::frontMatches(fileName, "bsl",     0)
                     ? 3
                     : Ut::frontMatches(fileName, "tst_bsl", 0)
                     ? 7
                     : 0;
        if (matchIdx) {
            if      (Ut::frontMatches(fileName, "stl_", matchIdx)) {
                s_componentPrefix = BDEFLAG_CP_BSLSTL;
            }
            else if (Ut::frontMatches(fileName, "mf_",  matchIdx)) {
                s_componentPrefix = BDEFLAG_CP_BSLMF;
            }
        }
    }

    bsl::ifstream fin(fileName);
    if (!fin) {
        s_couldntOpenFile = true;
        return;                                                       // RETURN
    }

    {
        // Estimate the file as having one line for every 20 chars, reserve
        // that much space in the vector.

        struct stat st;
        stat(fileName, &st);
        const int ESTLINES = st.st_size / 20;
        s_lines.reserve(ESTLINES);
    }

    s_lines.push_back("");

    // Read all lines into the vector 'lines'.  The newlines are discarded.

    while (true) {
        bsl::string oneLine;
        bsl::getline(fin, oneLine, '\n');
        if (fin.eof() && 0 == oneLine.length()) {
            break;
        }
        s_lines.push_back(oneLine);
    }

    fin.close();

    s_lineCount = s_lines.size();
    s_lines.push_back("");    // Add 1 extra line so we don't segfault if
                              // we access one line over.
    s_comments.insert(s_comments.end(), s_lines.size(), BDEFLAG_NONE);
    s_commentIndents.insert(s_commentIndents.end(), s_lines.size(), -1);
    s_lineIndents.insert(s_lineIndents.end(),       s_lines.size(),  0);
    s_statementEnds.insert(s_statementEnds.end(), s_lines.size(), false);

    s_state = BDEFLAG_LOADED;

    firstDetect();
    untabify();
    checkIncludes();
    checkForAssert();
    checkPurpose();
    killQuotesComments();
    trimTrailingWhite();
    setLineIndents();
    wipeOutMacros();
    identifyStatements();
    identifyStatementEnds();
    identifyInlinesNotAlone();
}

Lines::Lines(const bsl::string& string)
{
    bslma_Allocator *da = bslma_Default::defaultAllocator();

    s_state = BDEFLAG_EMPTY;

    s_fileName = "dummy_string";
    s_fileType = BDEFLAG_DOT_CPP;
    s_lineCount = 0;

    s_lines.clear();
    s_badlyAlignedImplicits.clear();
    s_badlyAlignedReturns.clear();
    s_comments.clear();
    s_longLines.clear();
    s_cStyleComments.clear();
    s_tbds.clear();
    s_contComments.clear();
    s_purposeFlags = 0;
    s_hasTabs = false;
    s_hasCrs = false;
    s_hasTrailingBlanks = false;
    s_includesAssertH = false;
    s_includesCassert = false;
    s_includesDoubleQuotes = false;
    s_assertFound = false;
    s_includesComponentDotH = false;
    s_couldntOpenFile = false;
    s_componentPrefix = BDEFLAG_CP_UNRECOGNIZED;

    s_lines.push_back("");

    size_t pos = 0, nextPos;
    while (Ut::npos() != (nextPos = string.find('\n', pos))) {
        s_lines.push_back(string.substr(pos, nextPos - pos));
        pos = nextPos + 1;
    }
    if (pos < string.length()) {
        s_lines.push_back(string.substr(pos));
    }

    s_lineCount = s_lines.size();
    s_lines.push_back("");    // Add 1 extra line so we don't segfault if
                              // we access one line over.
    s_comments.insert(s_comments.end(), s_lines.size(), BDEFLAG_NONE);
    s_commentIndents.insert(s_commentIndents.end(), s_lines.size(), -1);
    s_lineIndents.insert(s_lineIndents.end(),       s_lines.size(),  0);
    s_statementEnds.insert(s_statementEnds.end(), s_lines.size(), false);

    s_state = BDEFLAG_LOADED;

    firstDetect();
    checkIncludes();
    checkForAssert();
    checkPurpose();
    killQuotesComments();
    trimTrailingWhite();
    setLineIndents();
    wipeOutMacros();
    identifyStatements();
    identifyStatementEnds();
    identifyInlinesNotAlone();
}

Lines::~Lines()
{
    s_fileName = "";
    s_lines.clear();
    s_comments.clear();
    s_lineIndents.clear();
    s_commentIndents.clear();
    s_statements.clear();
    s_statementEnds.clear();
    s_lineCount = 0;
    s_longLines.clear();
    s_cStyleComments.clear();
    s_inlinesNotAlone.clear();
    s_badlyAlignedImplicits.clear();
    s_badlyAlignedReturns.clear();
    s_tbds.clear();
    s_contComments.clear();
    s_state = BDEFLAG_EMPTY;
    s_hasTabs = false;
    s_hasCrs = false;
    s_hasTrailingBlanks = false;
    s_includesAssertH = false;
    s_includesCassert = false;
    s_includesDoubleQuotes = false;
}

// ACCESSORS

void Lines::printWarnings(bsl::ostream *stream) const
{
    if (s_hasTabs) {
        *stream << "Warning: file " << s_fileName << " has tab(s).\n";
    }
    if (s_hasCrs && !Lines_StartProgram::s_crsOK) {
        *stream << "Warning: file " << s_fileName << " has '\\r'(s).\n";

        static bool firstTime = true;
        if (firstTime) {
            firstTime = false;
            *stream << "    Note: warnings about '\\r's can be suppressed by"
                                                " setting environment variable"
                                     " '$BDEFLAG_TOLERATE_CARRIAGE_RETURNS'\n";
        }
    }
    if (!s_nonAsciiLines.empty()) {
        *stream << "Warning: file " << s_fileName <<
                 " has non-ascii chars on line(s) " << s_nonAsciiLines << endl;
    }
    if (s_hasTrailingBlanks) {
        *stream << "Warning: file " << s_fileName <<
                                                   " has trailing blank(s).\n";
    }
    if (s_includesDoubleQuotes) {
        *stream << "Warning: " << s_fileName <<
                   ": 'include \"*\"' encountered, should be 'include <*>'.\n";
    }
    if (s_includesAssertH) {
        *stream << "Warning: " << s_fileName <<
                    ": 'include <assert.h>' encountered, use bsls_assert.h.\n";
    }
    if (s_includesCassert) {
        *stream << "Warning: " << s_fileName <<
                     ": 'include <cassert>' encountered, use bsls_assert.h.\n";
    }
    if (s_assertFound) {
        *stream << "Warning: " << s_fileName <<
                                    ": 'ASSERT' found in comment in .h file\n";
    }
    if (BDEFLAG_DOT_H != s_fileType && !s_includesComponentDotH &&
              !s_couldntOpenFile && Ut::npos() == s_fileName.find(".m.cpp")) {
        *stream << "Warning: " << s_fileName <<
                        ": should include, as the first include, '#include " <<
                                                  componentInclude() << "'.\n";
    }
    if (s_couldntOpenFile) {
        *stream << "Warning: " << s_fileName << ": could not be opened\n";
    }
    if (!s_longLines.empty()) {
        *stream << "Warning: long line(s) in " << s_fileName <<
                                        " at line(s): " << s_longLines << endl;
    }
    if (!s_cStyleComments.empty()) {
        *stream << "Warning: C-style comment(s) in " << s_fileName <<
                                   " at line(s): " << s_cStyleComments << endl;
    }
    if (!s_inlinesNotAlone.empty()) {
        *stream << "Warning: in " << s_fileName << " 'inline' not on its own"
                " line ('inline static' is OK): " << s_inlinesNotAlone << endl;
    }
    if (!s_badlyAlignedImplicits.empty()) {
        *stream << "Warning: in " << s_fileName << " '// IMPLICIT' comment not"
                                 " right-justified to 79 chars at line(s): " <<
                                               s_badlyAlignedImplicits << endl;
    }
    if (!s_badlyAlignedReturns.empty()) {
        *stream << "Warning: in " << s_fileName << " '// RETURN' comment not"
                                 " right-justified to 79 chars at line(s): " <<
                                                 s_badlyAlignedReturns << endl;
    }
    if (!s_tbds.empty()) {
        *stream << "Warning: in " << s_fileName << " 'TBD' comments found on"
                                                 " line(s) " << s_tbds << endl;
    }
    if (!s_contComments.empty()) {
        *stream << "Warning: in " << s_fileName <<
          " '\\' at end of comment line on line(s) " << s_contComments << endl;
    }
    if (s_purposeFlags) {
        if (s_purposeFlags & BDEFLAG_NO_PURPOSE) {
            *stream << "Warning: in " << s_fileName <<
                                             " no '@PURPOSE:' comment" << endl;
        }
        if (s_purposeFlags & BDEFLAG_PURPOSE_LACKS_PROVIDE) {
            *stream << "Warning: in " << s_fileName <<
                       " '@PURPOSE:' comment doesn't start with \"Provide\"\n";
        }
        if (s_purposeFlags & BDEFLAG_PURPOSE_LACKS_PERIOD) {
            *stream << "Warning: in " << s_fileName <<
                                 " '@PURPOSE:' comment doesn't end with '.'\n";
        }
    }
}

bsl::string Lines::asString()
{
    BSLS_ASSERT_OPT(lineCount() >= 1);
    BSLS_ASSERT_OPT(0 == line(0).length());

    int totalSize = 0;
    for (int i = 1; i < lineCount(); ++i) {
        totalSize += line(i).length();
    }
    totalSize += lineCount() - 1;    // '\n's
    ++totalSize;    // terminating '\0' in c_str()

    bsl::string ret;
    ret.reserve(totalSize);

    for (int i = 1; i < lineCount(); ++i) {
        ret += line(i);
        ret += '\n';
    }
    ret.c_str();

    return ret;
}

// FREE OPERATORS
bsl::ostream& operator<<(bsl::ostream& stream, Lines::CommentType commentType)
{
    switch (commentType) {
      case Lines::BDEFLAG_NONE: {
        stream << "BDEFLAG_NONE";
      }  break;
      case Lines::BDEFLAG_RETURN: {
        stream << "BDEFLAG_RETURN";
      }  break;
      case Lines::BDEFLAG_TYPE: {
        stream << "BDEFLAG_TYPE";
      }  break;
      case Lines::BDEFLAG_CLASS_DATA: {
        stream << "BDEFLAG_CLASS_DATA";
      }  break;
      case Lines::BDEFLAG_DATA: {
        stream << "BDEFLAG_DATA";
      }  break;
      case Lines::BDEFLAG_FRIEND: {
        stream << "BDEFLAG_FRIEND";
      }  break;
      case Lines::BDEFLAG_TRAITS: {
        stream << "BDEFLAG_TRAITS";
      }  break;
      case Lines::BDEFLAG_INVARIANTS: {
        stream << "BDEFLAG_INVARIANTS";
      }  break;
      case Lines::BDEFLAG_CLASS_METHOD: {
        stream << "BDEFLAG_CLASS_METHOD";
      }  break;
      case Lines::BDEFLAG_NOT_IMPLEMENTED: {
        stream << "BDEFLAG_NOT_IMPLEMENTED";
      }  break;
      case Lines::BDEFLAG_CREATOR: {
        stream << "BDEFLAG_CREATOR";
      }  break;
      case Lines::BDEFLAG_MANIPULATOR: {
        stream << "BDEFLAG_MANIPULATOR";
      }  break;
      case Lines::BDEFLAG_ACCESSOR: {
        stream << "BDEFLAG_ACCESSOR";
      }  break;
      case Lines::BDEFLAG_FREE_OPERATOR: {
        stream << "BDEFLAG_FREE_OPERATOR";
      }  break;
      case Lines::BDEFLAG_CLOSE_NAMESPACE: {
        stream << "BDEFLAG_CLOSE_NAMESPACE";
      }  break;
      case Lines::BDEFLAG_CLOSE_UNNAMED_NAMESPACE: {
        stream << "BDEFLAG_CLOSE_UNNAMED_NAMESPACE";
      }  break;
      case Lines::BDEFLAG_CLOSE_ENTERPRISE_NAMESPACE: {
        stream << "BDEFLAG_CLOSE_ENTERPRISE_NAMESPACE";
      }  break;
      case Lines::BDEFLAG_CLOSE_PACKAGE_NAMESPACE: {
        stream << "BDEFLAG_CLOSE_PACKAGE_NAMESPACE";
      }  break;
      case Lines::BDEFLAG_UNRECOGNIZED: {
        stream << "BDEFLAG_UNRECOGNIZED";
      }  break;
      default: {
        stream << "invalid comment type";
      }
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
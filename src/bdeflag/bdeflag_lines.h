// bdeflag_report.h                                                   -*-C++-*-

#ifndef INCLUDED_BDEFLAG_LINES
#define INCLUDED_BDEFLAG_LINES

#ifndef INCLUDED_BSLS_IDENT
#include <bsls_ident.h>
#endif
BSLS_IDENT("$Id: $")

//@PURPOSE: Provide vectorized representation of a source file.
//
//@CLASSES:
//    Lines: vectorized representation of a source file
//
//@AUTHOR: Bill Chapman
//
//@DESCRIPTION: The component is capable of reading in a source file, via two
// constructors.  One, which takes a bsl::string, assumes the string contains
// the C++ source to be read.  The other, taking a 'const char *', assumes the
// argument is the path to a file to be read.
//
// The bdeflag::Line class contains no instance data, but it can be constructed
// and destructed.  When constructed, it initializes a lot of static variables,
// when destructed, it makes sure any allocated memory is freed.  It creates a
// description of the file, which is a vector of string with the comments,
// macros, and newlines stripped.  There are separate vectors, one of strings
// containing code, one of enum's describing certain special comments that are
// recognized, one of enum's describing certain reserved words if they appear
// at the start of lines, one of ints representing the indentation of comments,
// and one of ints representing the indentation of the first nonwhite char of
// the line.  It has other static state, such as a set of line numbers of lines
// that were too long, a set of line numbers where C-style comments happened,
// and booleans, for example whether there were any tabs in the file.
//
// In practice, a caller constructs a line object, and then does not use the
// object but rather calls static methods within the class for services until
// finished, then destroys the object.

#ifndef INCLUDED_BDEFLAG_UT
#include <bdeflag_ut.h>
#endif

#ifndef INLCUDED_BSL_IOSTREAM
#include <bsl_iostream.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#endif

#ifndef INCLUDED_BSL_UTILITY
#include <bsl_utility.h>
#endif

#ifndef INCLUDED_BSL_LIST
#include <bsl_list.h>
#endif

#ifndef INCLUDED_BSL_VECTOR
#include <bsl_vector.h>
#endif

namespace BloombergLP {

namespace bdeFlag {

class Lines {
  public:
    // TYPES
    enum CommentType {
        BDEFLAG_NONE,
        BDEFLAG_RETURN,
        BDEFLAG_TYPE,
        BDEFLAG_CLASS_DATA,
        BDEFLAG_DATA,
        BDEFLAG_FRIEND,
        BDEFLAG_TRAITS,
        BDEFLAG_INVARIANTS,
        BDEFLAG_CLASS_METHOD,
        BDEFLAG_NOT_IMPLEMENTED,
        BDEFLAG_CREATOR,
        BDEFLAG_MANIPULATOR,
        BDEFLAG_ACCESSOR,
        BDEFLAG_FREE_OPERATOR,
        BDEFLAG_CLOSE_NAMESPACE,
        BDEFLAG_CLOSE_UNNAMED_NAMESPACE,
        BDEFLAG_CLOSE_ENTERPRISE_NAMESPACE,
        BDEFLAG_UNRECOGNIZED };

    enum StatementType {
        BDEFLAG_S_NONE,                  // also means 'unrecognized'
        BDEFLAG_S_BLANKLINE,             // also means 'comment only'
        BDEFLAG_S_PRIVATE,
        BDEFLAG_S_PUBLIC,
        BDEFLAG_S_PROTECTED,
        BDEFLAG_S_CLASS_STRUCT_UNION,
        BDEFLAG_S_TEMPLATE,
        BDEFLAG_S_RETURN,
        BDEFLAG_S_IF_WHILE_FOR,
        BDEFLAG_S_DO,
        BDEFLAG_S_ELSE,
        BDEFLAG_S_TRY,
        BDEFLAG_S_NAMESPACE,
        BDEFLAG_S_SWITCH,
        BDEFLAG_S_CASE,
        BDEFLAG_S_DEFAULT,
        BDEFLAG_S_ENUM,
        BDEFLAG_S_ASSERT,
        BDEFLAG_S_FRIEND,
        BDEFLAG_S_INLINE,
        BDEFLAG_S_STATIC,
        BDEFLAG_S_EXTERN,
        BDEFLAG_S_TYPEDEF };

    enum FileType {
        BDEFLAG_DOT_CPP,
        BDEFLAG_DOT_H,
        BDEFLAG_DOT_T_DOT_CPP };

    enum PurposeFlags {
        BDEFLAG_NO_PURPOSE            = 0x1,
        BDEFLAG_PURPOSE_LACKS_PROVIDE = 0x2,
        BDEFLAG_PURPOSE_LACKS_PERIOD  = 0x4 };

  private:
    // PRIVATE TYPES
    typedef bsl::vector<bsl::string>   LineVec;
    typedef bsl::vector<CommentType>   CommentVec;
    typedef bsl::vector<int>           IndentVec;
    typedef bsl::vector<StatementType> StatementVec;

    enum State {
        BDEFLAG_EMPTY,
        BDEFLAG_LOADED,
        BDEFLAG_FIRST_DETECTED,
        BDEFLAG_INCLUDES_CHECKED,
        BDEFLAG_QUOTES_COMMENTS_KILLED,
        BDEFLAG_MACROS_WIPED_OUT,
        BDEFLAG_LINE_INDENTS_CALCULATED,
        BDEFLAG_STATEMENTS_IDENTIFIED,
        BDEFLAG_STATEMENT_ENDS_IDENTIFIED,
        BDEFLAG_INLINES_NOT_ALONE };

  private:
    // CLASS DATA
    static bsl::string         s_fileName;
    static FileType            s_fileType;
    static LineVec             s_lines;
    static CommentVec          s_comments;
    static IndentVec           s_commentIndents;
    static IndentVec           s_lineIndents;
    static StatementVec        s_statements;
    static bsl::vector<bool>   s_statementEnds;
    static int                 s_lineCount;
    static Ut::LineNumSet      s_longLines;
    static Ut::LineNumSet      s_cStyleComments;
    static Ut::LineNumSet      s_inlinesNotAlone;
    static Ut::LineNumSet      s_badlyAlignedReturns;
    static Ut::LineNumSet      s_tbds;
    static State               s_state;
    static int                 s_purposeFlags;
    static bool                s_hasTabs;
    static bool                s_hasTrailingBlanks;
    static bool                s_includesAssertH;
    static bool                s_includesCassert;
    static bool                s_includesDoubleQuotes;
    static bool                s_assertFound;
    static bool                s_includesComponentDotH;
    static bool                s_couldntOpenFile;

    // Only manipulators can change the value of static members

    // PRIVATE MANIPULATORS
    void checkForAssert();
        // If this is a .h file, it is an error if there are any 'ASSERT'
        // calls in the comments.  Note 'BSLS_ASSERT(' is not an error, and
        // the 'ASSERT' has to be immediately followed by a '('.

    void checkIncludes();
        // Set the values of the 's_include*' static flags.

    void checkPurpose();
        // If the file is a .h file, check the 'Purpose' line.

    void firstDetect();
        // Detect any long lines and tabs in the file, don't print out any
        // errors, just record them in static data.

    void identifyInlinesNotAlone();
        // Identify any 'inline' statements that are not on their own line,
        // except for 'inline static' which is OK.

    void identifyStatements();
        // Populate the 's_statement' vector of enums representing certain
        // reserved words which may appear at the start of the line.

    void identifyStatementEnds();
        // Populate the vector identify which lines contain end of statements.

    void killQuotesComments();
        // Replace quoted strings with solid blocks of quotes, remove comments.

    void setLineIndents();
        // Populate the vector of indentations of first nonwhite chars of
        // lines.

    void trimTrailingWhite();
        // Trim trailing whitespace from all the lines.

    void untabify();
        // Expand tabs into spaces.

    void wipeOutMacros();
        // Remove macros, also remove all code enclosed by '#else' - '#endif'
        // blocks.

  public:
    // Note class methods do not change value of static members.

    // CLASS METHODS
    static
    bsl::string asString();
        // Return the whole collection of lines as a single string.  For
        // testing.

    static
    CommentType comment(int index);
        // Return the enum representing any standard comment found at line
        // line indicated by 'index'

    static
    bsl::string commentAsString(CommentType comment);
        // Given the specified 'comment', which is an enum representing a
        // standard comment, give the comment in string form.

    static
    int commentIndent(int index);
        // Return the indentation of any comment on line indicated by 'index'.

    static
    const Ut::LineNumSet& cStyleComments();
        // Return the set of line numbers which had C-style comments beginning
        // on them.

    static
    const bsl::string& fileName();
        // Return the name of the current file.

    static
    FileType fileType();
        // Return an enum representing the type of the current file, '.h',
        // '.cpp', or '.t.cpp'.

    static
    bool hasTabs();
        // Return 'true' if the current file had any tabs in it and 'false'
        // otherwise.

    static
    bool hasTrailingBlanks();
        // Return 'true' if the file had any trailing blanks on lines and
        // 'false' otherwise.

    static
    bool includesDoubleQuotes();
        // Return 'true' if the file had any includes with double quotes and
        // 'false' otherwise.

    static
    bool includesAssertH();
        // Return 'true' if the file include 'assert.h' and 'false' otherwise.

    static
    bool includesCassert();
        // Return 'true' if the file include 'cassert' and 'false' otherwise.

    static
    bool isProtectionLine(int index);
        // Return 'true' if the line indicated by the specified 'index' had
        // 'private', 'protected', or 'public' on it, and false otherwise.

    static
    const bsl::string& line(int index);
        // Return a const reference to the string representing the line
        // indicated by the specified 'index'.

    static
    int lineBefore(int *cli_p);
        // Return the line before the current statement.  Note this is not
        // Place::statementStart().lineNum() - 1, it is the statement before
        // any of the statement gets underway.  '*cli_p' is the statement
        // we began on, except it is clipped to be in the range
        // '[ 0 .. lineCount() )'.

    static
    int lineCount();
        // Return the number of lines in the file (including the 0 line).

    static
    int lineIndent(int index);
        // Return the indentation of the line indicated by the specified
        // 'index'.

    static
    int lineLength(int index);
        // Return the length of the line indicated by the specified 'index'.
        // This is sometimes preferred to 'line(index).length()' because it
        // returns an 'int' and not a 'size_t'.

    static
    const Ut::LineNumSet& longLines();
        // Return the set of line numbers of lines that were too long.

    static
    StatementType statement(int index);
        // Return an enum representing any of a number of standard words that
        // may have begun the line indicated by the specified 'index'.

    static
    bool statementEnds(int index);
        // Return 'true' if the line specified by 'index' ends a statement.

    static
    const Ut::LineNumSet& tbds();
        // Return the set of line #'s containing comments with the abbreviation
        // for 'To Be Done' in them.

    // Initializes static data structures.  Aborts on failure.

    // CREATORS
    explicit
    Lines(const char *fileName);
        // Populates the static data according to the data in the file
        // specified by 'fileName'.

    explicit
    Lines(const bsl::string& string);
        // Populates the static data according to the specified 'string' as
        // though 'string' was the source of the file itself.  's_fileName' is
        // initialized to 'dummy_string' and 's_fileType' is set to '.cpp'.

    ~Lines();
        // Destructor.  Clears all static data and frees all memory.

    // ACCESSORS
    void printWarnings(bsl::ostream *stream);
        // Print warnings according to the static data in this class.
};

// CLASS METHODS
inline
Lines::CommentType Lines::comment(int index)
{
    return s_comments[index];
}

inline
int Lines::commentIndent(int index)
{
    return s_commentIndents[index];
}

inline
const bsl::string& Lines::fileName()
{
    return s_fileName;
}

inline
Lines::FileType Lines::fileType()
{
    return s_fileType;
}

inline
bool Lines::hasTabs()
{
    return s_hasTabs;
}

inline
bool Lines::includesDoubleQuotes()
{
    return s_includesDoubleQuotes;
}

inline
bool Lines::includesAssertH()
{
    return s_includesAssertH;
}

inline
bool Lines::includesCassert()
{
    return s_includesCassert;
}

inline
bool Lines::isProtectionLine(int index)
{
    const StatementType st = statement(index);

    return BDEFLAG_S_PRIVATE   == st ||
           BDEFLAG_S_PUBLIC    == st ||
           BDEFLAG_S_PROTECTED == st;
}

inline
const bsl::string& Lines::line(int index)
{
    return s_lines[index];
}

inline
int Lines::lineCount()
{
    return s_lineCount;
}

inline
int Lines::lineIndent(int index)
{
    return s_lineIndents[index];
}

inline
int Lines::lineLength(int index)
{
    return index >= s_lineCount ? 0 : s_lines[index].length();
}

inline
const Ut::LineNumSet& Lines::longLines()
{
    return s_longLines;
}

inline
const Ut::LineNumSet& Lines::cStyleComments()
{
    return s_cStyleComments;
}

inline
Lines::StatementType Lines::statement(int index)
{
    return s_statements[index];
}

inline
bool Lines::statementEnds(int index)
{
    return s_statementEnds[index];
}

inline
const Ut::LineNumSet& Lines::tbds()
{
    return s_tbds;
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

// bdeflag_group.cpp                                                  -*-C++-*-

#include <bdeflag_group.h>
#include <bdeflag_lines.h>
#include <bdeflag_ut.h>

#include <bdes_bitutil.h>
#include <bdeu_string.h>

#include <bslma_allocator.h>
#include <bslma_default.h>
#include <bslma_rawdeleterproctor.h>
#include <bslmf_assert.h>
#include <bsls_assert.h>

#include <bsl_list.h>
#include <bsl_string.h>

#include <bsl_algorithm.h>
#include <bsl_iostream.h>
#include <bsl_string.h>

#include <ctype.h>

#define P(x)          Ut::p(#x, (x))

using bsl::cerr;
using bsl::endl;

namespace BloombergLP {

namespace bdeFlag {

// store strings in a static vector for comparisons - a compare with a string
// is faster that with a 'const char *'.
enum {
    MATCH_STRUCT,
    MATCH_CLASS,
    MATCH_UNION,
    MATCH_IS,
    MATCH_ARE,
    MATCH_HAS,
    MATCH_ENUM,
    MATCH_CONST,
    MATCH_VOLATILE,
    MATCH_ASM,
    MATCH_IF,
    MATCH_WHILE,
    MATCH_FOR,
    MATCH_SWITCH,
    MATCH_CATCH,
    MATCH_BSLS_CATCH,
    MATCH_BOOL,
    MATCH_NIL,
    MATCH_NESTED_TRAITS,
    MATCH_INLINE_STATIC,
    MATCH_NAMESPACE,
    MATCH_OPERATOR,
    MATCH_OPERATOR_SHIFT,
    MATCH_OPERATOR_SHIFT_RIGHT,
    MATCH_OPERATOR_BRACES,
    MATCH_LHS,
    MATCH_RHS,
    MATCH_SWAP,
    MATCH_OTHER,
    MATCH_ORIGINAL,
    MATCH_QUOTE_C,
    MATCH_THREE_QUOTES,
    MATCH_EXTERN,
    MATCH_ASM__,
    MATCH_VOLATILE__,
    MATCH_RCSID,
    MATCH_BSLMA_ALLOCATOR,
    MATCH_BSLMA_ALLOCATOR_B,
    MATCH_THROW,
    MATCH_BSLS_EXCEPTION_SPEC,
    MATCH_BSLS_NOTHROW_SPEC,
    MATCH__TRY,
    MATCH__EXCEPT,
    MATCH_PRINT,
    MATCH_BDEAT_DECL,
    MATCH_EXPLICIT,
    MATCH_BLOOMBERGLP,
    MATCH_NUM_CONSTANTS };

static bsl::vector<bsl::string> match;
const bsl::vector<bsl::string>& MATCH = match;

static Group *findGroupForPlaceGroup_p = 0;
bsl::set<bsl::string> shouldBool;    // Routines That Should Have Bool Names

static Ut::LineNumSet assertsNeedBlankLine;
static Ut::LineNumSet strangelyIndentedComments;
static Ut::LineNumSet strangelyIndentedStatements;
static Ut::LineNumSet commentNeedsBlankLines;
static Ut::LineNumSet badlyAlignedFuncStartBrace;

static bsl::set<bsl::string> routinesNeedDoc;
static bsl::set<bsl::string> routinesDocced;

static Ut::LineNumSet returnCommentsNeeded;
static Ut::LineNumSet returnCommentsNotNeeded;

static bsl::set<bsl::string> boolOperators;
static bsl::set<bsl::string> binaryOperators;
static bsl::set<bsl::string> unaryOperators;

static bsl::set<bsl::string> annoyingMacros;

struct StartProgram {
    // An object of this type is declared 'static' so that the c'tor will be
    // run once when the program when the program starts and not again on each
    // processed file.

    // CREATOR
    StartProgram();
        // Initialize constants in this imp file that need only be initialized
        // once per run of the program and not changed for every file
        // processed.
};
static StartProgram startProgram;

// CREATORS
StartProgram::StartProgram()
{
    match.resize(MATCH_NUM_CONSTANTS);
    match[MATCH_STRUCT]          = "struct";
    match[MATCH_CLASS]           = "class";
    match[MATCH_UNION]           = "union";
    match[MATCH_IS]              = "is";
    match[MATCH_ARE]             = "are";
    match[MATCH_HAS]             = "has";
    match[MATCH_ENUM]            = "enum";
    match[MATCH_CONST]           = "const";
    match[MATCH_VOLATILE]        = "volatile";
    match[MATCH_ASM]             = "asm";
    match[MATCH_IF]              = "if";
    match[MATCH_WHILE]           = "while";
    match[MATCH_FOR]             = "for";
    match[MATCH_SWITCH]          = "switch";
    match[MATCH_CATCH]           = "catch";
    match[MATCH_BSLS_CATCH]      = "BSLS_CATCH";
    match[MATCH_BOOL]            = "bool";
    match[MATCH_NIL]             = "";
    match[MATCH_NESTED_TRAITS]   = "BSLALG_DECLARE_NESTED_TRAITS";
    match[MATCH_INLINE_STATIC]   = "inline static";
    match[MATCH_NAMESPACE]       = "namespace";
    match[MATCH_OPERATOR]        = "operator";
    match[MATCH_OPERATOR_SHIFT]  = "operator<<";
    match[MATCH_OPERATOR_SHIFT_RIGHT]
                                 = "operator>>";
    match[MATCH_OPERATOR_BRACES] = "operator()";
    match[MATCH_LHS]             = "lhs";
    match[MATCH_RHS]             = "rhs";
    match[MATCH_SWAP]            = "swap";
    match[MATCH_OTHER]           = "other";
    match[MATCH_ORIGINAL]        = "original";
    match[MATCH_QUOTE_C]         = "\"C\"";
    match[MATCH_THREE_QUOTES]    = "\"\"\"";
    match[MATCH_EXTERN]          = "extern";
    match[MATCH_ASM__]           = "__asm__";
    match[MATCH_VOLATILE__]      = "__volatile__";
    match[MATCH_RCSID]           = "RCSID";
    match[MATCH_BSLMA_ALLOCATOR] = "bslma_Allocator *";
    match[MATCH_BSLMA_ALLOCATOR_B] = "bslma_Allocator*";
    match[MATCH_THROW]           = "throw";
    match[MATCH_BSLS_EXCEPTION_SPEC] = "BSLS_EXCEPTION_SPEC";
    match[MATCH_BSLS_NOTHROW_SPEC] = "BSLS_NOTHROW_SPEC";
    match[MATCH__EXCEPT]         = "__except";
    match[MATCH_PRINT]           = "print";
    match[MATCH_BDEAT_DECL]      = "BDEAT_DECL_";
    match[MATCH_BLOOMBERGLP]     = "BloombergLP";
    match[MATCH_EXPLICIT]        = "explicit";

    static const char *arrayBoolOperators[] = {
        "!", "<", "<=", ">", ">=", "==", "!=", "&&", "||" };
    enum { NUM_ARRAY_BOOL_OPERATORS = sizeof arrayBoolOperators /
                                                  sizeof *arrayBoolOperators };
    for (int i = 0; i < NUM_ARRAY_BOOL_OPERATORS; ++i) {
        boolOperators.insert(arrayBoolOperators[i]);
    }

    static const char *arrayBinaryOperators[] = {
        "*", "/", "%", "+", "-", "<", "<=", ">", ">=", "==", "!=",
        "&", "^", "|", "&&", "||" };
    enum { NUM_ARRAY_BINARY_OPERATORS = sizeof arrayBinaryOperators /
                                                sizeof *arrayBinaryOperators };
    for (int i = 0; i < NUM_ARRAY_BINARY_OPERATORS; ++i) {
        binaryOperators.insert(arrayBinaryOperators[i]);
    }

    static const char *arrayUnaryOperators[] = {
        "*", "+", "-", "&", "!", "~", "++", "--" };

    enum { NUM_ARRAY_UNARY_OPERATORS = sizeof arrayUnaryOperators /
                                                 sizeof *arrayUnaryOperators };
    for (int i = 0; i < NUM_ARRAY_UNARY_OPERATORS; ++i) {
        unaryOperators.insert(arrayUnaryOperators[i]);
    }

    static const char *arrayAnnoyingMacros[] = {
        "BSLS_IDENT", "BDES_IDENT", "BSLS_IDENT_RCSID", "BDES_IDENT_RCSID",
        "BSLMF_ASSERT", "sizeof" };
    enum { NUM_ANNOYING_MACROS = sizeof arrayAnnoyingMacros /
                                                 sizeof *arrayAnnoyingMacros };
    for (int i = 0; i < NUM_ANNOYING_MACROS; ++i) {
        annoyingMacros.insert(arrayAnnoyingMacros[i]);
    }
}

static
void printStringSet(const bsl::set<bsl::string>& s)
    // Print a set of strings to cerr with commas separating them.
{
    typedef bsl::set<bsl::string>::iterator It;
    const It end = s.end();
    bool firstTime = true;
    for (It it = s.begin(); end != it; ++it) {
        if (firstTime) {
            firstTime = false;
        }
        else {
            cerr << ", ";
        }
        cerr << "'" << *it << "'";
    }
    cerr << endl;
}

static bool isAnnoying(const bsl::string& routineName)
    // Is the specified 'routineName' one of a number of macros that can be
    // safely ignored?
{
    return annoyingMacros.count(routineName) ||
                Ut::frontMatches(routineName, MATCH[MATCH_NESTED_TRAITS], 0) ||
                     Ut::frontMatches(routineName, MATCH[MATCH_BDEAT_DECL], 0);
}

static inline
bool isProtectionStatement(Lines::StatementType st)
    // Is the statement 'public:', 'private:', or 'protected:'?
{
    return Lines::BDEFLAG_S_PUBLIC == st || Lines::BDEFLAG_S_PRIVATE == st ||
                                              Lines::BDEFLAG_S_PROTECTED == st;
}

static size_t matchesAnyStruct(const bsl::string& curLine)
    // Return 'true' if the separate keywords 'struct', 'class', or 'union'
    // occur anywhere in the specified 'curLine', and 'false' otherwise.
{
    size_t pos;
    int matchStrLen;
    pos = curLine.find(MATCH[MATCH_STRUCT]);
    if (Ut::npos() != pos) {
        matchStrLen = MATCH[MATCH_STRUCT].length();
    }
    else {
        pos = curLine.find(MATCH[MATCH_CLASS]);
        if (Ut::npos() != pos) {
            matchStrLen = MATCH[MATCH_CLASS].length();
        }
        else {
            pos = curLine.find(MATCH[MATCH_UNION]);
            if (Ut::npos() != pos) {
                matchStrLen = MATCH[MATCH_UNION].length();
            }
            else {
                return Ut::npos();                                    // RETURN
            }
        }
    }

    if ((pos > 0 && Ut::alphaNumOrColon(curLine[pos - 1]))
       || (curLine.length() > pos + matchStrLen &&
                            Ut::alphaNumOrColon(curLine[pos + matchStrLen]))) {
        return Ut::npos();                                            // RETURN
    }

    return pos;
}

                                // -----
                                // Group
                                // -----

// CLASS DATA
Group *Group::s_topLevel = 0;

// PRIVATE MANIPULATORS
Group *Group::recurseFindGroupForPlace(Group *group)
{
    const Place& place = group->d_open;

    BSLS_ASSERT_OPT(d_open  <= place);
    BSLS_ASSERT_OPT(d_close >= place);

    GroupSetIt it = d_subGroups.upper_bound(group);
    if (d_subGroups.begin() != it) {
        --it;

        Group *newGroup = *it;
        BSLS_ASSERT_OPT(d_open  < newGroup->d_open);
        BSLS_ASSERT_OPT(d_close > newGroup->d_close);

        // 'it' now points to the highest group that starts at <= place

        if (place >= newGroup->d_open && place <= newGroup->d_close) {
            return newGroup->recurseFindGroupForPlace(group);         // RETURN
        }
    }

    return this;
}

int Group::recurseInitGroup(Place       *place,
                            const Group *parent)
{
    BSLMF_ASSERT(sizeof(int) == sizeof(size_t));
    BSLS_ASSERT_OPT((0 == parent) == (&topLevel() == this));

    bslma_Allocator *da = bslma_Default::defaultAllocator();

    d_parent = parent;

    char close;
    char closeWrong;
    Place& cursor = *place;

    if (d_parent) {
        for (;;) {
            cursor = cursor.findFirstOf("(){}");
            if (Place::end() == cursor) {
                d_flags.d_noGroupsFound = true;
                return  -1;                                           // RETURN
            }
            const char c = *cursor;
            if (strchr("({", c)) {
                break;
            }
            cerr << "Error: " << Lines::fileName() << ": Unexpected '" << c <<
                                                     "' at " << cursor << endl;
            ++cursor;
        }

        d_open = cursor;

        BSLS_ASSERT_OPT(('(' == *cursor) == d_flags.d_parenBased);

        close      = d_flags.d_parenBased ? ')' : '}';
        closeWrong = d_flags.d_parenBased ? '}' : ')';

        d_statementStart = cursor.findStatementStart();
        d_prevWord = (cursor - 1).wordBefore(&d_prevWordBegin);
        if (d_prevWordBegin < d_statementStart &&
                           (MATCH[MATCH_NIL] != d_prevWord ||
                                        0 ==strchr(";}{", *d_prevWordBegin))) {
            // probably '{' lined up under 'struct' or 'template'

            d_statementStart = d_prevWordBegin.findStatementStart();
        }
        if (MATCH[MATCH_NIL] == d_prevWord && '>' == *d_prevWordBegin) {
            // There's a real problem here, they might just be saying
            // 'a > (c + d)' and it's not really a template.  So what precedes
            // a '(', to be even possibly considered a template, the '>' must
            // touch the '('.

            if (!d_flags.d_parenBased ||
                            (d_prevWordBegin.col() == d_open.col() - 1 &&
                             d_prevWordBegin.lineNum() == d_open.lineNum())) {
                Place tnBegin;
                bsl::string tn = (d_open - 1).templateNameBefore(&tnBegin);
                if (MATCH[MATCH_NIL] != tn) {
                    d_prevWord = tn;
                    d_prevWordBegin = tnBegin;
                }
            }
        }
    }
    else {
        // We are the top level

        BSLS_ASSERT_OPT(Place(0, 0) == cursor);
        d_open  = cursor;
        d_close = Place::end();

        close      = '}';
        closeWrong = ')';

        d_statementStart = d_open;
    }

    while (Place::end() != (cursor = (++cursor).findFirstOf("(){}"))) {
        const char c = *cursor;
        if (close == c) {
            d_close = cursor;
            return 0;                                                 // RETURN
        }
        else if (closeWrong == c) {
            cursor.error() << "unmatched '" << c << "'\n";
            if (d_flags.d_parenBased) {
                // keep bubbling up until we reach a '{' block or the top

                d_flags.d_closedWrong = true;
                return -1;                                            // RETURN
            }
            // We're a '{' group and we hit an excess ')'.  Continue.
        }
        else {
            BSLS_ASSERT_OPT(Ut::charInString(*cursor, "({"));

            bool parenBased     = '(' == *cursor;
            GroupType groupType = parenBased ? BDEFLAG_UNKNOWN_PARENS
                                             : BDEFLAG_UNKNOWN_BRACES;

            Group *subGroup = new (*da) Group(groupType, parenBased);
            bslma_RawDeleterProctor<Group, bslma_Allocator>
                                                         proctor(subGroup, da);

            if (0 == subGroup->recurseInitGroup(&cursor, this)) {
                d_subGroups.insert(subGroup);
                proctor.release();

                // continue finding more groups to add
            }
            else {
                if (subGroup->d_flags.d_closedWrong) {
                    BSLS_ASSERT_OPT(subGroup->d_flags.d_parenBased);
                    BSLS_ASSERT_OPT('}' == *cursor);

                    if (d_flags.d_parenBased) {
                        // keep bubbling up until we reach a '{' block or the
                        // top

                        d_flags.d_closedWrong = true;
                        return -1;                                    // RETURN
                    }
                    else {
                        BSLS_ASSERT_OPT(close == *cursor);

                        // the buck stops here -- continue

                        d_close = cursor;
                        return 0;                                     // RETURN
                    }
                }

                // eof without closing block

                BSLS_ASSERT_OPT(subGroup->d_flags.d_earlyEof);
                BSLS_ASSERT_OPT(Place::end() == cursor);
                break;
            }
        }

        BSLS_ASSERT_OPT(Place::end() != cursor);
    }

    if (d_parent) {
        d_open.error() << "reached EOF: Unmatched " << *d_open << endl;
    }

    d_flags.d_earlyEof = true;
    return -1;
}

void Group::recurseMemTraverse(const Group::GroupMemFunc func)
{
    (this->*func)();

    const GroupSetIt end = d_subGroups.end();
    for (GroupSetIt it = d_subGroups.begin(); end != it; ++it) {
        (*it)->recurseMemTraverse(func);
    }
}

void Group::recurseMemTraverse(const Group::GroupMemFuncConst func)
{
    (this->*func)();

    const GroupSetIt end = d_subGroups.end();
    for (GroupSetIt it = d_subGroups.begin(); end != it; ++it) {
        (*it)->recurseMemTraverse(func);
    }
}

// CLASS METHODS
void Group::checkAllArgNames()
{
    topLevel().recurseMemTraverse(&Group::checkArgNames);
}

void Group::checkAllBooleanRoutineNames()
{
    shouldBool.clear();

    topLevel().recurseMemTraverse(&Group::checkBooleanRoutineNames);

    if (!shouldBool.empty()) {
        cerr << Lines::fileName() << ": the following routine(s) should"
                                                            " return 'bool': ";
        printStringSet(shouldBool);

        shouldBool.clear();
    }
}

void Group::checkAllCodeComments()
{
    topLevel().recurseMemTraverse(&Group::checkCodeComments);

    if (!strangelyIndentedComments.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                    ": strangely indented comments at line(s) " <<
                                             strangelyIndentedComments << endl;
        strangelyIndentedComments.clear();
    }
    if (!commentNeedsBlankLines.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                ": comments should be separated from code by a blank line"
                              " at line(s) " << commentNeedsBlankLines << endl;
        commentNeedsBlankLines.clear();
    }
}

void Group::checkAllCodeIndents()
{
    topLevel().recurseMemTraverse(&Group::checkCodeIndents);

    if (!strangelyIndentedStatements.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                               ": strangely indented Statements at line(s) " <<
                                           strangelyIndentedStatements << endl;
        strangelyIndentedStatements.clear();
    }
}

void Group::checkAllFunctionDoc()
{
    if (Lines::BDEFLAG_DOT_T_DOT_CPP == Lines::fileType()) {
        return;
    }

    topLevel().recurseMemTraverse(&Group::checkFunctionDoc);

    routinesNeedDoc.erase(MATCH[MATCH_OPERATOR]);

    if (!routinesNeedDoc.empty()) {
        typedef bsl::set<bsl::string>::iterator It;
        const It end = routinesNeedDoc.end();

        bool found = false;
        for (It it = routinesNeedDoc.begin(); end != it; ++it) {
            if (0 == routinesDocced.count(*it)) {
                found = true;
                break;
            }
        }

        if (found) {
            cerr << "Warning: " << Lines::fileName() <<
                          ": the following routine(s) need(s) documentation: ";
            bool firstTime = true;
            for (It it = routinesNeedDoc.begin(); end != it; ++it) {
                if (0 == routinesDocced.count(*it)) {
                    if (firstTime) {
                        firstTime = false;
                    }
                    else {
                        cerr << ", ";
                    }
                    cerr << "'" << *it << "'";
                }
            }
            cerr << endl;
        }

        routinesNeedDoc.clear();
    }

    routinesDocced.clear();
}

void Group::checkAllIfWhileFor()
{
    if (Lines::BDEFLAG_DOT_T_DOT_CPP != Lines::fileType()) {
        topLevel().recurseMemTraverse(&Group::checkIfWhileFor);
    }
}

void Group::checkAllNotImplemented()
{
    topLevel().recurseMemTraverse(&Group::checkNotImplemented);
}

void Group::checkAllNamespaces()
{
    topLevel().recurseMemTraverse(&Group::checkNamespace);
}

void Group::checkAllReturns()
{
    topLevel().recurseMemTraverse(&Group::checkReturns);

    if (!returnCommentsNeeded.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                    ": '// RETURN' comment(s) needed on returns at line(s) " <<
                                                  returnCommentsNeeded << endl;
    }
    if (!returnCommentsNotNeeded.empty()) {
        cerr << "Warning:" << Lines::fileName() <<
             ": '// RETURN' comment(s) should not happen on return(s) at end"
                                                " of routine(s) at line(s) " <<
                                               returnCommentsNotNeeded << endl;
    }

    returnCommentsNeeded.clear();
    returnCommentsNotNeeded.clear();
}

void Group::checkAllRoutineCallArgLists()
{
    if (Lines::BDEFLAG_DOT_T_DOT_CPP != Lines::fileType()) {
        topLevel().recurseMemTraverse(&Group::checkRoutineCallArgList);
    }
}

void Group::checkAllStartingAsserts()
{
    assertsNeedBlankLine.clear();

    topLevel().recurseMemTraverse(&Group::checkStartingAsserts);

    if (!assertsNeedBlankLine.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                                      ": asserts (or groups of asserts) at the"
                 " beginnings of routines should be followed by blank lines: ";
        cerr << assertsNeedBlankLine << endl;

        assertsNeedBlankLine.clear();
    }
}

void Group::checkAllStartingBraces()
{
    badlyAlignedFuncStartBrace.clear();

    topLevel().recurseMemTraverse(&Group::checkStartingBraces);

    if (!badlyAlignedFuncStartBrace.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                ": opening '{' of function should be properly aligned alone"
                " at start of line(s): " << badlyAlignedFuncStartBrace << endl;

        badlyAlignedFuncStartBrace.clear();
    }
}

void Group::checkAllStatics()
{
    if (Lines::BDEFLAG_DOT_H != Lines::fileType()) {
        return;                                                       // RETURN
    }

    for (int li = 0; li < Lines::lineCount(); ++li) {
        if (Lines::BDEFLAG_S_STATIC == Lines::statement(li)) {
            const Place place(li, 0);
            const GroupType parentType = findGroupForPlace(place)->d_type;

            if (BDEFLAG_TOP_LEVEL == parentType ||
                                             BDEFLAG_NAMESPACE == parentType) {
                bsl::string s;
                for (int lj = li; lj < Place::end().lineNum(); ++lj) {
                    const bsl::string& line = Lines::line(lj);

                    s += line;

                    if (Ut::npos() != line.find_first_of(";)")) {
                        break;
                    }
                }

                if (!bdeu_String::strstrCaseless(s.c_str(),
                                                 s.length(),
                                                 "rcs",
                                                 3)) {
                    place.warning() << "static in .h file\n";
                }
            }
        }
    }
}

void Group::checkAllTemplateOnOwnLine()
{
    Ut::LineNumSet warnings;

    const int end = Lines::lineCount();
    for (int li = 1; li < end; ++li) {
        if (Lines::BDEFLAG_S_TEMPLATE == Lines::statement(li)) {
            const int col = Lines::lineIndent(li);
            Place cursor(li, col + 7);
            BSLS_ASSERT_OPT('e' == *cursor);
            ++cursor;
            if ('<' != *cursor) {
                (cursor - 8).error() << "'template' not followed by '<'\n";
                continue;
            }
            Place tnEnd;
            if (MATCH[MATCH_NIL] == cursor.templateNameAfter(&tnEnd)) {
                (cursor - 8).error() << "'template' occurred in  very"
                                                          " strange context\n";
                continue;
            }
            if (Lines::lineLength(tnEnd.lineNum()) - 1 > tnEnd.col()) {
                warnings.insert(li);
                continue;
            }
            const int nextLine = tnEnd.lineNum() + 1;
            if (Lines::BDEFLAG_S_BLANKLINE == Lines::statement(nextLine)) {
                warnings.insert(li);
                continue;
            }
            if (Lines::lineIndent(nextLine) != col) {
                warnings.insert(li);
                continue;
            }
        }
    }

    if (!warnings.empty()) {
        cerr << "Warning: " << Lines::fileName() << ": 'template' might not"
            " have occurred on its own line on the following line(s), or the"
                    " line following 'template' might not have been properly"
                                   " aligned underneath: " << warnings << endl;

        warnings.clear();
    }
}

void Group::clearGroups()
{
    bslma_Allocator *da = bslma_Default::defaultAllocator();

    da->deleteObjectRaw(findGroupForPlaceGroup_p);

    da->deleteObjectRaw(s_topLevel);
    s_topLevel = 0;
}

void Group::doEverything()
{
    initGroups();
    checkAllBooleanRoutineNames();
    checkAllFunctionDoc();
    checkAllReturns();
    checkAllNotImplemented();
    checkAllNamespaces();
    checkAllStartingAsserts();
    checkAllStartingBraces();
    checkAllTemplateOnOwnLine();
    checkAllCodeComments();
    checkAllArgNames();
    checkAllIfWhileFor();
    checkAllStatics();

    //  checkAllRoutineCallArgLists();

    checkAllCodeIndents();
    clearGroups();
}

Group *Group::findGroupForPlace(const Place& place)
{
    findGroupForPlaceGroup_p->d_open = place;

    if (topLevel().d_open  > place) {
        place.error() << "findGroupForPlace place before start of file\n";
        return &topLevel();                                           // RETURN
    }
    if (topLevel().d_close < place) {
        place.error() << "findGroupForPlace given place after end() == " <<
                                                          Place::end() << endl;
        return &topLevel();                                           // RETURN
    }

    return topLevel().recurseFindGroupForPlace(findGroupForPlaceGroup_p);
}

void Group::initGroups()
{
    bslma_Allocator *da = bslma_Default::defaultAllocator();
    s_topLevel = new (*da) Group(BDEFLAG_TOP_LEVEL, false);

    findGroupForPlaceGroup_p = new (*da) Group(BDEFLAG_UNKNOWN_PARENS, true);

    s_topLevel->initTopLevelGroup();

    s_topLevel->recurseMemTraverse(&Group::determineGroupType);
}

void Group::printAll()
{
    s_topLevel->recurseMemTraverse(&Group::print);
}

// MANIPULATORS
void Group::determineGroupType()
{
    if (BDEFLAG_TOP_LEVEL == d_type) {
        return;                                                       // RETURN
    }

    BSLS_ASSERT_OPT(d_open > Place::rEnd());

    char pwbc = *d_prevWordBegin;

    if (d_flags.d_parenBased) {
        BSLS_ASSERT_OPT(d_parent);

        if (0 == d_open.col()) {
            d_type = BDEFLAG_EXPRESSION_PARENS;
            d_open.warning() << "'(' in col 0'" << endl;
            return;                                                   // RETURN
        }

        if (MATCH[MATCH_NIL] == d_prevWord) {
            bool expression = false;
            if (Ut::charInString(pwbc, "~!%^&*-+=<>,?:(){}|[]/")) {
                expression = true;
                if (d_open.lineNum() == d_prevWordBegin.lineNum()) {
                    const bsl::string curLine = Lines::line(d_open.lineNum());
                    size_t pos = curLine.rfind(MATCH[MATCH_OPERATOR],
                                               d_prevWordBegin.col());
                    int iPos = pos;
                    if (Ut::npos() != pos) {
                        const bsl::string& sub =
                              curLine.substr(iPos,
                                             d_prevWordBegin.col() + 1 - iPos);
                        const bsl::string op = Ut::spacesOut(sub);
                        Place begin(d_open.lineNum(), iPos);
                        if (op.length() <= 11 && MATCH[MATCH_OPERATOR] ==
                                                        Ut::wordAfter(op, 0)) {
                            // it's something like 'operator+(' or
                            // 'operator()(', note 'operator() (' or
                            // 'operator<<=(' are possible.

                            d_prevWord = op;
                            d_prevWordBegin = begin;
                            pwbc = d_prevWord[0];
                            expression = false;
                        }
                        else if (('*' == pwbc || '&' == pwbc) &&
                                       Ut::npos() == sub.find_first_of("()")) {
                            // it's something like 'operator float&('

                            d_prevWord = sub;
                            d_prevWordBegin = begin;
                            pwbc = d_prevWord[0];
                            expression = false;
                            Ut::trim(&d_prevWord);    // trim trailing spaces
                        }
                    }
                }
            }
            else if ('"' == pwbc && BDEFLAG_ASM == d_parent->d_type) {
                expression = true;
            }
            else if (';' == pwbc) {
                expression = true;
            }
            else {
                d_statementStart.error() << "'(' in strange context\n";
            }

            if (expression) {
                d_type = BDEFLAG_EXPRESSION_PARENS;
                return;                                               // RETURN
            }
        }

        BSLS_ASSERT_OPT(d_prevWord.length() > 0);

        if   (MATCH[MATCH_IF]    == d_prevWord
           || MATCH[MATCH_WHILE] == d_prevWord
           || MATCH[MATCH_FOR]   == d_prevWord) {
            d_type = BDEFLAG_IF_WHILE_FOR;
            if (BDEFLAG_ROUTINE_BODY != d_parent->d_type &&
                                       BDEFLAG_CODE_BODY != d_parent->d_type) {
                d_prevWordBegin.error() << d_prevWord <<
                                      " in strange context, parent type is " <<
                                           typeToStr(d_parent->d_type) << endl;
            }
            return;                                                   // RETURN
        }

        if (MATCH[MATCH_SWITCH] == d_prevWord) {
            d_type = BDEFLAG_SWITCH_PARENS;
            if (BDEFLAG_ROUTINE_BODY != d_parent->d_type &&
                                       BDEFLAG_CODE_BODY != d_parent->d_type) {
                d_prevWordBegin.error() << d_prevWord <<
                                      " in strange context, parent type is " <<
                                           typeToStr(d_parent->d_type) << endl;
            }
            return;                                                   // RETURN
        }

        if   (MATCH[MATCH_CATCH] == d_prevWord
           || MATCH[MATCH_BSLS_CATCH] == d_prevWord
           || MATCH[MATCH__EXCEPT] == d_prevWord) {
            d_type = BDEFLAG_CATCH_PARENS;
            if (BDEFLAG_ROUTINE_BODY != d_parent->d_type &&
                                       BDEFLAG_CODE_BODY != d_parent->d_type &&
                                       BDEFLAG_NAMESPACE != d_parent->d_type &&
                                       BDEFLAG_TOP_LEVEL != d_parent->d_type) {
                d_prevWordBegin.error() << d_prevWord <<
                                      " in strange context, parent type is " <<
                                           typeToStr(d_parent->d_type) << endl;
            }
            return;                                                   // RETURN
        }

        if ((MATCH[MATCH_ASM__] == d_prevWord ||
              (MATCH[MATCH_VOLATILE__] == d_prevWord &&
                  MATCH[MATCH_ASM__] == (d_prevWordBegin - 1).wordBefore())) ||
            (MATCH[MATCH_ASM] == d_prevWord ||
                (MATCH[MATCH_VOLATILE] == d_prevWord &&
                    MATCH[MATCH_ASM] == (d_prevWordBegin - 1).wordBefore()))) {
            d_type = BDEFLAG_ASM;
            return;                                                   // RETURN
        }

        if (MATCH[MATCH_THROW] == d_prevWord ||
                              MATCH[MATCH_BSLS_EXCEPTION_SPEC] == d_prevWord) {
            d_type = BDEFLAG_THROW_PARENS;
            return;                                                   // RETURN
        }

        d_type = BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL;

        bool missed = false;
        switch (d_parent->d_type) {
          case BDEFLAG_TOP_LEVEL:
          case BDEFLAG_NAMESPACE:
          case BDEFLAG_CLASS: {
            Place beforePrevWord = d_prevWordBegin - 1;

            char c = *beforePrevWord;
            if (':' == c || ':' == d_prevWord[0]) {
                Lines::StatementType st =
                                    Lines::statement(beforePrevWord.lineNum());
                if (Lines::BDEFLAG_S_PRIVATE == st ||
                                               Lines::BDEFLAG_S_PUBLIC == st ||
                                            Lines::BDEFLAG_S_PROTECTED == st) {
                    d_type = BDEFLAG_ROUTINE_DECL;
                }
                else {
                    d_type = BDEFLAG_CTOR_CLAUSE;
                }
                return;                                               // RETURN
            }
            else if (',' == c) {
                d_type = BDEFLAG_CTOR_CLAUSE;
                return;                                               // RETURN
            }
            else {
                int cli = d_open.lineNum();
                int li = Lines::lineBefore(&cli);
                for (++li ; li <= cli; ++li) {
                    Lines::StatementType st = Lines::statement(li);
                    if (Lines::BDEFLAG_S_TEMPLATE == st) {
                        d_type = BDEFLAG_ROUTINE_DECL;
                        return;                                       // RETURN
                    }
                    if (Lines::BDEFLAG_S_TYPEDEF == st) {
                        d_type = BDEFLAG_ROUTINE_CALL;
                        return;                                       // RETURN
                    }
                }
                if (d_prevWordBegin !=
                               d_statementStart.findFirstOf("=",
                                                            true,
                                                            d_prevWordBegin)) {
                    d_type = BDEFLAG_ROUTINE_CALL;
                    return;                                           // RETURN
                }
                else {
                    d_type = BDEFLAG_ROUTINE_DECL;
                    return;                                           // RETURN
                }
            }
          }  break;
          case BDEFLAG_INIT_BRACES:
          case BDEFLAG_ROUTINE_BODY:
          case BDEFLAG_CODE_BODY:
          case BDEFLAG_ROUTINE_CALL:
          case BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL:
          case BDEFLAG_ROUTINE_DECL:
          case BDEFLAG_CTOR_CLAUSE:
          case BDEFLAG_IF_WHILE_FOR:
          case BDEFLAG_SWITCH_PARENS:
          case BDEFLAG_CATCH_PARENS:
          case BDEFLAG_ENUM:
          case BDEFLAG_EXPRESSION_PARENS: {
            d_type = BDEFLAG_ROUTINE_CALL;
            return;                                                   // RETURN
          }  break;
          case BDEFLAG_UNKNOWN_BRACES:
          case BDEFLAG_UNKNOWN_PARENS:
          default: {
            BSLS_ASSERT_OPT(BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL == d_type);

            d_open.error() << "routine call or decl in strange context,"
              "  parent block is type " << typeToStr(d_parent->d_type) << endl;
            return;                                                   // RETURN
          }
        }

        return;                                                       // RETURN
    }
    else {
        // braces based

        if (d_parent->d_flags.d_parenBased) {
            d_open.error() << "braces block surrounded by parens block\n";
        }

        if ('=' == pwbc || (BDEFLAG_INIT_BRACES == d_parent->d_type &&
                                               (',' == pwbc || '{' == pwbc))) {
            d_type = BDEFLAG_INIT_BRACES;
            return;                                                   // RETURN
        }

        Lines::StatementType st = Lines::statement(d_statementStart.lineNum());
        switch (st) {
          case Lines::BDEFLAG_S_CLASS_STRUCT_UNION: {
            Place endName;
            bsl::string name = d_statementStart.findFirstOf(" ").nameAfter(
                                                                     &endName);
            char c = ':' == Ut::lastCharOf(name) ? ':' : *(endName + 1);
            if (Ut::charInString(c, ":{")) {
                d_className = name;
                d_type = BDEFLAG_CLASS;
                return;                                               // RETURN
            }
          }  break;
          case Lines::BDEFLAG_S_DO:
          case Lines::BDEFLAG_S_ELSE:
          case Lines::BDEFLAG_S_TRY:
          case Lines::BDEFLAG_S_CASE: {
            d_type = BDEFLAG_CODE_BODY;
            return;                                                   // RETURN
          }
          case Lines::BDEFLAG_S_EXTERN: {
            if (Lines::BDEFLAG_S_EXTERN == st &&
                   MATCH[MATCH_NIL] == d_prevWord && '"' == *d_prevWordBegin) {
                int li = d_prevWordBegin.lineNum();
                const bsl::string& curLine = Lines::line(li);
                int col = d_prevWordBegin.col();
                while (col > 0 && '"' == curLine[col - 1]) {
                    --col;
                }
                if (MATCH[MATCH_EXTERN] == (Place(li, col) - 1).wordBefore()) {
                    d_prevWord = MATCH[MATCH_QUOTE_C];
                    d_prevWordBegin = d_prevWordBegin - 2;
                    d_type = BDEFLAG_NAMESPACE;
                    return;                                           // RETURN
                }

                d_statementStart.error() << "confusing 'extern' braces\n";
            }
            else {
                // hopefully its a routine body -- let it fall through

                ;
            }
          } break;
          case Lines::BDEFLAG_S_NAMESPACE: {
            d_type = BDEFLAG_NAMESPACE;
            return;                                                   // RETURN
          }
          case Lines::BDEFLAG_S_ENUM: {
            d_type = BDEFLAG_ENUM;
            return;                                                   // RETURN
          }
        }

        if (MATCH[MATCH_NIL] != d_prevWord) {
            if   (MATCH[MATCH_STRUCT] == d_prevWord
               || MATCH[MATCH_CLASS]  == d_prevWord
               || MATCH[MATCH_UNION]  == d_prevWord) {
                // there is no class name

                d_type = BDEFLAG_CLASS;
                return;                                               // RETURN
            }

            if (MATCH[MATCH_BSLS_NOTHROW_SPEC] == d_prevWord) {
                d_type = BDEFLAG_ROUTINE_BODY;
                return;                                               // RETURN
            }

            Place secondPrevWordBegin;
            bsl::string secondPrevWord =
                        (d_prevWordBegin - 1).wordBefore(&secondPrevWordBegin);

            if   (MATCH[MATCH_STRUCT] == secondPrevWord
               || MATCH[MATCH_CLASS]  == secondPrevWord
               || MATCH[MATCH_UNION]  == secondPrevWord) {
                // prevWord or secondPrevWord are 'struct', 'class', or 'union'

                d_className = d_prevWord;
                d_type = BDEFLAG_CLASS;
                return;                                               // RETURN
            }
            if (')' == *secondPrevWordBegin &&
                                            MATCH[MATCH_CONST] == d_prevWord) {
                Group *prevGroup =findGroupForPlace(secondPrevWordBegin);
                if (prevGroup->d_flags.d_parenBased) {
                    prevGroup->d_type = BDEFLAG_ROUTINE_DECL;
                    d_type = BDEFLAG_ROUTINE_BODY;
                    return;                                           // RETURN
                }
            }
            if (Lines::BDEFLAG_S_TEMPLATE == st) {
                int li = d_statementStart.lineNum();
                Place startName(li, Lines::lineIndent(li) + 7);
                BSLS_ASSERT_OPT('e' == *startName);
                ++startName;
                Place tnEnd;
                if (MATCH[MATCH_NIL] == startName.templateNameAfter(&tnEnd)) {
                    d_statementStart.error() << "'template' in very strange"
                                                                " context\n";
                }
                else {
                    const int liStart = tnEnd.lineNum() + 1;
                    for (li = liStart; li <= d_open.lineNum(); ++li) {
                        if (Lines::BDEFLAG_S_CLASS_STRUCT_UNION ==
                                                        Lines::statement(li)) {
                            if (Lines::lineIndent(li) ==
                                                      d_statementStart.col()) {
                                Place cursor =
                                             Place(li, d_statementStart.col());
                                Place nameEnd;
                                bsl::string name =
                                   cursor.findFirstOf(" ").nameAfter(&nameEnd);
                                char c = ':' == Ut::lastCharOf(name)
                                       ? ':'
                                       : *(nameEnd + 1);
                                if (Ut::charInString(c, ":{")) {
                                    d_className = name;
                                    d_type = BDEFLAG_CLASS;
                                    return;                           // RETURN
                                }
                            }
                        }
                    }
                    for (li = liStart; li <= d_open.lineNum(); ++li) {
                        if (Lines::BDEFLAG_S_CLASS_STRUCT_UNION ==
                                                        Lines::statement(li)) {
                            Place cursor =
                                   Place(li, Lines::lineIndent(li));
                            Place nameEnd;
                            bsl::string name =
                               cursor.findFirstOf(" ").nameAfter(&nameEnd);
                            char c = ':' == Ut::lastCharOf(name)
                                   ? ':'
                                   : *(nameEnd + 1);
                            if (Ut::charInString(c, ":{")) {
                                d_className = name;
                                d_type = BDEFLAG_CLASS;
                                return;                               // RETURN
                            }
                        }
                    }
                    for (int li = (tnEnd + 1).lineNum();
                                                li <= d_open.lineNum(); ++li) {
                        size_t pos = matchesAnyStruct(Lines::line(li));
                        if (Ut::npos() != pos) {
                            Place cursor(li, pos);
                            Place nameEnd;
                            bsl::string name =
                                   cursor.findFirstOf(" ").nameAfter(&nameEnd);
                            char c = ':' == Ut::lastCharOf(name)
                                   ? ':'
                                   : *(nameEnd + 1);
                            if (Ut::charInString(c, ":{")) {
                                d_className = name;
                                d_type = BDEFLAG_CLASS;
                                return;                               // RETURN
                            }
                        }
                    }
                }

                // don't know what's going on
            }
            if (BDEFLAG_CODE_BODY == d_parent->d_type ||
                                    BDEFLAG_ROUTINE_BODY == d_parent->d_type) {
                d_type = BDEFLAG_CODE_BODY;
                return;                                               // RETURN
            }
            if (MATCH[MATCH_ENUM] == d_prevWord ||
                MATCH[MATCH_ENUM] == secondPrevWord) {
                d_type = BDEFLAG_ENUM;
                return;                                               // RETURN
            }
        }
        else if (')' == pwbc) {
            Group *prevGroup = findGroupForPlace(d_prevWordBegin);
            GroupType prevType = prevGroup->d_type;
            GroupType pType = d_parent->d_type;

            bool found = true;
            switch (prevType) {
              case BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL:
              case BDEFLAG_ROUTINE_CALL:
              case BDEFLAG_ROUTINE_DECL:
              case BDEFLAG_CTOR_CLAUSE: {
                if (BDEFLAG_ROUTINE_CALL == prevType) {
                    if   ((BDEFLAG_CODE_BODY    == pType
                        || BDEFLAG_ROUTINE_BODY == pType)
                       && Ut::isUpperCaseString(prevGroup->d_prevWord)) {
                        // code body following a macro

                        d_type = BDEFLAG_CODE_BODY;
                        break;
                    }
                    prevGroup->d_open.error() << "apparent routine call to " <<
                       prevGroup->d_prevWord << " is followed by code block\n";
                }
                if (BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL == prevType ||
                                            BDEFLAG_ROUTINE_CALL == prevType) {
                    prevGroup->d_type = BDEFLAG_ROUTINE_DECL;
                }
                if (BDEFLAG_CLASS != pType && BDEFLAG_NAMESPACE != pType &&
                                                  BDEFLAG_TOP_LEVEL != pType) {
                    d_open.error() << "routine body in strange context,"
                        " contained in group type " << typeToStr(pType) <<endl;
                }
                d_type = BDEFLAG_ROUTINE_BODY;
              }  break;
              case BDEFLAG_CATCH_PARENS: {
                if (BDEFLAG_CLASS != pType && BDEFLAG_NAMESPACE != pType &&
                    BDEFLAG_TOP_LEVEL != pType && BDEFLAG_CODE_BODY != pType &&
                                               BDEFLAG_ROUTINE_BODY != pType) {
                    d_open.error() << "catch block in strange context,"
                        " contained in group type " << typeToStr(pType) <<endl;
                }
                d_type = BDEFLAG_CODE_BODY;
              }  break;
              case BDEFLAG_IF_WHILE_FOR:
              case BDEFLAG_SWITCH_PARENS: {
                if (BDEFLAG_CODE_BODY != pType &&
                                               BDEFLAG_ROUTINE_BODY != pType) {
                    d_open.error() << "code body in strange context,"
                       " contained in group type " << typeToStr(pType) << endl;
                }
                d_type = BDEFLAG_CODE_BODY;
              }  break;
              case BDEFLAG_THROW_PARENS: {
                if (BDEFLAG_CLASS != pType && BDEFLAG_TOP_LEVEL != pType &&
                                                  BDEFLAG_NAMESPACE != pType) {
                    d_open.error() << "routine body following throw clause"
                                         " in strange context, parent type is "
                                                   << typeToStr(pType) << endl;
                }
                d_type = BDEFLAG_ROUTINE_BODY;
              }  break;
              case BDEFLAG_EXPRESSION_PARENS: {
                d_open.error() << " '{' block following expression" <<
                                           " parens without terminating ';'\n";
              }  break;
              default: {
                prevGroup->d_open.error() << "unrecognized paren block type "<<
                             prevType << " preceding braces block at "
                                                             << d_open << endl;
                found = false;
              }
            }

            if (found) {
                return;                                               // RETURN
            }
        }
        else if (Ut::charInString(pwbc, ";{}") &&
                 (BDEFLAG_ROUTINE_BODY == d_parent->d_type ||
                  BDEFLAG_CODE_BODY    == d_parent->d_type)) {
            d_type = BDEFLAG_CODE_BODY;
            return;                                                   // RETURN
        }

        BSLS_ASSERT_OPT(BDEFLAG_UNKNOWN_BRACES == d_type);

        d_open.error() << "{} braces in strange context, parent group is" <<
                               " type " << typeToStr(d_parent->d_type) << endl;
        return;                                                       // RETURN
    }
}

int Group::initTopLevelGroup()
{
    Place cursor(0, 0);
    s_topLevel = this;

    d_flags.d_parenBased = false;
    d_type = BDEFLAG_TOP_LEVEL;

    int status = recurseInitGroup(&cursor, 0);
    if (0 != status && d_flags.d_earlyEof) {
        BSLS_ASSERT_OPT(Place::end() == cursor);

        d_close = Place::end();
        return 0;                                                     // RETURN
    }

    if (0 == status) {
        cursor.error() << "unmatched '}' at top level.\n";
    }
    else if (d_flags.d_closedWrong) {
        cursor.error() << "unmatched ')' at top level.\n";
    }
    else {
        cursor.error() << "unknown error at top level\n";
    }

    return -1;
}

// ACCESSORS
void Group::checkArgNames() const
{
    if (BDEFLAG_ROUTINE_DECL != d_type || isAnnoying(d_prevWord)) {
        return;                                                       // RETURN
    }

    if ('*' == *(d_open + 1)) {
        // probably a function pointer declaration

        return;                                                       // RETURN
    }

    // avoid calling 'getArgList' outside of class except on binary operators

    bool anyOp = Ut::frontMatches(d_prevWord, MATCH[MATCH_OPERATOR], 0);
    bool binOp = anyOp && binaryOperators.count(d_prevWord.substr(8));
    if (BDEFLAG_CLASS != d_parent->d_type && !binOp) {
        return;                                                       // RETURN
    }

    bsl::vector<bsl::string> typeNames;
    bsl::vector<bsl::string> argNames;
    bsl::vector<int>         lineNums;

    getArgList(&typeNames, &argNames, &lineNums);
    const int argCount = argNames.size();

    bool namesPresent = false;
    for (int i = 0; i < argCount; ++i) {
        if (MATCH[MATCH_NIL] != argNames[i] && '=' != argNames[i][0]) {
            namesPresent = true;
            break;
        }
    }

#if 0
    // This is a stupid check.  It especially complains about normal printf's.

    if (lineNums.size() > 0) {
        bool differentLineNums = false;
        bool twoShareLineNum = false;
        int prevLineNum = lineNums[0];
        for (int i = 1; i < lineNums.size(); ++i) {
            if (lineNums[i] == prevLineNum) {
                twoShareLineNum = true;
            }
            else {
                differentLineNums = true;
            }
            prevLineNum = lineNums[i];
        }
        if (differentLineNums && twoShareLineNum) {
            d_open.warning() << d_prevWord << ": arguments should either be"
                               " all on one line or each on a separate line\n";
        }
    }
#endif

    bool notImplemented = false;
    bool isFriend = false;
    if (BDEFLAG_CLASS == d_parent->d_type) {
        int classBegin = d_parent->d_open.lineNum();
        for (int li = d_open.lineNum(); li > classBegin; --li) {
            if (Lines::BDEFLAG_NOT_IMPLEMENTED == Lines::comment(li)) {
                notImplemented = true;
                break;
            }

            if (Lines::BDEFLAG_S_BLANKLINE == Lines::statement(li)) {
                break;
            }
        }

        int cli = d_open.lineNum();
        int li = Lines::lineBefore(&cli);
        for (++li ; li <= cli; ++li) {
            if (Lines::BDEFLAG_S_FRIEND == Lines::statement(li)) {
                isFriend = true;
                break;
            }
        }
    }

    if (!notImplemented) {
        if (MATCH[MATCH_SWAP] != d_prevWord) {
            if (argCount >= 1) {
                const bsl::string& tn = typeNames[0];
                const bsl::string& an = argNames[0];
                if (0 == tn.length()) {
                    d_open.error() <<
                              "null typename for first argument of routine " <<
                                                            d_prevWord << endl;
                }
                else if ('&' == tn[tn.length() - 1] &&
                                   Ut::npos() == tn.find(MATCH[MATCH_CONST]) &&
                                 !(bdeu_String::strstrCaseless(tn.c_str(),
                                                               tn.length(),
                                                               "stream", 6) ||
                                   bdeu_String::strstrCaseless(an.c_str(),
                                                               an.length(),
                                                               "stream", 6))) {
                    d_open.warning() << " first argument of routine " <<
                             d_prevWord << " is being passed as a reference" <<
                                                   " to a modifiable object\n";
                }
            }

            for (int i = 1; i < argCount; ++i) {
                const bsl::string& tn = typeNames[i];
                if (0 == tn.length()) {
                    d_open.error() << "null typename for " <<
                             Ut::nthString(i + 1) << " argument of routine " <<
                                                            d_prevWord << endl;
                }
                else if ('&' == tn[tn.length() - 1] &&
                                   Ut::npos() == tn.find(MATCH[MATCH_CONST])) {
                    d_open.warning() << Ut::nthString(i + 1) << " argument of"
                           " routine " << d_prevWord << " is being passed as a"
                                         " reference to a modifiable object\n";
                }
            }
        }
    }

    switch (d_parent->d_type) {
      case BDEFLAG_TOP_LEVEL:
      case BDEFLAG_NAMESPACE: {
        if (2 == argCount && (binOp || MATCH[MATCH_SWAP] == d_prevWord)) {
            if   (MATCH[MATCH_LHS] != argNames[0]
               || MATCH[MATCH_RHS] != argNames[1]) {
                if (0 != argCount ||
                                 !unaryOperators.count(d_prevWord.substr(8))) {
                    d_statementStart.warning() << "argument names of binary" <<
                                                 " operator '" << d_prevWord <<
                                               "' should be 'lhs' and 'rhs'\n";
                }
            }

            return;                                                   // RETURN
        }
      }  break;
      case BDEFLAG_CLASS: {
        if (binOp) {
            if (argCount != (isFriend ? 2 : 1)) {
                if (0 != argCount ||
                                 !unaryOperators.count(d_prevWord.substr(8))) {
                    d_open.error() << "confused, binary operator '" <<
                                  d_prevWord << "'with wrong number of args\n";
                }
            }
            else if (!isFriend && !notImplemented) {
                BSLS_ASSERT_OPT(1 == argCount);
                if (MATCH[MATCH_RHS] != argNames[0]) {
                    d_open.warning() << "argument name of binary operator " <<
                                            d_prevWord << " should be 'rhs'\n";
                }
            }
        }

        if (namesPresent) {
            if (isFriend) {
                d_open.warning() << "'friend' declaration of '"
                              << d_prevWord << "' should not have arg names\n";
                return;                                               // RETURN
            }

            if (notImplemented) {
                d_open.warning() << "'NOT IMPLEMENTED' function '" <<
                        d_prevWord <<
                            "' should not have arg names in the declaration\n";
                return;                                               // RETURN
            }

            if (binOp) {
                if (MATCH[MATCH_RHS] != argNames[0]) {
                    d_open.warning() << "binary operator '" << d_prevWord <<
                        "' should have arg name 'rhs', not '" << argNames[0] <<
                                                                         "'\n";
                }
                return;                                               // RETURN
            }

            if (!anyOp) {
                for (int i = 0; i < argCount; ++i) {
                    if  (MATCH[MATCH_LHS] == argNames[i]
                       ||MATCH[MATCH_RHS] == argNames[i]) {
                        d_open.warning() << d_prevWord << ": arg name '" <<
                         argNames[i] << "' is reserved for binary operators\n";
                    }
                }
            }

            if (MATCH[MATCH_SWAP] == d_prevWord) {
                if (1 == argCount && MATCH[MATCH_OTHER] != argNames[0]) {
                    d_open.warning() << "'swap' member function arg name"
                           " should be 'other', not '" << argNames[0] << "'\n";
                }
                return;                                               // RETURN
            }
        }

        if (d_prevWord == d_parent->d_className) {
            switch (argCount) {
              case 0: {
                ; // do nothing
              }  break;
              case 1: {
                const bsl::string& s = "const " + d_prevWord;
                bool copyCtor = false;

                if (typeNames[0] == (s + "&") || typeNames[0] == (s + " &")) {
                    copyCtor = true;
                }
                else {
                    bsl::string t = typeNames[0];
                    bsl::size_t start = t.find('<');

                    if (Ut::npos() != start) {
                        bsl::size_t finish = t.rfind('>');
                        if (Ut::npos() == finish) {
                            d_open.error() << d_prevWord <<
                                              ": strange template statement\n";
                        }
                        else {
                            t = t.substr(0, start) + t.substr(finish + 1);

                            if ((s + "&") == t || (s + " &") == t) {
                                copyCtor = true;
                            }
                        }
                    }
                }
                if (copyCtor) {
                    if (!notImplemented &&
                                        MATCH[MATCH_ORIGINAL] != argNames[0]) {
                        d_open.warning() << d_prevWord << " copy c'tor arg"
                                                      " name not 'original'\n";
                    }
                }
                else if (MATCH[MATCH_EXPLICIT] !=
                                          (d_prevWordBegin - 1).wordBefore()) {
                    d_open.warning() << d_prevWord << ": single argument"
                                      " constructor not declared 'explicit'\n";
                }
              }  break;
              case 2: {
                bool copyCtor = false;
                const bool potentialSingleArg =
                                         (Ut::npos() != argNames[1].find('='));

                if ((typeNames[1] == MATCH[MATCH_BSLMA_ALLOCATOR] ||
                             typeNames[1] == MATCH[MATCH_BSLMA_ALLOCATOR_B]) &&
                                                          potentialSingleArg) {
                    const bsl::string& s = "const " + d_prevWord;

                    if (typeNames[0] == (s + "&") ||
                                                  typeNames[0] == (s + " &")) {
                        copyCtor = true;
                    }
                    else {
                        bsl::string t = typeNames[0];
                        bsl::size_t start = t.find('<');
                        if (Ut::npos() != start) {
                            bsl::size_t finish = t.rfind('>');
                            if (Ut::npos() == finish) {
                                d_open.error() << d_prevWord <<
                                              ": strange template statement\n";
                            }
                            else {
                                t = t.substr(0, start) + t.substr(finish + 1);

                                if ((s + "&") == t || (s + " &") == t) {
                                    copyCtor = true;
                                }
                            }
                        }
                    }
                }
                copyCtor &= (typeNames[1] == MATCH[MATCH_BSLMA_ALLOCATOR] ||
                             typeNames[1] == MATCH[MATCH_BSLMA_ALLOCATOR_B]);
                if (copyCtor) {
                    if (!notImplemented &&
                                        MATCH[MATCH_ORIGINAL] != argNames[0]) {
                        d_open.warning() << d_prevWord << " copy c'tor arg"
                                                      " name not 'original'\n";
                    }
                }
                else if (potentialSingleArg && MATCH[MATCH_EXPLICIT] !=
                                          (d_prevWordBegin - 1).wordBefore()) {
                    // potentially single arg non-copy c'tor

                    d_open.warning() << d_prevWord << ": double argument"
                                        " constructor with default 2nd arg not"
                                                      " declared 'explicit'\n";
                }
              }  break;
              default: {
                BSLS_ASSERT_OPT(argCount >= 3);

                if (Ut::npos() != argNames[1].find('=')) {
                    if (MATCH[MATCH_EXPLICIT] !=
                                          (d_prevWordBegin - 1).wordBefore()) {
                        d_open.warning() << d_prevWord << ": many argument"
                                        " constructor with default 2nd arg not"
                                                      " declared 'explicit'\n";
                    }
                }
              }  break;
            }
        }
      } break;
    }
}

void Group::checkBooleanRoutineNames() const
{
    if (BDEFLAG_ROUTINE_DECL != d_type) {
        return;                                                       // RETURN
    }

    switch (d_parent->d_type) {
      case BDEFLAG_CLASS:
      case BDEFLAG_NAMESPACE:
      case BDEFLAG_TOP_LEVEL: {
        ; // do nothing
      }  break;
      default: {
        return;                                                       // RETURN
      }
    }

    if (Ut::npos() == d_prevWord.find(':')
       && (Ut::frontMatches(d_prevWord, MATCH[MATCH_IS],  0)
           || Ut::frontMatches(d_prevWord, MATCH[MATCH_ARE], 0)
           || (Ut::frontMatches(d_prevWord, MATCH[MATCH_HAS],  0) &&
                               d_prevWord.length() > 3 && 'h' != d_prevWord[3])
           || (Ut::frontMatches(d_prevWord, MATCH[MATCH_OPERATOR], 0) &&
                                               ':' != *(d_prevWordBegin - 1) &&
                                 boolOperators.count(d_prevWord.substr(8))))) {
        Place pb = d_prevWordBegin - 1;    // Place Before
        Place typeWordBegin;
        bsl::string typeWord = pb.wordBefore(&typeWordBegin);
        if ('&' == *typeWordBegin) {
            pb = typeWordBegin - 1;
            typeWord = pb.wordBefore();
        }

        if (MATCH[MATCH_BOOL] != typeWord) {
            shouldBool.insert(d_prevWord);
        }
    }
}

void Group::checkCodeComments() const
{
    switch (d_type) {
      case BDEFLAG_CLASS:
      case BDEFLAG_ROUTINE_BODY:
      case BDEFLAG_CODE_BODY: {
        ; // do nothing;
      }  break;
      default: {
        return;                                                       // RETURN
      }  break;
    }

    // Test drivers are totally screwy.  Give up unless we're in a class.

    if (Lines::BDEFLAG_DOT_T_DOT_CPP == Lines::fileType() &&
                                                     BDEFLAG_CLASS != d_type) {
        return;                                                       // RETURN
    }

    Lines::StatementType st = Lines::statement(d_statementStart.lineNum());
    const int expectIndent = Lines::BDEFLAG_S_CASE == st ||
                                               Lines::BDEFLAG_S_SWITCH == st ||
                                                 Lines::BDEFLAG_S_DEFAULT == st
                           ? d_close.col() + 2
                           : d_close.col() + 4;

    const int begin = d_open.lineNum() + 1;
    int li = begin;
    const int bigEnd = d_close.lineNum() - 1;

    const GroupSetIt endIt = d_subGroups.end();
    GroupSetIt it          = d_subGroups.begin();
    while (true) {
        const int end = endIt == it ? bigEnd
                                    : (*it)->d_open.lineNum() - 1;

        for ( ; li <= end; ++li) {
            const int commentStart = li;
            const int startIndent = Lines::commentIndent(li);
            if (Lines::BDEFLAG_S_BLANKLINE == Lines::statement(li)
               && Lines::BDEFLAG_UNRECOGNIZED == Lines::comment(li)) {
                bool ok = false;
                if (li > begin && Lines::BDEFLAG_S_BLANKLINE !=
                                                       Lines::statement(li - 1)
                                          && startIndent >= expectIndent + 4) {
                    ok = true;
                }
                else {
                    if (startIndent != expectIndent &&
                                             startIndent < expectIndent + 10) {
                        strangelyIndentedComments.insert(commentStart);
                    }
                }
                while (li <= end) {
                    if (Lines::BDEFLAG_S_BLANKLINE ==
                                                    Lines::statement(li + 1)) {
                        if (Lines::BDEFLAG_UNRECOGNIZED ==
                                                      Lines::comment(li + 1)) {
                            const int thisIndent = Lines::commentIndent(li);
                            const int nextIndent = Lines::commentIndent(li+1);
                            if (thisIndent != nextIndent
                               && (thisIndent != startIndent ||
                                               nextIndent != thisIndent + 4)) {
                                strangelyIndentedComments.insert(li + 1);
                            }
                            ++li;
                        }
                        else {
                            break;
                        }
                    }
                    else {
                        if (!ok && li < bigEnd) {
                            commentNeedsBlankLines.insert(li);
                        }
                        break;
                    }
                }
            }
        }

        if (endIt == it) {
            return;                                                   // RETURN
        }
        li = (*it)->d_close.lineNum() + 1;
        ++it;
    }
}


void Group::checkCodeIndents() const
{
    switch (d_type) {
      case BDEFLAG_CLASS:
      case BDEFLAG_CODE_BODY:
      case BDEFLAG_ROUTINE_BODY:
      case BDEFLAG_NAMESPACE:
      case BDEFLAG_TOP_LEVEL: {
        ; // do nothing
      }  break;
      default: {
        return;                                                       // RETURN
      }  break;
    }

    Lines::StatementType blockSt =
                                  Lines::statement(d_statementStart.lineNum());
    const int expectIndent = BDEFLAG_TOP_LEVEL == d_type
                           ? 0
                           : Lines::BDEFLAG_S_CASE == blockSt ||
                                         Lines::BDEFLAG_S_DEFAULT == blockSt ||
                                         Lines::BDEFLAG_S_SWITCH  == blockSt
                           ? d_close.col() + 2
                           : d_close.col() + 4;

    const int begin = d_open.lineNum() + 1;
    int li = begin;
    const int bigEnd = d_close.lineNum() - 1;

    const GroupSetIt endIt = d_subGroups.end();
    GroupSetIt it          = d_subGroups.begin();
    bool statementStart = true;
    while (true) {
        const int end = endIt == it ? bigEnd
                                    : (*it)->d_open.lineNum();

        for ( ; li <= end; ++li) {
            Lines::StatementType st = Lines::statement(li);

            if (statementStart) {
                int indent = Lines::lineIndent(li);
                bool prot = isProtectionStatement(st);
                if ((Lines::BDEFLAG_S_BLANKLINE != st &&
                                             expectIndent != indent) || prot) {
                    if (prot) {
                        if (BDEFLAG_CLASS != d_type) {
                            Place(li, indent).error() <<
                                                      "'public', 'private', or"
                                       " 'protected' statement not in class\n";
                        }
                        else {
                            if (expectIndent - 2 != indent) {
                                Place(li, indent).warning() << "'public',"
                                     " 'private', or 'protected' statement not"
                                                            " indented by 2\n";
                            }
                        }
                    }
                    else {
                        if ((BDEFLAG_NAMESPACE != d_type || 0 != indent) &&
                             (Lines::BDEFLAG_DOT_T_DOT_CPP != Lines::fileType()
                                                 || BDEFLAG_CLASS == d_type)) {
                            strangelyIndentedStatements.insert(li);
                        }
                    }
                }
            }

            statementStart = Lines::BDEFLAG_S_BLANKLINE == st
                           ? statementStart
                           : Lines::statementEnds(li);
        }

        if (endIt == it) {
            return;                                                   // RETURN
        }
        li = (*it)->d_close.lineNum();
        statementStart = Lines::statementEnds(li);
        ++li;
        ++it;
    }
}

void Group::checkFunctionDoc() const
{
    if (BDEFLAG_ROUTINE_DECL != d_type || isAnnoying(d_prevWord)) {
        return;                                                       // RETURN
    }

    bool exempt    = false;
    bool inClass   = false;
    bool doc       = false;
    bool isUnNamed = false;

    Place docPlace = d_close;
    char nextChar = *(d_close + 1);

    if (Ut::npos() != d_prevWord.find(':')) {
        // Defining something separately declared in a class somewhere.  It
        // should be documented in the class.

        return;                                                       // RETURN
    }

    if (BDEFLAG_CLASS == d_parent->d_type) {
        int cli = d_open.lineNum();
        int li = Lines::lineBefore(&cli);
        for (++li ; li <= cli; ++li) {
            if (Lines::BDEFLAG_S_FRIEND == Lines::statement(li)) {
                return;                                               // RETURN
            }
        }

        if (':' == nextChar) {
            // probably followed by c'tor clauses.  Move docplace to the the
            // close of the last ctor clause

            GroupSetIt it = d_parent->d_subGroups.find(this);
            BSLS_ASSERT_OPT(this == *it);
            const Group *group;
            for (++it; d_parent->d_subGroups.end() != it &&
                   (group = *it, BDEFLAG_CTOR_CLAUSE == group->d_type); ++it) {
                docPlace = group->d_close;
            }
        }

        inClass = true;
        doc     = true;
    }
    else {
        switch (Lines::fileType()) {
          case Lines::BDEFLAG_DOT_T_DOT_CPP: {
            return;                                                   // RETURN
          } break;
          case Lines::BDEFLAG_DOT_CPP: {
            if (BDEFLAG_NAMESPACE == d_parent->d_type &&
                                 !strncmp(d_prevWord.c_str(), "operator", 8)) {
                return;                                               // RETURN
            }
          } break;
        }

        if (';' == nextChar) {
            // Might be a variable or forward declaration.  If it is
            // documented, however, we want to note that, so don't return.

            exempt = true;
        }

        if (BDEFLAG_NAMESPACE == d_parent->d_type) {
            isUnNamed = MATCH[MATCH_NAMESPACE] == d_parent->d_prevWord;
            doc = true;
        }
        else {
            int cli = d_open.lineNum();
            int li = Lines::lineBefore(&cli);
            for (++li ; li <= cli; ++li) {
                const bsl::string& curLine = Lines::line(li);
                BSLS_ASSERT_OPT(curLine.length() > 0);

                if (Lines::BDEFLAG_S_STATIC == Lines::statement(li)
                   || (Lines::BDEFLAG_S_INLINE == Lines::statement(li) &&
                                      MATCH[MATCH_INLINE_STATIC] == curLine)) {
                    doc = true;
                    break;
                }
            }
            if (li > cli) {
                return;                                               // RETURN
            }
        }
    }

    BSLS_ASSERT_OPT(doc);

#if 0
    // This was totally unnecessary -- if we docced the last one, we're OK,
    // but for a free operator declared after the class and docced, immediately
    // followed by a full definition not docced, this was getting confused.

    // if another routine declaration of the same routine follows this one,
    // don't have to doc this one

    GroupSetIt it = d_parent->d_subGroups.find(this);
    BSLS_ASSERT_OPT(this == *it);
    ++it;
    if (d_parent->d_subGroups.end() != it) {
        const Group *group = *it;
        if (BDEFLAG_ROUTINE_DECL == group->d_type &&
                                             group->d_prevWord == d_prevWord) {
            return;                                                   // RETURN
        }
    }
#endif

    if (inClass) {
        int classBegin = d_parent->d_open.lineNum();
        for (int li = d_open.lineNum(); li > classBegin; --li) {
            if (Lines::BDEFLAG_NOT_IMPLEMENTED == Lines::comment(li)) {
                return;                                               // RETURN
            }

            if (Lines::BDEFLAG_S_BLANKLINE == Lines::statement(li)) {
                break;
            }
        }
    }

    if (Lines::BDEFLAG_UNRECOGNIZED != Lines::comment(docPlace.lineNum()+1)) {
        if (!exempt) {
            routinesNeedDoc.insert(d_prevWord);
        }
    }
    else {
        routinesDocced.insert(d_prevWord);
    }
}

void Group::checkIfWhileFor() const
{
    if (BDEFLAG_IF_WHILE_FOR != d_type) {
        return;                                                       // RETURN
    }

    char nextChar = *(d_close + 1);

    if ('{' == nextChar) {
        return;                                                       // RETURN
    }

    if (';' == nextChar && MATCH[MATCH_WHILE] == d_prevWord &&
                                               '}' == *(d_prevWordBegin - 1)) {
        return;                                                       // RETURN
    }

    d_close.warning() << "if/while/for doesn't control a {} block\n";
}


void Group::checkNamespace() const
{
    if (BDEFLAG_NAMESPACE != d_type || MATCH[MATCH_QUOTE_C] == d_prevWord) {
        return;                                                       // RETURN
    }

    bool commentFound = false;
    if ("namespace" == d_prevWord) {
        // unnamed namespace

        if (Lines::BDEFLAG_DOT_H == Lines::fileType()) {
            d_open.warning() << "unnamed namespace in .h file\n";
        }

        if (Lines::BDEFLAG_CLOSE_UNNAMED_NAMESPACE !=
                                           Lines::comment(d_close.lineNum())) {
            d_close.warning() << "when closed, the unnamed namespace should"
                            " have the comment '// close unnamed namespace'\n";
        }
        else {
            commentFound = true;
        }
    }
    else if ("BloombergLP" == d_prevWord) {
        // enterprise namespace

        Lines::CommentType closingCmt = Lines::comment(d_close.lineNum());
        if (Lines::BDEFLAG_CLOSE_NAMESPACE != closingCmt
           && Lines::BDEFLAG_CLOSE_ENTERPRISE_NAMESPACE != closingCmt) {
            d_close.warning() << "when closed, the BloombergLP namespace"
                       " should have the comment '// close namespace"
                       " BloombergLP' or '// close enterprise namespace'\n";
        }
        else {
            commentFound = true;
        }
    }
    else {
        if (Lines::BDEFLAG_CLOSE_NAMESPACE !=
                                           Lines::comment(d_close.lineNum())) {
            d_close.warning() << "when closed, namespaces should have the"
                         " comment '// close namespace <name of namespace>'\n";
        }
        else {
            commentFound = true;
        }
    }

    if (commentFound) {
        int col = Lines::commentIndent(d_close.lineNum());
        if (d_close.col() + 3 != col) {
            Place(d_close.lineNum(), col).warning() << "comments on closing"
                     " namespaces should be indented 2 spaces after the '}'\n";
        }
    }
}

void Group::checkNotImplemented() const
{
    if (BDEFLAG_CLASS != d_type) {
        return;                                                       // RETURN
    }

    int li = d_open.lineNum() + 1;
    const GroupSetIt endIt = d_subGroups.end();
    GroupSetIt it          = d_subGroups.begin();
    while (true) {
        int end = endIt == it ? d_close.lineNum() : (*it)->d_open.lineNum();

        for ( ; li <= end; ++li) {
            if (Lines::BDEFLAG_NOT_IMPLEMENTED == Lines::comment(li)) {
                if (Lines::BDEFLAG_S_PRIVATE == Lines::statement(li)) {
                    Place(li, Lines::commentIndent(li)).warning() <<
                        "'// NOT IMPLEMENTED' should"
                        " not be on same line as 'private:', it should be on"
                                        " a separate line immediately after\n";
                } else if (Lines::BDEFLAG_S_PRIVATE !=
                                                    Lines::statement(li - 1)) {
                    Place(li, Lines::commentIndent(li)).warning() <<
                          "'// NOT IMPLEMENTED' should"
                          " follow on line after line containing 'private:'\n";
                }
            }
        }

        if (endIt == it) {
            return;                                                   // RETURN
        }
        li = (*it)->d_close.lineNum() + 1;
        ++it;
    }
}

void Group::checkReturns() const
{
    bool find;
    switch (d_type) {
      case BDEFLAG_ROUTINE_BODY: {
        find = false;
      }  break;
      case BDEFLAG_CODE_BODY: {
        find = true;
      }  break;
      default: {
        return;                                                       // RETURN
      }  break;
    }

    int li = d_open.lineNum() + 1;

    const GroupSetIt endIt = d_subGroups.end();
    GroupSetIt it          = d_subGroups.begin();
    while (true) {
        int end = endIt == it ? d_close.lineNum() : (*it)->d_open.lineNum();

        for ( ; li <= end; ++li) {
            if (Lines::BDEFLAG_S_RETURN == Lines::statement(li)) {
                Place semiColon = Place(li, 0).findFirstOf(";");
                int startSearch = li;
                int endSearch   = semiColon.lineNum() + 1;
                bool found = false;
                for (int liB = startSearch; liB <= endSearch; ++liB) {
                    if (Lines::BDEFLAG_RETURN == Lines::comment(liB)) {
                        found = true;
                        break;
                    }
                }

                if (find) {
                    if (!found) {
                        returnCommentsNeeded.insert(li);
                    }
                }
                else {
                    if (found) {
                        returnCommentsNotNeeded.insert(li);
                    }
                }
            }
        }

        if (endIt == it) {
            return;                                                   // RETURN
        }
        li = (*it)->d_close.lineNum() + 1;
        ++it;
    }
}

// This routine is no longer called.  It is a stupid check that complains
// about the average printf.
void Group::checkRoutineCallArgList() const
{
    if (BDEFLAG_ROUTINE_CALL != d_type) {
        return;                                                       // RETURN
    }

    bsl::vector<int> lineNums;

    Place begin = d_open + 1;
    bool continuation = false;
    while (true) {
        if (!continuation) {
            lineNums.push_back(begin.lineNum());
        }
        continuation = false;

        Place end = begin.findFirstOf(",()");
        if (d_close == end) {
            break;
        }
        char c = *end;
        if (')' == c) {
            d_open.error() << d_prevWord << ": confusing arg list\n";
            return;                                                   // RETURN
        }
        else if ('(' == c) {
            const Group *group = findGroupForPlace(end);
            begin = group->d_close + 1;
            continuation = true;
        }
        else {    // ',' == c
            begin = end + 1;
        }
    }

    bool differentLineNums = false;
    bool twoShareLineNum = false;
    int prevLineNum = lineNums[0];
    for (int i = 1; i < lineNums.size(); ++i) {
        if (lineNums[i] == prevLineNum) {
            twoShareLineNum = true;
        }
        else {
            differentLineNums = true;
        }
        prevLineNum = lineNums[i];
    }
    if (differentLineNums && twoShareLineNum) {
        d_open.warning() << d_prevWord << ": arguments should either be"
                           " all on one line or each on a separate line\n";
    }
}

void Group::checkStartingAsserts() const
{
    if (BDEFLAG_ROUTINE_BODY != d_type) {
        return;                                                       // RETURN
    }

    int li = d_open.lineNum() + 1;
    if (Lines::BDEFLAG_S_ASSERT != Lines::statement(li)) {
        return;                                                       // RETURN
    }

    int endRoutine = d_close.lineNum();
    while (li < endRoutine) {
        if (Lines::BDEFLAG_S_BLANKLINE == Lines::statement(li)) {
            break;
        }
        else if (Lines::BDEFLAG_S_ASSERT != Lines::statement(li)) {
            assertsNeedBlankLine.insert(li);
            break;
        }
        li = Place(li, 0).findFirstOf(";").lineNum() + 1;
    }
}

void Group::checkStartingBraces() const
{
    if (BDEFLAG_ROUTINE_BODY != d_type) {
        return;                                                       // RETURN
    }

    int indent = 0;
    switch (d_parent->d_type) {
      case BDEFLAG_TOP_LEVEL:
      case BDEFLAG_NAMESPACE: {
        indent = 0;
      }  break;
      case BDEFLAG_CLASS: {
        if (Lines::BDEFLAG_DOT_H != Lines::fileType() &&
                                       d_close.lineNum() == d_open.lineNum()) {
            // It's evidently a one line function definition not in a .h file,
            // allow it.

            return;
        }

        indent = d_parent->d_close.col() + 4;
      }  break;
      case BDEFLAG_UNKNOWN_BRACES: {
        // Somewhat confused.  Give up.

        return;
      }  break;
      default: {
        // Really confused.  Complain.

        d_open.error() << "Confused -- function within brace pair of type \""
                                      << typeToStr(d_parent->d_type) << "\"\n";
        return;
      }
    }

    if (d_open.col() != indent ||
                        Lines::lineIndent(d_open.lineNum()) != indent ||
                        Lines::line(d_open.lineNum()).length() != indent + 1) {
        badlyAlignedFuncStartBrace.insert(d_open.lineNum());
    }
}

void Group::getArgList(bsl::vector<bsl::string> *typeNames,
                       bsl::vector<bsl::string> *names,
                       bsl::vector<int>         *lineNums) const
{
    if (BDEFLAG_ROUTINE_DECL != d_type) {
        return;                                                       // RETURN
    }
    BSLS_ASSERT_OPT(d_flags.d_parenBased);

    Place begin = d_open + 1;
    if (d_close == begin) {
        return;                                                       // RETURN
    }
    Place end = begin.findFirstOf(",()");
    while (true) {
        char c = *end;
        if ('(' == c || (')' == c && end != d_close)) {
            // Function pointer type in arglist.  Give up.

            typeNames->clear();
            names->clear();
            lineNums->clear();
            return;                                                   // RETURN
        }
        Place typeNameEnd;
        bsl::string typeName = begin.nameAfter(&typeNameEnd);
        if (MATCH[MATCH_NIL] == typeName) {
            begin.error() << "confusing arg list\n";
            typeNames->clear();
            names->clear();
            lineNums->clear();
            return;                                                   // RETURN
        }
        while (MATCH[MATCH_CONST] == typeName ||
                    MATCH[MATCH_VOLATILE] == typeName || '*' == *typeNameEnd) {
            typeName = (typeNameEnd + 1).nameAfter(&typeNameEnd);
        }
        if ('&' == *typeNameEnd) {
            begin.error() << "confusing arg declaration '" <<
                                       begin.twoPointsString(end - 1) << "'\n";
            typeNames->clear();
            names->clear();
            lineNums->clear();
            return;                                                   // RETURN
        }
        if (typeNameEnd > end) {
            // there was probably a ',' within a templated type

            if (typeNameEnd > d_close) {
                begin.error() << "strange argument definition '" <<
                                       begin.twoPointsString(end - 1) << "'\n";
                typeNames->clear();
                names->clear();
                lineNums->clear();
                return;                                               // RETURN
            }

            end = (typeNameEnd + 1).findFirstOf(",)(");
            if ('(' == *end || (')' == *end && end != d_close)) {
                // Function pointer type in arglist.  Give up.

                typeNames->clear();
                names->clear();
                lineNums->clear();
                return;                                               // RETURN
            }
        }

        // We got something other than "const", "volatile", or '*'.

        Place postTypeEnd;
        bsl::string postType = (typeNameEnd + 1).nameAfter(&postTypeEnd);
        while (MATCH[MATCH_CONST] == postType ||
                    MATCH[MATCH_VOLATILE] == postType || '*' == *postTypeEnd) {
            postType = (postTypeEnd + 1).nameAfter(&postTypeEnd);
        }
        char pte = *postTypeEnd;
        Place startName;
        if ('&' == pte) {
            startName = postTypeEnd + 1;
        }
        else if (',' == pte || ')' == pte) {
            startName = postTypeEnd;
        }
        else if ('=' == pte) {
            startName = postTypeEnd;
        }
        else {
            if (!Ut::alphaNumOrColon(pte)) {
                begin.error() << "strange argument def '" <<
                                       begin.twoPointsString(end - 1) << "'\n";
                typeNames->clear();
                names->clear();
                lineNums->clear();
                return;                                               // RETURN
            }

            postTypeEnd.wordBefore(&startName);
        }

        typeNames->push_back(begin.twoPointsString(startName - 1));
        names->push_back(startName.twoPointsString(end - 1));
        lineNums->push_back(begin.lineNum());

        if (end >= d_close) {
            break;
        }

        begin = end + 1;
        end = begin.findFirstOf(",()");
    }

    BSLS_ASSERT_OPT(end == d_close);
}

void Group::print() const
{
    bsl::cout << *d_open << ": Open: " << d_open << ", close: " << d_close <<
                 ", sStart: " << d_statementStart << ", prev: '" <<
                 d_prevWord << "', type: " << typeToStr(d_type) << endl;
}

const char *Group::typeToStr(Group::GroupType groupType)
{
    switch (groupType) {
      case BDEFLAG_UNKNOWN_BRACES:        return "UNKNOWN_BRACES";    // RETURN
      case BDEFLAG_TOP_LEVEL:             return "TOP_LEVEL";         // RETURN
      case BDEFLAG_NAMESPACE:             return "NAMESPACE";         // RETURN
      case BDEFLAG_CLASS:                 return "CLASS";             // RETURN
      case BDEFLAG_ENUM:                  return "ENUM";              // RETURN
      case BDEFLAG_INIT_BRACES:           return "INIT_BRACES";       // RETURN
      case BDEFLAG_ROUTINE_BODY:          return "ROUTINE_BODY";      // RETURN
      case BDEFLAG_CODE_BODY:             return "CODE_BODY";         // RETURN
      case BDEFLAG_UNKNOWN_PARENS:        return "UNKNOWN_PARENS";    // RETURN
      case BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL: {
        return "ROUTINE_UNKNOWN_CALL_OR_DECL";                        // RETURN
      }  break;
      case BDEFLAG_ROUTINE_DECL:          return "ROUTINE_DECL";      // RETURN
      case BDEFLAG_CTOR_CLAUSE:           return "CTOR_CLAUSE";       // RETURN
      case BDEFLAG_ROUTINE_CALL:          return "ROUTINE_CALL";      // RETURN
      case BDEFLAG_IF_WHILE_FOR:          return "IF_WHILE_FOR";      // RETURN
      case BDEFLAG_SWITCH_PARENS:         return "SWITCH_PARENS";     // RETURN
      case BDEFLAG_CATCH_PARENS:          return "CATCH_PARENS";      // RETURN
      case BDEFLAG_EXPRESSION_PARENS:     return "EXPRESSION_PARENS"; // RETURN
      case BDEFLAG_ASM:                   return "ASM";               // RETURN
      default:                            return "<strange type>";    // RETURN
    }
}
                                // ---------------
                                // Group::GroupSet
                                // ---------------

// CREATORS
Group::GroupSet::~GroupSet()
{
    bslma_Allocator *da = bslma_Default::defaultAllocator();
    const GroupSetIt constEnd = end();
    for (GroupSetIt it = begin(); constEnd != it; ++it) {
        da->deleteObjectRaw(*it);
    }
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

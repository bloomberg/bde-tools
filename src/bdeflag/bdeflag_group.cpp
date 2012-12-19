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

#include <bsl_algorithm.h>
#include <bsl_iostream.h>
#include <bsl_sstream.h>
#include <bsl_string.h>

#include <bsl_cstdlib.h>

#include <ctype.h>

#define P(x)          Ut::p(#x, (x))

namespace BloombergLP {

using bsl::cerr;
using bsl::endl;

namespace bdeflag {

static const bsl::string MATCH_STRUCT          = "struct";
static const bsl::string MATCH_CLASS           = "class";
static const bsl::string MATCH_UNION           = "union";
static const bsl::string MATCH_IS              = "is";
static const bsl::string MATCH_ARE             = "are";
static const bsl::string MATCH_HAS             = "has";
static const bsl::string MATCH_ENUM            = "enum";
static const bsl::string MATCH_CONST           = "const";
static const bsl::string MATCH_VOLATILE        = "volatile";
static const bsl::string MATCH_ASM             = "asm";
static const bsl::string MATCH_IF              = "if";
static const bsl::string MATCH_WHILE           = "while";
static const bsl::string MATCH_FOR             = "for";
static const bsl::string MATCH_SWITCH          = "switch";
static const bsl::string MATCH_CATCH           = "catch";
static const bsl::string MATCH_BSLS_CATCH      = "BSLS_CATCH";
static const bsl::string MATCH_BOOL            = "bool";
static const bsl::string MATCH_NIL             = "";
static const bsl::string MATCH_BSLALG_NESTED_TRAITS =
                                                "BSLALG_DECLARE_NESTED_TRAITS";
static const bsl::string MATCH_BSLMF_NESTED_TRAITS =
                                              "BSLMF_NESTED_TRAIT_DECLARATION";
static const bsl::string MATCH_INLINE_STATIC   = "inline static";
static const bsl::string MATCH_NAMESPACE       = "namespace";
static const bsl::string MATCH_OPERATOR        = "operator";
static const bsl::string MATCH_OPERATOR_LEFT_SHIFT  = "operator<<";
static const bsl::string MATCH_OPERATOR_RIGHT_SHIFT = "operator>>";
static const bsl::string MATCH_LHS             = "lhs";
static const bsl::string MATCH_RHS             = "rhs";
static const bsl::string MATCH_SWAP            = "swap";
static const bsl::string MATCH_OTHER           = "other";
static const bsl::string MATCH_ORIGINAL        = "original";
static const bsl::string MATCH_QUOTE_C         = "\"C\"";
static const bsl::string MATCH_THREE_QUOTES    = "\"\"\"";
static const bsl::string MATCH_EXTERN          = "extern";
static const bsl::string MATCH_ASM__           = "__asm__";
static const bsl::string MATCH_VOLATILE__      = "__volatile__";
static const bsl::string MATCH_RCSID           = "RCSID";
static const bsl::string MATCH_THROW           = "throw";
static const bsl::string MATCH_BSLS_EXCEPTION_SPEC = "BSLS_EXCEPTION_SPEC";
static const bsl::string MATCH_BSLS_NOTHROW_SPEC = "BSLS_NOTHROW_SPEC";
static const bsl::string MATCH__EXCEPT         = "__except";
static const bsl::string MATCH_PRINT           = "print";
static const bsl::string MATCH_BDEAT_DECL      = "BDEAT_DECL_";
static const bsl::string MATCH_EXPLICIT        = "explicit";
static const bsl::string MATCH_BLOOMBERGLP     = "BloombergLP";
static const bsl::string MATCH_TEMPLATE        = "template";
static const bsl::string MATCH_MAIN            = "main";
static const bsl::string MATCH_TEST            = "test";
static const bsl::string MATCH_BSLMF_METAINT   = "bslmf_MetaInt";
static const bsl::string MATCH_TYPENAME        = "typename";
static const bsl::string MATCH_BSLALG_TYPETRAITS = "bslalg_TypeTraits";
static const bsl::string MATCH_TYPETRAITS      = "TypeTraits";
static const bsl::string MATCH_ANGLES          = "<>";
static const bsl::string MATCH_STATIC          = "static";
static const bsl::string MATCH_STREAM          = "stream";
static const bsl::string MATCH_LEVEL           = "level";
static const bsl::string MATCH_SPACES_PER_LEVEL= "spacesPerLevel";
static const bsl::string MATCH_TST             = "tst_";

static bsl::vector<bool> classBoundaries;

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
static bsl::set<bsl::string> stlClasses;
static bsl::set<bsl::string> bslmfNonTraits;
static bsl::set<bsl::string> otherExemptClasses;

static bsl::set<bsl::string> validFriendTargets;

static struct ClassNameVals {
    // Only valid within 'checkAllClassNames

    bsl::string d_componentPrefix;
    bsl::string d_componentName;
    bsl::string d_componentNameNoPrefix;    // empty if no '_' in componentName
} classNameVals;

static bool tolerateSnugComments;

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
    static const char *arrayBoolOperators[] = {
        "!", "<", "<=", ">", ">=", "==", "!=", "&&", "||" };
    enum { NUM_ARRAY_BOOL_OPERATORS = sizeof arrayBoolOperators /
                                                  sizeof *arrayBoolOperators };
    for (int i = 0; i < NUM_ARRAY_BOOL_OPERATORS; ++i) {
        boolOperators.insert(arrayBoolOperators[i]);
    }

    static const char *arrayBinaryOperators[] = {
        "*", "/", "%", "+", "-", "<", "<=", ">", ">=", "==", "!=",
        "&", "^", "|", "&&", "||", "=" };
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
        "BSLMF_ASSERT", "sizeof", "__attribute__" };
    enum { NUM_ANNOYING_MACROS = sizeof arrayAnnoyingMacros /
                                                 sizeof *arrayAnnoyingMacros };
    for (int i = 0; i < NUM_ANNOYING_MACROS; ++i) {
        annoyingMacros.insert(arrayAnnoyingMacros[i]);
    }

    static const char *arrayStlClasses[] = {
        "allocator", "allocator_traits", "bitset", "reference", "deque",
        "equal_to", "hash", "char_traits", "basic_stringbuf",
        "basic_istringstream",
        "basic_ostringstream", "basic_stringstream", "basic_stringbuf",
        "stringbuf", "istringstream", "ostringstream", "stringstream",
        "wstringbuf", "wistringstream", "wostringstream", "wstringstream",
        "iterator_traits", "reverse_iterator", "list", "map", "multimap",
         "set","multiset", "pair", "priority_queue", "queue", "stack",
        "string", "basic_stringbuf", "basic_string",
        "stringbuf", "wstringbuf", "unordered_map", "unordered_multimap",
        "unordered_multiset", "unordered_set", "vector", "value_compare" };
    enum { NUM_ARRAY_STL_CLASSES =
                            sizeof arrayStlClasses / sizeof *arrayStlClasses };
    for (int i = 0; i < NUM_ARRAY_STL_CLASSES; ++i) {
        stlClasses.insert(arrayStlClasses[i]);
    }

    static const char *arrayBslmfNonTraits[] = {
        "add_const", "add_cv", "add_lvalue_reference", "add_pointer",
        "add_rvalue_reference", "add_volatile", "conditional", "enable_if",
        "integral_constant", "false_type", "true_type", "is_arithmetic",
        "is_array", "is_class", "is_const", "is_convertible", "is_enum",
        "is_floating_point", "is_function", "is_fundamental", "is_integral",
        "is_lvalue_reference", "is_member_function_pointer",
        "is_member_object_pointer", "is_member_pointer", "is_pointer",
        "is_reference", "is_rvalue_reference",
        "is_same", "is_void", "is_volatile",
        "remove_const", "remove_cv", "remove_pointer", "remove_reference",
        "remove_volatile" };
    enum { NUM_ARRAY_BSLMF_NON_TRAITS = sizeof arrayBslmfNonTraits /
                                                 sizeof *arrayBslmfNonTraits };
    for (int i = 0; i < NUM_ARRAY_BSLMF_NON_TRAITS; ++i) {
        bslmfNonTraits.insert(arrayBslmfNonTraits[i]);
    }

    static const char *arrayOtherExemptClasses[] = {
        "is_polymorphic", "is_trivially_copyable",
        "is_trivially_default_constructible",
        "bslalg_TypeTraits", "TypeTraits" };
    enum { NUM_ARRAY_OTHER_EXEMPT_CLASSES = sizeof arrayOtherExemptClasses
                                           / sizeof *arrayOtherExemptClasses };
    for (int i = 0; i < NUM_ARRAY_OTHER_EXEMPT_CLASSES; ++i) {
        otherExemptClasses.insert(arrayOtherExemptClasses[i]);
    }

    tolerateSnugComments = !!bsl::getenv("BDEFLAG_TOLERATE_SNUG_COMMENTS");
}

static
bool isAllocatorPtrType(const bsl::string& typeName)
    // Return 'true' if 'typeName' is a pointer to a type whose name ends with
    // 'Allocator'.
{
    static const bsl::string alloc = "Allocator";

    size_t idx = typeName.rfind(alloc);
    if (Ut::npos() == idx) {
        return false;                                                 // RETURN
    }
    const bsl::string& tn = typeName.substr(idx);

    size_t tl = tn.length();
    switch (tl - alloc.length()) {
      case 1: {
        return '*' == tn[tl - 1];                                     // RETURN
      } break;
      case 2: {
        return ' ' == tn[tl - 2] &&
               '*' == tn[tl - 1];                                     // RETURN
      } break;
      default: {
        return false;                                                 // RETURN
      }
    }
}

static
void removeUpThroughLastColon(bsl::string *s)
    // Remove any namespaces, containing classes, from a name -- everything up
    // through, and including, the last ':'.
{
    size_t u = s->rfind(':');
    if (Ut::npos() != u) {
        s->erase(0, u + 1);
    }
}

static
bool isExemptClassName(const bsl::string className)
    // Certain special class names, especially in bslstl and bslmf, are exempt
    // from normal rules for class names (i.e. starting with upper case).
{
    return (Lines::componentPrefix() == Lines::BDEFLAG_CP_BSLSTL &&
            stlClasses.       count(className))
        || (Lines::componentPrefix() == Lines::BDEFLAG_CP_BSLMF &&
            bslmfNonTraits.   count(className))
        || otherExemptClasses.count(className);
}

static
bool isModifiableRef(const bsl::string& typeName)
    // Given a typename of an arg to a method, return true if the type
    // describes a reference to a modifiable object.  Note that C++11 'rvalue'
    // '&&' refs do not qualify as modifiable refs.
{
    const int len = typeName.length();

    if (len >= 1) {
        if ('&' == typeName[len - 1]) {
            if (len >= 2) {
                if ('&' == typeName[len - 2]) {
                    // Rvalue

                    return false;                                     // RETURN
                }
            }

            if (! Ut::frontMatches(typeName, MATCH_CONST)) {
                return true;                                          // RETURN
            }
        }
    }

    return false;
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
                Ut::frontMatches(routineName, MATCH_BSLALG_NESTED_TRAITS, 0) ||
                Ut::frontMatches(routineName, MATCH_BSLMF_NESTED_TRAITS,  0) ||
                            Ut::frontMatches(routineName, MATCH_BDEAT_DECL, 0);
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
    pos = curLine.find(MATCH_STRUCT);
    if (Ut::npos() != pos) {
        matchStrLen = MATCH_STRUCT.length();
    }
    else {
        pos = curLine.find(MATCH_CLASS);
        if (Ut::npos() != pos) {
            matchStrLen = MATCH_CLASS.length();
        }
        else {
            pos = curLine.find(MATCH_UNION);
            if (Ut::npos() != pos) {
                matchStrLen = MATCH_UNION.length();
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
        if (d_prevWordBegin < d_statementStart && (!d_prevWord.empty() ||
                                        0 ==strchr(";}{", *d_prevWordBegin))) {
            // probably '{' lined up under 'struct' or 'template'

            d_statementStart = d_prevWordBegin.findStatementStart();
        }
        if (d_prevWord.empty() && '>' == *d_prevWordBegin) {
            // There's a real problem here, they might just be saying
            // 'a > (c + d)' and it's not really a template.  So what precedes
            // a '(', to be even possibly considered a template, the '>' must
            // touch the '('.

            if (!d_flags.d_parenBased ||
                            (d_prevWordBegin.col() == d_open.col() - 1 &&
                             d_prevWordBegin.lineNum() == d_open.lineNum())) {
                Place tnBegin;
                bsl::string tn = (d_open - 1).templateNameBefore(&tnBegin);
                if (!tn.empty()) {
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

void Group::checkAllCasesPresentInTestDriver()
{
    if (Lines::BDEFLAG_DOT_T_DOT_CPP != Lines::fileType()) {
        return;                                                       // RETURN
    }

    GroupSetIt endIt = topLevel().d_subGroups.end();
    GroupSetIt it    = topLevel().d_subGroups.begin();
    GroupSetIt prev  = it;

    const Group *mainGroup = 0;

    for (; endIt != it; prev = it, ++it) {
        if (BDEFLAG_ROUTINE_BODY != (*it)->d_type
           || BDEFLAG_ROUTINE_DECL != (*prev)->d_type
           || MATCH_MAIN != (*prev)->d_prevWord) {
            continue;
        }

        // we've found main

        if (mainGroup) {
            (*it)->d_open.warning() << "multiple 'main's found in test"
                                                                    "driver\n";
        }
        mainGroup = *it;
    }

    if (!mainGroup) {
        topLevel().d_close.warning() << "no 'main' routine found in test"
                                                                    "driver\n";
        return;                                                       // RETURN
    }

    endIt = mainGroup->d_subGroups.end();
    it    = mainGroup->d_subGroups.begin();
    prev  = it;

    GroupSet_Base switchCandidates;

    for (; endIt != it; prev = it, ++it) {
        if (BDEFLAG_CODE_BODY != (*it)->d_type
           || BDEFLAG_SWITCH_PARENS != (*prev)->d_type) {
            continue;
        }

        switchCandidates.insert(*it);
    }

    const Group *switchGroup = 0;

    switch (switchCandidates.size()) {
      case 0: {
        return;                                                       // RETURN
      }  break;
      case 1: {
        switchGroup = *switchCandidates.begin();
      }  break;
      default: {
        endIt = switchCandidates.end();
        it    = switchCandidates.begin();
        for (; endIt != it; ++it) {
            Place p = (*it)->d_open;
            --p;
            if (MATCH_TEST == p.wordBefore()) {
                if (switchGroup) {
                    p.warning() << "multiple 'switch (test)' in 'main()',"
                             " can't tell which is primary.  Assuming last.\n";
                }
                switchGroup = *it;
            }
        }
      }
    }

    if (!switchGroup) {
        return;                                                       // RETURN
    }

    Ut::LineNumSet caseNumbers;
    bool defaultFound = false;

    int li = switchGroup->d_open.lineNum() + 1;

    endIt = switchGroup->d_subGroups.end();
    it    = switchGroup->d_subGroups.begin();
    while (true) {
        int end = endIt == it ? switchGroup->d_close.lineNum()
                              : (*it)->d_open.lineNum();

        for ( ; li <= end; ++li) {
            const Lines::StatementType st = Lines::statement(li);
            if (Lines::BDEFLAG_S_CASE == st) {
                const bsl::string& ln = Lines::line(li);
                bsl::istringstream iss(ln.substr(Lines::lineIndent(li) + 4));
                int caseNumber;
                iss >> caseNumber;
                if (!iss.fail()) {
                    caseNumbers.insert(caseNumber);
                }
            }
            else if (Lines::BDEFLAG_S_DEFAULT == st) {
                defaultFound = true;
            }
        }

        if (endIt == it) {
            break;
        }
        li = (*it)->d_close.lineNum() + 1;
        ++it;
    }

    if (!defaultFound) {
        switchGroup->d_open.warning() << "no default case found in main"
                                                  " 'switch' in test driver\n";
    }

    Ut::LineNumSet missingNumbers;

    const Ut::LineNumSetIt endCNIt = caseNumbers.end();
    Ut::LineNumSetIt          cNIt = caseNumbers.begin();
    int cN = -1;

    for (; cNIt != endCNIt; ++cNIt) {
        if (*cNIt >= 1) {
            if (1 == *cNIt) {
                cN = 1;
            }
            else {
                if (cN < *cNIt) {
                    if (cN < 0) {
                        cN = 1;
                    }
                    for (; cN < *cNIt; ++cN) {
                        missingNumbers.insert(cN);
                    }
                }
            }
            ++cN;
        }
    }

    if (0 != missingNumbers.size()) {
        switchGroup->d_open.warning() << "main switch in test driver skipped"<<
                                         " case(s) " << missingNumbers << endl;
    }
}

void Group::checkAllClassNames()
{
    ClassNameVals& cnv = classNameVals;

    cnv.d_componentName = Lines::fileName();

    // take basename, chop off suffix
    {
        bsl::size_t u = cnv.d_componentName.rfind('/');
        if (Ut::npos() != u) {
            cnv.d_componentName = cnv.d_componentName.substr(u + 1);
        }
        u = cnv.d_componentName.find('.');
        if (Ut::npos() != u) {
            cnv.d_componentName.resize(u);
        }
        if (Ut::frontMatches(cnv.d_componentName, MATCH_TST, 0)) {
            cnv.d_componentName = cnv.d_componentName.substr(4);
        }
    }

    // find prefix.  Note that 'a_' is not a prefix, 'a_bdema_' is.  Also be
    // able to handle 'z_a_bdema_'.

    cnv.d_componentPrefix.clear();
    cnv.d_componentNameNoPrefix.clear();
    for (bsl::size_t uu = 0, nn; true; uu = nn) {
        nn = cnv.d_componentName.find('_', uu);
        if (Ut::npos() != nn) {
            ++nn;
            if (nn - uu > 2) {
                cnv.d_componentNameNoPrefix = cnv.d_componentName.substr(nn);
                cnv.d_componentPrefix       = cnv.d_componentName.substr(0,nn);
                break;
            }
        }
        else {
            break;
        }
    }

    topLevel().recurseMemTraverse(&Group::checkClassName);
}

void Group::checkAllCodeComments()
{
    strangelyIndentedComments.clear();
    commentNeedsBlankLines.clear();

    topLevel().recurseMemTraverse(&Group::checkCodeComments);

    if (!strangelyIndentedComments.empty()) {
        cerr << "Warning: " << Lines::fileName() <<
                    ": strangely indented comments at line(s) " <<
                                             strangelyIndentedComments << endl;
        strangelyIndentedComments.clear();
    }
    if (!tolerateSnugComments && !commentNeedsBlankLines.empty()) {
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

void Group::checkAllFriends()
{
    if (Lines::BDEFLAG_DOT_H != Lines::fileType()) {
        return;                                                       // RETURN
    }

    validFriendTargets.clear();

    // Collect all declarations of subroutines and class/struct/union
    // definitions

    topLevel().recurseMemTraverse(&Group::registerValidFriendTarget);

    bool dump = false;
    static bool firstTime = true;
    if (firstTime) {
        firstTime = false;

        dump = !!bsl::getenv("BDEFLAG_DUMP_FRIENDSHIP_TARGETS");

        if (dump) {
            bsl::cout << "Recursion-found friendship targets:";
            for (bsl::set<bsl::string>::iterator it =
                                                    validFriendTargets.begin();
                                        validFriendTargets.end() != it; ++it) {
                bsl::cout << ' ' << *it;
            }
            bsl::cout << bsl::endl;
        }
    }

    // Also traverse all class/struct/union statements looking for forward
    // declarations within classes, and only those.

    for (int li = 1; li < Lines::lineCount(); ++li) {
        if (Lines::BDEFLAG_S_CLASS_STRUCT_UNION == Lines::statement(li)) {
            Place pl(li, Lines::lineIndent(li));
            if ('{' == *(pl.findFirstOf(";{"))) {
                // Not a forward declaration.  Redundant.

                continue;
            }

            Group *parent = findGroupForPlace(pl);
            if (BDEFLAG_CLASS != parent->d_type) {
                // Not a forward declaration within a class.  Not a valid
                // friendship target.

                continue;
            }

            pl.wordAfter(&pl);            // skip 'class', 'struct', or 'union'
            ++pl;

            bsl::string className = pl.wordAfter();    // ignores '<' and after
            BSLS_ASSERT(Ut::npos() == className.find('<'));

            if (Ut::npos() != className.find(':')) {
                pl.error() << "Forward declaring class '" << className <<
                                      "' with ':' in name -- not valid C++!\n";
                continue;
            }

            validFriendTargets.insert(className);
        }
    }

    if (dump) {
        bsl::cout << "Recursion+scan-found friendship targets:";
        for (bsl::set<bsl::string>::iterator it = validFriendTargets.begin();
                                        validFriendTargets.end() != it; ++it) {
            bsl::cout << ' ' << *it;
        }
        bsl::cout << bsl::endl;
    }

    for (int li = 1; li < Lines::lineCount(); ++li) {
        if (Lines::BDEFLAG_S_FRIEND == Lines::statement(li)) {
            const bsl::string& curLine = Lines::line(li);
            int namePos = Lines::lineIndent(li) + 6;
            BSLS_ASSERT('d' == curLine[namePos - 1]);

            bool isClass = false;
            bool isOp = false;
            bsl::string friendName;
            Place pl = Place(li, namePos).findFirstOf(";(");
            if (';' == *pl) {
                // It's a class

                isClass = true;

                friendName = Place(li, namePos).wordAfter(&pl);

                bool tplate = false;
                if (MATCH_TEMPLATE == friendName) {
                    tplate = true;

                    (pl + 1).templateNameAfter(&pl);

                    friendName = (pl + 1).wordAfter(&pl);
                }

                if (MATCH_CLASS  != friendName &&
                    MATCH_STRUCT != friendName &&
                    MATCH_UNION  != friendName) {
                    // confused.  skip it.

                    if (!tplate) {
                        pl.error() << "Confusing 'friend' statement, not"
                                " routine, class, struct, or union\n";
                    }
                }

                friendName = (pl + 1).wordAfter();

                BSLS_ASSERT(Ut::npos() == friendName.find('<'));
            }
            else {
                BSLS_ASSERT_OPT('(' == *pl);

                // it's a routine

                Group *group = findGroupForPlace(pl);

                friendName = group->d_prevWord;
                isOp = Ut::frontMatches(friendName, MATCH_OPERATOR);
                if (!isOp) {
                    size_t pos = friendName.find('<');
                    if (Ut::npos() != pos) {
                        friendName.resize(pos);
                    }
                }
            }
            BSLS_ASSERT(isOp || Ut::npos() == friendName.find_first_of(
                                                                MATCH_ANGLES));
                                                        // match_angles == "<>"

            if (friendName.empty()) {
                continue;
            }

            if (dump) {
                bsl::cout << "Friend search at " << pl << " on '" <<
                                                           friendName << "'\n";
            }

            // The friended thing may be a compound name of several things
            // things mashed together with "::"s.  If ANY of them are valid
            // friend targets, then it's an acceptable friendship.

            bsl::string compoundFriendName = friendName;

            bool found = false;
            while (true) {
                size_t colon = compoundFriendName.find(':');
                bsl::string subName = Ut::npos() == colon
                                    ? compoundFriendName
                                    : compoundFriendName.substr(0, colon);
                if (validFriendTargets.count(subName)) {
                    found = true;
                    break;
                }
                else if (isClass) {
                    typedef bsl::set<bsl::string>::iterator It;
                    It end = validFriendTargets.end();
                    for (It it = validFriendTargets.begin(); end != it; ++it) {
                        if (Ut::frontMatches(subName, *it, 0)) {
                            found = true;
                            break;
                        }
                    }
                }
                if (Ut::npos() == colon) {
                    break;
                }

                size_t notColon = compoundFriendName.find_first_not_of(
                                                                   ':', colon);
                compoundFriendName = compoundFriendName.substr(notColon);
            }

            if (!found) {
                Place(li, Lines::lineIndent(li)).warning() << "friendship"
                           " of '" << friendName << "' outside of component\n";
            }
        }
    }
}

void Group::checkAllFunctionDoc()
{
    if (Lines::BDEFLAG_DOT_T_DOT_CPP == Lines::fileType()) {
        return;                                                       // RETURN
    }

    topLevel().recurseMemTraverse(&Group::checkFunctionDoc);

    if (routinesNeedDoc.count(MATCH_OPERATOR)) {
        routinesNeedDoc.erase(MATCH_OPERATOR);
    }

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

void Group::checkAllFunctionSections()
{
    if (Lines::BDEFLAG_DOT_T_DOT_CPP == Lines::fileType()) {
        return;                                                       // RETURN
    }

    classBoundaries.clear();
    classBoundaries.resize(Lines::lineCount() + 1, false);
    topLevel().recurseMemTraverse(&Group::markClassBoundaries);

    topLevel().recurseMemTraverse(&Group::checkFunctionSection);
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
                Place cA;
                const bsl::string nWord = cursor.nameAfter(&cA, true);
                ++cA;
                Place cB;
                cA.nameAfter(&cB, true);
                ++cB;
                if   ((MATCH_STRUCT == nWord
                   ||  MATCH_CLASS  == nWord
                   ||  MATCH_UNION  == nWord) && ';' == *cB
                   ||  '(' == *cB) {
                    // forward template instantiation -- ignore it

                    continue;
                }
                (cursor - 8).error() << "'template' not followed by '<'\n";
                continue;
            }
            Place tnEnd;
            if (cursor.templateNameAfter(&tnEnd).empty()) {
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
    checkAllClassNames();
    checkAllFunctionDoc();
    checkAllFunctionSections();
    checkAllReturns();
    checkAllNotImplemented();
    checkAllNamespaces();
    checkAllStartingAsserts();
    checkAllStartingBraces();
    checkAllTemplateOnOwnLine();
    checkAllCodeComments();
    checkAllFriends();
    checkAllArgNames();
    checkAllIfWhileFor();
    checkAllStatics();
    checkAllCasesPresentInTestDriver();

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

        if (d_prevWord.empty()) {
            bool expression = false;
            if (Ut::charInString(pwbc, "~!%^&*-+=<>,?:(){}|[]/")) {
                expression = true;
                if (d_open.lineNum() == d_prevWordBegin.lineNum()) {
                    const bsl::string curLine = Lines::line(d_open.lineNum());
                    size_t pos = curLine.rfind(MATCH_OPERATOR,
                                               d_prevWordBegin.col());
                    int iPos = pos;
                    if (Ut::npos() != pos) {
                        const bsl::string& sub =
                              curLine.substr(iPos,
                                             d_prevWordBegin.col() + 1 - iPos);
                        const bsl::string op = Ut::spacesOut(sub);
                        Place begin(d_open.lineNum(), iPos);
                        if (op.length() <= 11 && MATCH_OPERATOR ==
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

        if   (MATCH_IF    == d_prevWord
           || MATCH_WHILE == d_prevWord
           || MATCH_FOR   == d_prevWord) {
            d_type = BDEFLAG_IF_WHILE_FOR;
            if (BDEFLAG_ROUTINE_BODY != d_parent->d_type &&
                                       BDEFLAG_CODE_BODY != d_parent->d_type) {
                d_prevWordBegin.error() << d_prevWord <<
                                      " in strange context, parent type is " <<
                                           typeToStr(d_parent->d_type) << endl;
            }
            return;                                                   // RETURN
        }

        if (MATCH_SWITCH == d_prevWord) {
            d_type = BDEFLAG_SWITCH_PARENS;
            if (BDEFLAG_ROUTINE_BODY != d_parent->d_type &&
                                       BDEFLAG_CODE_BODY != d_parent->d_type) {
                d_prevWordBegin.error() << d_prevWord <<
                                      " in strange context, parent type is " <<
                                           typeToStr(d_parent->d_type) << endl;
            }
            return;                                                   // RETURN
        }

        if   (MATCH_CATCH == d_prevWord
           || MATCH_BSLS_CATCH == d_prevWord
           || MATCH__EXCEPT == d_prevWord) {
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

        if ((MATCH_ASM__ == d_prevWord ||
              (MATCH_VOLATILE__ == d_prevWord &&
                  MATCH_ASM__ == (d_prevWordBegin - 1).wordBefore())) ||
            (MATCH_ASM == d_prevWord ||
                (MATCH_VOLATILE == d_prevWord &&
                    MATCH_ASM == (d_prevWordBegin - 1).wordBefore()))) {
            d_type = BDEFLAG_ASM;
            return;                                                   // RETURN
        }

        if (MATCH_THROW == d_prevWord ||
                                     MATCH_BSLS_EXCEPTION_SPEC == d_prevWord) {
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
                Ut::stripAngleBrackets(&d_className);
                removeUpThroughLastColon(&d_className);
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
                               d_prevWord.empty() && '"' == *d_prevWordBegin) {
                int li = d_prevWordBegin.lineNum();
                const bsl::string& curLine = Lines::line(li);
                int col = d_prevWordBegin.col();
                while (col > 0 && '"' == curLine[col - 1]) {
                    --col;
                }
                if (MATCH_EXTERN == (Place(li, col) - 1).wordBefore()) {
                    d_prevWord = MATCH_QUOTE_C;
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

        if (!d_prevWord.empty()) {
            if   (MATCH_STRUCT == d_prevWord
               || MATCH_CLASS  == d_prevWord
               || MATCH_UNION  == d_prevWord) {
                // there is no class name

                d_type = BDEFLAG_CLASS;
                return;                                               // RETURN
            }

            if (MATCH_BSLS_NOTHROW_SPEC == d_prevWord) {
                d_type = BDEFLAG_ROUTINE_BODY;
                return;                                               // RETURN
            }

            Place secondPrevWordBegin;
            bsl::string secondPrevWord =
                        (d_prevWordBegin - 1).wordBefore(&secondPrevWordBegin);

            if   (MATCH_STRUCT == secondPrevWord
               || MATCH_CLASS  == secondPrevWord
               || MATCH_UNION  == secondPrevWord) {
                // prevWord or secondPrevWord are 'struct', 'class', or 'union'

                d_className = d_prevWord;
                Ut::stripAngleBrackets(&d_className);
                removeUpThroughLastColon(&d_className);
                d_type = BDEFLAG_CLASS;
                return;                                               // RETURN
            }
            if (')' == *secondPrevWordBegin && MATCH_CONST == d_prevWord) {
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
                if (startName.templateNameAfter(&tnEnd).empty()) {
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
                                    Ut::stripAngleBrackets(&d_className);
                                    removeUpThroughLastColon(&d_className);
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
                                Ut::stripAngleBrackets(&d_className);
                                removeUpThroughLastColon(&d_className);
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
                                Ut::stripAngleBrackets(&d_className);
                                removeUpThroughLastColon(&d_className);
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
            if (MATCH_ENUM == d_prevWord ||
                MATCH_ENUM == secondPrevWord) {
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

    bool anyOp = Ut::frontMatches(d_prevWord, MATCH_OPERATOR, 0);
    bool binOp = anyOp && binaryOperators.count(d_prevWord.substr(8));
    bool shiftOp = anyOp && !binOp &&
                                   (MATCH_OPERATOR_LEFT_SHIFT  == d_prevWord ||
                                    MATCH_OPERATOR_RIGHT_SHIFT == d_prevWord);
    if (BDEFLAG_CLASS != d_parent->d_type && !binOp && !shiftOp) {
        return;                                                       // RETURN
    }

    bsl::vector<bsl::string> typeNames;
    bsl::vector<bsl::string> argNames;
    bsl::vector<int>         lineNums;
    bool potentialSingleArg;

    getArgList(&typeNames, &argNames, &lineNums, &potentialSingleArg);
    const int argCount = argNames.size();

    bool namesPresent = false;
    for (int i = 0; i < argCount; ++i) {
        if (!argNames[i].empty() && '=' != argNames[i][0]) {
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
        if (MATCH_SWAP != d_prevWord) {
            if (argCount >= 1) {
                const bsl::string& tn = typeNames[0];
                const bsl::string& an = argNames[0];
                if (0 == tn.length()) {
                    d_open.error() <<
                              "null typename for first argument of routine " <<
                                                            d_prevWord << endl;
                }
                else if (isModifiableRef(tn)) {
                    bool ok = false;
                    static struct {
                        int         d_length;
                        const char *d_name;
                    } okNames[] = { 0, "stream",
                                    0, "manipulator",
                                    0, "accessor",
                                    0, "visitor" };
                    enum { NUM_OKNAMES = sizeof okNames / sizeof *okNames };
                    if (0 == okNames[0].d_length) {
                        for (int i = 0; i < NUM_OKNAMES; ++i) {
                            okNames[i].d_length =
                                                bsl::strlen(okNames[i].d_name);
                        }
                    }
                    for (int i = 0; i < NUM_OKNAMES; ++i) {
                        if (Ut::npos() != an.find(okNames[i].d_name)) {
                            ok = true;
                            break;
                        }
                    }
                    if (!ok) {
                        for (int i = 0; i < NUM_OKNAMES; ++i) {
                            if (bdeu_String::strstrCaseless(
                                                        tn.c_str(),
                                                        tn.length(),
                                                        okNames[i].d_name,
                                                        okNames[i].d_length)) {
                                ok = true;
                                break;
                            }
                        }
                    }
                    if (!ok) {
                        d_open.warning() << " first argument of routine " <<
                                            d_prevWord << " of type '" << tn <<
                                          "' is being passed as a reference" <<
                                                   " to a modifiable object\n";
                    }
                }
            }

            for (int i = 1; i < argCount; ++i) {
                const bsl::string& tn = typeNames[i];
                if (0 == tn.length()) {
                    d_open.error() << "null typename for " <<
                             Ut::nthString(i + 1) << " argument of routine " <<
                                                            d_prevWord << endl;
                }
                else if (isModifiableRef(tn)) {
                    if (1 != i || MATCH_OPERATOR_RIGHT_SHIFT != d_prevWord) {
                        d_open.warning() << Ut::nthString(i + 1) <<
                                       " argument of routine " << d_prevWord <<
                                 " of type '" << tn << "' is being passed as a"
                                         " reference to a modifiable object\n";
                    }
                }
            }
        }
    }

    switch (d_parent->d_type) {
      case BDEFLAG_TOP_LEVEL:
      case BDEFLAG_NAMESPACE: {
        if (2 == argCount && (binOp || MATCH_SWAP == d_prevWord)) {
            if   (MATCH_LHS != argNames[0]
               || MATCH_RHS != argNames[1]) {
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
                if (!unaryOperators.count(d_prevWord.substr(8)) ||
                                              argCount != (isFriend ? 1 : 0)) {
                    d_open.error() << "confused, binary operator '" <<
                                  d_prevWord << "'with wrong number of args\n";
                }
            }
#if 0
            else if (!isFriend && !notImplemented) {
                BSLS_ASSERT_OPT(1 == argCount);
                if (MATCH_RHS != argNames[0]) {
                    d_open.warning() << "argument name of binary operator " <<
                                  d_prevWord << " should be 'rhs' and not '" <<
                                                          argNames[0] << "'\n";
                }
            }
#endif
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
                if (MATCH_RHS != argNames[0]) {
                    d_open.warning() << "binary operator '" << d_prevWord <<
                        "' should have arg name 'rhs', not '" << argNames[0] <<
                                                                         "'\n";
                }
                return;                                               // RETURN
            }

            if (!anyOp) {
                for (int i = 0; i < argCount; ++i) {
                    if  (MATCH_LHS == argNames[i]
                       ||MATCH_RHS == argNames[i]) {
                        d_open.warning() << d_prevWord << ": arg name '" <<
                         argNames[i] << "' is reserved for binary operators\n";
                    }
                }
            }

            if (MATCH_SWAP == d_prevWord) {
                if (1 == argCount && MATCH_OTHER != argNames[0]) {
                    d_open.warning() << "'swap' member function arg name"
                           " should be 'other', not '" << argNames[0] << "'\n";
                }
                return;                                               // RETURN
            }

            if (MATCH_PRINT == d_prevWord) {
                if (3 != argNames.size()) {
                    d_open.warning() << "'print' should have 3 args\n";
                }
                else {
                    if (MATCH_STREAM != argNames[0]) {
                        d_open.warning() << "first arg of 'print' should be"
                                                          " named 'stream'.\n";
                    }
                    if (MATCH_LEVEL != argNames[1]) {
                        d_open.warning() << "second arg of 'print' should be"
                                                           " named 'level'.\n";
                    }
                    if (MATCH_SPACES_PER_LEVEL != argNames[2]) {
                        d_open.warning() << "third arg of 'print' should be"
                                                  " named 'spacesPerLevel'.\n";
                    }
                    if (!potentialSingleArg) {
                        d_open.warning() << "2nd and 3rd args of 'print'"
                                                      " should be optional.\n";
                    }
                }
            }
        }

        bsl::string lastPartOfClassName = d_parent->d_className;
        {
            size_t u = lastPartOfClassName.rfind(':');
            if (Ut::npos() != u) {
                lastPartOfClassName = lastPartOfClassName.substr(u + 1);
            }
        }

        if (d_prevWord == lastPartOfClassName) {
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
                    if (!notImplemented && MATCH_ORIGINAL != argNames[0]) {
                        d_open.warning() << d_prevWord << " copy c'tor arg"
                                                      " name not 'original'\n";
                    }
                }
                else if (MATCH_EXPLICIT !=
                                          (d_prevWordBegin - 1).wordBefore() &&
                                                         !isMarkedImplicit()) {
                    d_open.warning() << d_prevWord << ": single argument"
                                         " constructor not declared 'explicit'"
                                                  " or marked '// IMPLICIT'\n";
                }
              }  break;
              case 2: {
                bool copyCtor = false;
                if (isAllocatorPtrType(typeNames[1]) && potentialSingleArg) {
                    const bsl::string& s = "const " + d_prevWord;

                    if     (typeNames[0] == (s + "&") ||
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
                copyCtor &= isAllocatorPtrType(typeNames[1]);
                if (copyCtor) {
                    if (!notImplemented && MATCH_ORIGINAL != argNames[0]) {
                        d_open.warning() << d_prevWord << " copy c'tor arg"
                                                      " name not 'original'\n";
                    }

                    // note we don't mark copy c'tors 'explicit'
                }
                else if (potentialSingleArg && MATCH_EXPLICIT !=
                                          (d_prevWordBegin - 1).wordBefore() &&
                                                         !isMarkedImplicit()) {
                    // potentially single arg non-copy c'tor

                    d_open.warning() << d_prevWord << ": double argument"
                               " constructor with default 2nd arg not declared"
                                       " 'explicit' or marked '// IMPLICIT'\n";
                }
              }  break;
              default: {
                BSLS_ASSERT_OPT(argCount >= 3);

                if (potentialSingleArg) {
                    if (MATCH_EXPLICIT != (d_prevWordBegin - 1).wordBefore() &&
                                                         !isMarkedImplicit()) {
                        d_open.warning() << d_prevWord << ": many argument"
                               " constructor with default 2nd arg not declared"
                                       " 'explicit' or marked '// IMPLICIT'\n";
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
       && (Ut::frontMatches(d_prevWord, MATCH_IS,  0)
           || Ut::frontMatches(d_prevWord, MATCH_ARE, 0)
           || (Ut::frontMatches(d_prevWord, MATCH_HAS,  0) &&
                             d_prevWord.length() > 3 && isupper(d_prevWord[3]))
           || (Ut::frontMatches(d_prevWord, MATCH_OPERATOR, 0) &&
                                               ':' != *(d_prevWordBegin - 1) &&
                                 boolOperators.count(d_prevWord.substr(8))))) {
        Place pb = d_prevWordBegin - 1;    // Place Before
        if ('>' == *pb) {
            if (!Ut::frontMatches(pb.templateNameBefore(),
                                  MATCH_BSLMF_METAINT,
                                  0)) {
                shouldBool.insert(d_prevWord);
            }
            return;                                                   // RETURN
        }
        if ('&' == *pb) {
            --pb;
        }
        if (MATCH_BOOL != pb.wordBefore()) {
            shouldBool.insert(d_prevWord);
        }
    }
}

void Group::checkClassName() const
{
    if (BDEFLAG_CLASS != d_type) {
        return;                                                       // RETURN
    }

    if (d_className.empty() | (MATCH_STRUCT == d_className) |
                              (MATCH_CLASS  == d_className) |
                              (MATCH_UNION  == d_className)) {
        return;                                                       // RETURN
    }

    bsl::string className = Ut::removeTemplateAngleBrackets(d_className);
    if (MATCH_ANGLES == className) {    // match_angles == "<>"
        d_statementStart.error() << "strange class name '" << d_className <<
                                                                     bsl::endl;
        return;                                                       // RETURN
    }

    bsl::size_t u = className.rfind(':');
    if (Ut::npos() != u) {
        className = className.substr(u + 1);
    }

    const ClassNameVals& cnv = classNameVals;

    // it's a type -- check first letter is uppercase.  Note that sometimes it
    // is appropriate to declare template classes of type traits in other
    // components.

    unsigned leadingIdx = !strncmp(className.c_str(),
                                   cnv.d_componentPrefix.c_str(),
                                   cnv.d_componentPrefix.length())
                        ? cnv.d_componentPrefix.length()
                        : Lines::BDEFLAG_DOT_T_DOT_CPP == Lines::fileType() &&
                                          !strncmp(className.c_str(), "my_", 3)
                          ? 3
                          : 0;
    char leadingChar = className.length() > leadingIdx
                     ? className[leadingIdx]
                     : ' ';
    if (! isupper(leadingChar) && ! isExemptClassName(className)) {
        d_statementStart.warning() << "class name " << d_className <<
                                             " begins with '" << leadingChar <<
                                               "' -- not an upper case char\n";
    }

    // the following checks are only for classes in .h files that are not
    // nested classes

    if (Lines::BDEFLAG_DOT_H != Lines::fileType() ||
                         (d_parent && BDEFLAG_NAMESPACE != d_parent->d_type &&
                                      BDEFLAG_TOP_LEVEL != d_parent->d_type) ||
                         (d_parent && BDEFLAG_NAMESPACE == d_parent->d_type &&
                                  MATCH_BLOOMBERGLP != d_parent->d_prevWord)) {
        return;                                                       // RETURN
    }

    bdeu_String::toLower(&className);

    // compare with component name without package prefix

    if (! cnv.d_componentNameNoPrefix.empty() &&
                              !strncmp(className.c_str(),
                                       cnv.d_componentNameNoPrefix.c_str(),
                                       cnv.d_componentNameNoPrefix.length())) {
        return;                                                       // RETURN
    }

    // compare with component name with package prefix

    if (!strncmp(className.c_str(),
                 cnv.d_componentName.c_str(),
                 cnv.d_componentName.length())) {
        return;                                                       // RETURN
    }

    if (isExemptClassName(className)) {
        return;                                                       // RETURN
    }

    d_statementStart.warning() << "class name " << d_className <<
                                    " doesn't start with the component name\n";
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
                bool snugOk = false;
                if (startIndent != expectIndent) {
                    if (li > begin &&
                        (Lines::BDEFLAG_S_BLANKLINE !=
                                                    Lines::statement(li - 1) ||
                         Lines::BDEFLAG_BANG == Lines::comment(li - 1)) &&
                                  (startIndent == expectIndent + 4 ||
                                   startIndent >= expectIndent + 10)) {
                        // deeply indented comment -- ok

                        snugOk = true;
                    }
                    else if (startIndent < expectIndent + 10 &&
                                                          !(0 == startIndent &&
                                  Lines::BDEFLAG_DOT_H != Lines::fileType())) {
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
                            // it's a blank line and not a comment, it's ok

                            break;
                        }
                    }
                    else {
                        // Note we tolerate snug comments if the line following
                        // them begins with '{'.

                        if (!snugOk && li < bigEnd &&
                                        '{' != Lines::line(li + 1)[
                                                  Lines::lineIndent(li + 1)]) {
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
    Place after = d_close + 1;
    char nextChar = *after;

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

            GroupSetIt it =
                         d_parent->d_subGroups.find(const_cast<Group *>(this));
            BSLS_ASSERT_OPT(this == *it);
            const Group *group;
            for (++it; d_parent->d_subGroups.end() != it &&
                   (group = *it, BDEFLAG_CTOR_CLAUSE == group->d_type); ++it) {
                docPlace = group->d_close;
            }
        }

        if (isalpha(nextChar)) {
            after.wordAfter(&after);
            docPlace = after;

            ++after;
            nextChar = *after;
        }

        {
            Place pl;
            if ('=' == nextChar && "0" == (after + 1).wordAfter(&pl)) {
                docPlace = pl;

                after = pl + 1;
                nextChar = *after;
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
            isUnNamed = MATCH_NAMESPACE == d_parent->d_prevWord;
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
                                             MATCH_INLINE_STATIC == curLine)) {
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

void Group::checkFunctionSection() const
{
    if (BDEFLAG_ROUTINE_DECL != d_type ||
        !d_parent || BDEFLAG_CLASS != d_parent->d_type) {
        // Note we're just not checking BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL

        return;                                                       // RETURN
    }
    BSLS_ASSERT(!d_prevWord.empty());

    bool isCtor, isConst, isStatic;
    {
        isCtor = d_parent->d_className == d_prevWord ||
                         ('~' == d_prevWord[0] &&
                                  ('~' + d_parent->d_className) == d_prevWord);

        Place endDecl = d_close.findFirstOf("{;");
        isConst = Ut::npos() != d_close.twoPointsString(endDecl).find(
                                                                  MATCH_CONST);
        isStatic = false;
        int cli = d_open.lineNum();
        int li = Lines::lineBefore(&cli);
        for (++li ; li <= cli; ++li) {
            if   (Lines::BDEFLAG_S_FRIEND == Lines::statement(li)
               || Lines::BDEFLAG_S_TYPEDEF == Lines::statement(li)) {
                // friend or typedef -- doesn't belong in a function decl
                // section

                return;                                               // RETURN
            }

            if (Lines::BDEFLAG_S_STATIC == Lines::statement(li)) {
                isStatic = true;
                break;
            }

            const bsl::string& curLine = Lines::line(li);
            bsl::size_t staticPos = curLine.find(MATCH_STATIC);
            if (Ut::npos() != staticPos) {
                if ((0 == staticPos || !isalnum(curLine[staticPos - 1]))
                   && (curLine.length() == staticPos + 6 ||
                                       !isalnum(curLine[staticPos + 6]))) {
                    isStatic = true;
                    break;
                }
            }
        }
    }

    for (int li = d_open.lineNum(); li > 0; --li) {
        if (classBoundaries[li]) {
            break;
        }

        switch (Lines::comment(li)) {
          case Lines::BDEFLAG_NOT_IMPLEMENTED: {
            // handled elsewhere

            return;                                                   // RETURN
          } break;
          case Lines::BDEFLAG_CLASS_METHOD: {
            if (isCtor) {
                d_open.warning() << "c'tor " << d_prevWord << " declared in"
                                               " '// CLASS METHODS' section\n";
            }
            if (!isStatic) {
                d_open.warning() << "class method " << d_prevWord << " not"
                                                        " declared 'static'\n";
            }
            // if it's declared 'static' and 'const' the compiler will complain

            return;                                                   // RETURN
          } break;
          case Lines::BDEFLAG_CREATOR: {
            if (!isCtor) {
                d_open.warning() << "non c'tor " << d_prevWord << " declared"
                                                 " in '// CREATORS' section\n";
            }
            // If a c'tor is declared 'static' or 'const', the compiler will
            // complain.

            return;                                                   // RETURN
          } break;
          case Lines::BDEFLAG_MANIPULATOR: {
            if (isCtor) {
                d_open.warning() << "c'tor " << d_prevWord <<
                                    " declared in '// MANIPULATORS' section\n";
            }
            if (isStatic) {
                d_open.warning() << "static method " << d_prevWord <<
                                    " declared in '// MANIPULATORS' section\n";
            }
            if (isConst) {
                d_open.warning() << "const method " << d_prevWord <<
                                    " declared in '// MANIPULATORS' section\n";
            }
            return;                                                   // RETURN
          } break;
          case Lines::BDEFLAG_ACCESSOR: {
            if (isCtor) {
                d_open.warning() << "c'tor " << d_prevWord <<
                                       " declared in '// ACCESSORS' section\n";
            }
            if (isStatic) {
                d_open.warning() << "static method " << d_prevWord <<
                                       " declared in '// ACCESSORS' section\n";
            }
            if (!isConst) {
                d_open.warning() << "non-const method " << d_prevWord <<
                                       " declared in '// ACCESSORS' section\n";
            }
            return;                                                   // RETURN
          } break;
          default: {
            ; // do nothing
          }
        }
    }

    if (isAnnoying(d_prevWord)) {
        // nested traits or the like, no section needed

        return;                                                       // RETURN
    }

    {
        Place pl(d_open);
        if ('*' == *++pl && d_close == ++pl) {
            // '(*)' -- function declaration -- probably a func ptr variable

            return;                                                   // RETURN
        }
    }

    d_open.warning() << "routine " << d_prevWord << " declared outside"
                       " section (no '// CREATORS', '// MANIPULATORS', etc)\n";
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

    if (';' == nextChar && MATCH_WHILE == d_prevWord &&
                                               '}' == *(d_prevWordBegin - 1)) {
        return;                                                       // RETURN
    }

    d_close.warning() << "if/while/for doesn't control a {} block\n";
}


void Group::checkNamespace() const
{
    if (BDEFLAG_NAMESPACE != d_type || MATCH_QUOTE_C == d_prevWord) {
        return;                                                       // RETURN
    }

    // check name is acceptable

    bool commentFound = false;
    if (MATCH_NAMESPACE == d_prevWord) {
        // unnamed namespace

        if (Lines::BDEFLAG_DOT_H == Lines::fileType()) {
            d_open.warning() << "unnamed namespace in .h file\n";
        }

        if (d_open.lineNum() == d_close.lineNum()) {
            // Single line namespace.  No closing comment necessary.

            return;                                                   // RETURN
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
    else if (MATCH_BLOOMBERGLP == d_prevWord) {
        // enterprise namespace

        if (d_open.lineNum() == d_close.lineNum()) {
            // Single line namespace.  No closing comment necessary.

            return;                                                   // RETURN
        }

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
        if (Lines::BDEFLAG_DOT_T_DOT_CPP != Lines::fileType()) {
            for (bsl::size_t u = 0; u < d_prevWord.length(); ++u) {
                if (isupper(d_prevWord[u])) {
                    d_open.warning() << "namespace name '" << d_prevWord <<
                                             "' contains upper case char(s)\n";
                    break;
                }
            }
        }

        if (d_open.lineNum() == d_close.lineNum()) {
            // Single line namespace.  No closing comment necessary.

            return;                                                   // RETURN
        }

        Lines::CommentType closingCmt = Lines::comment(d_close.lineNum());
        if   (Lines::BDEFLAG_CLOSE_NAMESPACE         != closingCmt
           && Lines::BDEFLAG_CLOSE_PACKAGE_NAMESPACE != closingCmt) {
            d_close.warning() << "when closed, namespaces should have the"
                         " comment '// close namespace <name of namespace>' or"
                                             " '// close package namespace'\n";
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

        if (d_open.col() == indent && d_close.lineNum() == d_open.lineNum() &&
                                           d_close.col() == d_open.col() + 1) {
            // It a '{}' function.  Allow it.

            return;                                                   // RETURN
        }
      }  break;
      case BDEFLAG_CLASS: {
        if (Lines::BDEFLAG_DOT_H != Lines::fileType() &&
                                       d_close.lineNum() == d_open.lineNum()) {
            // It's evidently a one line function definition not in a .h file,
            // allow it.

            return;                                                   // RETURN
        }

        indent = d_parent->d_close.col() + 4;
      }  break;
      case BDEFLAG_UNKNOWN_BRACES: {
        // Somewhat confused.  Give up.

        return;                                                       // RETURN
      }  break;
      default: {
        // Really confused.  Complain.

        d_open.error() << "Confused -- function within brace pair of type \""
                                      << typeToStr(d_parent->d_type) << "\"\n";
        return;                                                       // RETURN
      }
    }

    if (d_open.col() != indent ||
                        Lines::lineIndent(d_open.lineNum()) != indent ||
                        Lines::line(d_open.lineNum()).length() != indent + 1) {
        badlyAlignedFuncStartBrace.insert(d_open.lineNum());
    }
}

void Group::markClassBoundaries() const
{
    if (BDEFLAG_CLASS != d_type) {
        return;                                                       // RETURN
    }

    classBoundaries[d_open. lineNum()] = true;
    classBoundaries[d_close.lineNum()] = true;
}

void Group::registerValidFriendTarget() const
{
    BSLS_ASSERT(Lines::BDEFLAG_DOT_H == Lines::fileType());

    bsl::string name;

    switch (d_type) {
      case BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL:
      case BDEFLAG_ROUTINE_DECL: {
        switch (d_parent->d_type) {
          case BDEFLAG_UNKNOWN_BRACES:
          case BDEFLAG_TOP_LEVEL:
          case BDEFLAG_NAMESPACE: {
            name = d_prevWord;
          }  break;
          default: {
            return;                                                   // RETURN
          }
        }
      }  break;
      case BDEFLAG_CLASS: {
        name = d_className;
      }  break;
      default: {
        return;                                                       // RETURN
      }
    }

    if (name.empty()) {
        // anonymous union of dysfunctional routine decl

        return;                                                       // RETURN
    }

    if (!Ut::frontMatches(name, MATCH_OPERATOR)) {
        // clip off template part

        size_t angle = name.find_first_of('<');
        if (Ut::npos() != angle) {
            name.resize(angle);
        }

        // if ':'s, take part after last one

        size_t colon = name.find_last_of(':');
        if (Ut::npos() != colon) {
            name = name.substr(colon + 1);
        }
    }

    validFriendTargets.insert(name);
}

void Group::getArgList(bsl::vector<bsl::string> *typeNames,
                       bsl::vector<bsl::string> *names,
                       bsl::vector<int>         *lineNums,
                       bool                     *potentialSingleArg) const
{
    if (BDEFLAG_ROUTINE_DECL != d_type) {
        return;                                                       // RETURN
    }
    BSLS_ASSERT_OPT(d_flags.d_parenBased);

    *potentialSingleArg = false;

    Place begin = d_open + 1;
    if (d_close == begin) {
        return;                                                       // RETURN
    }
    Place end = begin.findFirstOf(",()");
    int numArgs = 0;
    for (; true; ++numArgs) {
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
        if (typeName.empty()) {
            if ('.' == *typeNameEnd) {
                const bsl::string& curLine =
                                            Lines::line(typeNameEnd.lineNum());
                if ("..." == curLine.substr(typeNameEnd.col(), 3) &&
                                                  d_close == typeNameEnd + 3) {
                    // don't analyze this arg -- we're done with the others

                    break;
                }
            }

            begin.error() << "confusing arg list\n";
            typeNames->clear();
            names->clear();
            lineNums->clear();
            return;                                                   // RETURN
        }
        while (MATCH_CONST == typeName ||
                           MATCH_TYPENAME == typeName ||
                           MATCH_VOLATILE == typeName || '*' == *typeNameEnd) {
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
        while (MATCH_CONST == postType ||
                           MATCH_TYPENAME == typeName ||
                           MATCH_VOLATILE == postType || '*' == *postTypeEnd) {
            postType = (postTypeEnd + 1).nameAfter(&postTypeEnd);
        }
        char pte;
        while ('&' == (pte = *postTypeEnd)) {
            ++postTypeEnd;
        }
        Place startName;
#if 0
        if ('&' == pte) {
            startName = postTypeEnd + 1;    // simple ref or rvalue
            if ('&' == *startName) {
                ++startName;                // rvalue
            }
        }
#endif
        if (',' == pte || ')' == pte || '=' == pte) {
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

        bsl::string argName = startName.twoPointsString(end - 1);
        bsl::size_t equalsIdx = argName.find('=');
        if (Ut::npos() != equalsIdx) {
            *potentialSingleArg |= (1 == numArgs);
            argName.resize(equalsIdx);
            Ut::trim(&argName);
        }

        typeNames->push_back(begin.twoPointsString(startName - 1));
        names->push_back(argName);
        lineNums->push_back(begin.lineNum());

        if (end >= d_close) {
            break;
        }

        begin = end + 1;
        end = begin.findFirstOf(",()");
    }

    *potentialSingleArg |= (0 == numArgs);    // numArgs will be 0 if there
                                              // is just a single arg.

    BSLS_ASSERT_OPT(end == d_close);
}

void Group::print() const
{
    bsl::cout << *d_open << ": Open: " << d_open << ", close: " << d_close <<
                 ", sStart: " << d_statementStart << ", prev: '" <<
                 d_prevWord << "', type: " << typeToStr(d_type) << endl;
}

bool Group::isMarkedImplicit() const
{
    return Lines::BDEFLAG_IMPLICIT == Lines::comment(d_close.lineNum()) ||
           Lines::BDEFLAG_IMPLICIT == Lines::comment(d_close.lineNum() + 1);
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

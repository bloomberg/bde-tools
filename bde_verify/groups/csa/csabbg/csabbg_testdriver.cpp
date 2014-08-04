// csabbg_testdriver.cpp                                              -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/Expr.h>
#include <clang/AST/Stmt.h>
#include <clang/ASTMatchers/ASTMatchFinder.h>
#include <clang/ASTMatchers/ASTMatchers.h>
#include <clang/ASTMatchers/ASTMatchersInternal.h>
#include <clang/ASTMatchers/ASTMatchersMacros.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Basic/Specifiers.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <csabase_visitor.h>
#include <ctype.h>
#include <ext/alloc_traits.h>
#include <llvm/ADT/APSInt.h>
#include <llvm/ADT/Optional.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/ADT/VariadicFunction.h>
#include <llvm/Support/Casting.h>
#include <llvm/Support/Regex.h>
#include <stddef.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <limits>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace clang;
using namespace clang::ast_matchers;
using namespace csabase;

namespace clang { class Token; }

// ----------------------------------------------------------------------------

static std::string const check_name("test-driver");

// ----------------------------------------------------------------------------

namespace clang {
namespace ast_matchers {
    AST_MATCHER_P(ReturnStmt, returnExpr,
                    internal::Matcher<Expr>, InnerMatcher) {
        return InnerMatcher.matches(*Node.getRetValue(), Finder, Builder);
    }
    AST_MATCHER_P(Expr, callTo, CXXMethodDecl *, method) {
        const Decl *callee = 0;
        if (const CallExpr *call = llvm::dyn_cast<CallExpr>(&Node)) {
            callee = call->getCalleeDecl();
        } else if (const CXXConstructExpr *ctor =
                       llvm::dyn_cast<CXXConstructExpr>(&Node)) {
            callee = ctor->getConstructor();
        }
        if (callee) {
            const Decl *mc = method->getCanonicalDecl();
            const FunctionDecl *fd = llvm::dyn_cast<FunctionDecl>(callee);
            if (fd) {
                fd = fd->getInstantiatedFromMemberFunction();
                if (fd && fd->getCanonicalDecl() == mc) {
                    return true;                                      // RETURN
                }
            }
            return callee->getCanonicalDecl() == mc;                  // RETURN
        }
        return false;
    }
}
}

namespace
{

struct data
    // Data attached to analyser for this check.
{
    data();
        // Create an object of this type.

    typedef std::vector<SourceRange> Comments;
    Comments d_comments;  // Comment blocks per file.

    typedef std::map<size_t /* line */, size_t /* index */> CommentsOfLines;
    CommentsOfLines d_comments_of_lines;

    typedef std::map<const FunctionDecl*, SourceRange> FunDecls;
    FunDecls d_fundecls;  // FunDecl, comment

    typedef std::multimap<long long, std::string> TestsOfCases;
    TestsOfCases d_tests_of_cases;  // Map functions to test numbers.

    typedef std::multimap<std::string, long long> CasesOfTests;
    CasesOfTests d_cases_of_tests;  // Map test numbers to functions.

    typedef std::set<size_t> CCLines;  // Conditional compilation lines.
    CCLines d_cclines;

    const CompoundStmt *d_main;  // The compound statement of 'main()'.
    const Stmt *d_return;        // The correct 'main()' return statement.

    enum { NOT_YET, NOW, DONE };
    int d_collecting_classes;  // True for //@CLASSES: section.
    std::map<llvm::StringRef, SourceRange> d_classes;  // classes named
    std::map<std::string, unsigned> d_names_to_test;   // public method namess
    std::map<std::string, unsigned> d_names_in_plan;   // method namess tested
    std::set<const CXXMethodDecl *> d_methods;         // public methods
};

data::data()
: d_main(0)
, d_return(0)
, d_collecting_classes(NOT_YET)
{
}

struct report
    // Callback object for inspecting test drivers.
{
    Analyser&      d_analyser;
    SourceManager& d_manager;
    data&          d_data;

    report(Analyser& analyser);
        // Initialize an object of this type.

    SourceRange get_test_plan();
        // Return the TEST PLAN comment block.

    void operator()();
        // Callback for the end of the translation unit.

    void operator()(SourceRange comment);
        // Callback for the specified 'comment'.

    void mark_ccline(SourceLocation loc);
        // Mark the line of the specified 'loc' as a preprocessor conditional.

    void operator()(const FunctionDecl *function);
        // Callback for the specified 'function'.

    void operator()(SourceLocation loc, SourceRange);
        // Callback for '#if' and '#elif' at the specified 'loc'.

    void operator()(SourceLocation loc, const Token&);
        // Callback for '#ifdef' and '#ifndef' at the specified 'loc'.

    void operator()(SourceLocation loc, SourceLocation);
        // Callback for '#else' and '#endif' at the specified 'loc'.

    void check_boilerplate();
        // Check test driver boilerplate in the main file.

    void get_function_names();
        // Find the public methods of the classes in @CLASSES.

    void search(SourceLocation *best_loc,
                llvm::StringRef *best_needle,
                size_t *best_distance,
                llvm::StringRef key,
                const std::vector<llvm::StringRef>& needles,
                FileID fid);
        // Search the contents of the file specified by 'fid' for the closest
        // match to one of the specified 'needles' near the specified 'key' and
        // set the specified 'best_loc', 'best_needle', and 'best_distance' to
        // the matched position, string, and closeness respectively.

    void match_print_banner(const BoundNodes &nodes);
    bool found_banner;
    llvm::StringRef banner_text;
    const StringLiteral *banner_literal;

    void match_noisy_print(const BoundNodes &nodes);
    void match_no_print(const BoundNodes &nodes);
    void match_return_status(const BoundNodes &nodes);
    void match_set_status(const BoundNodes &nodes);
};

report::report(Analyser& analyser)
: d_analyser(analyser)
, d_manager(analyser.manager())
, d_data(analyser.attachment<data>())
{
}

// Loosely match the banner of a TEST PLAN.
llvm::Regex test_plan_banner(
    "//[[:blank:]]*" "[-=_]([[:blank:]]?[-=_])*"  "[[:blank:]]*\n"
    "//[[:blank:]]*" "TEST" "[[:blank:]]*" "PLAN" "[[:blank:]]*\n"
    "//[[:blank:]]*" "[-=_]([[:blank:]]?[-=_])*"  "[[:blank:]]*\n",
    llvm::Regex::Newline | llvm::Regex::IgnoreCase);

SourceRange report::get_test_plan()
{
    data::Comments::iterator b = d_data.d_comments.begin();
    data::Comments::iterator e = d_data.d_comments.end();
    for (data::Comments::iterator i = b; i != e; ++i) {
        llvm::StringRef comment = d_analyser.get_source(*i);
        if (test_plan_banner.match(comment)) {
            return *i;                                                // RETURN
        }
    }
    return SourceRange();
}

llvm::Regex separator("//[[:blank:]]*-{60,}$\n", llvm::Regex::Newline);
    // Loosely match a long dashed separator.

llvm::Regex test_plan(
    "//"  "([^][[:alnum:]]*)"
    "\\[" "[[:blank:]]*" "(" "-?" "[[:digit:]]*" ")" "\\]"
          "[[:blank:]]*"
    "(.*)$",
    llvm::Regex::Newline);  // Match a test plan item.  [ ] are essential.

llvm::Regex test_title(
    "[[:blank:]]*//[[:blank:]]*" "[-=_]([[:blank:]]?[-=_])*"  "[[:blank:]]*\n"
    "[[:blank:]]*//[[:blank:]]*" "(.*[^[:blank:]])" "[[:blank:]]*\n",
    llvm::Regex::Newline);  // Match the title of a test case.

llvm::Regex testing(
    "//[[:blank:]]*Test(ing|ed|s)?[[:blank:]]*:?[[:blank:]]*\n",
    llvm::Regex::IgnoreCase);  // Loosely match 'Testing:' in a case comment.

llvm::Regex test_item(
    "^[^.;]*[[:alpha:]][^.;]*;?[^.;]*$",
    llvm::Regex::Newline);  // Loosely match a test item; at least one letter,
                            // no more than one ';', and no '.'.

llvm::Regex tested_method(
    "(" "operator" " *" "(" "[(] *[)]"
                        "|" "[^([:alnum:]_[:space:]]+"
                        ")"
    "|" "~?[[:alnum:]_]+"
    ")" "[[:space:]]*[(]",
    llvm::Regex::Newline);  // Match a method name in a test item.

const internal::DynTypedMatcher &
print_banner_matcher()
    // Return an AST matcher which looks for the banner printer in a test case
    // statement.  It is satisfied with a 'printf' or 'cout' version, with or
    // without a leading newline/'endl'.  The 'printf' string literal combining
    // text and underlining is bound to "BANNER", the 'cout' banner text is
    // bound to "TEST" and the 'cout' underlining is bound to "====".  Valid
    // cases look like one of
    //: o 'cout' with initial 'endl'
    //..
    //    if (verbose) cout << endl
    //                      << "TESTING FOO" << endl
    //                      << "===========" << endl;
    //..
    //: o 'cout' without initial 'endl'
    //..
    //    if (verbose) cout << "TESTING FOO" << endl
    //                      << "===========" << endl;
    //..
    //: o 'printf' with initial '\n'
    //..
    //    if (verbose) printf("\nTESTING FOO\n===========\n");
    //..
    //: o 'printf' without initial '\n'
    //..
    //    if (verbose) printf("TESTING FOO\n===========\n");
    //..
{
    static const internal::DynTypedMatcher matcher =
        caseStmt(has(compoundStmt(hasDescendant(ifStmt(
            hasCondition(ignoringImpCasts(declRefExpr(to(
                varDecl(hasName("verbose")))))
            ),
            anyOf(
                hasDescendant(
                    callExpr(
                        argumentCountIs(1),
                        callee(functionDecl(hasName("printf"))),
                        hasArgument(0, ignoringImpCasts(
                            stringLiteral().bind("BANNER")))
                    )
                ),
                hasDescendant(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(declRefExpr(to(
                            varDecl(hasName("cout")))))),
                        hasArgument(1, ignoringImpCasts(declRefExpr(to(
                            functionDecl(hasName("endl"))))))))),
                        hasArgument(1, ignoringImpCasts(
                            stringLiteral().bind("TEST")))))),
                        hasArgument(1, ignoringImpCasts(declRefExpr(to(
                            functionDecl(hasName("endl"))))))))),
                        hasArgument(1, ignoringImpCasts(
                            stringLiteral().bind("====")))))),
                        hasArgument(1, ignoringImpCasts(declRefExpr(to(
                            functionDecl(hasName("endl")))))))
                ),
                hasDescendant(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(declRefExpr(to(
                            varDecl(hasName("cout")))))),
                        hasArgument(1, ignoringImpCasts(
                            stringLiteral().bind("TEST")))))),
                        hasArgument(1, ignoringImpCasts(declRefExpr(to(
                            functionDecl(hasName("endl"))))))))),
                        hasArgument(1, ignoringImpCasts(
                            stringLiteral().bind("====")))))),
                        hasArgument(1, ignoringImpCasts(declRefExpr(to(
                            functionDecl(hasName("endl")))))))
                ),
                hasDescendant(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(
                    operatorCallExpr(
                        hasOverloadedOperatorName("<<"),
                        hasArgument(0, ignoringImpCasts(declRefExpr(to(
                            varDecl(hasName("cout")))))),
                        hasArgument(1, ignoringImpCasts(
                            stringLiteral().bind("TEST")))))),
                        hasArgument(1, ignoringImpCasts(
                            stringLiteral().bind("====")))))),
                        hasArgument(1, ignoringImpCasts(declRefExpr(to(
                            functionDecl(hasName("endl")))))))
                )
            )
        )))));
    return matcher;
}

const internal::DynTypedMatcher &
noisy_print_matcher()
    // Return an AST matcher which looks for (not very) verbose output inside
    // loops in a test case statement.
{
    static const internal::DynTypedMatcher matcher =
        caseStmt(has(compoundStmt(forEachDescendant(
            ifStmt(hasCondition(ignoringImpCasts(
                       declRefExpr(to(varDecl(hasName("verbose")))))),
                   anyOf(hasAncestor(doStmt(unless(anyOf(
                            hasCondition(boolLiteral(equals(false))),
                            hasCondition(characterLiteral(equals('\0'))),
                            hasCondition(integerLiteral(equals(0))),
                            hasCondition(nullPtrLiteralExpr())
                         )))),
                         hasAncestor(forStmt()),
                         hasAncestor(whileStmt()))).bind("noisy")))));
    return matcher;
}

const internal::DynTypedMatcher &
no_print_matcher()
    // Return an AST matcher which looks for missing verbose output inside
    // loops in a test statement.
{
    static const internal::DynTypedMatcher matcher =
        caseStmt(has(compoundStmt(
            eachOf(
                forEachDescendant(doStmt().bind("try")),
                forEachDescendant(forStmt().bind("try")),
                forEachDescendant(whileStmt().bind("try"))),
            forEachDescendant(stmt(
                equalsBoundNode("try"),
                unless(hasDescendant(ifStmt(
                    hasCondition(ignoringImpCasts(declRefExpr(to(varDecl(anyOf(
                        hasName("verbose"),
                        hasName("veryVerbose"),
                        hasName("veryVeryVerbose"),
                        hasName("veryVeryVeryVerbose")
                    ))))))
                ))),
                unless(hasAncestor(ifStmt(
                    hasCondition(ignoringImpCasts(declRefExpr(to(varDecl(anyOf(
                        hasName("verbose"),
                        hasName("veryVerbose"),
                        hasName("veryVeryVerbose"),
                        hasName("veryVeryVeryVerbose")
                    ))))))
                )))
            ).bind("loop"))
        )));
    return matcher;
}

const internal::DynTypedMatcher &
return_status_matcher()
    // Return an AST matcher which looks for a 'return testStatus;' statement.
{
    static const internal::DynTypedMatcher matcher =
        returnStmt(returnExpr(ignoringParenImpCasts(declRefExpr(hasDeclaration(
            namedDecl(hasName("testStatus"))
        ))))).bind("good");
    return matcher;
}

void report::match_return_status(const BoundNodes& nodes)
{
    d_data.d_return = nodes.getNodeAs<Stmt>("good");
}

const internal::DynTypedMatcher &
set_status_matcher()
    // Return an AST matcher which looks for 'testStatus = -1;'.
{
    static const internal::DynTypedMatcher matcher =
        defaultStmt(anyOf(
            defaultStmt(hasDescendant(binaryOperator(
                hasOperatorName("="),
                hasLHS(declRefExpr(hasDeclaration(namedDecl(
                    hasName("testStatus"))))
                ),
                hasRHS(unaryOperator(
                    hasOperatorName("-"),
                    hasUnaryOperand(integerLiteral(equals(1)))
                ))
            ))).bind("good"),
            defaultStmt().bind("bad")
        ));
    return matcher;
}

void report::match_set_status(const BoundNodes& nodes)
{
    if (const Stmt *bad = nodes.getNodeAs<Stmt>("bad")) {
        d_analyser.report(bad->getLocEnd(), check_name, "TP24",
                          "`default:` case should set `testStatus = -1;`");
    }
}

void report::get_function_names()
{
    for (auto p : d_data.d_classes) {
        std::string name = p.first.str();
        if (!p.first.startswith("::")) {
            name = "::" + name;
        }
        bool is_bsl = llvm::StringRef(name).startswith("::bsl::");
        NamedDecl *nd = d_analyser.lookup_name(name);
        if (!nd && is_bsl) {
            nd = d_analyser.lookup_name("::std::" + name.substr(7));
        }
        if (!nd) {
            nd = d_analyser.lookup_name(
                "::" + d_analyser.config()->toplevel_namespace() + name);
            if (!nd && is_bsl) {
                nd = d_analyser.lookup_name(
                    "::" + d_analyser.config()->toplevel_namespace() +
                    "::std::" + name.substr(7));
            }
        }

        CXXRecordDecl *record = 0;
        if (nd) {
            while (UsingShadowDecl *usd =
                       llvm::dyn_cast<UsingShadowDecl>(nd)) {
                nd = usd->getTargetDecl();
            }
            record = llvm::dyn_cast<CXXRecordDecl>(nd);
            if (!record) {
                ClassTemplateDecl *tplt =
                    llvm::dyn_cast<ClassTemplateDecl>(nd);
                if (tplt) {
                    record = tplt->getTemplatedDecl();
                }
            }
        }
        if (record) {
            CXXRecordDecl::method_iterator b = record->method_begin();
            CXXRecordDecl::method_iterator e = record->method_end();
            for (; b != e; ++b) {
                const CXXMethodDecl *m = *b;
                if (m->getAccess() == AS_public &&
                    m->isUserProvided() &&
                    !m->getLocation().isMacroID()) {
                    MatchFinder mf;
                    bool found = false;
                    OnMatch<> m1([&](const BoundNodes &) { found = true; });
                    mf.addDynamicMatcher(
                        decl(hasDescendant(namedDecl(
                            hasName("main"),
                            eachOf(
                                forEachDescendant(callExpr(callTo(m))),
                                forEachDescendant(constructExpr(callTo(m)))
                            )
                        ))),
                        &m1);
                    mf.match(*m->getTranslationUnitDecl(),
                             *d_analyser.context());
                    if (!found) {
                        d_analyser.report(m, check_name, "TP27",
                                          "Method not called in test driver");
                    }
                    std::string method = m->getNameAsString();
                    size_t lt = method.find('<');
                    if (lt != method.npos &&
                        !llvm::StringRef(method).startswith("operator")) {
                        method = method.substr(0, lt);
                    }
                    d_data.d_methods.insert(m);
                    ++d_data.d_names_to_test[method];
                }
            }
        }
        else {
            d_analyser.report(p.second.getBegin(), check_name, "TP25",
                              "Cannot find definition of class '%0' from "
                              "@CLASSES section.")
                << p.first;
        }
    }
}

void report::operator()()
{
    if (!d_analyser.is_test_driver()) {
        return;                                                       // RETURN
    }

    check_boilerplate();

    get_function_names();

    SourceRange plan_range = get_test_plan();

    if (!plan_range.isValid()) {
        d_analyser.report(
            d_manager.getLocForStartOfFile(d_manager.getMainFileID()),
            check_name, "TP14",
            "TEST PLAN section is absent");
    }

    llvm::StringRef plan = d_analyser.get_source(plan_range);

    llvm::SmallVector<llvm::StringRef, 7> matches;
    size_t offset = 0;

    // Hack off the banner.
    if (test_plan_banner.match(plan.drop_front(offset), &matches)) {
        offset += plan.drop_front(offset).find(matches[0]) + matches[0].size();
    }

    // Find the separator if there is one.
    size_t sep_offset = 0;
    if (separator.match(plan.drop_front(offset), &matches)) {
        sep_offset = offset + plan.drop_front(offset).find(matches[0]);
    }

    // Hack off everything before the first item with brackets.
    if (test_plan.match(plan.drop_front(offset), &matches)) {
        offset += plan.drop_front(offset).find(matches[0]);
    }

    if (sep_offset > offset) {
        d_analyser.report(plan_range.getBegin(),
                          check_name, "TP02",
                          "TEST PLAN section is missing '// ---...---' "
                          "separator line between preamble and methods list");
    }

    size_t plan_pos = offset;

    llvm::StringRef s;
    size_t count = 0;
    while (test_plan.match(s = plan.drop_front(offset), &matches)) {
        ++count;
        llvm::StringRef line = matches[0];
        llvm::StringRef cruft = matches[1];
        llvm::StringRef number = matches[2];
        llvm::StringRef item = matches[3];
        size_t matchpos = offset + s.find(line);
        offset = matchpos + line.size();
        long long test_num = 0;
        if (number.getAsInteger(10, test_num)) {
            test_num = std::numeric_limits<long long>::min();
        }
        size_t lb = matchpos + line.find('[');
        size_t rb = matchpos + line.find(']');
        SourceRange bracket_range(getOffsetRange(plan_range, lb, rb - lb));

        if (number.empty()) {
            d_analyser.report(bracket_range.getBegin(),
                              check_name, "TP03",
                              "Missing test number")
                << bracket_range;
        }

        if (test_num == 0) {
            d_analyser.report(bracket_range.getBegin(),
                              check_name, "TP04",
                              "Test number may not be 0")
                << bracket_range;
        }

        if (item.empty()) {
            d_analyser.report(bracket_range.getEnd().getLocWithOffset(1),
                              check_name, "TP07",
                              "Missing test item");
        } else {
            d_data.d_tests_of_cases.insert(std::make_pair(test_num, item));
            d_data.d_cases_of_tests.insert(std::make_pair(item, test_num));
            if (tested_method.match(item, &matches)) {
                ++d_data.d_names_in_plan[matches[1]];
            }
        }

        if (cruft.find_first_not_of(" ") != cruft.npos) {
            d_analyser.report(bracket_range.getBegin().getLocWithOffset(-1),
                              check_name, "TP16",
                              "Extra characters before test number brackets");
        }
    }
    if (count == 0) {
        d_analyser.report(plan_range.getBegin().getLocWithOffset(plan_pos),
                          check_name, "TP13",
                          "No test items found in test plan");
    }
    else {
        for (const auto &a : d_data.d_names_to_test) {
            if (a.second > d_data.d_names_in_plan[a.first]) {
                d_analyser.report(
                    plan_range.getBegin().getLocWithOffset(plan_pos),
                    check_name, "TP26",
                    "Tested %plural{1:class has|:classes have}0 "
                    "%plural{1:a|:%1}1 function%s1 named '%2' "
                    "but the test plan has %plural{0:none|:%3}3")
                << int(d_data.d_classes.size())
                << int(a.second)
                << a.first
                << int(d_data.d_names_in_plan[a.first]);
            }
        }
    }

    CompoundStmt const* stmt = d_data.d_main;
    if (!stmt) {
        return;                                                       // RETURN
    }

    // Find the main switch statement.
    const SwitchStmt *ss = 0;
    CompoundStmt::const_body_iterator b = stmt->body_begin();
    CompoundStmt::const_body_iterator e = stmt->body_end();
    for (CompoundStmt::const_body_iterator i = b; !ss && i != e; ++i) {
        ss = llvm::dyn_cast<SwitchStmt>(*i);
    }
    if (ss) {
        MatchFinder mf;
        OnMatch<report, &report::match_return_status> m1(this);
        mf.addDynamicMatcher(return_status_matcher(), &m1);
        const Stmt *last = stmt->body_back();
        if (!last) {
            last = stmt;
        }
        d_data.d_return = 0;
        mf.match(*last, *d_analyser.context());
        if (!d_data.d_return) {
            d_analyser.report(last->getLocEnd(), check_name, "TP23",
                              "Final statement of `main()` must be "
                              "`return testStatus;`");
        }
    } else {
        d_analyser.report(stmt, check_name, "TP11",
                          "No switch statement found in test driver main");
        return;                                                       // RETURN
    }

    const SwitchCase* sc;
    for (sc = ss->getSwitchCaseList(); sc; sc = sc->getNextSwitchCase()) {
        size_t line = Location(d_manager, sc->getColonLoc()).line() + 1;

        // Skip over preprocessor conditionals.
        while (d_data.d_cclines.find(line) != d_data.d_cclines.end()) {
            ++line;
        }

        SourceRange cr;
        if (d_data.d_comments_of_lines.find(line) !=
            d_data.d_comments_of_lines.end()) {
            cr = d_data.d_comments[d_data.d_comments_of_lines[line]];
        }

        const CaseStmt* cs = llvm::dyn_cast<CaseStmt>(sc);
        if (!cs) {
            // Default case.
            MatchFinder mf;
            OnMatch<report, &report::match_set_status> m1(this);
            mf.addDynamicMatcher(set_status_matcher(), &m1);
            mf.match(*sc, *d_analyser.context());
            continue;
        }

        llvm::APSInt case_value;
        cs->getLHS()->EvaluateAsInt(case_value, *d_analyser.context());
        bool negative = 0 >  case_value.getSExtValue();
        bool zero     = 0 == case_value.getSExtValue();

        MatchFinder mf;
        OnMatch<report, &report::match_print_banner> m1(this);
        mf.addDynamicMatcher(print_banner_matcher(), &m1);
        OnMatch<report, &report::match_noisy_print> m2(this);
        mf.addDynamicMatcher(noisy_print_matcher(), &m2);
        OnMatch<report, &report::match_no_print> m3(this);
        mf.addDynamicMatcher(no_print_matcher(), &m3);

        found_banner = false;
        banner_text = llvm::StringRef();
        banner_literal = 0;
        mf.match(*cs, *d_analyser.context());
        if (!found_banner && !zero) {
            d_analyser.report(sc->getLocStart(),
                              check_name, "TP17",
                              "Test case does not contain "
                              "'if (verbose) print test banner'");
        }

        if (!cr.isValid()) {
            if (!zero) {
                d_analyser.report(sc->getLocStart(),
                                  check_name, "TP05",
                                  "Test case has no comment");
            }
            continue;
        } else {
            if (zero) {
                d_analyser.report(sc->getLocStart(),
                        check_name, "TP10",
                        "Case 0 should not have a test comment");
            }
        }

        llvm::StringRef comment = d_analyser.get_source(cr);
        llvm::SmallVector<llvm::StringRef, 7> matches;
        size_t testing_pos = 0;
        size_t line_pos = 0;

        if (found_banner) {
            if (test_title.match(comment, &matches)) {
                llvm::StringRef t = matches[2];
                testing_pos = comment.find(t);
                line_pos = testing_pos + t.size();
                std::pair<size_t, size_t> m = mid_mismatch(t, banner_text);
                if (m.first != t.size()) {
                    d_analyser.report(
                        cr.getBegin().getLocWithOffset(testing_pos + m.first),
                        check_name, "TP22",
                        "Mismatch between title in comment and as printed");
                    d_analyser.report(banner_literal,
                                      check_name, "TP22",
                                      "Printed title is",
                                      false, DiagnosticsEngine::Note);
                }
            } else {
                d_analyser.report(
                        cr.getBegin().getLocWithOffset(comment.find('\n') + 1),
                        check_name, "TP22",
                        "Test case title should be\n%0")
                    << banner_text;
            }
        }

        if (testing.match(comment, &matches)) {
            llvm::StringRef t = matches[0];
            testing_pos = comment.find(t);
            line_pos = testing_pos + t.size();
            std::pair<size_t, size_t> m =
                mid_mismatch(t, "// Testing:\n");
            if (m.first != t.size()) {
                d_analyser.report(
                    cr.getBegin().getLocWithOffset(testing_pos + m.first),
                    check_name, "TP15",
                    "Correct format is '// Testing:'");
            }
        } else if (!negative) {
            d_analyser.report(cr.getBegin(),
                              check_name, "TP12",
                              "Comment should contain a 'Testing:' section");
        }

        for (size_t end_pos = 0;
             (line_pos = comment.find("//", line_pos)) != comment.npos;
             line_pos = end_pos) {
            end_pos = comment.find('\n', line_pos);
            llvm::StringRef line = comment.slice(line_pos + 2, end_pos).trim();
            if (testing_pos == 0 && line.empty()) {
                break;
            }
            typedef data::CasesOfTests::const_iterator Ci;
            std::pair<Ci, Ci> be = d_data.d_cases_of_tests.equal_range(line);
            Ci match_itr;
            for (match_itr = be.first; match_itr != be.second; ++match_itr) {
                if (match_itr->second == case_value.getSExtValue()) {
                    break;
                }
            }
            if (match_itr != be.second) {
                continue;
            }
            if (be.first != be.second) {
                size_t off = plan_pos;
                off += plan.drop_front(off).find(line);
                off = plan.rfind(']', off) - 1;
                d_analyser.report(cr.getBegin().getLocWithOffset(line_pos),
                        check_name, "TP08",
                        "Test plan does not have case number %0 for this item")
                    << case_value.getSExtValue();
                d_analyser.report(
                        plan_range.getBegin().getLocWithOffset(off),
                        check_name, "TP08",
                        "Test plan item is", false,
                        DiagnosticsEngine::Note);
            }
            else if (!negative && test_item.match(line)) {
                d_analyser.report(cr.getBegin().getLocWithOffset(line_pos),
                                  check_name, "TP09",
                                  "Test plan should contain this item from "
                                  "'Testing' section of case %0")
                    << case_value.getSExtValue();
            }
        }

        typedef data::TestsOfCases::const_iterator Ci;
        std::pair<Ci, Ci> be = d_data.d_tests_of_cases.equal_range(
            case_value.getSExtValue());
        for (Ci i = be.first; i != be.second; ++i) {
            if (comment.drop_front(testing_pos).find(i->second) ==
                comment.npos) {
                d_analyser.report(
                    plan_range.getBegin().getLocWithOffset(
                        plan_pos + plan.drop_front(plan_pos).find(i->second)),
                    check_name, "TP06",
                    "'Testing' section of case %0 should contain this item "
                    "from test plan")
                    << case_value.getSExtValue();
            }
        }
    }
}

llvm::Regex classes(
    "^// *" "("
                      "[[:alpha:]][[:alnum:]_]*"
                "(" "::[[:alpha:]][[:alnum:]_]*" ")*"
            ")");

void report::operator()(SourceRange range)
{
    Location location(d_analyser.get_location(range.getBegin()));
    if (location.file() == d_analyser.toplevel()) {
        data::Comments& c = d_data.d_comments;
        if (c.size() == 0 ||
            !areConsecutive(d_manager, c.back(), range)) {
            d_data.d_comments_of_lines[location.line()] = c.size();
            c.push_back(range);
        }
        else {
            c.back().setEnd(range.getEnd());
        }
    }
    if (d_data.d_collecting_classes != data::DONE &&
        d_analyser.is_component(location.file())) {
        llvm::StringRef line = d_analyser.get_source_line(location.location());
        if (d_data.d_collecting_classes == data::NOT_YET) {
            if (line.find("//@CLASS") == 0) {
                d_data.d_collecting_classes = data::NOW;
            }
        }
        else {
            llvm::SmallVector<llvm::StringRef, 7> matches;
            if (classes.match(line, &matches)) {
                d_data.d_classes[matches[1]] = range;
            }
            else {
                d_data.d_collecting_classes = data::DONE;
            }
        }
    }
}

void report::operator()(const FunctionDecl *function)
{
    if (function->isMain() && function->hasBody()) {
        d_data.d_main = llvm::dyn_cast<CompoundStmt>(function->getBody());
    }
}

void report::mark_ccline(SourceLocation loc)
{
    Location location(d_analyser.get_location(loc));
    if (location.file() == d_analyser.toplevel()) {
        d_data.d_cclines.insert(location.line());
    }
}

void report::operator()(SourceLocation loc, SourceRange)
{
    mark_ccline(loc);
}

void report::operator()(SourceLocation loc, const Token&)
{
    mark_ccline(loc);
}

void report::operator()(SourceLocation loc, SourceLocation)
{
    mark_ccline(loc);
}

static bool is_all_cappish(llvm::StringRef s)
    // Return 'true' iff all letters in the specified string 's' are upper-case
    // except for portions in quotes.
{
    bool in_single_quotes = false;
    bool in_double_quotes = false;

    for (size_t i = 0; i < s.size(); ++i) {
        switch (s[i]) {
          case '\'': {
            if (!in_double_quotes) {
                in_single_quotes = !in_single_quotes;
            }
          } break;
          case '"': {
            if (!in_single_quotes) {
                in_double_quotes = !in_double_quotes;
            }
          } break;
          case 'a': case 'b': case 'c': case 'd': case 'e': case 'f': case 'g':
          case 'h': case 'i': case 'j': case 'k': case 'l': case 'm': case 'n':
          case 'o': case 'p': case 'q': case 'r': case 's': case 't': case 'u':
          case 'v': case 'w': case 'x': case 'y': case 'z': {
            if (!in_single_quotes && !in_double_quotes) {
                return false;                                         // RETURN
            }
          } break;
        }
    }
    return true;
}

static std::string cappish(llvm::StringRef ref)
    // Return cappish version of the specified string 's'.
{
    std::string s = ref.str();
    bool in_single_quotes = false;
    bool in_double_quotes = false;

    for (size_t i = 0; i < s.size(); ++i) {
        switch (s[i]) {
          case '\'': {
            if (!in_double_quotes) {
                in_single_quotes = !in_single_quotes;
            }
          } break;
          case '"': {
            if (!in_single_quotes) {
                in_double_quotes = !in_double_quotes;
            }
          } break;
          case 'a': case 'b': case 'c': case 'd': case 'e': case 'f': case 'g':
          case 'h': case 'i': case 'j': case 'k': case 'l': case 'm': case 'n':
          case 'o': case 'p': case 'q': case 'r': case 's': case 't': case 'u':
          case 'v': case 'w': case 'x': case 'y': case 'z': {
            if (!in_single_quotes && !in_double_quotes) {
                s[i] = std::toupper(s[i]);
            }
          } break;
        }
    }
    return s;
}

void report::match_print_banner(const BoundNodes& nodes)
{
    const StringLiteral *l1 = nodes.getNodeAs<StringLiteral>("BANNER");
    const StringLiteral *l2 = nodes.getNodeAs<StringLiteral>("TEST");
    const StringLiteral *l3 = nodes.getNodeAs<StringLiteral>("====");

    found_banner = true;

    if (l1) {
        llvm::StringRef s = l1->getString();
        size_t n = s.size();
        // e.g., n == 11
        // \n TEST \n ==== \n
        //  0 1234  5 6789 10
        // or n == 10
        // TEST \n ==== \n
        // 0123  4 5678  9
        banner_text = s.ltrim().split('\n').first;
        banner_literal = l1;
        if ((s.count('\n') != 3 ||
             s[0] != '\n' ||
             s[n - 1] != '\n' ||
             s[n / 2] != '\n' ||
             s.find_first_not_of('=', n / 2 + 1) != n - 1 ||
             !is_all_cappish(s)) &&
            (s.count('\n') != 2 ||
             s[n - 1] != '\n' ||
             s[n / 2 - 1] != '\n' ||
             s.find_first_not_of('=', n / 2) != n - 1 ||
             !is_all_cappish(s))
           ) {
            size_t col = d_manager.getPresumedColumnNumber(l1->getLocStart());
            std::string indent(col - 1, ' ');
            d_analyser.report(l1, check_name, "TP18",
                              "Incorrect test banner format");
            d_analyser.report(l1, check_name, "TP18",
                              "Correct format is\n%0",
                              false, DiagnosticsEngine::Note)
                << indent
                 + "\"\\n"
                 + cappish(banner_text)
                 + "\\n"
                 + std::string(banner_text.size(), '=')
                 + "\\n\"";
        }
    } else if (l2 && l3) {
        llvm::StringRef text = l2->getString();
        llvm::StringRef ul = l3->getString();
        if (text.size() > 0 && text[0] == '\n' &&
            ul  .size() > 0 && ul  [0] == '\n') {
            text = text.substr(1);
            ul   = ul  .substr(1);
        }
        banner_text = text.ltrim().split('\n').first;
        banner_literal = l2;
        if (text.size() != ul.size() ||
            ul.find_first_not_of('=') != ul.npos ||
            !is_all_cappish(text)) {
            size_t col = d_manager.getPresumedColumnNumber(l2->getLocStart());
            std::string indent(col > 9 ? col - 9 : col, ' ');
            d_analyser.report(l2, check_name, "TP18",
                              "Incorrect test banner format");
            d_analyser.report(l2, check_name, "TP18",
                              "Correct format is\n%0",
                              false, DiagnosticsEngine::Note)
                << indent
                 + "cout << endl\n"
                 + indent
                 + "     << \""
                 + cappish(banner_text)
                 + "\" << endl\n"
                 + indent
                 + "     << \""
                 + std::string(banner_text.size(), '=')
                 + "\" << endl;\n";
        }
    }
}

void report::match_noisy_print(const BoundNodes& nodes)
{
    const IfStmt *noisy = nodes.getNodeAs<IfStmt>("noisy");

    if (noisy->getLocStart().isMacroID()) {
        return;                                                       // RETURN
    }

    d_analyser.report(noisy->getCond(), check_name, "TP20",
                      "Within loops, act on very verbose");
}

void report::match_no_print(const BoundNodes& nodes)
{
    const Stmt *quiet = nodes.getNodeAs<Stmt>("loop");

    if (quiet->getLocStart().isMacroID()) {
        return;                                                       // RETURN
    }

    // Don't warn about this in case 0, the usage example, or in negative cases
    // (which are not regulare tests).
    for (const Stmt *s = quiet;
         const CaseStmt *cs = d_analyser.get_parent<CaseStmt>(s);
         s = cs) {
        llvm::APSInt val;
        if (cs->getLHS()->isIntegerConstantExpr(val, *d_analyser.context()) &&
            !val.isStrictlyPositive()) {
            return;                                                   // RETURN
        }
    }

    // Require that the loop contain a call to a tested method.
    llvm::StringRef code = d_analyser.get_source(quiet->getSourceRange());
    for (const auto& func_count : d_data.d_names_to_test) {
        size_t pos = code.find(func_count.first);
        if (pos != code.npos) {
            if (pos > 0) {
                unsigned char c = code[pos - 1];
                if (c == '_' || std::isalnum(c)) {
                    continue;
                }
            }
            pos += func_count.first.size();
            if (pos + 1 < code.size()) {
                unsigned char c = code[pos];
                if (c == '_' || std::isalnum(c)) {
                    continue;
                }
            }
            d_analyser.report(quiet, check_name, "TP21",
                              "Loops must contain very verbose action");
            break;
        }
    }
}

#undef  NL
#define NL "\n"

const char standard_bde_assert_test_macros[] =
"// ==================="
"========================================================="                  NL
"//                      STANDARD BDE ASSERT TEST MACROS"                    NL
"// -------------------"
"---------------------------------------------------------"                  NL
""                                                                           NL
"static int testStatus = 0;"                                                 NL
""                                                                           NL
"static void aSsErT(int c, const char *s, int i)"                            NL
"{"                                                                          NL
"    if (c) {"                                                               NL
"        cout << \"Error \" << __FILE__ << \"(\" << i << \"): \" << s"       NL
"             << \"    (failed)\" << endl;"                                  NL
"        if (testStatus >= 0 && testStatus <= 100) ++testStatus;"            NL
"    }"                                                                      NL
"}"                                                                          NL
#if 0
"#define ASSERT(X) { aSsErT(!(X), #X, __LINE__); }"                          NL
#endif
;

const char standard_bde_assert_test_macros_bsl[] =
"// ==================="
"========================================================="                  NL
"//                      STANDARD BDE ASSERT TEST MACRO"                     NL
"// -------------------"
"---------------------------------------------------------"                  NL
"// NOTE: THIS IS A LOW-LEVEL COMPONENT AND MAY NOT USE ANY C++ LIBRARY"     NL
"// FUNCTIONS, INCLUDING IOSTREAMS."                                         NL
"static int testStatus = 0;"                                                 NL
""                                                                           NL
"static void aSsErT(bool b, const char *s, int i)"                           NL
"{"                                                                          NL
"    if (b) {"                                                               NL
"        printf(\"Error \" __FILE__ \"(%d): %s    (failed)\\n\", i, s);"     NL
"        if (testStatus >= 0 && testStatus <= 100) ++testStatus;"            NL
"    }"                                                                      NL
"}"                                                                          NL
;

const char standard_bde_assert_test_macros_ns_bsl[] =
"// ==================="
"========================================================="                  NL
"//                      STANDARD BDE ASSERT TEST MACROS"                    NL
"// -------------------"
"---------------------------------------------------------"                  NL
"// NOTE: THIS IS A LOW-LEVEL COMPONENT AND MAY NOT USE ANY C++ LIBRARY"     NL
"// FUNCTIONS, INCLUDING IOSTREAMS."                                         NL
""                                                                           NL
"namespace {"                                                                NL
""                                                                           NL
"int testStatus = 0;"                                                        NL
""                                                                           NL
"void aSsErT(bool b, const char *s, int i)"                                  NL
"{"                                                                          NL
"    if (b) {"                                                               NL
"        printf(\"Error \" __FILE__ \"(%d): %s    (failed)\\n\", i, s);"     NL
"        if (testStatus >= 0 && testStatus <= 100) ++testStatus;"            NL
"    }"                                                                      NL
"}"                                                                          NL
""                                                                           NL
"}  // close unnamed namespace"                                              NL
;

const char standard_bde_loop_assert_test_macros_old[] =
"// ================="
"==========================================================="                NL
"//                  STANDARD BDE LOOP-ASSERT TEST MACROS"                   NL
"// -----------------"
"-----------------------------------------------------------"                NL
""                                                                           NL
"#define LOOP_ASSERT(I,X) { \\"                                              NL
"    if (!(X)) { cout << #I << \": \" << I << \"\\n\"; "
"aSsErT(1, #X, __LINE__); }}"                                                NL
""                                                                           NL
"#define LOOP2_ASSERT(I,J,X) { \\"                                           NL
"    if (!(X)) { cout << #I << \": \" << I << \"\\t\" "
"<< #J << \": \" \\"                                                         NL
"              << J << \"\\n\"; "
"aSsErT(1, #X, __LINE__); } }"                                               NL
""                                                                           NL
"#define LOOP3_ASSERT(I,J,K,X) { \\"                                         NL
"    if (!(X)) { cout << #I << \": \" << I << \"\\t\" "
"<< #J << \": \" << J << \"\\t\" \\"                                         NL
"              << #K << \": \" << K << \"\\n\"; "
"aSsErT(1, #X, __LINE__); } }"                                               NL
""                                                                           NL
"#define LOOP4_ASSERT(I,J,K,L,X) { \\"                                       NL
"    if (!(X)) { cout << #I << \": \" << I << \"\\t\" "
"<< #J << \": \" << J << \"\\t\" << \\"                                      NL
"       #K << \": \" << K << \"\\t\" << #L << \": \" << L << \"\\n\"; \\"    NL
"       aSsErT(1, #X, __LINE__); } }"                                        NL
""                                                                           NL
"#define LOOP5_ASSERT(I,J,K,L,M,X) { \\"                                     NL
"    if (!(X)) { cout << #I << \": \" << I << \"\\t\" "
"<< #J << \": \" << J << \"\\t\" << \\"                                      NL
"       #K << \": \" << K << \"\\t\" << #L << \": \" << L << \"\\t\" << \\"  NL
"       #M << \": \" << M << \"\\n\"; \\"                                    NL
"       aSsErT(1, #X, __LINE__); } }"                                        NL
;

const char standard_bde_loop_assert_test_macros_new[] =
""                                                                           NL
"// ================="
"==========================================================="                NL
"//                    STANDARD BDE LOOP-ASSERT TEST MACROS"                 NL
"// -----------------"
"-----------------------------------------------------------"                NL
""                                                                           NL
"#define C_(X)   << #X << \": \" << X << '\\t'"                              NL
"#define A_(X,S) { if (!(X)) { cout S << endl; aSsErT(1, #X, __LINE__); } }" NL
"#define LOOP_ASSERT(I,X)            A_(X,C_(I))"                            NL
"#define LOOP2_ASSERT(I,J,X)         A_(X,C_(I)C_(J))"                       NL
"#define LOOP3_ASSERT(I,J,K,X)       A_(X,C_(I)C_(J)C_(K))"                  NL
"#define LOOP4_ASSERT(I,J,K,L,X)     A_(X,C_(I)C_(J)C_(K)C_(L))"             NL
"#define LOOP5_ASSERT(I,J,K,L,M,X)   A_(X,C_(I)C_(J)C_(K)C_(L)C_(M))"        NL
"#define LOOP6_ASSERT(I,J,K,L,M,N,X) A_(X,C_(I)C_(J)C_(K)C_(L)C_(M)C_(N))"   NL
;

const char standard_bde_loop_assert_test_macros_bsl[] =
"// ================="
"==========================================================="                NL
"//                      STANDARD BDE TEST DRIVER MACROS"                    NL
"// -----------------"
"-----------------------------------------------------------"                NL
""                                                                           NL
"#define ASSERT       BSLS_BSLTESTUTIL_ASSERT"                               NL
"#define LOOP_ASSERT  BSLS_BSLTESTUTIL_LOOP_ASSERT"                          NL
"#define LOOP0_ASSERT BSLS_BSLTESTUTIL_LOOP0_ASSERT"                         NL
"#define LOOP1_ASSERT BSLS_BSLTESTUTIL_LOOP1_ASSERT"                         NL
"#define LOOP2_ASSERT BSLS_BSLTESTUTIL_LOOP2_ASSERT"                         NL
"#define LOOP3_ASSERT BSLS_BSLTESTUTIL_LOOP3_ASSERT"                         NL
"#define LOOP4_ASSERT BSLS_BSLTESTUTIL_LOOP4_ASSERT"                         NL
"#define LOOP5_ASSERT BSLS_BSLTESTUTIL_LOOP5_ASSERT"                         NL
"#define LOOP6_ASSERT BSLS_BSLTESTUTIL_LOOP6_ASSERT"                         NL
"#define ASSERTV      BSLS_BSLTESTUTIL_ASSERTV"                              NL
""                                                                           NL
;

const char standard_bde_loop_assert_test_macros_bdl[] =
"// ================="
"==========================================================="                NL
"//                      STANDARD BDE TEST DRIVER MACROS"                    NL
"// -----------------"
"-----------------------------------------------------------"                NL
""                                                                           NL
"#define ASSERT       BDLS_TESTUTIL_ASSERT"                                  NL
"#define LOOP_ASSERT  BDLS_TESTUTIL_LOOP_ASSERT"                             NL
"#define LOOP0_ASSERT BDLS_TESTUTIL_LOOP0_ASSERT"                            NL
"#define LOOP1_ASSERT BDLS_TESTUTIL_LOOP1_ASSERT"                            NL
"#define LOOP2_ASSERT BDLS_TESTUTIL_LOOP2_ASSERT"                            NL
"#define LOOP3_ASSERT BDLS_TESTUTIL_LOOP3_ASSERT"                            NL
"#define LOOP4_ASSERT BDLS_TESTUTIL_LOOP4_ASSERT"                            NL
"#define LOOP5_ASSERT BDLS_TESTUTIL_LOOP5_ASSERT"                            NL
"#define LOOP6_ASSERT BDLS_TESTUTIL_LOOP6_ASSERT"                            NL
"#define ASSERTV      BDLS_TESTUTIL_ASSERTV"                                 NL
""                                                                           NL
;

const char semi_standard_test_output_macros[] =
""                                                                           NL
"// ================="
"==========================================================="                NL
"//                  SEMI-STANDARD TEST OUTPUT MACROS"                       NL
"// -----------------"
"-----------------------------------------------------------"                NL
""                                                                           NL
"#define P(X) cout << #X \" = \" << (X) << endl; "
"// Print identifier and value."                                             NL
"#define Q(X) cout << \"<| \" #X \" |>\" << endl;  "
"// Quote identifier literally."                                             NL
"#define P_(X) cout << #X \" = \" << (X) << \", \" << flush; "
"// 'P(X)' without '\\n'"                                                    NL
"#define T_ cout << \"\\t\" << flush;             // Print tab w/o newline." NL
"#define L_ __LINE__                           // current Line number"       NL
;

const char semi_standard_test_output_macros_bsl[] =
""                                                                           NL
"#define Q   BSLS_BSLTESTUTIL_Q   // Quote identifier literally."            NL
"#define P   BSLS_BSLTESTUTIL_P   // Print identifier and value."            NL
"#define P_  BSLS_BSLTESTUTIL_P_  // P(X) without '\\n'."                    NL
"#define T_  BSLS_BSLTESTUTIL_T_  // Print a tab (w/o newline)."             NL
"#define L_  BSLS_BSLTESTUTIL_L_  // current Line number"                    NL
""                                                                           NL
;

const char semi_standard_test_output_macros_bdl[] =
""                                                                           NL
"#define Q   BDLS_TESTUTIL_Q   // Quote identifier literally."               NL
"#define P   BDLS_TESTUTIL_P   // Print identifier and value."               NL
"#define P_  BDLS_TESTUTIL_P_  // P(X) without '\\n'."                       NL
"#define T_  BDLS_TESTUTIL_T_  // Print a tab (w/o newline)."                NL
"#define L_  BDLS_TESTUTIL_L_  // current Line number"                       NL
""                                                                           NL
;

static llvm::StringRef squash(std::string &out, llvm::StringRef in)
    // Copy the specified 'in' string to the specified 'out' string with all
    // spaces removed.
{
    out.clear();
    out.reserve(in.size());
    for (size_t i = 0; i < in.size(); ++i) {
        if (in[i] != ' ') {
            out += in[i];
        }
    }
    return out;
}

void report::search(SourceLocation *best_loc,
                    llvm::StringRef *best_needle,
                    size_t *best_distance,
                    llvm::StringRef key,
                    const std::vector<llvm::StringRef> &needles,
                    FileID fid)
{
    const SourceManager &m = d_analyser.manager();
    SourceLocation top = m.getLocForStartOfFile(fid);
    llvm::StringRef haystack = m.getBufferData(fid);
    size_t num_lines = haystack.count('\n');

    // For each needle, get its number of lines and blank lines, and determine
    // the maximum number of lines over all needles.
    size_t ns = needles.size();
    std::vector<size_t> needle_lines(ns);
    std::vector<size_t> needle_blank_lines(ns);
    size_t max_needle_lines = 0;
    for (size_t n = 0; n < ns; ++n) {
        llvm::StringRef needle = needles[n];
        needle_lines[n] = needle.count('\n');
        needle_blank_lines[n] = needle.count("\n\n");
        if (max_needle_lines < needle_lines[n]) {
            max_needle_lines = needle_lines[n];
        }
    }

    // Compute the set of lines to examine.  Always examine last line, so that
    // some match is returned.
    std::set<size_t> lines;
    lines.insert(Location(m, m.getLocForEndOfFile(fid)).line());

    // For each line in the haystack where we find the key, add the range of
    // lines around it, 'max_needle_lines' in each direction, to the set of
    // lines to be examined.
    for (size_t key_pos = haystack.find(key); key_pos != haystack.npos;) {
        size_t key_line = Location(m, top.getLocWithOffset(key_pos)).line();
        for (size_t i = 0; i <= max_needle_lines; ++i) {
            if (key_line > i && key_line - i <= num_lines) {
                lines.insert(key_line - i);
            }
            if (key_line + i <= num_lines) {
                lines.insert(key_line + i);
            }
        }
        size_t pos = haystack.drop_front(key_pos + key.size()).find(key);
        if (pos == haystack.npos) {
            break;
        }
        key_pos += key.size() + pos;
    }

    *best_distance = ~size_t(0);

    // For each line to be examined...
    std::set<size_t>::const_iterator bl = lines.begin();
    std::set<size_t>::const_iterator el = lines.end();
    std::string squashed_needle;
    std::string squashed_haystack;
    for (std::set<size_t>::const_iterator il = bl; il != el; ++il) {
        size_t line = *il;
        SourceLocation begin = m.translateLineCol(fid, line, 1);
        // For each needle...
        for (size_t n = 0; n < ns; ++n) {
            llvm::StringRef needle = needles[n];
            squash(squashed_needle, needle);
            size_t nl = needle_lines[n];
            size_t nbl = needle_blank_lines[n];
            // Examine successively smaller ranges of lines from the starting
            // line, beginning with the number of lines in the needle down to
            // that number less the number of blank lines in the needle.
            for (size_t nn = nl; nn >= nl - nbl; --nn) {
                SourceLocation end = m.translateLineCol(fid, line + nn, 1);
                SourceRange r(begin, end);
                llvm::StringRef s = d_analyser.get_source(r, true);
                size_t distance = squash(squashed_haystack, s)
                                      .edit_distance(squashed_needle);
                // Record a better match whenever one is found.
                if (distance < *best_distance) {
                    *best_distance = distance;
                    std::pair<size_t, size_t> mm = mid_mismatch(s, needle);
                    *best_loc = r.getBegin().getLocWithOffset(mm.first);
                    *best_needle = needle;
                    // Return on an exact match.
                    if (distance == 0 || mm.first == s.size()) {
                        return;                                       // RETURN
                    }
                }
            }
        }
    }
}

void report::check_boilerplate()
{
    const SourceManager &m = d_analyser.manager();
    FileID fid = m.getMainFileID();

    size_t distance;
    llvm::StringRef needle;
    std::vector<llvm::StringRef> needles;
    SourceLocation loc;

    needles.clear();
    needles.push_back(standard_bde_assert_test_macros);
    needles.push_back(standard_bde_assert_test_macros_bsl);
    needles.push_back(standard_bde_assert_test_macros_ns_bsl);
    search(&loc, &needle, &distance, "(failed)", needles, fid);
    if (distance != 0) {
        d_analyser.report(loc, check_name, "TP19",
                          "Missing or malformed standard test driver section");
        d_analyser.report(loc, check_name, "TP19",
                          "One correct form (of several possible) is\n%0",
                          false, DiagnosticsEngine::Note)
            << needle;
    }

    needles.clear();
    needles.push_back(standard_bde_loop_assert_test_macros_old);
    needles.push_back(standard_bde_loop_assert_test_macros_new);
    needles.push_back(standard_bde_loop_assert_test_macros_bsl);
    needles.push_back(standard_bde_loop_assert_test_macros_bdl);
    search(&loc, &needle, &distance, "define LOOP_ASSERT", needles, fid);
    if (distance != 0) {
        d_analyser.report(loc, check_name, "TP19",
                          "Missing or malformed standard test driver section");
        d_analyser.report(loc, check_name, "TP19",
                          "One correct form (of several possible) is\n%0",
                          false, DiagnosticsEngine::Note)
            << needle;
    }

    needles.clear();
    needles.push_back(semi_standard_test_output_macros);
    needles.push_back(semi_standard_test_output_macros_bsl);
    needles.push_back(semi_standard_test_output_macros_bdl);
    search(&loc, &needle, &distance, "define P_", needles, fid);
    if (distance != 0) {
        d_analyser.report(loc, check_name, "TP19",
                          "Missing or malformed standard test driver section");
        d_analyser.report(loc, check_name, "TP19",
                          "One correct form (of several possible) is\n%0",
                          false, DiagnosticsEngine::Note)
            << needle;
    }
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
    // Hook up the callback functions.
{
    analyser.onTranslationUnitDone += report(analyser);
    visitor.onFunctionDecl += report(analyser);
    observer.onComment += report(analyser);
    observer.onIf += report(analyser);
    observer.onElif += report(analyser);
    observer.onIfdef += report(analyser);
    observer.onIfndef += report(analyser);
    observer.onElse += report(analyser);
    observer.onEndif += report(analyser);
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &subscribe);

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------

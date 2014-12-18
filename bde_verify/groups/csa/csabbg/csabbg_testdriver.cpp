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
#include <csabase_debug.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_report.h>
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
    AST_MATCHER_P(Expr, callTo, Decl *, method) {
        const Decl *callee = 0;
        const CXXDestructorDecl *dtor = 0;
        if (const CallExpr *call = llvm::dyn_cast<CallExpr>(&Node)) {
            callee = call->getCalleeDecl();
        }
        else if (const CXXConstructExpr *ctor =
                                     llvm::dyn_cast<CXXConstructExpr>(&Node)) {
            callee = ctor->getConstructor();
            dtor = ctor->getConstructor()->getParent()->getDestructor();
        }
        else if (const DeclRefExpr *dr = llvm::dyn_cast<DeclRefExpr>(&Node)) {
            callee = dr->getDecl();
        }
        while (callee) {
            const Decl *mc = method->getCanonicalDecl();
            const FunctionDecl *fd = llvm::dyn_cast<FunctionDecl>(callee);
            if (fd) {
                fd = fd->getInstantiatedFromMemberFunction();
                if (fd && fd->getCanonicalDecl() == mc) {
                    return true;                                      // RETURN
                }
            }
            if (callee->getCanonicalDecl() == mc) {
                return true;                                          // RETURN
            }
            callee = dtor;
            dtor = 0;
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
    std::map<std::string, unsigned> d_names_to_test;   // public method names
    std::map<std::string, unsigned> d_names_in_plan;   // method namess tested
};

data::data()
: d_main(0)
, d_return(0)
, d_collecting_classes(NOT_YET)
{
}

struct report : Report<data>
    // Callback object for inspecting test drivers.
{
    using Report<data>::Report;

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

    void note_function(std::string m);
        // Mark the speciied 'm' as a public method of a class in @CLASSES.

    void process_function(CXXMethodDecl *decl);
        // Handle one public method of the classes in @CLASSES.

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

    void check_banner(SourceLocation bl, llvm::StringRef s);
        // Check the specified banner 's' at the specified position 'bl'.

    void match_noisy_print(const BoundNodes &nodes);
    void match_no_print(const BoundNodes &nodes);
    void match_return_status(const BoundNodes &nodes);
    void match_set_status(const BoundNodes &nodes);
};

// Loosely match the banner of a TEST PLAN.
llvm::Regex test_plan_banner(
    "//[[:blank:]]*" "[-=_]([[:blank:]]?[-=_])*"  "[[:blank:]]*\n"
    "//[[:blank:]]*" "TEST" "[[:blank:]]*" "PLAN" "[[:blank:]]*\n"
    "//[[:blank:]]*" "[-=_]([[:blank:]]?[-=_])*"  "[[:blank:]]*\n",
    llvm::Regex::Newline | llvm::Regex::IgnoreCase);

SourceRange report::get_test_plan()
{
    data::Comments::iterator b = d.d_comments.begin();
    data::Comments::iterator e = d.d_comments.end();
    for (data::Comments::iterator i = b; i != e; ++i) {
        llvm::StringRef comment = a.get_source(*i);
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
                        "|" "[][)([:alnum:]_[:space:]*&]+"
                        ")"
    "|" "~?[[:alnum:]_]+"
    ")" "[[:space:]]*[(]",
    llvm::Regex::Newline);  // Match a method name in a test item.

const internal::DynTypedMatcher &
print_matcher()
{
    static const internal::DynTypedMatcher matcher =
        caseStmt(has(compoundStmt(has(ifStmt(
            hasCondition(ignoringImpCasts(
                declRefExpr(to(varDecl(hasName("verbose"))))
            )),
            forEachDescendant(expr(anyOf(
                callExpr(argumentCountIs(1),
                         callee(functionDecl(hasName("printf"))),
                         hasArgument(0, ignoringImpCasts(stringLiteral()
                                                         .bind("ps")
                         ))
                ),
                callExpr(argumentCountIs(1),
                         callee(functionDecl(hasName("printf"))),
                         hasArgument(0, ignoringImpCasts(characterLiteral()
                                                         .bind("pc")
                         ))
                ),
                operatorCallExpr(
                    hasOverloadedOperatorName("<<"),
                    hasArgument(1, ignoringImpCasts(declRefExpr(to(
                        functionDecl(hasName("endl"))
                    )).bind("ce")))
                ),
                operatorCallExpr(
                    hasOverloadedOperatorName("<<"),
                    hasArgument(1, ignoringImpCasts(stringLiteral()
                                                    .bind("cs")
                    ))
                ),
                operatorCallExpr(
                    hasOverloadedOperatorName("<<"),
                    hasArgument(1, ignoringImpCasts(characterLiteral()
                                                    .bind("cc")
                    ))
                )
            )))
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
    d.d_return = nodes.getNodeAs<Stmt>("good");
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
        a.report(bad->getLocEnd(), check_name, "TP24",
                 "`default:` case should set `testStatus = -1;`");
    }
}

void report::note_function(std::string f)
{
    size_t lt = f.find('<');
    if (lt != f.npos && !llvm::StringRef(f).startswith("operator")) {
        f = f.substr(0, lt);
    }
    ++d.d_names_to_test[f];
}

void report::process_function(CXXMethodDecl *f)
{
    if (f->getAccess() == AS_public &&
        f->isUserProvided() &&
        !f->getLocation().isMacroID() &&
        !a.config()->suppressed(
            "TP27", m.getLocForStartOfFile(m.getMainFileID()))) {
        MatchFinder mf;
        bool found = false;
        OnMatch<> m1([&](const BoundNodes &nodes) {
            if (m.getFileID(m.getExpansionLoc(
                    nodes.getNodeAs<Expr>("expr")->getExprLoc())) ==
                m.getMainFileID()) {
                found = true;
            }
        });
        mf.addDynamicMatcher(
            decl(hasDescendant(
                namedDecl(hasName("main"),
                          forEachDescendant(expr(callTo(f)).bind("expr"))))),
            &m1);
        mf.match(*f->getTranslationUnitDecl(), *a.context());
        if (!found) {
            a.report(f, check_name, "TP27",
                     "Method not called in test driver");
        }
        note_function(f->getNameAsString());
    }
}

void report::get_function_names()
{
    for (auto p : d.d_classes) {
        std::string name = p.first.str();
        if (!p.first.startswith("::")) {
            name = "::" + name;
        }
        bool is_bsl = llvm::StringRef(name).startswith("::bsl::");
        NamedDecl *nd = a.lookup_name(name);
        if (!nd && is_bsl) {
            nd = a.lookup_name("::std::" + name.substr(7));
        }
        if (!nd) {
            nd = a.lookup_name("::" + a.config()->toplevel_namespace() + name);
            if (!nd && is_bsl) {
                nd = a.lookup_name(
                    "::" + a.config()->toplevel_namespace() +
                    "::std::" + name.substr(7));
            }
        }

        CXXRecordDecl *record = 0;
        if (nd) {
            while (UsingShadowDecl *usd =
                       llvm::dyn_cast<UsingShadowDecl>(nd)) {
                nd = usd->getTargetDecl();
            }
            if (llvm::dyn_cast<TypedefDecl>(nd)) {
                // @CLASSES sometimes contains typedefs.  Ignore them.
                continue;
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
            DeclContext::decl_iterator b = record->decls_begin();
            DeclContext::decl_iterator e = record->decls_end();
            for (; b != e; ++b) {
                if (auto *t = llvm::dyn_cast<FunctionTemplateDecl>(*b)) {
                    auto sb = t->spec_begin();
                    auto se = t->spec_end();
                    if (sb == se) {
                        a.report(t, check_name, "TP27",
                                 "Method not called in test driver");
                        note_function(t->getNameAsString());
                    }
                    for (; sb != se; ++sb) {
                        if (auto *m = llvm::dyn_cast<CXXMethodDecl>(*sb)) {
                            process_function(m);
                        }
                    }
                }
                else if (auto *m = llvm::dyn_cast<CXXMethodDecl>(*b)) {
                    process_function(m);
                }
            }
        }
        else {
            a.report(p.second.getBegin(), check_name, "TP25",
                     "Cannot find definition of class '%0' from "
                     "@CLASSES section.")
                << p.first;
        }
    }
}

void report::operator()()
{
    if (!a.is_test_driver()) {
        return;                                                       // RETURN
    }

    check_boilerplate();

    get_function_names();

    SourceRange plan_range = get_test_plan();

    if (!plan_range.isValid()) {
        a.report(m.getLocForStartOfFile(m.getMainFileID()), check_name, "TP14",
                 "TEST PLAN section is absent");
    }

    llvm::StringRef plan = a.get_source(plan_range);

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
        a.report(plan_range.getBegin(), check_name, "TP02",
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
            a.report(bracket_range.getBegin(), check_name, "TP03",
                     "Missing test number")
                << bracket_range;
        }

        if (test_num == 0) {
            a.report(bracket_range.getBegin(), check_name, "TP04",
                     "Test number may not be 0")
                << bracket_range;
        }

        if (item.empty()) {
            a.report(bracket_range.getEnd().getLocWithOffset(1),
                     check_name, "TP07",
                     "Missing test item");
        } else {
            d.d_tests_of_cases.insert(std::make_pair(test_num, item));
            d.d_cases_of_tests.insert(std::make_pair(item, test_num));
            if (tested_method.match(item, &matches)) {
                ++d.d_names_in_plan[matches[1]];
            }
        }

        if (cruft.find_first_not_of(" ") != cruft.npos) {
            a.report(bracket_range.getBegin().getLocWithOffset(-1),
                     check_name, "TP16",
                     "Extra characters before test number brackets");
        }
    }
    if (count == 0) {
        a.report(plan_range.getBegin().getLocWithOffset(plan_pos),
                 check_name, "TP13",
                 "No test items found in test plan");
    }
    else {
        for (const auto &n : d.d_names_to_test) {
            if (n.second > d.d_names_in_plan[n.first]) {
                a.report(
                    plan_range.getBegin().getLocWithOffset(plan_pos),
                    check_name, "TP26",
                    "Tested %plural{1:class has|:classes have}0 "
                    "%plural{1:a|:%1}1 function%s1 named '%2' "
                    "but the test plan has %plural{0:none|:%3}3")
                << int(d.d_classes.size())
                << int(n.second)
                << n.first
                << int(d.d_names_in_plan[n.first]);
            }
        }
    }

    CompoundStmt const* stmt = d.d_main;
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
        d.d_return = 0;
        mf.match(*last, *a.context());
        if (!d.d_return) {
            a.report(last->getLocEnd(), check_name, "TP23",
                   "Final statement of `main()` must be `return testStatus;`");
        }
    } else {
        a.report(stmt, check_name, "TP11",
                 "No switch statement found in test driver main");
        return;                                                       // RETURN
    }

    const SwitchCase* sc;
    for (sc = ss->getSwitchCaseList(); sc; sc = sc->getNextSwitchCase()) {
        size_t line = Location(m, sc->getColonLoc()).line() + 1;

        // Skip over preprocessor conditionals.
        while (d.d_cclines.find(line) != d.d_cclines.end()) {
            ++line;
        }

        SourceRange cr;
        if (d.d_comments_of_lines.find(line) !=
            d.d_comments_of_lines.end()) {
            cr = d.d_comments[d.d_comments_of_lines[line]];
        }

        const CaseStmt* cs = llvm::dyn_cast<CaseStmt>(sc);
        if (!cs) {
            // Default case.
            MatchFinder mf;
            OnMatch<report, &report::match_set_status> m1(this);
            mf.addDynamicMatcher(set_status_matcher(), &m1);
            mf.match(*sc, *a.context());
            continue;
        }

        llvm::APSInt case_value;
        cs->getLHS()->EvaluateAsInt(case_value, *a.context());
        bool negative = 0 >  case_value.getSExtValue();
        bool zero     = 0 == case_value.getSExtValue();

        MatchFinder mf;
        OnMatch<report, &report::match_noisy_print> m2(this);
        mf.addDynamicMatcher(noisy_print_matcher(), &m2);
        OnMatch<report, &report::match_no_print> m3(this);
        mf.addDynamicMatcher(no_print_matcher(), &m3);
        std::string banner;
        SourceLocation bl;
        OnMatch<> m4([&](const BoundNodes &nodes) {
            if (auto sl = nodes.getNodeAs<DeclRefExpr>("ce")) {
                banner = "\n" + banner;
                bl = sl->getExprLoc();
            }
            else if (auto sl = nodes.getNodeAs<StringLiteral>("ps")) {
                banner = sl->getString().str() + banner;
                bl = sl->getExprLoc();
            }
            else if (auto sl = nodes.getNodeAs<StringLiteral>("cs")) {
                banner = sl->getString().str() + banner;
                bl = sl->getExprLoc();
            }
            else if (auto sl = nodes.getNodeAs<CharacterLiteral>("pc")) {
                banner = char(sl->getValue()) + banner;
                bl = sl->getExprLoc();
            }
            else if (auto sl = nodes.getNodeAs<CharacterLiteral>("cc")) {
                banner = char(sl->getValue()) + banner;
                bl = sl->getExprLoc();
            }
        });
        mf.addDynamicMatcher(print_matcher(), &m4);

        mf.match(*cs, *a.context());

        if (!zero) {
            check_banner(bl, banner);
        }

        if (!bl.isValid() && !zero) {
            a.report(sc->getLocStart(), check_name, "TP17",
                "Test case does not contain 'if (verbose) print test banner'");
        }

        if (!cr.isValid()) {
            if (!zero) {
                a.report(sc->getLocStart(), check_name, "TP05",
                         "Test case has no comment");
            }
            continue;
        } else {
            if (zero) {
                a.report(sc->getLocStart(), check_name, "TP10",
                         "Case 0 should not have a test comment");
            }
        }

        llvm::StringRef comment = a.get_source(cr);
        llvm::SmallVector<llvm::StringRef, 7> matches;
        size_t testing_pos = 0;
        size_t line_pos = 0;

        if (bl.isValid()) {
            llvm::StringRef banner_text =
                llvm::StringRef(banner).ltrim().split('\n').first;
            if (test_title.match(comment, &matches)) {
                llvm::StringRef t = matches[2];
                testing_pos = comment.find(t);
                line_pos = testing_pos + t.size();
                std::pair<size_t, size_t> m = mid_mismatch(t, banner_text);
                if (m.first != t.size()) {
                    a.report(
                        cr.getBegin().getLocWithOffset(testing_pos + m.first),
                        check_name, "TP22",
                        "Mismatch between title in comment and as printed");
                    a.report(bl, check_name, "TP22",
                             "Printed title is",
                             false, DiagnosticIDs::Note);
                }
            } else {
                a.report(
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
                a.report(cr.getBegin().getLocWithOffset(testing_pos + m.first),
                         check_name, "TP15",
                         "Correct format is '// Testing:'");
            }
        } else if (!negative) {
            a.report(cr.getBegin(), check_name, "TP12",
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
            std::pair<Ci, Ci> be = d.d_cases_of_tests.equal_range(line);
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
                a.report(cr.getBegin().getLocWithOffset(line_pos),
                         check_name, "TP08",
                        "Test plan does not have case number %0 for this item")
                    << case_value.getSExtValue();
                a.report(plan_range.getBegin().getLocWithOffset(off),
                         check_name, "TP08",
                         "Test plan item is",
                         false, DiagnosticIDs::Note);
            }
            else if (!negative && test_item.match(line)) {
                a.report(cr.getBegin().getLocWithOffset(line_pos),
                         check_name, "TP09",
                         "Test plan should contain this item from "
                         "'Testing' section of case %0")
                    << case_value.getSExtValue();
            }
        }

        typedef data::TestsOfCases::const_iterator Ci;
        std::pair<Ci, Ci> be = d.d_tests_of_cases.equal_range(
            case_value.getSExtValue());
        for (Ci i = be.first; i != be.second; ++i) {
            if (comment.drop_front(testing_pos).find(i->second) ==
                comment.npos) {
                a.report(plan_range.getBegin().getLocWithOffset(
                         plan_pos + plan.drop_front(plan_pos).find(i->second)),
                         check_name, "TP06",
                         "'Testing' section of case %0 should contain this "
                         "item from test plan")
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
    Location location(a.get_location(range.getBegin()));
    if (location.file() == a.toplevel()) {
        data::Comments& c = d.d_comments;
        if (c.size() == 0 ||
            !areConsecutive(m, c.back(), range)) {
            d.d_comments_of_lines[location.line()] = c.size();
            c.push_back(range);
        }
        else {
            c.back().setEnd(range.getEnd());
        }
    }
    if (d.d_collecting_classes != data::DONE &&
        a.is_component(location.file())) {
        llvm::StringRef line = a.get_source_line(location.location());
        if (d.d_collecting_classes == data::NOT_YET) {
            if (line.find("//@CLASS") == 0) {
                d.d_collecting_classes = data::NOW;
            }
        }
        else {
            llvm::SmallVector<llvm::StringRef, 7> matches;
            if (classes.match(line, &matches)) {
                d.d_classes[matches[1]] = range;
            }
            else {
                d.d_collecting_classes = data::DONE;
            }
        }
    }
}

void report::operator()(const FunctionDecl *function)
{
    if (function->isMain() && function->hasBody()) {
        d.d_main = llvm::dyn_cast<CompoundStmt>(function->getBody());
    }
}

void report::mark_ccline(SourceLocation loc)
{
    Location location(a.get_location(loc));
    if (location.file() == a.toplevel()) {
        d.d_cclines.insert(location.line());
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

    for (char c : s) {
        if (c == '\'') {
            if (!in_double_quotes) {
                in_single_quotes = !in_single_quotes;
            }
        }
        else if (c == '"') {
            if (!in_single_quotes) {
                in_double_quotes = !in_double_quotes;
            }
        }
        else if (std::islower(static_cast<unsigned char>(c))) {
            if (!in_single_quotes && !in_double_quotes) {
                return false;                                         // RETURN
            }
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

    for (char& c : s) {
        if (c == '\'') {
            if (!in_double_quotes) {
                in_single_quotes = !in_single_quotes;
            }
        }
        else if (c == '"') {
            if (!in_single_quotes) {
                in_double_quotes = !in_double_quotes;
            }
        }
        else if (std::islower(static_cast<unsigned char>(c))) {
            if (!in_single_quotes && !in_double_quotes) {
                c = std::toupper(static_cast<unsigned char>(c));
            }
        }
    }
    return s;
}

void report::check_banner(SourceLocation bl, llvm::StringRef s)
{
    if (!bl.isValid()) {
        a.report(bl, check_name, "TP17",
                "Test case does not contain 'if (verbose) print test banner'");
    }
    else {
        size_t n = s.size();
        llvm::StringRef text = s.ltrim().split('\n').first;
        bool c = is_all_cappish(s);
        if ((s.count('\n') != 3 ||
             s[0] != '\n' ||
             s[n - 1] != '\n' ||
             s[n / 2] != '\n' ||
             s.find_first_not_of('=', n / 2 + 1) != n - 1 ||
             !c) &&
            (s.count('\n') != 2 ||
             s[n - 1] != '\n' ||
             s[n / 2 - 1] != '\n' ||
             s.find_first_not_of('=', n / 2) != n - 1 ||
             !c)
           ) {
            size_t col = m.getPresumedColumnNumber(bl);
            std::string indent(col - 1, ' ');
            a.report(bl, check_name, "TP18",
                     c ? "Incorrect test banner format"
                       : "Incorrect test banner format (not ALL CAPS)");
            a.report(bl, check_name, "TP18",
                     "Correct format is\n%0",
                     false, DiagnosticIDs::Note)
                << indent
                 + (s[0] == '\n' ? "\"\\n\" " : "")
                 + "\"" + cappish(text) + "\" \"\\n\"\n"
                 + indent
                 + (s[0] == '\n' ? "     " : "")
                 + "\"" + std::string(text.size(), '=') + "\" \"\\n\"";
        }
    }
}

void report::match_noisy_print(const BoundNodes& nodes)
{
    const IfStmt *noisy = nodes.getNodeAs<IfStmt>("noisy");

    if (noisy->getLocStart().isMacroID()) {
        return;                                                       // RETURN
    }

    a.report(noisy->getCond(), check_name, "TP20",
             "Within loops, act on very verbose");
}

void report::match_no_print(const BoundNodes& nodes)
{
    const Stmt *quiet = nodes.getNodeAs<Stmt>("loop");

    if (quiet->getLocStart().isMacroID()) {
        return;                                                       // RETURN
    }

    // Don't warn about this in case 0, the usage example, or in negative cases
    // (which are not regular tests).
    for (const Stmt *s = quiet;
         const CaseStmt *cs = a.get_parent<CaseStmt>(s);
         s = cs) {
        llvm::APSInt val;
        if (cs->getLHS()->isIntegerConstantExpr(val, *a.context()) &&
            !val.isStrictlyPositive()) {
            return;                                                   // RETURN
        }
    }

    // Require that the loop contain a call to a tested method.
    llvm::StringRef code = a.get_source(quiet->getSourceRange());
    for (const auto& func_count : d.d_names_to_test) {
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
            a.report(quiet, check_name, "TP21",
                     "Loops must contain very verbose action");
            break;
        }
    }
}

const char standard_bde_assert_test_function[] = R"BDE(
// ============================================================================
//                     STANDARD BDE ASSERT TEST FUNCTION
// ----------------------------------------------------------------------------

namespace {

int testStatus = 0;

void aSsErT(bool condition, const char *message, int line)
{
    if (condition) {
        cout << "Error " __FILE__ "(" << line << "): " << message
             << "    (failed)" << endl;

        if (0 <= testStatus && testStatus <= 100) {
            ++testStatus;
        }
    }
}

}  // close unnamed namespace
)BDE";

const char standard_bde_assert_test_function_bsl[] = R"BDE(
// ============================================================================
//                     STANDARD BSL ASSERT TEST FUNCTION
// ----------------------------------------------------------------------------

namespace {

int testStatus = 0;

void aSsErT(bool condition, const char *message, int line)
{
    if (condition) {
        printf("Error " __FILE__ "(%d): %s    (failed)\n", line, message);

        if (0 <= testStatus && testStatus <= 100) {
            ++testStatus;
        }
    }
}

}  // close unnamed namespace
)BDE";

const char standard_bde_test_driver_macro_abbreviations[] = R"BDE(
// ============================================================================
//               STANDARD BDE TEST DRIVER MACRO ABBREVIATIONS
// ----------------------------------------------------------------------------

#define ASSERT       BDLS_TESTUTIL_ASSERT
#define ASSERTV      BDLS_TESTUTIL_ASSERTV

#define LOOP_ASSERT  BDLS_TESTUTIL_LOOP_ASSERT
#define LOOP0_ASSERT BDLS_TESTUTIL_LOOP0_ASSERT
#define LOOP1_ASSERT BDLS_TESTUTIL_LOOP1_ASSERT
#define LOOP2_ASSERT BDLS_TESTUTIL_LOOP2_ASSERT
#define LOOP3_ASSERT BDLS_TESTUTIL_LOOP3_ASSERT
#define LOOP4_ASSERT BDLS_TESTUTIL_LOOP4_ASSERT
#define LOOP5_ASSERT BDLS_TESTUTIL_LOOP5_ASSERT
#define LOOP6_ASSERT BDLS_TESTUTIL_LOOP6_ASSERT

#define Q            BDLS_TESTUTIL_Q   // Quote identifier literally.
#define P            BDLS_TESTUTIL_P   // Print identifier and value.
#define P_           BDLS_TESTUTIL_P_  // P(X) without '\n'.
#define T_           BDLS_TESTUTIL_T_  // Print a tab (w/o newline).
#define L_           BDLS_TESTUTIL_L_  // current Line number
)BDE";

const char standard_bde_test_driver_macro_abbreviations_bsl[] = R"BDE(
// ============================================================================
//               STANDARD BSL TEST DRIVER MACRO ABBREVIATIONS
// ----------------------------------------------------------------------------

#define ASSERT       BSLS_BSLTESTUTIL_ASSERT
#define ASSERTV      BSLS_BSLTESTUTIL_ASSERTV

#define LOOP_ASSERT  BSLS_BSLTESTUTIL_LOOP_ASSERT
#define LOOP0_ASSERT BSLS_BSLTESTUTIL_LOOP0_ASSERT
#define LOOP1_ASSERT BSLS_BSLTESTUTIL_LOOP1_ASSERT
#define LOOP2_ASSERT BSLS_BSLTESTUTIL_LOOP2_ASSERT
#define LOOP3_ASSERT BSLS_BSLTESTUTIL_LOOP3_ASSERT
#define LOOP4_ASSERT BSLS_BSLTESTUTIL_LOOP4_ASSERT
#define LOOP5_ASSERT BSLS_BSLTESTUTIL_LOOP5_ASSERT
#define LOOP6_ASSERT BSLS_BSLTESTUTIL_LOOP6_ASSERT

#define Q            BSLS_BSLTESTUTIL_Q   // Quote identifier literally.
#define P            BSLS_BSLTESTUTIL_P   // Print identifier and value.
#define P_           BSLS_BSLTESTUTIL_P_  // P(X) without '\n'.
#define T_           BSLS_BSLTESTUTIL_T_  // Print a tab (w/o newline).
#define L_           BSLS_BSLTESTUTIL_L_  // current Line number
)BDE";

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
                llvm::StringRef s = a.get_source(r, true);
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
    FileID fid = m.getMainFileID();

    size_t distance;
    llvm::StringRef needle;
    std::vector<llvm::StringRef> needles;
    SourceLocation loc;

    needles.clear();
    needles.push_back(standard_bde_assert_test_function);
    needles.push_back(standard_bde_assert_test_function_bsl);
    search(&loc, &needle, &distance, "(failed)", needles, fid);
    if (distance != 0) {
        a.report(loc, check_name, "TP19",
                 "Missing or malformed standard test driver section");
        a.report(loc, check_name, "TP19",
                 "One correct form (of several possible) is\n%0",
                 false, DiagnosticIDs::Note)
            << needle;
    }

    needles.clear();
    needles.push_back(standard_bde_test_driver_macro_abbreviations);
    needles.push_back(standard_bde_test_driver_macro_abbreviations_bsl);
    search(&loc, &needle, &distance, "define LOOP_ASSERT", needles, fid);
    if (distance != 0) {
        a.report(loc, check_name, "TP19",
                 "Missing or malformed standard test driver section");
        a.report(loc, check_name, "TP19",
                 "One correct form (of several possible) is\n%0",
                 false, DiagnosticIDs::Note)
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

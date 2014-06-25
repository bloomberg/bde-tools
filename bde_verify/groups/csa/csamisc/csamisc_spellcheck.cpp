// csamisc_spellcheck.cpp                                             -*-C++-*-

#include <clang/AST/ASTContext.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/ASTMatchers/ASTMatchFinder.h>
#include <clang/ASTMatchers/ASTMatchers.h>
#include <clang/ASTMatchers/ASTMatchersInternal.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <ctype.h>
#include <ext/alloc_traits.h>
#include <llvm/ADT/Optional.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/ADT/VariadicFunction.h>
#include <llvm/Support/Regex.h>
#include <stddef.h>
#include <stdlib.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace csabase { class Visitor; }

using namespace clang;
using namespace csabase;
using namespace clang::ast_matchers;

// ----------------------------------------------------------------------------

static std::string const check_name("spell-check");

// ----------------------------------------------------------------------------

#if SPELL_CHECK

#include <aspell.h>

namespace
{

struct data
    // Data holding seen comments.
{
    typedef std::vector<SourceRange> Ranges;
    typedef std::map<std::string, Ranges> Comments;
    Comments d_comments;

    void append(Analyser& analyser, SourceRange range);
};

void data::append(Analyser& analyser, SourceRange range)
{
    SourceManager& m = analyser.manager();
    data::Ranges& c = d_comments[m.getFilename(range.getBegin())];
    if (c.size() != 0 && areConsecutive(m, c.back(), range)) {
        c.back().setEnd(range.getEnd());
    } else {
        c.push_back(range);
    }
}

struct report
    // Callback object for inspecting files.
{
    Analyser& d_analyser;                   // Analyser object.

    report(Analyser& analyser);
        // Create a 'report' object, accessing the specified 'analyser'.

    void operator()(SourceRange range);
        // The specified comment 'range' is added to the stored data.

    void operator()();
        // Inspect all comments.

    void check_spelling(SourceRange range);
        // Spell check the comment.

    void break_for_spelling(std::vector<SourceRange>* words,
                            SourceRange               range);
        // Break the comment at the specified 'range' into words suitable for
        // spell checking and load them into the specified 'words' vector.

    void check_parameters();
        // Check that function parameters consist of real words.

    void match_parameter(const BoundNodes &nodes);
        // Callback for named function parameters.

    typedef std::map<std::string, std::vector<SourceRange> > Errors;
    Errors d_errors;

    AspellSpeller *spell_checker;
};

report::report(Analyser& analyser)
: d_analyser(analyser)
, spell_checker(0)
{
}

void report::operator()(SourceRange range)
{
    d_analyser.attachment<data>().append(d_analyser, range);
}

void report::operator()()
{
    AspellConfig *spell_config = new_aspell_config();
    aspell_config_replace(spell_config, "lang", "en_US");
    aspell_config_replace(spell_config, "size", "90");
    aspell_config_replace(spell_config, "ignore-case", "true");
    aspell_config_replace(spell_config, "add-extra-dicts", "en_CA");
    aspell_config_replace(spell_config, "add-extra-dicts", "en_GB");
    aspell_config_replace(spell_config, "guess", "true");
    AspellCanHaveError *possible_err = new_aspell_speller(spell_config);
    if (aspell_error_number(possible_err) != 0) {
        SourceManager& m = d_analyser.manager();
        d_analyser.report(m.getLocForStartOfFile(m.getMainFileID()),
                          check_name, "SP02",
                          "Cannot start spell checker: %0")
            << aspell_error_message(possible_err);
            return;                                                   // RETURN
    }
    spell_checker = to_aspell_speller(possible_err);
    llvm::SmallVector<llvm::StringRef, 10> good_words;
    llvm::StringRef(d_analyser.config()->value("dictionary")).
        split(good_words, " ", -1, false);
    for (size_t i = 0; i < good_words.size(); ++i) {
        aspell_speller_add_to_session(
            spell_checker, good_words[i].data(), good_words[i].size());
    }

    for (const auto& file_comment : d_analyser.attachment<data>().d_comments) {
        const std::string &file_name = file_comment.first;
        if (d_analyser.is_component(file_comment.first)) {
            for (const auto& comment : file_comment.second) {
                check_spelling(comment);
            }
        }
    }

    size_t limit = std::strtoul(
        d_analyser.config()->value("spelled_ok_count").c_str(),
        0, 10);

    Errors::const_iterator b = d_errors.begin();
    Errors::const_iterator e = d_errors.end();
    for (; b != e; ++b) {
        const std::vector<SourceRange>& locs = b->second;
        if (limit == 0 || locs.size() < limit) {
            for (size_t j = 0; j < locs.size(); ++j) {
                d_analyser.report(locs[j].getBegin(), check_name, "SP01",
                                  "Misspelled word '%0'")
                    << b->first
                    << locs[j];
            }
        }
    }

    check_parameters();

    delete_aspell_config(spell_config);
}

void
report::break_for_spelling(std::vector<SourceRange>* words, SourceRange range)
{
    llvm::StringRef comment = d_analyser.get_source(range, true);
    words->clear();
    bool in_single_quotes = false;
    bool in_double_quotes = false;
    bool in_block = false;
    size_t start_of_last_block = 0;
    static llvm::Regex code("^[[:blank:]]*//[.][.]$", llvm::Regex::Newline);
    llvm::SmallVector<llvm::StringRef, 7> matches;
    size_t code_pos = comment.size() + 1;
    // If the comment has a "//.." line, note its end position.
    if (code.match(comment, &matches)) {
        llvm::StringRef m = matches[0];
        code_pos = comment.find(m) + m.size() - 1;
    }
    static const llvm::StringRef punct("!:;,.?");
    static const std::vector<llvm::StringRef> empty;
    for (size_t i = 0; i <= comment.size(); ++i) {
        if (i == code_pos) {
            llvm::StringRef tail = comment.drop_front(i);
            // At a "//.." line, go to the next one.
            if (code.match(tail, &matches)) {
                llvm::StringRef m = matches[0];
                i += tail.find(m) + m.size() - 1;
                tail = comment.drop_front(i);
            }
            // If the contract has another "//.." line, note its end position.
            if (code.match(tail, &matches)) {
                llvm::StringRef m = matches[0];
                code_pos = i + tail.find(m) + m.size() - 1;
            } else {
                code_pos = comment.size() + 1;
            }
        }

        unsigned char c =
            i == comment.size() ? ' ' : static_cast<unsigned char>(comment[i]);
        if (c == '\'') {
            if (!in_double_quotes) {
                in_single_quotes = !in_single_quotes;
                if (!in_block) {
                    in_block = true;
                    start_of_last_block = i;
                }
            }
        } else if (c == '"') {
            if (!in_single_quotes) {
                in_double_quotes = !in_double_quotes;
                if (!in_block) {
                    in_block = true;
                    start_of_last_block = i;
                }
            }
        } else if (!in_single_quotes && !in_double_quotes) {
            if (c == '/' &&
                (i == 0 || comment[i - 1] == '\n') &&
                comment.substr(i).startswith("//@AUTHOR:")) {
                size_t j = comment.substr(i).find("\n//\n");
                if (j != comment.npos) {
                    i += j;
                }
            } else if (std::isspace(c)) {
                if (in_block) {
                    in_block = false;
                    bool saw_lower = false;
                    size_t last = i;
                    bool found = true;
                    for (size_t j = start_of_last_block; found && j < last;
                         ++j) {
                        c = static_cast<unsigned char>(comment[j]);
                        if (!std::isalpha(c)) {
                            if (j != i - 1) {
                                found = false;
                            } else if (punct.find(c) != punct.npos) {
                                --last;
                            } else {
                                found = false;
                            }
                        } else if (std::islower(c)) {
                            saw_lower = true;
                        } else if (std::isupper(c) && saw_lower) {
                            found = false;
                        }
                    }
                    if (found) {
                        words->push_back(SourceRange(
                            range.getBegin().getLocWithOffset(
                                start_of_last_block),
                            range.getBegin().getLocWithOffset(last)));
                    }
                    start_of_last_block = 0;
                }
            } else {
                if (!in_block) {
                    in_block = true;
                    start_of_last_block = i;
                }
            }
        }
    }
}

void report::check_spelling(SourceRange comment)
{
    std::vector<SourceRange> words;
    break_for_spelling(&words, comment);
    for (size_t i = 0; i < words.size(); ++i) {
        llvm::StringRef word = d_analyser.get_source(words[i], true);
        if (!aspell_speller_check(
                 spell_checker, word.data(), word.size())) {
            d_errors[word.lower()].push_back(words[i]);
        }
    }
}

const internal::DynTypedMatcher &
parameter_matcher()
    // Return an AST matcher which looks for named parameters.
{
    static const internal::DynTypedMatcher matcher = decl(forEachDescendant(
        parmVarDecl(matchesName(".")).bind("parm")
    ));
    return matcher;
}

void report::match_parameter(const BoundNodes &nodes)
{
    const ParmVarDecl *parm = nodes.getNodeAs<ParmVarDecl>("parm");
    if (d_analyser.is_component(parm)) {
        llvm::StringRef name = parm->getName();
        static llvm::Regex words("[[:digit:]_]*([[:alpha:]][[:lower:]]*)");
        llvm::SmallVector<llvm::StringRef, 7> matches;
        size_t pos = 0;
        while (words.match(name.substr(pos), &matches)) {
            llvm::StringRef word = matches[1];
            pos = name.find(word, pos);
            if (!aspell_speller_check(
                spell_checker, word.data(), word.size())) {
                d_analyser.report(
                        parm->getLocation().getLocWithOffset(pos),
                        check_name, "SP03",
                        "Parameter name contains misspelled word '%0'")
                    << word;
            }
            pos += word.size();
        }
    }
}

void report::check_parameters()
{
    MatchFinder mf;
    OnMatch<report, &report::match_parameter> m1(this);
    mf.addDynamicMatcher(parameter_matcher(), &m1);
    mf.match(*d_analyser.context()->getTranslationUnitDecl(),
             *d_analyser.context());
}

void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
    // Hook up the callback functions.
{
    analyser.onTranslationUnitDone += report(analyser);
    observer.onComment             += report(analyser);
}

}  // close anonymous namespace

#else   // SPELL_CHECK

void subscribe(Analyser&, Visitor&, PPObserver&)
    // Do nothing
{
}

#endif  // SPELL_CHECK

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

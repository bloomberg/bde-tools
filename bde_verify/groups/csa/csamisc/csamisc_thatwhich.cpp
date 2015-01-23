// csafmt_thatwhich.cpp                                               -*-C++-*-

#include <llvm/ADT/StringExtras.h>
#include <clang/AST/Decl.h>
#include <csabase_analyser.h>
#include <csabase_debug.h>
#include <csabase_registercheck.h>
#include <csabase_report.h>
#include <csabase_util.h>
#include <string>
#include <unordered_set>
#include <vector>

using namespace clang;
using namespace csabase;

static std::string const check_name("that-which");

namespace std
{

template <>
struct hash<llvm::StringRef>
{
    size_t operator()(llvm::StringRef s) const
    {
        return llvm::HashString(s);
    }
};

}

namespace
{

struct Word
{
    llvm::StringRef word;
    size_t          offset;
    bool            is_comma         : 1;
    bool            is_em_dash       : 1;
    bool            is_period        : 1;
    bool            is_question_mark : 1;
    bool            is_semicolon     : 1;
    bool            is_copyright     : 1;
    bool            is_preposition   : 1;
    bool            is_that          : 1;
    bool            is_which         : 1;

    Word();

    void set(llvm::StringRef s, size_t position);
};

Word::Word()
: word()
, offset(llvm::StringRef::npos)
, is_comma(false)
, is_em_dash(false)
, is_period(false)
, is_question_mark(false)
, is_semicolon(false)
, is_copyright(false)
, is_preposition(false)
, is_that(false)
, is_which(false)
{
}

void Word::set(llvm::StringRef s, size_t position)
{
    static std::unordered_set<llvm::StringRef> prepositions {
        "about",   "above",      "across",  "after",   "against", "among",
        "around",  "at",         "before",  "behind",  "below",   "beneath",
        "beside",  "besides",    "between", "beyond",  "by",      "during",
        "for",     "from",       "in",      "inside",  "into",    "near",
        "of",      "on",         "out",     "outside", "over",    "since",
        "through", "throughout", "till",    "to",      "toward",  "under",
        "until",   "up",         "upon",    "with",    "without",
    };

    word             = s;
    offset           = position;
    is_comma         = s.equals(",");
    is_em_dash       = s.equals("-");
    is_period        = s.equals(".");
    is_question_mark = s.equals("?");
    is_semicolon     = s.equals(";");
    is_copyright     = s.equals_lower("copyright");
    is_that          = s.equals_lower("that");
    is_which         = s.equals_lower("which");
    is_preposition   = prepositions.count(s) || s.endswith("ing");
}

struct data
{
    std::vector<SourceRange> comments;
};

struct report : Report<data>
{
    using Report<data>::Report;

    void operator()();
    void operator()(SourceRange range);

    void that_which(SourceRange range);
    void split(std::vector<Word> *words, llvm::StringRef comment);
};

void report::split(std::vector<Word> *words, llvm::StringRef comment)
{
    words->clear();
    bool in_single_quotes = false;
    bool last_char_was_backslash = false;
    bool in_word = false;
    size_t start_of_last_word = 0;
    bool in_code = false;

    for (size_t i = 0; i < comment.size(); ++i) {
        if (i > 0 && comment[i - 1] == '\n') {
            while (comment[i] == ' ' && i < comment.size()) {
                ++i;
            }
        }
        llvm::StringRef sub = comment.substr(i);
        if (sub.startswith("//..\n")) {
            i += 4 - 1;
            if (in_code) {
                words->push_back(Word());
                words->back().set(",", i);
                in_code = false;
            } else {
                in_code = true;
            }
            continue;
        }
        if (in_code) {
            continue;
        }
        if (sub.startswith("//")) {
            i += 2 - 1;
            continue;
        }
        unsigned char c = static_cast<unsigned char>(comment[i]);
        bool is_id = std::isalnum(c) || c == '_' || c == '-';
        if (in_word) {
            if (!is_id) {
                words->back().set(comment.slice(start_of_last_word, i),
                                  start_of_last_word);
            }
        } else if (is_id) {
            start_of_last_word = i;
            words->push_back(Word());
            words->back().set(comment.substr(start_of_last_word),
                              start_of_last_word);
        }
        if (!is_id) {
            last_char_was_backslash = c == '\\' && !last_char_was_backslash;
            if (c == '\'') {
                if (in_word) {
                    if (in_single_quotes) {
                        in_single_quotes = false;
                    } else {
                        is_id = true;
                    }
                } else if (!last_char_was_backslash) {
                    in_single_quotes = !in_single_quotes;
                }
            }
        }
        in_word = is_id;
        if (!is_id) {
            if (!std::isspace(c)) {
                words->push_back(Word());
                words->back().set(comment.slice(i, i + 1), i);
            }
        }
    }
}

void report::that_which(SourceRange range)
{
    llvm::StringRef c = a.get_source(range);
    std::vector<Word> w;
    split(&w, c);

    for (size_t i = 0; i < w.size(); ++i) {
        if (w[i].is_copyright) {
            break;
        }
        if (i == 0) {
            continue;
        }
        if (w[i].is_which &&
            !w[i - 1].is_comma &&
            !w[i - 1].is_that &&
            !w[i - 1].is_preposition) {
            a.report(range.getBegin().getLocWithOffset(w[i].offset),
                     check_name, "TW01",
                     "Possibly prefer 'that' over 'which'");
        }
#if 0  // We haven't found a good ", that" rule yet.
        size_t np = 0;
        size_t nd = 0;
        if (w[i].is_that && w[i - 1].is_comma) {
            size_t prev_comma = i;
            for (size_t j = 0; j < i - 1; ++j) {
                if (w[j].is_comma) {
                    prev_comma = j;
                    np = 0;
                    nd = 0;
                } else if (w[j].is_period ||
                           w[j].is_semicolon ||
                           w[j].is_question_mark) {
                    ++np;
                } else if (w[j].is_em_dash) {
                    ++nd;
                }
            }
            if (prev_comma == i || np || nd & 1) {
                a.report(range.getBegin().getLocWithOffset(w[i].offset),
                         check_name, "TW02",
                         "Possibly incorrect comma before 'that'");
            }
        }
#endif
    }
}

void report::operator()(SourceRange range)
{
    if (a.is_component(range.getBegin())) {
        if (d.comments.size() && areConsecutive(m, d.comments.back(), range)) {
            d.comments.back().setEnd(range.getEnd());
        } else {
            d.comments.push_back(range);
        }
    }
}

void report::operator()()
{
    for (const auto& r : d.comments) {
        that_which(r);
    }
}

void subscribe(Analyser& analyser, Visitor& visitor, PPObserver& observer)
    // Hook up the callback functions.
{
    analyser.onTranslationUnitDone += report(analyser);
    observer.onComment             += report(analyser);
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &subscribe);

// ----------------------------------------------------------------------------
// Copyright (C) 2015 Bloomberg Finance L.P.
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

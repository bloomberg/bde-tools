// csafmt_comments.cpp                                                -*-C++-*-

#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <ext/alloc_traits.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/ADT/Twine.h>
#include <llvm/Support/Regex.h>
#include <stddef.h>
#include <stdlib.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("comments");

// ----------------------------------------------------------------------------

namespace
{

struct comments
    // Data holding seen comments.
{
    typedef std::vector<SourceRange> Ranges;
    typedef std::map<std::string, Ranges> Comments;
    Comments d_comments;

    typedef std::set<Range> Reported;
    Reported d_reported;

    void append(Analyser& analyser, SourceRange range);
};

void comments::append(Analyser& analyser, SourceRange range)
{
    SourceManager& m = analyser.manager();
    comments::Ranges& c = d_comments[m.getFilename(range.getBegin())];
    if (c.size() != 0 && areConsecutive(m, c.back(), range)) {
        c.back().setEnd(range.getEnd());
    } else {
        c.push_back(range);
    }
}

struct files
    // Callback object for inspecting files.
{
    Analyser& d_analyser;                   // Analyser object.

    files(Analyser& analyser);
        // Create a 'files' object, accessing the specified 'analyser'.

    void operator()(SourceRange range);
        // The specified comment 'range' is added to the stored data.

    void operator()();
        // Inspect all comments.

    void check_fvs(SourceRange range);
        // Warn about comment containing "fully value semantic".

    void check_pp(SourceRange range);
        // Warn about comment containing "pure procedure(s)".

    void check_mr(SourceRange range);
        // Warn about comment containing "modifiable reference".

    void check_bubble(SourceRange range);
        // Warn about comment containing badly formed inheritance diagram.

    void report_bubble(const Range &r, llvm::StringRef text);
        // Warn about a single bad inheritance bubble at the specified 'r'
        // containing the specified 'text'.

    void check_wrapped(SourceRange range);
        // Warn about comment containing incorrectly wrapped text.

    void check_purpose(SourceRange range);
        // Warn about incorrectly formatted @PURPOSE line.

    void check_description(SourceRange range);
        // Warn if the @DESCRIPTION doesn't contain the component name.
};

files::files(Analyser& analyser)
: d_analyser(analyser)
{
}

void files::operator()(SourceRange range)
{
    d_analyser.attachment<comments>().append(d_analyser, range);
}

void files::operator()()
{
    comments::Comments& file_comments =
        d_analyser.attachment<comments>().d_comments;

    for (comments::Comments::iterator file_begin = file_comments.begin(),
                                      file_end   = file_comments.end(),
                                      file_itr   = file_begin;
         file_itr != file_end;
         ++file_itr) {
        const std::string &file_name = file_itr->first;
        if (!d_analyser.is_component(file_name)) {
            continue;
        }
        comments::Ranges& comments = file_itr->second;
        for (comments::Ranges::iterator comments_begin = comments.begin(),
                                        comments_end   = comments.end(),
                                        comments_itr   = comments_begin;
             comments_itr != comments_end;
             ++comments_itr) {
            check_fvs(*comments_itr);
            check_pp(*comments_itr);
            check_mr(*comments_itr);
            check_bubble(*comments_itr);
            check_wrapped(*comments_itr);
            check_purpose(*comments_itr);
            check_description(*comments_itr);
        }
    }
}

llvm::Regex fvs(
    "fully" "[^_[:alnum:]]*" "value" "[^_[:alnum:]]*" "semantic",
    llvm::Regex::IgnoreCase);

void files::check_fvs(SourceRange range)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::StringRef comment = d_analyser.get_source(range, true);

    size_t offset = 0;
    llvm::StringRef s;
    while (fvs.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + text.size();
        d_analyser.report(range.getBegin().getLocWithOffset(matchpos),
                          check_name, "FVS01",
                          "The term \"%0\" is deprecated; use a description "
                          "appropriate to the component type")
            << text
            << getOffsetRange(range, matchpos, offset - 1 - matchpos);
    }
}

llvm::Regex pp(
    "pure" "[^_[:alnum:]]*" "procedure(s?)",
    llvm::Regex::IgnoreCase);

void files::check_pp(SourceRange range)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::StringRef comment = d_analyser.get_source(range, true);

    size_t offset = 0;
    llvm::StringRef s;
    while (pp.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + text.size();
        d_analyser.report(range.getBegin().getLocWithOffset(matchpos),
                          check_name, "PP01",
                          "The term \"%0\" is deprecated; use 'function%1'")
            << text
            << (matches[1].size() == 1 ? "s" : "")
            << getOffsetRange(range, matchpos, offset - 1 - matchpos);
    }
}

llvm::Regex mr(
    "((non-?)?" "modifiable)" "[^_[:alnum:]]*" "(references?)",
    llvm::Regex::IgnoreCase);

void files::check_mr(SourceRange range)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::StringRef comment = d_analyser.get_source(range, true);

    size_t offset = 0;
    llvm::StringRef s;
    while (mr.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + text.size();
        d_analyser.report(range.getBegin().getLocWithOffset(matchpos),
                          check_name, "MOR01",
                          "The term \"%0 %1\" is deprecated; use \"%1 "
                          "offering %0 access\"")
            << matches[1]
            << matches[3]
            << getOffsetRange(range, matchpos, offset - 1 - matchpos);
    }
}


llvm::Regex bad_bubble(
                             "([(]" "[[:blank:]]*"              // 1
                                    "([[:alnum:]_:]+)"          // 2
                                    "[[:blank:]]*"
                             "[)])" ".*\n"
        "//" "([[:blank:]]+)" "[|]" "[[:blank:]]*.*\n"          // 3
    "(" "//" "\\3"            "[|]" "[[:blank:]]*.*\n" ")*"     // 4
        "//" "\\3"            "[V]" "[[:blank:]]*.*\n"     
        "//" "[[:blank:]]*"  "([(]" "[[:blank:]]*"              // 5
                                    "([[:alnum:]_:]+)"          // 6
                                    "[[:blank:]]*"
                              "[)])",
    llvm::Regex::Newline);

llvm::Regex good_bubble(
    "//( *)" " [,](-+)[.]" "\n"
    "//\\1"  "[(]  .* [)]" "\n"
    "//\\1"  " [`]\\2[']"  "$",
    llvm::Regex::Newline);

std::string bubble(llvm::StringRef s, size_t column)
{
    std::string lead = "\n//" + std::string(column > 4 ? column - 4 : 1, ' ');
    return lead + " ,"  + std::string(s.size() + 1, '-') + "." +
           lead + "(  " + s.str()                        + " )" +
           lead + " `"  + std::string(s.size() + 1, '-') + "'";
}

void files::report_bubble(const Range &r, llvm::StringRef text)
{
    comments::Reported& reported_ranges =
        d_analyser.attachment<comments>().d_reported;
    if (!reported_ranges.count(r)) {
        reported_ranges.insert(r);
        d_analyser.report(r.from().location(), check_name, "BADB01",
                          "Incorrectly formed inheritance bubble")
            << SourceRange(r.from().location(), r.to().location());
        d_analyser.report(r.from().location(), check_name, "BADB01",
                          "Correct format is%0",
                          false, DiagnosticsEngine::Note)
            << bubble(text, r.from().column());
    }
}

void files::check_bubble(SourceRange range)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::StringRef comment = d_analyser.get_source(range, true);

    size_t offset = 0;
    llvm::StringRef s;
    size_t left_offset = comment.size();
    size_t leftmost_position = comment.size();

    while (good_bubble.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + text.size();
        if (matches[1].size() < left_offset) {
            left_offset = matches[1].size();
            leftmost_position =
                matchpos + comment.drop_front(matchpos).find('\n') + 1;
        }
    }
    if (left_offset != 2 && left_offset != comment.size()) {
        d_analyser.report(
                range.getBegin().getLocWithOffset(leftmost_position + 4),
                check_name, "AD01",
                "Display should begin in column 5 (from start of comment)");
    }

    offset = 0;
    while (bad_bubble.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + matches[1].size();

        Range b1(d_analyser.manager(),
                 getOffsetRange(range, matchpos, matches[1].size() - 1));
        report_bubble(b1, matches[2]);

        Range b2(
            d_analyser.manager(),
            getOffsetRange(range,
                           matchpos + matches[0].size() - matches[5].size(),
                           matches[5].size() - 1));
        report_bubble(b2, matches[6]);
    }
}

std::pair<size_t, size_t> bad_wrap_pos(llvm::StringRef text, size_t ll)
    // Return the position of a word in the specified 'text' that can fit on
    // the previous line, where line length is the specified 'll'.  If there is
    // no such word, return a pair of 'npos'.
{
    size_t offset = 0;
    for (;;) {
        size_t b = text.find("// ", offset);
        if (b == text.npos) {
            break;
        }
        size_t e = text.find("\n", b);
        if (e == text.npos) {
            e = text.size();
        }
        offset = e;
        size_t nextb = text.find("// ", e);
        if (nextb == text.npos) {
            break;
        }
        size_t nexte = text.find("\n", nextb);
        if (nexte == text.npos) {
            nexte = text.size();
        }
        enum State { e_C, e_Q1, e_Q2 } state = e_C;
        size_t i;
        for (i = nextb + 3; i < nexte; ++i) {
            char c = text[i];
            if (state == e_C) {
                if (c == ' ') {
                    break;
                }
                state = c == '\'' && text[i - 1] == ' ' ? e_Q1 :
                        c == '"'  && text[i - 1] == ' ' ? e_Q2 :
                                                          e_C;
            }
            else if (state == e_Q1) {
                state = c == '\'' ? e_C : e_Q1;
            }
            else if (state == e_Q2) {
                state = c == '"'  ? e_C : e_Q2;
            }
        }

        if (e > 0 && text[e - 1] == '.') {
            // Double space after periods.
            ++e;
        }

        if ((e - (b + 3)) + (i - (nextb + 3)) + 1 <= ll &&
            text.substr(nextb + 3, i - (nextb + 3)).find_first_of(
                "abcdefghijklmnopqrstuvwxyz") != text.npos) {
            return std::make_pair(nextb + 3, i - 1);
        }
    }
    return std::make_pair(text.npos, text.npos);
}

llvm::Regex display("^( *//[.][.])$", llvm::Regex::Newline);

void get_displays(llvm::StringRef text,
                  llvm::SmallVector<std::pair<size_t, size_t>, 7>* displays)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;

    size_t offset = 0;
    llvm::StringRef s;
    int n = 0;
    displays->clear();
    while (display.match(s = text.drop_front(offset), &matches)) {
        llvm::StringRef d = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, d);
        size_t matchpos = offset + m.first;
        offset = matchpos + d.size();

        if (n++ & 1) {
            displays->back().second = matchpos;
        } else {
            displays->push_back(std::make_pair(matchpos, text.size()));
        }
    }
}

llvm::Regex block_comment("((^ *// [^[ ].*$\n?){2,})", llvm::Regex::Newline);
llvm::Regex banner("^ *(// ?([-=_] ?)+)$", llvm::Regex::Newline);
llvm::Regex copyright("Copyright.*[[:digit:]]{4}", llvm::Regex::IgnoreCase);

void files::check_wrapped(SourceRange range)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::SmallVector<llvm::StringRef, 7> banners;
    llvm::SmallVector<std::pair<size_t, size_t>, 7> displays;
    llvm::StringRef comment = d_analyser.get_source(range, true);

    if (copyright.match(comment) && banner.match(comment)) {
        return;                                                       // RETURN
    }

    get_displays(comment, &displays);

    size_t dnum = 0;
    size_t offset = 0;
    llvm::StringRef s;
    size_t wrap_slack =
        std::strtoul(d_analyser.config()->value("wrap_slack",
                                                range.getBegin()).c_str(),
                     0, 10);
    while (block_comment.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + text.size();

        while (dnum < displays.size() && displays[dnum].second < matchpos) {
            ++dnum;
        }
        if (   dnum < displays.size()
            && displays[dnum].first <= matchpos
            && matchpos <= displays[dnum].second) {
            offset = displays[dnum].second;
            continue;
        }

        size_t n = text.find('\n');
        size_t c = text.find("//", n);
        size_t ll = banner.match(text, &banners) ? banners[1].size() - 3 :
                                                   77 - (c - n);

        std::pair<size_t, size_t> bad_pos =
            bad_wrap_pos(text, ll - wrap_slack);
        if (bad_pos.first != text.npos) {
            d_analyser.report(
                range.getBegin().getLocWithOffset(matchpos + bad_pos.first),
                check_name, "BW01",
                "This text fits on the previous line - consider using bdewrap")
                << getOffsetRange(range,
                                  matchpos + bad_pos.first,
                                  bad_pos.second - bad_pos.first);
        }
    }
}

llvm::Regex loose_purpose(
    "^//"
    "[[:blank:]]*"
    "@"
    "[[:blank:]]*"
    "PURPOSE"
    "[[:blank:]]*"
    ":?"
    "[[:blank:]]*"
    "(([.]*[^.])*)([.]*)",
    llvm::Regex::Newline | llvm::Regex::IgnoreCase);

llvm::Regex strict_purpose(
    "^//@PURPOSE: [^[:blank:]].*[^.[:blank:]][.]$",
    llvm::Regex::Newline);

void files::check_purpose(SourceRange range)
{
    llvm::SmallVector<llvm::StringRef, 7> matches;
    llvm::StringRef comment = d_analyser.get_source(range, true);

    size_t offset = 0;
    llvm::StringRef s;
    while (loose_purpose.match(s = comment.drop_front(offset), &matches)) {
        llvm::StringRef text = matches[0];
        std::pair<size_t, size_t> m = mid_match(s, text);
        size_t matchpos = offset + m.first;
        offset = matchpos + text.size();

        if (!strict_purpose.match(text)) {
            std::string expected =
                "//@PURPOSE: " + matches[1].trim().str() + ".";
            std::pair<size_t, size_t> m = mid_mismatch(text, expected);
            d_analyser.report(
                    range.getBegin().getLocWithOffset(matchpos + m.first),
                    check_name, "PRP01",
                    "Invalid format for @PURPOSE line")
                << text;
            d_analyser.report(
                range.getBegin().getLocWithOffset(matchpos + m.first),
                    check_name, "PRP01",
                    "Correct format is\n%0",
                    false, DiagnosticsEngine::Note)
                << expected;
        }
    }
}

llvm::Regex classes(
    "^// *(@CLASSES: *)?" "("
                     "[[:alpha:]][[:alnum:]_]*"
               "(" "::[[:alpha:]][[:alnum:]_]*" ")*"
           ")" "( *: *[^:].*)?");

void files::check_description(SourceRange range)
{
    llvm::StringRef comment = d_analyser.get_source(range, true);
    size_t cpos = comment.find("//@CLASSES:");
    size_t end = comment.find("//\n", cpos);
    if (end == comment.npos) {
        end = comment.size();
    }
    size_t dpos = comment.find("//@DESCRIPTION:", cpos);
    llvm::StringRef desc = comment.slice(dpos, comment.find("\n//\n", dpos));

    if (cpos == comment.npos) {
        return;                                                       // RETURN
    }

    if (d_analyser.get_source_line(range.getBegin().getLocWithOffset(cpos))
                .trim() != "//@CLASSES:") {
        d_analyser.report(range.getBegin().getLocWithOffset(cpos + 11),
                          check_name, "CLS01",
                          "'//@CLASSES:' line should contain no other text "
                          "(classes go on subsequent lines, one per line)");
    }
    else {
        cpos = comment.find('\n', cpos) + 1;
    }

    while (cpos < end) {
        llvm::SmallVector<llvm::StringRef, 7> matches;
        if (!classes.match(comment.slice(cpos, end), &matches)) {
            d_analyser.report(range.getBegin().getLocWithOffset(cpos),
                              check_name, "CLS03",
                              "Badly formatted class line; should be "
                              "'//  class: description'");
        } else {
            cpos += comment.slice(cpos, end).find(matches[2]) +
                    matches[2].size();
            if (matches[4].empty()) {
                d_analyser.report(range.getBegin().getLocWithOffset(cpos),
                                  check_name, "CLS02",
                                  "Class name must be followed by "
                                  "': description'");
            }
            std::string qc = ("'" + matches[2] + "'").str();
            if (dpos != comment.npos && desc.find(qc) == desc.npos) {
                d_analyser.report(range.getBegin().getLocWithOffset(dpos),
                                  check_name, "DC01",
                                  "Description should contain single-quoted "
                                  "class name %0")
                    << qc;
            }
        }
        cpos = comment.find('\n', cpos);
        if (cpos != comment.npos) {
            ++cpos;
        }
    }
}

void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
    // Hook up the callback functions.
{
    analyser.onTranslationUnitDone += files(analyser);
    observer.onComment             += files(analyser);
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

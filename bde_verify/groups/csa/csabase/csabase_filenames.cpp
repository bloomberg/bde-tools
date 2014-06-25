// csabase_filenames.cpp                                              -*-C++-*-

#include <csabase_filenames.h>
#include <llvm/Support/Path.h>
#include <stddef.h>

// -----------------------------------------------------------------------------

namespace
{

llvm::StringRef subdir(llvm::StringRef path, llvm::StringRef dir)
    // Return the prefix of the specified 'path' whose final segement is the
    // specified 'dir', or 'path' if no such prefix exists.  The returned value
    // ends with a directory separator.
{
    size_t n = path.rfind(dir);
    while (n != 0 && n != path.npos) {
        if ((path.size() > n + dir.size() &&
             !llvm::sys::path::is_separator(path[n + dir.size()])) ||
            !llvm::sys::path::is_separator(path[n - 1])) {
            n = path.slice(0, n - 1).rfind(dir);
        } else {
            path = path.slice(0, n + dir.size() + 1);
            break;
        }
    }
    return path;
}

}

void csabase::FileName::reset(llvm::StringRef sr)
{
    full_ = sr;
    extension_ = sr.slice(sr.rfind('.'), sr.npos);
    prefix_ = sr.drop_back(extension_.size());
    directory_ = prefix_;
    while (directory_.size() > 0 &&
           !llvm::sys::path::is_separator(directory_.back())) {
        directory_ = directory_.drop_back(1);
    }
    name_ = sr.drop_front(directory_.size());
    extra_ = name_.slice(name_.find('.'), name_.rfind('.'));
    component_ = name_.slice(0, name_.find('.'));

    size_t under = component_.find('_');
    package_ = component_.slice(0, under);
    group_   = package_.slice(0, 3);
    if (under == 1) {
        under = component_.find('_', under + 1);
        package_ = component_.slice(0, under);
        if (package_[0] != 'a') {
            group_ = package_.slice(0, 5);
        } else {
            group_ = package_.slice(2, 5);
        }
    }
    pkgdir_ = subdir(directory_, package_);
    grpdir_ = subdir(pkgdir_, group_);
}

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

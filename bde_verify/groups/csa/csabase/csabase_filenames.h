// csabase_filenames.h                                                -*-C++-*-

#ifndef INCLUDED_CSABASE_FILENAMES
#define INCLUDED_CSABASE_FILENAMES

#include <llvm/ADT/StringRef.h>
#include <string>

// ----------------------------------------------------------------------------

namespace csabase
{
class FileName
{
    // This class facilitates dealing with the various pieces of file names.
    //
    // A library component file is expected to have a name like
    //     /initial/path/groups/GRP/GRPPKG/GRPPKG_COMP.t.cpp
    // and would be broken up as
    //     component   GRPPKG_COMP
    //     directory   /initial/path/groups/GRP/GRPPKG/
    //     extension   .cpp
    //     extra       .t
    //     full        /initial/path/groups/GRP/GRPPKG/GRPPKG_COMP.t.cpp
    //     group       GRP
    //     grpdir      /initial/path/groups/GRP/
    //     name        GRPPKG_COMP.t.cpp
    //     package     GRPPKG
    //     pkgdir      /initial/path/groups/GRP/GRPPKG/
    //     prefix      /initial/path/groups/GRP/GRPPKG/GRPPKG_COMP.t
    //     tag         (empty)
    //
    // An application component file is expected to have a name like
    //     /initial/path/applications/m_APPL/m_APPL_COMP.t.cpp
    // and would be broken up as
    //     component   m_APPL_COMP
    //     directory   /initial/path/applications/m_APPL/
    //     extension   .cpp
    //     extra       .t
    //     full        /initial/path/applications/m_APPL/m_APPL_COMP.t.cpp
    //     group       (empty)
    //     grpdir      (empty)
    //     name        m_APPL_COMP.t.cpp
    //     package     m_APPL
    //     pkgdir      /initial/path/applications/m_APPL/
    //     prefix      /initial/path/applications/m_APPL/m_APPL_COMP.t
    //     tag         m
    //
    // A service component file is expected to have a name like
    //     /initial/path/services/s_SRVC/s_SRVC_COMP.t.cpp
    // and is broken up like an application name.
    //
    // An adapter component file is expected to have a name like
    //     /initial/path/services/a_ADPT/a_ADPT_COMP.t.cpp
    // and is broken up like an application name.

public:
    FileName() { }
    FileName(llvm::StringRef sr) { reset(sr); }
    void reset(llvm::StringRef sr = llvm::StringRef());

    llvm::StringRef component() const { return component_; }
    llvm::StringRef directory() const { return directory_; }
    llvm::StringRef extension() const { return extension_; }
    llvm::StringRef extra()     const { return extra_;     }
    llvm::StringRef full()      const { return full_;      }
    llvm::StringRef group()     const { return group_;     }
    llvm::StringRef grpdir()    const { return grpdir_;    }
    llvm::StringRef name()      const { return name_;      }
    llvm::StringRef package()   const { return package_;   }
    llvm::StringRef pkgdir()    const { return pkgdir_;    }
    llvm::StringRef prefix()    const { return prefix_;    }
    llvm::StringRef tag()       const { return tag_;       }

private:
    llvm::StringRef component_;
    llvm::StringRef directory_;
    llvm::StringRef extension_;
    llvm::StringRef extra_;
    std::string     full_;
    llvm::StringRef group_;
    llvm::StringRef grpdir_;
    llvm::StringRef name_;
    llvm::StringRef package_;
    llvm::StringRef pkgdir_;
    llvm::StringRef prefix_;
    llvm::StringRef tag_;
};
}

//-----------------------------------------------------------------------------

#endif

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

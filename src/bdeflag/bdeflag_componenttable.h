// bdeflag_componenttable.h                                           -*-C++-*-

#ifndef INCLUDED_BDEFLAG_COMPONENTTABLE
#define INCLUDED_BDEFLAG_COMPONENTTABLE

#ifndef INCLUDED_BSLS_IDENT
#include <bsls_ident.h>
#endif
BSLS_IDENT("$Id: $")

//@PURPOSE: Provide managment of file names being processed by bdeflag.
//
//@CLASSES:
//    ComponentTable: Manage file names of components processed by bdeflag.
//
//@AUTHOR: Bill Chapman
//
//@DESCRIPTION: It is necessary for bdeflag to process files a component at
// a time in order to enfoce likeness of function signatures.  This list
// enables the client to access the components in the order in which they
// were first mentioned, but grouping files by component, and processing
// .h files before corresponding .cpp files.

#ifndef INCLUDED_BSL_IOSTREAM
#include <bsl_iostream.h>
#endif

#ifndef INCLUDED_BSL_SET
#include <bsl_set.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#endif

#ifndef INCLUDED_BSL_VECTOR
#include <bsl_vector.h>
#endif

namespace BloombergLP {
namespace bdeflag {

struct ComponentTable_Component {
    // CLASS METHODS
    struct HStringLess {
        // ACCESSORS
        bool operator()(const bsl::string& left,
                        const bsl::string& right) const;
            // Compare two suffixes.  This is equivalent to a strcmp, except
            // that 'h' is translated to 1, guaranteeing that .h files will
            // come before .c, .cpp, .t.cpp, .m.cpp.
    };

    // PUBLIC TYPES
    typedef bsl::set<bsl::string, HStringLess> FileNameSet;
    typedef FileNameSet::iterator              FileNameSetIterator;

    // DATA
    bsl::string d_componentPath;
    FileNameSet d_fileNames;

    // ACCESSORS
    FileNameSetIterator begin() const;
        // Return the iterator marking the beginning of the set of file names.

    FileNameSetIterator end()   const;
        // Return the iterator marking the ending of the set of file names.

    bsl::size_t numFiles() const;
        // Return the number of files stored in this component.
};

                            // --------------------
                            // class ComponentTable
                            // --------------------

class ComponentTable {
  public:
    // PUBLIC TYPES
    typedef ComponentTable_Component       Component;
    typedef Component::FileNameSetIterator FileNameSetIterator;

  private:
    // PRIVATE TYPES
    struct ComponentPtrCompare {
        // ACCESSORS
        bool operator()(const Component *left,
                        const Component *right) const;
            // Return 'true' if the component name of 'left' is less than the
            // component name of 'right'.
    };

    typedef bsl::set<Component *, ComponentPtrCompare>  ComponentSet;
    typedef ComponentSet::iterator                      ComponentSetIterator;

    // PRIVATE DATA
    bsl::vector<Component> d_components;
    ComponentSet           d_componentNameSet;

  private:
    // PRIVATE MANIPULATORS
    void pushComponent(const Component& component);
        // Push the component, which may involve rebuilding the component
        // name set from scratch.

  public:
    // CLASS METHODS
    static
    void getComponentName(bsl::string        *componentName,
                          const bsl::string&  fileName);
        // Given a fileName, return the corresponding component name.  The
        // original contents of '*componentName' are discarded.

    static
    bool isInclude(const bsl::string& fileName);
        // Return 'true' if the specified 'fileName' ends with '.h' and 'false'
        // otherwise.

    // CREATORS
    //! ComponentTable()  = default;
    //! ~ComponentTable() = default;

    // MANIPULATORS
    bool addComponent(const bsl::string& componentPath);
        // Add a component name to the list of components to be traversed.
        // Filenames '*.{h,c,cpp,t.cpp,m.cpp}' are attempted to be added, only
        // those that actually exist are added.  Return 'true' if any of the
        // files attempted to add existed, whether they were redundant with
        // entries already in the table or not, and return 'false' if no
        // file names corresponding to the component existed.

    bool addFileOrComponentName(const bsl::string& filePath);
        // If a file name ends with '.{h,c,cpp,t.cpp,m.cpp}', determine whether
        // the file exists or not.  If it exists, add it to the table and
        // return 'true' and return 'false' otherwise.  If the file name does
        // not end with one of those suffixes, it is taken to be a component
        // name, and 'addComponent' is called with 'filePath' and its return
        // value propagated.

    // ACCESSORS
    const Component& component(bsl::size_t index) const;
        // Return a const reference to the component with the given index.  The
        // behavior is undefined if 'index >= length()'.

    const bsl::size_t length() const;
        // Return the number of components in this table.
};

//=============================================================================
//                       INLINE FUNCTION DEFINITIONS
//=============================================================================

                    // -------------------------------------
                    // ComponentTable_Component::HStringLess
                    // -------------------------------------

inline
bool ComponentTable_Component::HStringLess::operator()(
                                                const bsl::string& left,
                                                const bsl::string& right) const
{
    const char *leftPc = left.c_str(), *rightPc = right.c_str();
    char leftC;
    while ((leftC = *leftPc) == *rightPc && leftC) {
        ++leftPc;
        ++rightPc;
    }

    char rightC = *rightPc;

    return ('h' == leftC ? 1 : leftC) < ('h' == rightC ? 1 : rightC);
}

                            // ------------------------
                            // ComponentTable_Component
                            // ------------------------

inline
ComponentTable_Component::FileNameSetIterator
                                        ComponentTable_Component::begin() const
{
    return d_fileNames.begin();
}

inline
ComponentTable_Component::FileNameSetIterator
                                          ComponentTable_Component::end() const
{
    return d_fileNames.end();
}

inline
bsl::size_t ComponentTable_Component::numFiles() const
{
    return d_fileNames.size();
}

                      // -----------------------------------
                      // ComponentTable::ComponentPtrCompare
                      // -----------------------------------

inline
bool ComponentTable::ComponentPtrCompare::operator()(
                                  const ComponentTable::Component *left,
                                  const ComponentTable::Component *right) const
{
    return left->d_componentPath < right->d_componentPath;
}

                                // --------------
                                // ComponentTable
                                // --------------

inline
bool ComponentTable::isInclude(const bsl::string& fileName)
{
    const bsl::size_t len = fileName.length();

    return len >= 2 && '.' == fileName[len - 2] && 'h' == fileName[len - 1];
}

inline
const ComponentTable_Component& ComponentTable::component(bsl::size_t index)
                                                                          const
{
    BSLS_ASSERT_OPT(index < d_components.size());

    return d_components[index];
}

inline
const bsl::size_t ComponentTable::length() const
{
    return d_components.size();
}

}  // close namespace bdeflag
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

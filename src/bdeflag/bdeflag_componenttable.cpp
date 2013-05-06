// bdeflag_componenttable.cpp                                         -*-C++-*-

#include <bdeflag_componenttable.h>

#include <bdeflag_ut.h>

#include <bdesu_fileutil.h>

#include <bsl_string.h>

#include <bsl_iostream.h>

namespace BloombergLP {

namespace bdeflag {

void ComponentTable::getComponentName(bsl::string        *componentName,
                                      const bsl::string&  fileName)
{
    static struct {
        bsl::size_t  d_len;
        const char  *d_string;
    } suffixes[] = { { 0, ".h" },
                     { 0, ".t.cpp" },
                     { 0, ".m.cpp" },
                     { 0, ".cpp" },
                     { 0, ".c" },
                     { 0, "." } };
    enum { NUM_SUFFIXES = sizeof suffixes / sizeof *suffixes };
    static bool firstTime = true;
    if (firstTime) {
        firstTime = false;
        for (int i = 0; i < NUM_SUFFIXES; ++i) {
            suffixes[i].d_len = bsl::strlen(suffixes[i].d_string);
        }
    }

    *componentName = fileName;
    for (int i = 0; i < NUM_SUFFIXES; ++i) {
        if (fileName.length() >= suffixes[i].d_len &&
                            !bsl::strcmp(fileName.c_str() + fileName.length() -
                                                             suffixes[i].d_len,
                                         suffixes[i].d_string)) {
            componentName->resize(fileName.length() - suffixes[i].d_len);
            return;                                                   // RETURN
        }
    }

    bsl::size_t idx = fileName.rfind('.');
    if (Ut::npos() != idx &&
                            Ut::npos() == fileName.find_first_of("/\\", idx)) {
        componentName->resize(idx);
    }
}

void ComponentTable::pushComponent(const Component& component)
{
    const bsl::size_t capacity = d_components.capacity();
    d_components.push_back(component);
    if (capacity == d_components.capacity()) {
        d_componentNameSet.insert(&d_components.back());
    }
    else {
        // resized vector, all the ptrs in the name set are now invalid

        d_componentNameSet.clear();
        const bsl::size_t size = d_components.size();
        for (bsl::size_t i = 0; i < size; ++i) {
            d_componentNameSet.insert(&d_components[i]);
        }
    }
}

bool ComponentTable::addComponent(const bsl::string& componentPath)
{
    char *suffixes[] = { ".h",
                         ".t.cpp",
                         ".cpp",
                         ".m.cpp",
                         ".c" };
    enum { NUM_SUFFIXES = sizeof suffixes / sizeof *suffixes };

    bool existed = false;

    Component newComponent;
    newComponent.d_componentPath = componentPath;

    const ComponentSetIterator it = d_componentNameSet.find(&newComponent);
    const bool found = d_componentNameSet.end() != it;
    Component& component = found ? **it : newComponent;

    bsl::string fileName = componentPath;
    for (int i = 0; i < NUM_SUFFIXES; ++i) {
        fileName.resize(componentPath.length());
        fileName += suffixes[i];
        if (bdesu_FileUtil::exists(fileName)) {
            component.d_fileNames.insert(fileName);
            existed = true;
        }
    }

    if (!existed) {
        return false;                                                 // RETURN
    }
    else if (!found) {
        BSLS_ASSERT_OPT(newComponent.d_fileNames.size() > 0);

        pushComponent(newComponent);
    }

    return true;
}

bool ComponentTable::addFileOrComponentName(const bsl::string& filePath)
{
    bsl::string componentPath;
    getComponentName(&componentPath, filePath);

    const bsl::size_t fpl = filePath.length();
    if ((componentPath.length() + 1 == fpl && '.' == filePath[fpl - 1]) ||
                                               componentPath.length() == fpl) {
        return addComponent(componentPath);                           // RETURN
    }

    if (!bdesu_FileUtil::exists(filePath)) {
        return false;                                                 // RETURN
    }

    Component newComponent;
    newComponent.d_componentPath = componentPath;

    const ComponentSetIterator it = d_componentNameSet.find(&newComponent);
    const bool found = d_componentNameSet.end() != it;
    if (!found) {
        pushComponent(newComponent);
    }
    Component& component = found ? **it : d_components.back();
    component.d_fileNames.insert(filePath);

    return true;
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

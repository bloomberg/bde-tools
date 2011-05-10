// filereader.h                                                       -*-C++-*-
#ifndef INCLUDED_FILEREADER
#define INCLUDED_FILEREADER

//@PURPOSE:  Manage an ASCII file and sequentially read one line at a time.
//
//@CLASSES:
// FileReader: ASCII file manager with sequential line-reading function
//
//@SEE_ALSO:
//
//@AUTHOR: tmarshall
//
//@DESCRIPTION: This component implements a file manager with the ability to
// sequentially read lines of ASCII text from an input file.  The file is
// closed and all resources are freed upon destruction of the manager.
//
///USAGE
///-----
// The following snippets of code illustrate how to create and use a
// 'FileReader'.  First create a 'FileReader' named 'myFileReader' that manages
// an existing file named "test.h"
//..
//      char      *myFileName = "test.h";
//      FileReader myFileReader(myFileName);
//..
// Then, read the first line from "test.h" using 'readLine', which loads the
// line into a user-supplied 'line' buffer and returns the 'lineLength'.
//..
//      std::vector<char> line;
//      int linelength = myFileReader.readLine(&line);
//..
// Note that all resources are freed when myFileReader goes out of scope.

#ifndef INCLUDED_VECTOR
#include <vector>
#define INCLUDED_VECTOR
#endif

#ifndef INCLUDED_FSTREAM
#include <fstream>
#define INCLUDED_FSTREAM
#endif

                                // ================
                                // class FileReader
                                // ================
class FileReader {
    // This class manages an existing ASCII file, and can sequentially read
    // lines from that file.  The file is closed and all file resources are
    // freed when the 'FileReader' object is destroyed.

    std::ifstream *d_file_p;            // input file stream (owned)
    int            d_lineNumber;        // line number of current line

  private:
    FileReader(FileReader&);            // NOT IMPLEMENTED
    FileReader& operator=(FileReader&); // NOT IMPLEMENTED

  public:
    // CREATORS
    FileReader(char *fileName);
        // Create a 'FileReader' object to manage the specified 'fileName'.
        // The behavior is undefined unless 'fileName' refers to an existing
        // file of ASCII characters.

    ~FileReader();
        // Close the associated file and free all managed resources.

    //MANIPULATORS
    int readLine(std::vector<char> *line);
        // Read the next line from the file managed by this object, including
        // the line-terminating '\n', into the specified 'line'.  Return the
        // line length on success, and a negative value if there are no more
        // lines to be read.  If the last character in the file is not a '\n'
        // then one is appended to 'line' when that line is read.

    // ACCESSORS
    int lineNumber() const;
        // Return the line number of the current line held by this input file.
};

// ============================================================================
//                      INLINE FUNCTION DEFINITIONS
// ============================================================================

// ACCESSORS
inline
int FileReader::lineNumber() const
{
    return d_lineNumber;
}

#endif

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//------------------------------ END OF FILE ----------------------------------

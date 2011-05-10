// filewriter.h                                                       -*-C++-*-
#ifndef INCLUDED_FILEWRITER
#define INCLUDED_FILEWRITER

//@PURPOSE:  Manage an ASCII file and sequentially write to that file.
//
//@CLASSES:
//     FileWriter: ASCII file manager with sequential writing function
//
//@SEE_ALSO:
//
//@AUTHOR: tmarshall
//
//@DESCRIPTION: This component implements an ASCII file manager with the
// ability to write a string of ASCII characters to that file.  A unique file
// is created upon construction of each manager object, and closed (with
// associated resources freed) upon destruction of the manager.  Note that the
// newline character ('\n') has no special significance in this component; the
// user must supply newlines as required.
//
///USAGE
///-----
// The following snippets of code illustrate how to create and use a
// 'FileWriter'.  First create a 'FileWriter' named 'myFileWriter' that will
// create and manage a new file named "test.txt"
//..
//      char       *myFileName = "test.txt";
//      FileWriter  myFileWriter(myFileName);
//..
// Next, write some text to "test.txt", storing the status of the write in
// 'lineStatus'
//..
//      vector<char> line(20, '\0');
//      strcpy(&line[0], "Hello, world!");
//      int lineStatus = outFile.write(line);
//..
// Note that this example writes the string "Hello, world!" to the managed file
// without a newline character ('\n') (and without modifying 'line').

#ifndef INCLUDED_VECTOR
#include <vector>
#define INCLUDED_VECTOR
#endif

#ifndef INCLUDED_FSTREAM
#include <fstream>
#define INCLUDED_FSTREAM
#endif

                            // ================
                            // class FileWriter
                            // ================

class FileWriter {
    // This class creates and manages an ASCII file, and can write a string of
    // ASCII characters to that file.  A unique file is created upon
    // construction of each 'FileWriter' object, and closed (with associated
    // resources freed) when the 'FileWriter' object is destroyed.  Note that
    // the newline character ('\n') has no special significance in this object.

    std::ofstream   *d_file_p;          // file output stream (owned)

  private:
    FileWriter(FileWriter&);            // NOT IMPLEMENTED
    FileWriter& operator=(FileWriter&); // NOT IMPLEMENTED

  public:
    // CREATORS
    FileWriter(char *fileName);
        // Create a 'FileWriter' object to create and manage the specified
        // 'fileName'.  Note that if 'fileName' already exists, that file will
        // be erased and overwritten.

    ~FileWriter();
        // Close the managed file and free the associated file resources.

    // MANIPULATORS
    int write(const std::vector<char>& buffer);
        // Write the specified 'buffer' to the file  associated with this
        // 'FileWriter' object.  Return zero on success and a non-zero value
        // otherwise.  Note that the newline character ('\n') has no special
        // significance in this function, and must be included in 'buffer' as
        // needed.
};

#endif

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//------------------------------ END OF FILE ----------------------------------

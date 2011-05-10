// filewriter.cpp                                                     -*-C++-*-
#include <filewriter.h>

using namespace std;

                            // ----------------
                            // class FileWriter
                            // ----------------

// CREATORS
FileWriter::FileWriter(char *fileName)
{
    d_file_p = new ofstream(fileName);
}

FileWriter::~FileWriter()
{
    d_file_p->close();
    delete d_file_p;
}

// MANIPULATORS
int FileWriter::write(const vector<char>& buffer)
{
    for (int i = 0; i < buffer.size(); ++i) {
        d_file_p->put(buffer[i]);
    }

    return 0;
}

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//------------------------------ END OF FILE ----------------------------------

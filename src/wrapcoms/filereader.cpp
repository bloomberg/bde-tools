// filereader.cpp                                                     -*-C++-*-
#include <filereader.h>

using namespace std;

                            // ----------------
                            // class FileReader
                            // ----------------

// CREATORS
FileReader::FileReader(char *fileName)
:d_lineNumber(0)
{
    d_file_p = new ifstream(fileName);
}

FileReader::~FileReader()
{
    d_file_p->close();
    delete d_file_p;
}

// MANIPULATORS
int FileReader::readLine(vector<char> *line)
{
    if (d_file_p->bad() || d_file_p->peek() == EOF) {
        return -1;
    }

    char c;
    ++d_lineNumber;

    while (d_file_p->get(c) && '\n' != c && '\0' != c) {
        line->push_back(c);
    }
    line->push_back('\n');

    return line->size();
}

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//--------------------------- END OF FILE -------------------------------------

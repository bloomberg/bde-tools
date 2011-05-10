// wrapcoms.cpp                 -*-C++-*-

#include <filereader.h>
#include <filewriter.h>
#include <commentparagraph.h>
#include <lineutils.h>

#include <vector>
#include <iostream.h>
#include <stdlib.h>   // atoi
#include <assert.h>   // assert

using namespace std;

int main(int argc, char* argv[])
{
    if (argc < 4) {
        cout << "Syntax:  WrapCom maxLineLength inFile outFile" << endl;
        return 1;
    }

    int               maxLineLength = atoi(argv[1]);
    char             *inFileName    = argv[2];
    char             *outFileName   = argv[3];
    FileReader        inFile(inFileName);
    FileWriter        outFile(outFileName);
    CommentParagraph  paragraph(maxLineLength);
    ListItem          listItem(maxLineLength);
    vector<char>      line;          line.reserve(128);     // line buffer
    vector<char>      result;        result.reserve(2048);  // paragraph buffer

    // State variables
    int commentIndex = -1;    // index of first '/' of '//' (or -1 if none)
    int classFlag    =  0;    // flag: in/out (1/0) of '//@CLASS' block
    int inList       =  0;    // flag: in/out (1/0) of List Marker block
    int inListItem   =  0;    // flag: in/out (1/0) of fillable List Item
    int inParagraph  =  0;    // flag: in/out (1/0) of fillable comment set
    int listLevel    =  0;    // level of fillable List Item
    int noFillFlag   =  0;    // flag: in/out (1/0) of no-fill block
    int noticeFlag   =  0;    // flag: have/have-not (1/0) seen "// NOTICE:"

    int lineLength;           // length of current line read in 'while' loop
    while ((lineLength = inFile.readLine(&line)) > -1) {
        // Stop processing, clean up, and echo everything else if "// NOTICE:"
        if (noticeFlag || LineUtils::isCopyrightNotice(line)) {
            noticeFlag = 1;
            if (inParagraph) {
                paragraph.formatParagraph(&result);
                outFile.write(result);
                inParagraph = 0;
            }
            outFile.write(line);
            line.clear();
            continue;
        }

        // Trim trailing spaces on all lines
        while (lineLength >= 2 && ' ' == line[lineLength - 2]) {
            vector<char>::iterator pos = line.end() - 2;
            line.erase(pos);
            --lineLength;
        }

        // 'commentIndex' is the index in 'line' of the first '/' in the
        // pattern " *//", or -1 if not matched.  Subsequent tests below
        // spoof the main processing block by setting 'commentIndex' to -1.
        commentIndex = LineUtils::findCommentIndex(line);

        // Opportunistic tests that adjust the state of the parser before
        // entering the main processing block.
        if (LineUtils::isCommentedDeclaration(line, commentIndex) ||
            LineUtils::isBlankListMarker(line, commentIndex)         ) {
            classFlag    =  0;
            commentIndex = -1;
        }
        else if (LineUtils::isNoFillToggle(line, commentIndex)) {
            commentIndex = -1;
            noFillFlag   = (0 == noFillFlag);
        }
        else if (LineUtils::isClassOrSeeAlsoComment(line)) {
            classFlag    =  1;
            commentIndex = -1;
        }
        else if (classFlag && (LineUtils::isHeadingComment(line, 0) ||
                               (6 < line.size() &&
                                '/' == line[0] && '/' == line[1] &&
                                '@' == line[2] && 'D' == line[3] &&
                                'E' == line[4] && 'S' == line[5])))   {
            classFlag    =  0;
        }
                 
        // Main processing block.  Clean up and echo 'line' if 'commentIndex'
        // is (or has become) negative or else process and/or accumulate
        // 'line' as appropriate.
        if (commentIndex < 0) {
            if (inListItem) {
                listItem.formatItem(&result);
                outFile.write(result);
                inListItem = 0;
            }
            else if (inParagraph) {
                paragraph.formatParagraph(&result);
                outFile.write(result);
                inParagraph = 0;
            }
            outFile.write(line);
            inList      = 0;
            inListItem  = 0;
            inParagraph = 0;
        }
        else if (noFillFlag || classFlag) {
            outFile.write(line);
        }
        else if (LineUtils::isListBlock(line, commentIndex)) {
            if (inParagraph) {
                paragraph.formatParagraph(&result);
                outFile.write(result);
                inParagraph = 0;
            }
            listLevel = LineUtils::isListBlockItem(line, commentIndex);
            if (0 < listLevel) {
                if (inListItem) {
                    listItem.formatItem(&result);
                    outFile.write(result);
                }
                inListItem = 1;
                listItem.setNewItem(line, listLevel, commentIndex);
            }
            else if (inListItem) {
                listItem.appendLine(line);
            }
            else {
                outFile.write(line);
            }
            inList  =  1;
        }
        else if (!inParagraph) {
            if (inListItem) {
                listItem.formatItem(&result);
                outFile.write(result);
                inListItem  = 0;
            }
            inParagraph = 1;
            paragraph.setNewParagraph(line, commentIndex);
        }
        else if (paragraph.getCommentIndex() != commentIndex) {
            paragraph.formatParagraph(&result);
            outFile.write(result);
            paragraph.setNewParagraph(line, commentIndex);
        }
        else {
            paragraph.appendLine(line);
        }
        line.clear();
    };

    if (inParagraph) {
        paragraph.formatParagraph(&result);
        outFile.write(result);
        inParagraph = 0;
    }
    else if (inListItem) {
        listItem.formatItem(&result);
        outFile.write(result);
        inListItem  = 0;
    }

    cout << "Processed " << inFile.lineNumber() << " lines of "
         << inFileName   << endl;

    return 0;
}

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//--------------------------- END OF FILE -------------------------------------

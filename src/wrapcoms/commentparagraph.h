// commentparagraph.h                                                 -*-C++-*-
#ifndef INCLUDED_COMMENTPARAGRAPH
#define INCLUDED_COMMENTPARAGRAPH

//@PURPOSE: Accumulate and reformat C++ comment lines in a BDE header.
//
//@CLASSES:
//  CommentParagraph: C++ comment paragraph text buffer with reformatting
//  ListItem:         BDE list item (paragraph) text buffer with reformatting
//
//@SEE_ALSO: lineutils.h
//
//@AUTHOR: tmarshall
//
//@DESCRIPTION: This component implements objects to accumulate a sequence of
// C++ comment lines and to reformat that text using 'bde' canon documentation
// rules.  Two classes are implemented, 'CommentParagraph' and 'ListItem', each
// one respecting different aspects of BDE formatting.  'CommentParagraph'
// formats a logical "comment paragraph" of the general form of these lines of
// text in component-level documentation, and also. e.g., function-level
// documentation.  (This paragraph is sligtly special because it contains the
// 'DESCRIPTION' heading, but correctly processing such markup is within the
// province of 'CommentParagraph'.)  'ListItem' is dedicated to formatting an
// individual list item line; see below for more about BDE lists.
//
// In all processing, only the space (' ') character itself is recognized as a
// whitespace character; it is assumed that there are no tab characters in the
// source text.  Newline characters are added and removed as appropriate for
// reformatting.  Non-breaking expressions are kept on a single line, even when
// doing so produces a long line.  It is up to the user to decide how best to
// break long-line expressions.
//
///Lists
///-----
// The term "list" refers to a hierarchical sequence of bullet list items and
// numbered list items analogous to the HTML '<ul><li>' and '<nl><li>'
// respectively.  The BDE markup language for a multi-level list is illustrated
// below.  All list lines are introduced by a "List Marker", denoted by the
// three characters '//:'.  A list consists of a sequence of "List Items".  A
// List Item in turn consists of a List Marker, an odd number 'n' of spaces, an
// "Item Token", and then the "Item Text".
//
// The level 'N' of a List Item, which indicates how deeply it is nested in the
// parent (level one) list, is encoded in the (odd) number of spaces 'n'
// according to the relationship:
//..
//  N = (n + 1) / 2    (n odd)
//..
// An Item Token is either the two characters 'o ' or else the sequence of
// characters matching the pattern '[1-9][0-9]* '.  List Text is all of the
// text on the List Item line after the Item Token, plus any additional text on
// subsequent "Item Continuation Lines", which are introduced by a List Marker
// but do not constitute a valid List Item line.
//
// An example of a list is:
//..
//: o This is a level-one bullet.
//:   1 This is a level-two *numbered* List Item.
//:   2 This is also a level-two *numbered* List Item.  It is allowed to
//:     continue on multiple lines as needed.  This is an example of a
//:     multi-line Item that will be accumulated and formatted by the
//:     ListItem object.
//: o We're back to level-one bullets.
//:   o This is a level-two bullets.
//:   o And another level-two bullet.
//:     o This is a level-three bullets.
//:     o And another level-three bullet.
//:       1 This is a level-four *numbered* List Item.
//: o Yet another level-one bullet.
//..
//
///USAGE
///-----
// The following code illustrates how to create and use the 'CommentParagraph'
// and 'ListItem' objects, in conjunction with 'FileReader' and 'FileWriter'
// objects and the utilities in the 'lineutils' component, to perform "comment
// paragraph filling" in a 'bde' header file.  The code is a full, buildable
// 'main'.
//
// The user sequentially fetches input lines using 'FileReader::readLine()',
// recognizes all non-"paragraph" lines using the 'LineUtils' utilities, and
// simply echoes such lines to the output file using 'FileWriter::write()'.
// Lines recognized as belonging to a (possibly one-line) "paragraph" are
// accumulated in the 'CommentParagraph' object.  When a subsequent line is
// recognized as not belonging to the current paragraph, the current paragraph
// is formatted and written to the output file, and then that newly read line
// is handled appropriately (using the above criteria).
//..
//  #include <filereader.h>
//  #include <filewriter.h>
//  #include <commentparagraph.h>
//  #include <lineutils.h>
//  
//  #include <vector>
//  #include <iostream.h>
//  #include <stdlib.h>   // atoi
//  #include <assert.h>   // assert
//  
//  using namespace std;
//  
//  int main(int argc, char* argv[])
//  {
//      if (argc < 4) {
//          cout << "Syntax:  WrapCom maxLineLength inFile outFile" << endl;
//          return 1;
//      }
//  
//      int                     maxLineLength = atoi(argv[1]);
//      char                   *inFileName    = argv[2];
//      char                   *outFileName   = argv[3];
//      FileReader              inFile(inFileName);
//      FileWriter              outFile(outFileName);
//      CommentParagraph        paragraph(maxLineLength);
//      ListItem                listItem(maxLineLength);
//      
//      // buffers for input line and output paragraph, respectively
//      vector<char>            line;    line.reserve(128);
//      vector<char>            result;  result.reserve(2048);
//  
//      // State variables
//      int commentIndex = -1;   // index of first '/' of '//' (or -1 if none)
//      int classFlag    =  0;   // flag: in/out (1/0) of '//@CLASS' block
//      int inList       =  0;   // flag: in/out (1/0) of List Marker block
//      int inListItem   =  0;   // flag: in/out (1/0) of fillable List Item
//      int inParagraph  =  0;   // flag: in/out (1/0) of fillable comment set
//      int listLevel    =  0;   // level of fillable List Item
//      int noFillFlag   =  0;   // flag: in/out (1/0) of no-fill block
//      int noticeFlag   =  0;   // flag: have/have-not (1/0) seen "// NOTICE:"
//  
//      int lineLength;          // length of current line read in 'while' loop
//      while ((lineLength = inFile.readLine(&line)) > -1) {
//          // Stop processing, clean up, echo everything else if "// NOTICE:"
//          if (noticeFlag || LineUtils::isCopyrightNotice(line)) {
//              noticeFlag = 1;
//              if (inParagraph) {
//                  paragraph.formatParagraph(&result);
//                  outFile.write(result);
//                  inParagraph = 0;
//              }
//              outFile.write(line);
//              line.clear();
//              continue;
//          }
//  
//          // Trim trailing spaces on all lines
//          while (lineLength >= 2 && ' ' == line[lineLength - 2]) {
//              vector<char>::iterator pos = line.end() - 2;
//              line.erase(pos);
//              --lineLength;
//          }
//  
//          // 'commentIndex' is the index in 'line' of the first '/' in the
//          // pattern " *//", or -1 if not matched.  Subsequent tests below
//          // spoof the main processing block by setting 'commentIndex' to -1.
//          commentIndex = LineUtils::findCommentIndex(line);
//  
//          // Opportunistic tests that adjust the state of the parser before
//          // entering the main processing block.
//          if (LineUtils::isCommentedDeclaration(line, commentIndex)) {
//              classFlag    =  0;
//              commentIndex = -1;
//          }
//          else if (LineUtils::isNoFillToggle(line, commentIndex)) {
//              commentIndex = -1;
//              noFillFlag   = (0 == noFillFlag);
//          }
//          else if (LineUtils::isClassOrSeeAlsoComment(line)) {
//              classFlag    =  1;
//              commentIndex = -1;
//          }
//          else if (classFlag && (LineUtils::isHeadingComment(line, 0) ||
//                                 (6 < line.size() &&
//                                  '/' == line[0] && '/' == line[1] &&
//                                  '@' == line[2] && 'D' == line[3] &&
//                                  'E' == line[4] && 'S' == line[5])))   {
//              classFlag    =  0;
//          }
//                   
//          // Main processing block.  Clean up and echo 'line' if
//          // 'commentIndex' is (or has become) negative or else process
//          // and/or accumulate 'line' as appropriate.
//          if (commentIndex < 0) {
//              if (inListItem) {
//                  listItem.formatItem(&result);
//                  outFile.write(result);
//                  inListItem = 0;
//              }
//              else if (inParagraph) {
//                  paragraph.formatParagraph(&result);
//                  outFile.write(result);
//                  inParagraph = 0;
//              }
//              outFile.write(line);
//              inList      = 0;
//              inListItem  = 0;
//              inParagraph = 0;
//          }
//          else if (noFillFlag || classFlag) {
//              outFile.write(line);
//          }
//          else if (LineUtils::isListBlock(line, commentIndex)) {
//              if (inParagraph) {
//                  paragraph.formatParagraph(&result);
//                  outFile.write(result);
//                  inParagraph = 0;
//              }
//              listLevel = LineUtils::isListBlockItem(line, commentIndex);
//              if (0 < listLevel) {
//                  if (inListItem) {
//                      listItem.formatItem(&result);
//                      outFile.write(result);
//                  }
//                  inListItem = 1;
//                  listItem.setNewItem(line, listLevel, commentIndex);
//              }
//              else if (inListItem) {
//                  listItem.appendLine(line);
//              }
//              else {
//                  outFile.write(line);
//              }
//              inList  =  1;
//          }
//          else if (!inParagraph) {
//              if (inListItem) {
//                  listItem.formatItem(&result);
//                  outFile.write(result);
//                  inListItem  = 0;
//              }
//              inParagraph = 1;
//              paragraph.setNewParagraph(line, commentIndex);
//          }
//          else if (paragraph.getCommentIndex() != commentIndex) {
//              paragraph.formatParagraph(&result);
//              outFile.write(result);
//              paragraph.setNewParagraph(line, commentIndex);
//          }
//          else {
//              paragraph.appendLine(line);
//          }
//          line.clear();
//      };
//  
//      if (inParagraph) {
//          paragraph.formatParagraph(&result);
//          outFile.write(result);
//          inParagraph = 0;
//      }
//      else if (inListItem) {
//          listItem.formatItem(&result);
//          outFile.write(result);
//          inListItem  = 0;
//      }
//  
//      cout << "Processed " << inFile.lineNumber() << " lines of "
//           << inFileName   << endl;
//  
//      return 0;
//  }
//..
// Note that all resources are returned as the various objects go out of scope.

#ifndef INCLUDED_VECTOR
#include <vector>
#define INCLUDED_VECTOR
#endif

                            // ======================
                            // class CommentParagraph
                            // ======================
class CommentParagraph {
    // This class accumulates a sequence of C++ comment lines that form a
    // logical "comment paragraph": each line has a "//" comment token in the
    // same column, with no non-whitespace characters before the "//" token and
    // no 'bde' canon no-fill tokens (e.g., "//..", "//@CLASS").  The
    // accumulated text can be reformatted such that each comment line is as
    // long as possible consistent with the maximum line length of the object
    // and the 'bde' canon rules for not breaking expressions.  The logical
    // function of this class is "paragraph filling", but for a "comment
    // paragraph" (of which this text is an example).  Note that only the space
    // character (' ') is recognized as a whitespace character; it is assumed
    // that there are no tab characters.  Newline characters are added and
    // removed as appropriate for reformatting.  Note that the special case
    // "//@DESCRIPTION:" is accumulated and formatted correctly.

    int                d_maxLen;       // maximum line lenght for formatting
    int                d_commentIndex; // index of first '/', or -1 if empty
    int                d_textIndex;    // index of first character after "//"
    std::vector<char> *d_buffer;       // holds text portion of comment (owned)

  private:
    CommentParagraph(CommentParagraph&);            // NOT IMPLEMENTED
    CommentParagraph& operator=(CommentParagraph&); // NOT IMPLEMENTED

  public:
    // CREATORS
    CommentParagraph(int maxLineLength);
        // Create a 'CommentParagraph' having the specified 'maxLineLength'.

    ~CommentParagraph();
        // Free all owned resources.

    // MANIPULATORS
    void appendLine(const std::vector<char>& line);
        // Append the specified 'line' to this 'CommentParagraph'.  The
        // behavior is undefined unless 'setNewParagraph' has been successfully
        // called and 'line' is a pure comment that belongs in this set (i.e.,
        // there are no non-whitespace characters to the left of the first
        // occurrance of '//', which begins at the comment index for this
        // 'CommentParagraph', and no 'bde' canon no-fill tokens).

    void setNewParagraph(const std::vector<char>& buffer, int commentIndex);
        // Set this 'CommentParagraph' to contain only the specified comment
        // 'line', with the comment token "//" beginning at the specified
        // 'commentIndex'.  The behavior is undefined unless 'line' is a pure
        // comment (i.e., there are no non-whitespace characters to the left of
        // 'commentIndex', and no 'bde' canon no-fill tokens).  Note that this
        // function must be called at least once before 'appendLine' or
        // 'writeParagraph' may be called.

    // ACCESSORS
    int formatParagraph(std::vector<char> *result) const;
        // Load the specified 'result' with the reformated contents of this
        // 'CommentParagraph'.  Return the non-negative size of 'result' on
        // success and a negative value otherwise.  The behavior is undefined
        // unless 'setNewParagraph' has been successfully called at least once
        // and all accumulated lines logically belong to this comment
        // paragraph.

    int getCommentIndex() const;
        // Return the index of the first character in the token '//' for this
        // 'CommentParagraph', or -1 if this object has not yet been set (with
        // 'setNewParagraph').
};

                            // ==============
                            // class ListItem
                            // ==============
class ListItem {
    // This class accumulates a sequence of C++ comment lines that form a
    // "list paragraph": each line has a "//:" List Marker in the same
    // column, with no non-whitespace characters before the "//:" marker.  The
    // accumulated text can be reformatted such that each bullet line is as
    // long as possible consistent with the maximum line length of the object
    // and the 'bde' canon rules for not breaking expressions.  The logical
    // function of this class is "paragraph filling", but for a "list item"
    // (defined in the component level documentation above).  Note that only
    // the space character (' ') is recognized as a whitespace character; it is
    // assumed that there are no tab characters.  Newline characters are added
    // and removed as appropriate for proper formatting.

    int                d_maxLen;       // maximum line lenght for formatting
    int                d_commentIndex; // index of first '/', or -1 if empty
    int                d_textIndex;    // index of first character after "//:"
    int                d_level;        // level of the list item
    int                d_token;        // Item Token; 0 => "o ", N > 0 => "N "
    std::vector<char> *d_buffer;       // holds text portion of comment (owned)

  private:
    ListItem(ListItem&);               // NOT IMPLEMENTED
    ListItem& operator=(ListItem&);    // NOT IMPLEMENTED

  public:
    // CREATORS
    ListItem(int maxLineLength);
        // Create a 'ListItem' having the specified 'maxLineLength'.

    ~ListItem();
        // Free all owned resources.

    // MANIPULATORS
    void appendLine(const std::vector<char>& line);
        // Append the specified 'line' to this 'ListItem'.  The behavior is
        // undefined unless 'setNewItem' has been successfully called and
        // 'line' is a pure comment that belongs in this set (i.e., there are
        // no non-whitespace characters to the left of the first occurrance of
        // '//', which begins at the comment index for this 'ListItem', and
        // no 'bde' canon no-fill tokens).

    void setNewItem(const std::vector<char>& item,
                    int                      level,
                    int                      commentIndex);
        // Set this 'ListItem' to contain only the specified comment
        // 'item' at the specified 'level', with the List Marker "//:"
        // beginning at the specified 'commentIndex'.  The behavior is
        // undefined unless 'item' is a pure List Item (i.e., there are no
        // non-whitespace characters to the left of 'commentIndex').  Note that
        // this function must be called at least once before 'appendLine' or
        // 'formatItem' may be called.

    // ACCESSORS
    int formatItem(std::vector<char> *result) const;
        // Load the specified 'result' with the reformated contents of this
        // 'ListItem'.  Return the non-negative size of 'result' on
        // success and a negative value otherwise.  The behavior is undefined
        // unless 'setNewItem' has been successfully called at least once
        // and all accumulated lines logically belong to this list paragraph.

    int getCommentIndex() const;
        // Return the index of the first character in the token '//:' for this
        // 'ListItem', or -1 if this object has not yet been set (with
        // 'setNewItem').
};

// ============================================================================
//                      INLINE FUNCTION DEFINITIONS
// ============================================================================

                        // ----------------------
                        // class CommentParagraph
                        // ----------------------

// ACCESSORS
inline
int CommentParagraph::getCommentIndex() const
{
    return d_commentIndex;
}

                            // --------------
                            // class ListItem
                            // --------------

// ACCESSORS
inline
int ListItem::getCommentIndex() const
{
    return d_commentIndex;
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

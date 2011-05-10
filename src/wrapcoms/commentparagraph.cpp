// commentparagraph.cpp                                               -*-C++-*-
#include <commentparagraph.h>

#include <vector>
#include <fstream>
#include <string>     // strchr
#include <ctype.h>    // isalnum, islower
#include <assert.h>   // assert

using namespace std;

// STATIC HELPER FUNCTIONS
static
int isDescriptionTag(const vector<char>& buffer)
    // Return 1 if the first word (at index 0) in the specified 'buffer' is
    // "@DESCRIPTION:" and 0 otherwise.
{
    return ! strncmp(&buffer[0], "@DESCRIPTION:", 13);  // logical-not strncmp
}

static
int isExpressionCharacter(char c)
    // Return 1 if the specified character 'c' is one of "<=>*/+-&|!^" and 0
    // otherwise.
{
    return strchr("<=>*+/-&|!^", c) && '\0' != c;
}

static
int isOpenTick(const vector<char>& buffer, int index)
    // Return 1 if the specified 'buffer' contains the sequence "('" beginning
    // at the specified 'index' and 0 otherwise.
{
    int        bufferLength = buffer.size();      assert(index < bufferLength);
    const char TICK         = '\'';

    if (bufferLength - 1 == index) {
        return 0;                                                     // RETURN
    }
    return ('(' == buffer[index] && TICK == buffer[index + 1]) ? 1 : 0;
}

static
int isPunctuationCharacter(char c)
    // Return 1 if the specified character 'c' is one of ".?!,;:" and 0
    // otherwise.
{
    return strchr(".?!,;:", c) && '\0' != c;
}

static
int isTerminalPunctuationCharacter(char c)
    // Return 1 if the specified character 'c' is one of ".?!" and 0
    // otherwise.
{
    return strchr(".?!", c) && '\0' != c;
}

static
int findCharacter(const vector<char>& buffer, char c, int index)
    // Return the position in the specified 'buffer' of the first occurrence of
    // the specified character 'c' at position greater than the specified
    // 'index', or a negative value if 'c' is not found.
{
    int bufferLength = buffer.size();             assert(index < bufferLength);

    while (++index < bufferLength && c != buffer[index]) {
        // Nothing to do in loop
    }
    return (index < bufferLength) ? index : -1;
}

static
int findWordEnd(const vector<char>& buffer, int index)
    // Return the position within the specified 'buffer' of the end of the word
    // (or non-breaking expression) that contains the character at the
    // specified 'index'.  The behavior is undefined unless 'index' points to a
    // non-space character within the buffer and 'index < buffer.size()'.  Note
    // that expressions such as "0 <= index < length" are treated as a single,
    // non-breaking word, but 'index' still may not point to an internal space
    // character.  Note also that this version attempts to honor properly
    // delimited non-breaking expressions, but also attempts to behave 
    // reasonably in the face of input error.
{
    int        bufferLength = buffer.size();      assert(index < bufferLength);
    int        endPos       = index;              // index of end of word
    int        status;                            // return status of helpers
    const char TICK         = '\'';

    // First see if 'buffer[index]' is a single-quote-delimited expression,
    // possibly in parentheses.  If so, return the position of the closing
    // 'TICK' adjusted for punctuation and parentheses as needed.

    if (TICK == buffer[index] || isOpenTick(buffer, index)) {
        // Total of two cases for opening: 1:  '  2:  '(
        if (TICK == buffer[index]) {
            status = findCharacter(buffer, TICK, index);     // (1) "'"
        }
        else {
            status = findCharacter(buffer, TICK, index + 1); // (2) "('"
        }
        if (0 <= status) {
            // Total of five cases for closing: 1: ' 2: '. 3: '.) 4: ') 5: ').
            if (status == bufferLength - 1  ||  ' ' == buffer[status + 1]) {
                return status;         // Case (1)  '                 // RETURN
            }
            else if (isPunctuationCharacter(buffer[status + 1])) {
                // Found "'." (or other punctuation)
                if (status + 2 < bufferLength  && ')' == buffer[status + 2]) {
                    return status + 2; // Case (3)  '.)               // RETURN
                }
                else {
                    return status + 1; // Case (2)  '.                // RETURN
                }
            }
            else if (')' == buffer[status + 1]) {
                // Found "')"
                if (status + 2 < bufferLength                 &&
                    isPunctuationCharacter(buffer[status + 2])   ) {
                    return status + 2; // Case (5)  ').               // RETURN
                }
                else {
                    return status + 1; // Case (4)  ')                // RETURN
                }
            }
        }
    }

    while (index < bufferLength && ' ' != buffer[index]) {
        ++index;                                     // skip non-spaces
    }
    endPos = index - 1;

    do {
        while (index < bufferLength && ' ' == buffer[index]) {
            ++index;                                 // skip spaces
        }
        if (index >= bufferLength) {
            return endPos;                                            // RETURN
        }
        if (isExpressionCharacter(buffer[index]) && '-' != buffer[index + 1]
                                                 && !isalnum(buffer[index + 1])
            || '.' == buffer[index] && '.' == buffer[index]) {  
                                         // check for expression or ".."
            while (index < bufferLength && ' ' != buffer[index]) {
                ++index;                             // add operator candidate
            }
            while (index < bufferLength && ' ' == buffer[index]) {
                ++index;                             // add spaces
            }
            while (index < bufferLength && ' ' != buffer[index]) {
                ++index;                             // add next word
            }
            endPos = index - 1;
        }
        else {
            return endPos;                                            // RETURN
        }
    } while (index < bufferLength);

    return endPos;
}

                        // ----------------------
                        // class CommentParagraph
                        // ----------------------

// CREATORS
CommentParagraph::CommentParagraph(int maxLineLength)
:d_maxLen(maxLineLength),
 d_commentIndex(-1),
 d_textIndex(1)
{
    d_buffer = new vector<char>;
    d_buffer->reserve(2048);
}

CommentParagraph::~CommentParagraph()
{
    delete d_buffer;
}

// MANIPULATORS
void CommentParagraph::appendLine(const vector<char>& line)
{
    if (' ' != line[d_textIndex]) {
        d_buffer->push_back(' ');
    }
    d_buffer->insert(d_buffer->end(),
                     line.begin() + d_textIndex,
                     line.end() - 1);                 // end() - 1 to omit '\n'
}

void CommentParagraph::setNewParagraph(const vector<char>& line,
                                       int                 commentIndex)
{
    d_commentIndex    = commentIndex;
    d_textIndex       = commentIndex + 2;
    
    d_buffer->clear();
    d_buffer->insert(d_buffer->end(),
                     line.begin() + d_textIndex,
                     line.end() - 1);                 // end() - 1 to omit '\n'
}

// ACCESSORS
int CommentParagraph::formatParagraph(vector<char> *result) const
{
    if (0 > d_commentIndex) {
        return -1;                                                    // RETURN
    }

    int          startPos      = 0;    // index in 'd_buffer' of start of word
    int          endPos        = 0;    // index in 'd_buffer' of end of word
    int          wordLength    = 0;    // lenght of next word in 'd_buffer'
    int          lineLength    = 0;    // lenght of (logical) line in '*result'
    int          nextOutOffset = 0;    // spaces before next output word
    int          bufferLength  = d_buffer->size();
    vector<char> prefix(d_textIndex + 1, ' ');  // Appropriately-indented
    prefix[d_commentIndex]     = '/';           // comment marker.
    prefix[d_commentIndex + 1] = '/';

    result->clear();                                 // clear result first
    while (startPos < bufferLength) {
        while (startPos < bufferLength && ' ' == d_buffer->at(startPos)) {
            ++startPos;                              // skip spaces
        }
        if (startPos >= bufferLength) {              // buffer ends with ' '
            break;
        }
        // Find next word and calculate if it will fit on current logical line.
        endPos = findWordEnd(*d_buffer, startPos);
        wordLength = endPos - startPos + 1;
        if (lineLength + wordLength + nextOutOffset > d_maxLen
            && lineLength > 0) {            // word won't fit && line not empty
            result->push_back('\n');
            lineLength = 0;
        }
        if (0 == lineLength) {
            result->insert(result->end(), prefix.begin(), prefix.end());
            lineLength = d_textIndex + 1;
        }
        else {                                          // add space(s)
            if (nextOutOffset > 1 && islower(d_buffer->at(startPos))) {
                nextOutOffset = 1;          // one space for "5 lbs. of... and"
            }
            for (int i = 1; i <= nextOutOffset; ++i) {
                result->push_back(' ');
            }
            lineLength += nextOutOffset;
        }
        if (0 == startPos && 13 == wordLength && isDescriptionTag(*d_buffer)) {
            vector<char>::iterator pos = result->begin() + (--lineLength);
            result->erase(pos);
        }
        result->insert(result->end(),
                       d_buffer->begin() + startPos,
                       d_buffer->begin() + startPos + wordLength);
        lineLength    += wordLength;
        // Skip two spaces after {{. or ! or ?}} or {{.) or !) or ?)}}
        if (isTerminalPunctuationCharacter(d_buffer->at(endPos))        ||
            (0 < endPos                                               &&
             isTerminalPunctuationCharacter(d_buffer->at(endPos - 1)) &&
             ')' == d_buffer->at(endPos)                                 )) {
            nextOutOffset = 2;
        }
        else {
            nextOutOffset = 1;
        }
        // If line is full, add '\n' and reset logical line length.
        if (lineLength + nextOutOffset > d_maxLen) {
            result->push_back('\n');
            lineLength = 0;
        }
        startPos = endPos + 1;
    }
    // Append final '\n' of the paragraph.
    if ('\n' != (*result)[result->size() - 1]) {
        result->push_back('\n');
    }
    return result->size();
}

                            // --------------
                            // class ListItem
                            // --------------

// CREATORS
ListItem::ListItem(int maxLineLength)
:d_maxLen(maxLineLength),
 d_commentIndex(-1),
 d_textIndex(1)
{
    d_buffer = new vector<char>;
    d_buffer->reserve(2048);
}

ListItem::~ListItem()
{
    delete d_buffer;
}

// MANIPULATORS
void ListItem::appendLine(const vector<char>& line)
{
    if (' ' != line[d_textIndex]) {
        d_buffer->push_back(' ');
    }
    d_buffer->insert(d_buffer->end(),
                     line.begin() + d_textIndex,
                     line.end() - 1);                 // end() - 1 to omit '\n'
}

void ListItem::setNewItem(const vector<char>& line,
                          int                 level,
                          int                 commentIndex)
{
    // Imp Note: All text to the right of the "//:", including the spaces to
    // the left of the bullet, is stored in 'd_buffer'.
    
    d_commentIndex    = commentIndex;
    d_level           = level;
    d_textIndex       = commentIndex + 3;
    
    d_buffer->clear();
    d_buffer->insert(d_buffer->end(),
                     line.begin() + d_textIndex,
                     line.end() - 1);                 // end() - 1 to omit '\n'
}

// ACCESSORS
int ListItem::formatItem(vector<char> *result) const
{
    // Imp Note: The bullet token, including spaces indicating the level, is
    // stored in 'd_buffer' and is output as written.  Subsequent indentation
    // is fomatted by this method.
    
    if (0 > d_commentIndex) {
        return -1;                                                    // RETURN
    }

    int startPos      = 0;          // index in 'd_buffer' of start of word
    int endPos        = 0;          // index in 'd_buffer' of end of word
    int wordLength    = 0;          // lenght of next word in 'd_buffer'
    int lineLength    = 0;          // lenght of (logical) line in '*result'
    int nextOutOffset = 0;          // spaces before next output word
    int bufferLength  = d_buffer->size();

    // Define appropriately-indented List Marker and append to 'result'.  Note
    // that 'listMarker' is correct for any continuation lines but 'result'
    // must be shortened after the initial 'append'.
    vector<char> listMarker(d_textIndex + (2 * d_level + 1), ' ');
    listMarker[d_commentIndex]     = '/';
    listMarker[d_commentIndex + 1] = '/';
    listMarker[d_commentIndex + 2] = ':';

    // clear 'result', append 'listMarker', which is too long, discard extra
    result->clear();                
    result->insert(result->end(), listMarker.begin(), listMarker.end());
    result->resize(d_textIndex);    // discard indentation spaces for 1st line
    
    // Write to 'result' the characters up to the *first* space after the
    // (single-character) bullet or (possibly multi-character) number string.
    startPos = 2 * d_level;         // one past position of first bullet char.
    while (startPos < bufferLength && ' ' != d_buffer->at(startPos)) {
        ++startPos;                                  // skip non-spaces
    }
    ++startPos;                                      // skip exactly one space
    result->insert(result->end(),
                   d_buffer->begin(),
                   d_buffer->begin()+ startPos);     // append the bullet
    lineLength = d_textIndex + startPos;
    
    while (startPos < bufferLength) {
        while (startPos < bufferLength && ' ' == d_buffer->at(startPos)) {
            ++startPos;                              // skip spaces
        }
        if (startPos >= bufferLength) {              // buffer ends with ' '
            break;
        }
        // Find next word and calculate if it will fit on current logical line.
        endPos = findWordEnd(*d_buffer, startPos);
        wordLength = endPos - startPos + 1;
        if (lineLength + wordLength + nextOutOffset > d_maxLen
            && lineLength > 0) {            // word won't fit && line not empty
            result->push_back('\n');
            lineLength = 0;
        }
        if (0 == lineLength) {
            result->insert(result->end(),
                           listMarker.begin(),
                           listMarker.end());
            lineLength = d_textIndex + (2 * d_level + 1);
        }
        else {                                          // add space(s)
            if (nextOutOffset > 1 && islower(d_buffer->at(startPos))) {
                nextOutOffset = 1;          // one space for "5 lbs. of... and"
            }
            for (int i = 1; i <= nextOutOffset; ++i) {
                result->push_back(' ');
            }
            lineLength += nextOutOffset;
        }
        result->insert(result->end(),
                       d_buffer->begin() + startPos,
                       d_buffer->begin() + startPos + wordLength);
        lineLength += wordLength;
        // Skip two spaces after {{. or ! or ?}} or {{.) or !) or ?)}}
        if (isTerminalPunctuationCharacter(d_buffer->at(endPos))        ||
            (0 < endPos                                               &&
             isTerminalPunctuationCharacter(d_buffer->at(endPos - 1)) &&
             ')' == d_buffer->at(endPos)                                 )) {
            nextOutOffset = 2;
        }
        else {
            nextOutOffset = 1;
        }
        // If line is full, add '\n' and reset logical line length.
        if (lineLength + nextOutOffset > d_maxLen) {
            result->push_back('\n');
            lineLength = 0;
        }
        startPos = endPos + 1;
    }
    // Append final '\n' of the item.
    if ('\n' != (*result)[result->size() - 1]) {
        result->push_back('\n');
    }
    return result->size();
}

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2004, 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
//------------------------------ END OF FILE ----------------------------------

				   -------
				   bdeFlag
				   -------

bdeFlag does readonly processing of one C++ file at a time.  It takes into
account the name of the file, which should end with '.t.cpp', '.h', or '.cpp'.
It flags a number of things that can occur in a file that violate the bde
coding standard.

At the first release, it flags the following problems:

-------------------------------------------------------------------------------
Things currently checked:

* - all lines longer than 79 chars
* - C-style comments
* - flag all includes of 'assert.h', 'cassert'
* - flag all '#include "*"' (rather than '#include <*>')
* - Comments before code must always be followed by blank line
* - Comments allowed after code indented by 4 or more, immediately following
    line
    *** -- reporting strangely indented comments.  However, some block
	comments indented to the middle are showing up.
* - BSLS_ASSERT*s at beginning of functions always followed by blank line
* - inline or template not appearing on its own line (allow "inline static" or
*   "static inline").
* - arg names
    - 'lhs', 'rhs' not used for methods other than binary operators
    - 'lhs', 'rhs' always used for certain binary operators (for '==' & '&&',
      but not '<<=', for example).
    - 'swap' member function arg name should be 'other'
    - copy c'tor arg name should be 'original'
    - '// NOT IMPLEMENTED' functions should not have arg names
    - friend functions should not have arg names
* - proper identation (and presence) of closing comments of namespaces, with
    unnamed namespaces and named namespaces having different style comments
    *** doesn't check names of named namespace in closing comments
* - routines beginning with 'is', 'are', 'has', and some binary operators (ie
    '==' and '&&' but not '+=' or '<<') returning bool ('bool&' is allowed)
* - all functions in classes must be doc'ed
    *** if a method is defined twice (say same method name in two
        classes, or same operator on two types), and docced only once, it is
        not reported.
* - all file-scoped static functions in .cpp should have function-level doc,
    not necessarily in .t.cpp
* - // NOT IMPLEMENTED must always be preceded by 'private:' on separate line
* - check for '// RETURN' on every return, right justified, but not on the
    last return of a function
* - all file-scoped static functions or functions in unnamed namespace in .cpp
    should have function-level doc, not necessarily in .t.cpp
* - report static functions or functions in unnamed namespace in .h files
* - bde-ize bdeflag code
* - if, while, for, do not followed by '{'. (.t.cpp's excepted)
* - catch args to functions that are references to modifiables, except for
    the first arg of 'swap', or the first arg of any function if the arg name
    contains 'stream'.
* - indentation
*   - not indented by 4 within a class
*   - not indented by 4 within code (.t.cpp's excepted)
*   - 'public:', 'private:', etc, not indented by 2
*   - stuff within a namespace not indented by 0 or 4
* - warning on single arg c'tor not explicit
* - detecting 'ASSERT' (not be confused with 'BSLS_ASSERT') in comments in .h
    files.

-------------------------------------------------------------------------------

The software consists of the 4 following components:

- bdeflag_ut
    // low level utilities, mostly operating on bsl::strings.  The class
    // bdeflag::Ut is just a namespace for a bunch of static functions and some
    // static data.
- bdeflag_line
    // the bdeflag::Line class contains no instance data, but it can be
    // constructed and destructed.  When constructed, it initializes a lot of
    // static variables, when destructed, it makes sure any allocated memory is
    // freed.  It creates a description of the file, which is a vector of
    // string with the comments, macros, and newlines stripped.  There are
    // separate vectors, one of strings containing code, one of enum's
    // describing certain special comments that are recognized, and one of
    // enum's describing certain reserved words if they appear at the start of
    // lines.  It has other static state, such as a set of line numbers of
    // lines that were too long, a set of line numbers where C-style comments
    // happened, and booleans, for example whether there were any tabs in the
    // file.
- bdeflag_place
    // describing class bdeflag::Place.  A place object is a coordinate pair,
    // describing a line number and a column of a position in the file.
    // operators '++' and '--' are supported, which always go to the next
    // nonwhite char, unless they go off the beginning or end of the file.
    // operator '*' is available, which means the char at that position
    // (returning 0 for invalid positions).  There is also 'findFirstOf',
    // and methods for finding words (or templates names) at, after, or before
    // a given positon.  Most operations on Place objects assume that the
    // statics 's_end' and 's_rEnd' are initialized, this happens by calling
    // the static method 'setEnd()', which must be called after an object of
    // class 'Lines' is created.
- bdeflag_group
    // top level, describing class bdeflag::Group.  A group describes a
    // matching pair of '()'s or '{}'s.  One object of type 'Group' describes
    // many things about such a pair -- the string, if any, that precedes it,
    // the Place where the statement that the group is within started, a set of
    // the groups that are contained within this group.  All groups are within
    // a recursive tree, and most checking is done by traversing that tree and
    // analyzing one group at a time.  This class does most of the checking for
    // errors. bdeflag_group.t.cpp is the main program called by the script
    // 'bdeflag.sh'.

-------------------------------------------------------------------------------
Future Goals:

  - disallow operators << & >> for bdex streams?  Ask John.
  - '?' & ':' must be 
    1: v = a ? b : c;
    2: v = a ? b
	     : c;
    3: v = a
         ? b
	 : c;
  - templates must use 'class' instead of 'typename' (get clarification from
    Alisdair on whether this is desirable.
  - look for obvious constants on rhs or == and != condtionals (hard in
    general case, could handle in simple cases)
  - names on closing comments of namespaces must match
  - all instance data members begin with 'd_'
  - all static data members begin with 's_'
  - all static data const members begin with 'S_'
  - all ptrs end with '_p'
  X ? match parameter names in definitions to parameter names in declarations?
    pretty hard.  Will not do, already handled by Steve's tool.
  - order of declarations
    X order of definitions.  Hard, already handled by Arthur's tool.
    - free operators -- '==' before '!='.
    - member operators -- '=' before '[]', before alphanum members.
  - verify every public member of the class is called in test driver (Hard,
    I'm only looking at one file now).  (How to identify private classes --
    '_' in names?).

Run times on all C++ source in bsl, bde, bce, bae, and bte
    - Linux: 1 minute 28 seconds
    - AIX: 1 minute 58 seconds
    - Sun: 3 minutes 5 seconds
    - HPUX: 8 minutes 15 seconds*

* - note code is built optimized on all platforms except HP.

-------------------------------------------------------------------------------

Separate tool (not written yet): deprecated identifier searchers
  - BSLS_ASSERT_H, BSLS_ASSERT_CPP
  - d_size should never happen
  - C-style casts to common types, ie '(int)', '(int *)', '(char *)'.

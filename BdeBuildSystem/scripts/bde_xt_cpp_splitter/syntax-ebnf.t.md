# `{|SCRIPT-NAME|}` Syntax EBNF

```
controlComment
    : '{|CONTROL-COMMENT-PREFIX|}' controlCommentContent "\n"
    ;

controlCommentContent
    : partsGuide
    | globalComment
    | forComment
    | slicingComment
    ;

partsGuide
    : 'PARTS (syntax version 1.0.0)' "\n" partsLine+
    ;

partsGuide
    : partsHead "\n" (partsLine "\n")* partsLine
    ;

partsHead
    : 'PARTS (syntax version 1.0.0)'
    ;

partsLine
    : partDefinition
    | partsEmptyLine
    | partsCommentLine
    ;

partDefinition
    : "CASE: " partItem ("," partItem)*
    ;

partItem
    : testCaseNumber
    | partSlicedTestCase
    ;

testCaseNumber
    : /[1-9][0-9]?/
    ;

partSlicedTestCase
    : /[1-9][0-9]?/ ".SLICES"
    ;

partsEmptyLine
    : "//@"
    ;

partsCommentLine
    : "//@" "#" any-text-as-the-comment
    ;

forComment
    : forBlockComment
    | forLineComment
    ;

forBlockComment
    : "FOR " forList ("BEGIN"|"END")
    ;

forLineComment
    : "FOR " forList
      # Must follow C++ code that it applies to
    ;

forList
    : forListItem ("," forListItem)*
    ;

forListItem
    : testCaseNumber
    | testCaseNumberSliceNumber
    ;

testCaseNumberSliceNumber
    : testCaseNumber "." sliceNumber
    ;

sliceNumber
    : /[1-9][0-9]?/
    ;

slicingComment
    : codeSlicingComment
    | typeListSlicingComment
    | intoSliceComment
    ;

codeSlicingComment
    : "CODE SLICING " ("BEGIN"|"BREAK"|"END")
    ;

typeListSlicingComment
    : " SLICING TYPELIST" "/" sliceNumber
      # Must be followed by #define
      # Maximum the number of types in the MACRO
    ;

intoSliceComment
    : intoSliceBlockComment
    | intoSliceLineComment
    ;

intoSliceBlockComment
    : "INTO " ("FIRST"|"LAST") " SLICE " ("BEGIN"|"END")
    ;

intoSliceLineComment
    : "INTO " ("FIRST"|"LAST") " SLICE"
      # Must follow C++ code that it applies to
    ;

globalComment
    : warningSuppress
    | lineDirective
    ;

warningSuppress
    : 'SILENCE WARNINGS: UNUSED'
    ;

lineDirective
    : 'LINE DIRECTIVES: ' /"OFF"|"ON"/
    ;
```

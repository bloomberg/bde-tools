# `{|SCRIPT-NAME|}` Usage Guide

`{|SCRIPT-NAME|}` is a script that splits BDE-style test drivers (with an
'.xt.cpp' extension) and generates several test driver sources that we call
PARTS.  The script generates ephemeral part files (.NN.t.cpp) that exist during
the build proces only and are not comitted to version control.  All files
created by the splitting process are written into a specific directory under
the build directory.

The '.xt.cpp' files contain control-comments that are special C++ line-comments
(not `/*` `*/`, but always `//`) that start with `{|CONTROL-COMMENT-PREFIX|}`.
Those control comments determine the pieces of the full test driver ('.xt.cpp')
go into the parts.

Control-comments may need multiply lines to be human-readable.  Currently the
`PARTS` guide is the only control comment that is not limited to one line.  The
additional lines that belong to such a control comment all start with `//@`,
but not with `{|CONTROL-COMMENT-PREFIX|}`.  Any line that does not start with
`//@`, or starts with `{|CONTROL-COMMENT-PREFIX|}` ends the control-comment
block.  The acceptable syntax within such a block is defined by the type of the
control-comment.

 The splitting process performs minimal transformations on the contents of the 
`.xt.cpp` file, primarily selectively taking or ignoring different parts of the 
original file.   Within `main`, the initial output message and test case 
numbering are modified, all other lines are copied over from the original 
`.xt.cpp` file.

Within the part files, preprocessor `#line` directives are added that refer
back to the original '.xt.cpp' source and line number, so compiler warning and
error messages, as well as runtime messages (such as `ASSERT`) will display the
original '.xt.cpp' file name and source line number.  (This behaviour can be
disabled if necessary, see Turning Off Line Directives.)

Negative test cases are moved into their parts unchanged.  Their code cannot be
sliced (it would not make much sense to slice a benchmark) and the negative
test case number will not change.

To avoid wasting time during running the tests each part will have its positive
test cases numbered (continuously) from 1.  The traditional `TEST` printout is
extended in the parts with additional information about the test case numbers.
The following is an example showing a simple renumbered test case, as well as a
test case slice `TEST` printout:

```txt
TEST bdlt_iso8601util.xt.cpp CASE 10 RUN AS bdlt_iso8601util.02.t CASE 1

TEST bslma_ctxutil.xt.cpp CASE 4 SLICE 1 RUN AS bslma_ctxutil.04.t CASE 1
```

The `RUN AS` part tells the programmer how to repeat a failed test run without
using the test runner of the build system.  There are also test case mapping
files generated for each '.xt.cpp' with the '.xt.cpp.mapping' suffixes.  The
mapping file provides two tables.  One maps the original test case numbers to
part numbers and case numbers in that part.  The other one lists the contents
of the parts, and is useful when asking the question: why may part 5 compile
(or run) so slow.

The renumbering is also visible in the part source code files created.  If a
(positive) test case is renumbered, its opening `case` line will indicate that
like so:

```cpp
      case 2: {  // 'case 11' slice 1 in "bdlt_iso8601util.xt.cpp"
```

## Motivation

Tests drivers may need to be split for several reasons:
  - the test driver does not compile on some compiler because it exceeds a
    limit or exhausts a resource
  - the test driver compiles extremely slowly due to code complexity
  - one or more test cases execute for too long time causing timeouts

The generated parts will have the '.NN.t.cpp' extensions where 'NN' is going
from 01 possibly all the way to 99, depending on how many parts are generated.

This documentation introduces each possible control comment, its syntax, and
its purpose.

## Overview

Every control comment is case-sensitive and the control part (after the
`{|CONTROL-COMMENT-PREFIX|}` prefix) is ALWAYS UPPERCASE to make these comments
stand out, and indicate that they behave much like an unsophisticated
preprocessor.

Use `{|SCRIPT-NAME|} --help syntax-ebnf` to see the EBNF description of the
supported control comments.

The most important control comment is the PARTS guide that determines what goes
into each generated test-driver (called 'parts').  This is the only comment
that is needed for simple splitting where test cases themslves do not need to
be sliced up between executables.

Additional control comments support slicing-up test cases either by slicing the
code inside a test case, or by creating slices that test a subset of a list of
types.

Miscellanous control comment exists as well, they will be described last.

## PARTS Guide

The parts comment must be unindented.  It always starts with the PARTS heading,
followed by a list of part definitions starting with `//@  CASES: `.  As able
control-comment block the `PARTS` guide ends with any line that does not start
with `//@`, or starts with `{|CONTROL-COMMENT-PREFIX|}`.

### Splitting on Whole Test Cases

The simplest form of splitting is when the test cases by themselves are not too
large, so we do not need to slice them up.  We can just place complete test
cases into the parts, maybe even more than one.  For example:

```cpp
{|CONTROL-COMMENT-PREFIX|}PARTS (syntax version 1.0.0)
//@
//@# This test driver will be split into multiple parts for faster compilation
//@# using bde_xt_cpp_splitter.py from the bde-tools repo.  Note that test
//@# cases may be further sliced into multiple parts within the test case
//@# itself (i.e., there is not a 1-1 mapping between the parts listed below
//@# and the generated files).  The specification for the {|CONTROL-COMMENT-PREFIX|}
//@# comments can be found:
//@#    bde_xt_cpp_splitter --help syntax-guide
//@#    bde_xt_cpp_splitter --help syntax-ebnf
//@
//@  CASES: 1..10, 19
//@  CASES: 11..END
```
The above PARTS definition creates two parts.  The first part contains test
cases 1 to 10 as well as test case 19 (USAGE EXAMPLE) as case 11.  The second
part contains the rest of the test cases (those originally numbered 11 to 18).
It is assumed here that the test driver had 19 test cases and USAGE EXAMPLE was
the last one, as required by our coding standards.  It is a good practice to
move that test case to the first part.

Observe that `//@` can be used to add empty lines.  One may also write comment
lines by having `#` as the first non-white space character after the `//@`:

```cpp
{|CONTROL-COMMENT-PREFIX|}PARTS (syntax version 1.0.0)
//@
//@  CASES: 1..10, 19
//@#        Test case 19 is USAGE EXAMPLE
//@  CASES: 11..END
//@         # Could have written 11..18
```
Comments on the `CASE:` lines themselves are not supported.

### Sliced Test Cases in PARTS Guide

Test cases for complicated C++ templates (with many template argument
combinations) may require slicing up single test cases into smaller pieces that
can be compiled, built, and run in a reasonable time.

The slicing of a test case is defined in the test case code itself.

Sliced test cases produce more than one part, and this is denoted in the PARTS
Guide by appending the case number of split test cases with .SLICES (as shown
below).  While this syntax is not strictly necessary, it calls attention to the
complexity of part numbers introduced by split test cases.

```cpp
{|CONTROL-COMMENT-PREFIX|}PARTS (syntax version 1.0.0)
//@
//@  CASES: 1, 24..25
//@  CASES: 2.SLICES
//@  CASES: 3.SLICES
//@ # Case 4 is sliced, case 5 is not - only one case per line may be sliced
//@  CASES: 4.SLICES, 5
//@  CASES: 6.SLICES
//@  CASES: 7.SLICES, 8
//@  CASES: 9.SLICES
//@  CASES: 10.SLICES, 11, 12
//@  CASES: 13.SLICES, 14
//@  CASES: 15.SLICES
//@  CASES: 16.SLICES
//@  CASES: 17.SLICES, 18..END
```
The above PARTS Guide shows the splitting of 'bslstl_hashtable.xt.cpp' (at the
time of writing this syntax help) and results in 45 parts.  That many parts
enables us to compile and run the individual test executables (from
'bslstl_hashtable.01.t' to 'bslstl_hashtable.45.t') even on the slowest
platforms (AIX).

As you can see in the example, the sliced test cases are indicated by adding
`.SLICES` right after the test case number.  This syntax is not strictly
necessary for the script to work, but it is required so that human observers
are aware of the complexity added by the slicing, and that they need to look at
the code of those test cases to see how many slices they have (how many parts
they add).

No two `.SLICES` test cases may appear on a single `CASES:` line.  Unsliced
test case numbers may precede or follow the `.SLICES` test case.  They will be
placed into the first or last part generated by the sliced test case, before or
after the first/last slice, respectively.

### Negative Test Cases

Negative test cases cannot be sliced.  Negative test cases are usually
interactive or benchmarking tests that will not work if sliced.

It is strongly recommended to place negative test cases into the first part.

Negative test cases will always be emitted into the output file after the
positive test cases regardless of the ordering in the PARTS Guide.

```cpp
{|CONTROL-COMMENT-PREFIX|}PARTS (syntax version 1.0.0)
//@
//@  CASES: -1, 1..10, 35
//@  CASES: 11..22
//@  CASES: 23..END
```
In the above example, test case -1 will be the last test case in the `main`
function of 'bslstl_deque.01.t.cpp', followed by the `default:` even though -1
is before the positive numbers in the `CASES:` line.

## Slicing Test Cases

Test cases can be sliced by slicing code, slicing a list of types (from a macro
definition), or certain combinations of the two.

### Slicing Code

Slicing code uses 3 control commments:
  1. `{|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN`
  2. `{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK`
  3. `{|CONTROL-COMMENT-PREFIX|}CODE SLICING END`

The script currently supports only one code slicing per test case.  Slicing the
code in two or more places would result in an exponential number of test cases.

#### Slicing Executable Code

Test cases are normally sliced because the code takes too long to compile.  The
following example demonstrates how code may be sliced to reduce compilation
time.

```cpp
      case 9: {
        // --------------------------------------------------------------------
        // TEST CASE TITLE
        // ~~~
        // --------------------------------------------------------------------

        if (verbose) puts("\nTEST CASE TITLE"
                          "\n===============");

        static struct {
            int d_line;
            ~~~
        } TEST_DATA[] = {
            { L_, ~~~ },
            ~~~
            { L_, ~~~ },
        };
        const size_t TEST_SIZE = sizeof TEST_DATA / sizeof *TESTDATA;

        for (size_t ti = 0; ti < TEST_SIZE; ++ti) {
            const int LINE = TEST_DATA[ti].d_line;
            ~~~

            if (veryVerbose) { P_(LINE) P_(~~~) P(~~~); }

            // for-loop-prefix-code
            ~~~

            {|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
            // long-to-compile-code-slice-1
            ~~~
            {|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
            // long-to-compile-code-slice-2
            ~~~
            {|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
            // long-to-compile-code-slice-3
            ~~~
            {|CONTROL-COMMENT-PREFIX|}CODE SLICING END

            // for-loop-suffix-code
            ~~~
        }
      } break;
```
The above code will result in 3 test case slices, example output for the first
slice is below.

```cpp
      case 9: {  // Case 9 slice 1
        // --------------------------------------------------------------------
        // TEST CASE TITLE
        // ~~~
        // --------------------------------------------------------------------

        if (verbose) puts("\nTEST CASE TITLE"
                          "\n===============");

        static struct {
            int d_line;
            ~~~
        } TEST_DATA[] = {
            { L_, ~~~ },
            ~~~
            { L_, ~~~ },
        };
        const size_t TEST_SIZE = sizeof TEST_DATA / sizeof *TESTDATA;

        for (size_t ti = 0; ti < TEST_SIZE; ++ti) {
            const int LINE = TEST_DATA[ti].d_line;
            ~~~

            if (veryVerbose) { P_(LINE) P_(~~~) P(~~~); }

            // for-loop-prefix-code
            ~~~

            // long-to-compile-code-slice-1
            ~~~

            // for-loop-suffix-code
            ~~~
        }
      } break;
```

#### Slicing on Test Data

When a test _runs_ for too long we may decide to compile slices with fewer test
data.  Similar to how code was sliced in the previous example we could slice
the lines of `TEST_DATA` into (say) 2 pieces:

```cpp
      case 9: {
        // --------------------------------------------------------------------
        // TEST CASE TITLE
        // ~~~
        // --------------------------------------------------------------------

        if (verbose) puts("\nTEST CASE TITLE"
                          "\n===============");

        static struct {
            int d_line;
            ~~~
        } TEST_DATA[] = {
        {|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
            { L_, ~~~ },
            ~~~
        {|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
            { L_, ~~~ },
            ~~~
        {|CONTROL-COMMENT-PREFIX|}CODE SLICING END
        };
        const size_t TEST_SIZE = sizeof TEST_DATA / sizeof *TESTDATA;

        for (size_t ti = 0; ti < TEST_SIZE; ++ti) {
            const int LINE = TEST_DATA[ti].d_line;
            ~~~
```
### Slicing Type Lists

Often when a test driver is too large to compile, a comma-separated list of
types is being used to test a template.  The script is able to create test case
slices that each test only a subset of those types.

Type list slicing requires the type list to be defined as a macro, immediately
following the `SLICING TYPELIST` comment.  This example is from
'bslstl_hastable.xt.cpp':

```cpp
    {|CONTROL-COMMENT-PREFIX|}SLICING TYPELIST / 4
    #define u_TESTED_TYPES                                                    \
        BSLTF_TEMPLATETESTFACILITY_TEST_TYPES_REGULAR,                        \
        bsltf::NonAssignableTestType,                                         \
        bsltf::NonDefaultConstructibleTestType,                               \
        TestTypes::MostEvilTestType
```

Type list slicing is a simple process.  The macro definition is "parsed" to get
out the name of the macro we need to (re)define in the part files, and the
initial list that needs to be expanded.

The expansion of the initial list is also a very simple process.  The script
does not do standard C preprocessing.  The details are described in Type List
Expansion Process, here only the important consequences are described.  The
macros may not be conditionally-defined, the script does not handle
preprocessor conditions (`#ifdef` etc).  There may be *one* definition of a
macro name in the list in the expected place, otherwise the script will give an
error.  The script does not care about the `#include` directives.  Macros whose
name match with exist component names will be looked up in that component,
while other macros will only be searched for in the .xt.cpp file itself.

Once the macro replacement is fully expanded we will a list of a certain number
of types.  The slicing uses integer divison to create the based-number of types
in a slice, then the remainder is distributed between the slices.  Suppose we
had 19 types, asked for 4 slices.  Integer division 19 / 4 results is 4 with a
remainder of 3.  The script will then increase the size of the first 3 type
slices by 1, resulting in a 5, 5, 5, 4 distribution of types.  First 5 types go
into slice 1, next 5  into slice 2, etc. and the last 4 types into slice 4.
	
The above example from bslstl_hashtable.xt.cpp will then be expanded into the
following  4 macro definitions in 4 separately generated parts:

```cpp
    //#bdetdsplit sliced typelist 'u_TESTED_TYPES' slice 1 of 4
#line 9539 "../../../bde/groups/bsl/bslstl/bslstl_hashtable.xt.cpp"
    #define u_TESTED_TYPES signed char, size_t, const char *, \
            bsltf::TemplateTestFacility::ObjectPtr,           \
            bsltf::TemplateTestFacility::FunctionPtr
```

```cpp
    //#bdetdsplit sliced typelist 'u_TESTED_TYPES' slice 2 of 4
#line 9539 "../../../bde/groups/bsl/bslstl/bslstl_hashtable.xt.cpp"
    #define u_TESTED_TYPES bsltf::TemplateTestFacility::MethodPtr, \
            bsltf::EnumeratedTestType::Enum, bsltf::UnionTestType, \
            bsltf::SimpleTestType, bsltf::AllocTestType
```

```cpp
    //#bdetdsplit sliced typelist 'u_TESTED_TYPES' slice 3 of 4
#line 9539 "../../../bde/groups/bsl/bslstl/bslstl_hashtable.xt.cpp"
    #define u_TESTED_TYPES bsltf::BitwiseCopyableTestType, \
            bsltf::BitwiseMoveableTestType,                \
            bsltf::AllocBitwiseMoveableTestType,           \
            bsltf::MovableTestType, bsltf::MovableAllocTestType
```

```cpp
    //#bdetdsplit sliced typelist 'u_TESTED_TYPES' slice 4 of 4
#line 9539 "../../../bde/groups/bsl/bslstl/bslstl_hashtable.xt.cpp"
    #define u_TESTED_TYPES bsltf::NonTypicalOverloadsTestType, \
            bsltf::NonAssignableTestType,                      \
            bsltf::NonDefaultConstructibleTestType,            \
            TestTypes::MostEvilTestType
```

There can be one sliced type list in a test case unless the different type
lists are each in their own code slice; see examples below.

#### Slicing More Than One Type List

When multiple typelists need to be broken up across different parts --- where
each typelist is used in different top-level slices of the same test case ---
different typelist slicings may be nested in distinct code slicing blocks.

```cpp
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
    //@bdetdsplit SLICING TYPELIST / 4
    #define u_TESTED_TYPES                                                    \
        BSLTF_TEMPLATETESTFACILITY_TEST_TYPES_REGULAR,                        \
        bsltf::NonAssignableTestType,                                         \
        bsltf::NonDefaultConstructibleTestType,                               \
        TestTypes::MostEvilTestType

        u_RUN_HARNESS(TestCases_BasicConfiguration);
        u_RUN_HARNESS(TestCases_BsltfConfiguration);

        ~~~
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
    #define u_TESTED_TYPES_NOALLOC                                            \
            BSLTF_TEMPLATETESTFACILITY_TEST_TYPES_PRIMITIVE,                  \
            bsltf::EnumeratedTestType::Enum,                                  \
            bsltf::UnionTestType,                                             \
            bsltf::SimpleTestType,                                            \
            bsltf::BitwiseMoveableTestType,                                   \
            bsltf::NonTypicalOverloadsTestType,                               \
            bsltf::NonTypicalOverloadsTestType,                               \
            bsltf::NonDefaultConstructibleTestType
        u_RUN_HARNESS_WITH(TestCases_ConvertibleValueConfiguration,
                           u_TEST_TYPES_NOALLOC);
{|CONTROL-COMMENT-PREFIX|}CODE SLICING END
```
In the above example `u_TESTED_TYPES_NOALLOC` is not sliced, so the number of
slices created is 4 + 1 => 5.  First 4 slices containing code slice 1 and
`u_TESTED_TYPES` slices 1 to 4, then the last slice contains code slice 2.

A more complicated example from the same file has both type lists sliced:

```cpp
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
    {|CONTROL-COMMENT-PREFIX|}SLICING TYPELIST / 5
    #define u_TESTED_TYPES                                                    \
        BSLTF_TEMPLATETESTFACILITY_TEST_TYPES_REGULAR,                        \
        bsltf::NonAssignableTestType,                                         \
        bsltf::NonDefaultConstructibleTestType,                               \
        TestTypes::MostEvilTestType

        u_RUN_HARNESS(TestCases_BasicConfiguration);
        u_RUN_HARNESS(TestCases_BsltfConfiguration);
        ~~~
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
    {|CONTROL-COMMENT-PREFIX|}SLICING TYPELIST / 2
#define u_TESTED_TYPES_NOALLOC                                                \
            BSLTF_TEMPLATETESTFACILITY_TEST_TYPES_PRIMITIVE,                  \
            bsltf::EnumeratedTestType::Enum,                                  \
            bsltf::UnionTestType,                                             \
            bsltf::SimpleTestType,                                            \
            bsltf::BitwiseMoveableTestType,                                   \
            bsltf::NonTypicalOverloadsTestType,                               \
            bsltf::NonTypicalOverloadsTestType,                               \
            bsltf::NonDefaultConstructibleTestType

        u_RUN_HARNESS_WITH(TestCases_StatefulAllocatorConfiguration,
                           u_TEST_TYPES_NOALLOC);
{|CONTROL-COMMENT-PREFIX|}CODE SLICING END
```
The above splitting will result in 7 slices, first the 5 type list slices of
code slice 1, then the 2 type list slices of code slice 2.

#### Nested Code Slicing

There may be a nested type slicing or a code slicing in a code slice.  Not both
for the same code slice.  See nested type slicing in the previous title.

When code-slicing we may meet a situation where the necessary slicing would
require duplicating code.  For example:

```cpp
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
		#define HELPER_MACRO ...
        // test code that "fills" one part

        // test code that "fills" one part

        // test code that "fills" one part
		#undef HELPER_MACRO
```

If we were to have only one level of code slicing we would need to either
duplicate the helper macro in each slice, or move its `#define` before the
`CODE SLICING BEGIN`, and the `#undef` after the `END`.  Both feel wrong, and
we can avid adding code smells like that by using a nested code slice:


```cpp
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
		#define HELPER_MACRO ...
  {|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN
        // test code that "fills" one part
  {|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
        // test code that "fills" one part
  {|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK
        // test code that "fills" one part
  {|CONTROL-COMMENT-PREFIX|}CODE SLICING END
		#undef HELPER_MACRO
```

#### Naming Code Slices

Code slices can have identifiers used by the `FOR` control-comment to refer to
them in a stable way.  (Code slice numbers may change.)

Code slice names must be identifiers (start with a letter, followed by letter,
decimal digit or underscore).  It is recommended to use names that describe why
it was necessary to name the slice, such as `uses_createWidgetIn3D`.

Code slice names must be unique within a test case.

The code slice names are placed to the end of the control comment that begins
the slice being named, so the can be on `CODE SLICING BEGIN` and `BREAK` lines,
but not on `END`.

```cpp
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BEGIN uses_createWidgetIn3D
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK uses_transmogrify
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING BREAK needs_debugprintWidget
        // test code that "fills" one part
{|CONTROL-COMMENT-PREFIX|}CODE SLICING END
```

For further information see Conditional Code Outside of Test Cases.

#### Last Resort, or Multiplicative Slicing

In a situation where a test case is so huge that even slicing every type in its
type list into its own part won't solve compilation or run time problems, it is
possible to slice a test case first on type list, then on code.  Such slicing
will produce a total number of slices equal to the product of the number of
type list slices and the number of code slices.  The emitted slices will first
test all code slices using the first type list slice (which will usually be the
first type) and then all the test code slices with the rest of the type slices
one by one.

At the time of writing no code requires such brute force slicing.

This kind of slicing can be easily recognized by observing that the type
slicing (and the type list macro definition) is outside of the code slicing.

Code slices may not be named in multiplicative slicing because they do not
correspond to one slice only.

### Placing Code Into First or Last slice

Sometimes test cases have both test code that uses a type list, and "special"
test code that does not use the type list.  It would be wasteful to have such
code built and executed in each test case slice, so we have control comments
that instruct the script to place them into the first or the last slice of the
test case.

If the type-list-independent code is so expensive that it needs its own test
slice, code slicing has to be used.

There are two ways to mark such code.  Blocks of code may use:
  - `{|CONTROL-COMMENT-PREFIX|}INTO FIRST SLICE BEGIN`
  - `{|CONTROL-COMMENT-PREFIX|}INTO FIRST SLICE END`
  - `{|CONTROL-COMMENT-PREFIX|}INTO LAST SLICE BEGIN`
  - `{|CONTROL-COMMENT-PREFIX|}INTO LAST SLICE END`

For a single line of code, end-of-line comment may be used:
  - `u_RUN_AWKWARD_MAP_LIKE(testCase10); {|CONTROL-COMMENT-PREFIX|}INTO FIRST SLICE`
  - `u_RUN_AWKWARD_MAP_LIKE(testCase10); {|CONTROL-COMMENT-PREFIX|}INTO LAST SLICE`

## Conditional Code Outside of Test Cases

As test cases (or part of sliced test cases) are omitted from the generated
parts we may receive compiler warnings about unused entities (mostly `static`
functions).  The script provides the `{|CONTROL-COMMENT-PREFIX|}FOR ...`
control comments to tell that certain code sections are needed only for certain
test cases, or test case slices.

The `FOR ` control comment needs attention as removing code in C++ may change
the meaning of code.  Do not use a `FOR` comment to remove functions from an
overload set, or a set of function-templates.

The intention of the `FOR` comment is to be able to indicate that some simple
code item (like a file-static helper function) is used only in certain test
cases (or slices) without disabling all unused-code warnings.  If adding just a
few and simple `FOR` comments does not solve the issue of unused warnings
consider adding `BSLA_MAYBE_UNUSED` annotations to the entities generating
them.  If that is too much work, consider the option described in the next
paragraph.

Note that a `{|CONTROL-COMMENT-PREFIX|}SILENCE WARNINGS: UNUSED` is available
to turn off compiler warnings about unused (common test) code for difficult
test drivers where adding `FOR` comments by hand would be too much work.  See
complete discussion of that feature under Miscellanous Control Comments.

`{|CONTROL-COMMENT-PREFIX|}FOR ...` comments may only be used outside of the
`switch(test)` block in main.  Attempting to use them within a test case will
result in an error when running the script.

There are begin/end, and single-line variations of the `FOR` control comment:

  - `{|CONTROL-COMMENT-PREFIX|}FOR case-or-slice-list BEGIN`
  - `{|CONTROL-COMMENT-PREFIX|}FOR case-or-slice-list END`
  - `typedef Elem int; {|CONTROL-COMMENT-PREFIX|}FOR case-or-slice-list`

The list is comma separated test case numbers, or `test-case.slice-name`.  For
slice names see Naming Code Slices.

The code will only be emitted when any of the listed test cases or test case
slices are active.  If a sliced test case is listed without a slice specified
(no `.slice-name`) the code will be active for every slice.

For example `{|CONTROL-COMMENT-PREFIX|}FOR 4, 6, 17.needs_ggg BEGIN` will emit
the conditional code block into the parts that contain test cases 4, 6, and
slice 2 of test case 17.  If test case 4 or 6 (or both) have slices, the
conditional code will be emitted for each part containing any slice of such
test cases.

`FOR` blocks may be nested.  The script does not verify whether the nesting
 "makes sense".  If a block for test case 4 is nested in a block for only test
case 2 the inner test case 2 block will never be emitted.

To ensure that `BEGIN`/`END` match up as intended the `END` block **must**
contain the **exact same** list as `BEGIN`.  'Exact same' here means matching
character by character.

Note that when removing code (that causes an "unused" warning) with a `FOR`
block you may need to remove other code with the same `FOR` condition (list) if
other code (outside of `main`) uses the "commented out" name.  For example in a
template test driver that has a `TestDriver<...>::testCase17()` function (that
uses the entity "unused" outside of test case 17) at least the function body of
`TestDriver<...>::testCase17()` has to be removed from parts where it is unsed
by using `{|CONTROL-COMMENT-PREFIX|}FOR 17 BEGIN/END`.

## Miscellanous Control Comments

There are two "special" control comments that control aspects that are not
splitting or slicing.

### Turning Off Warnings

`{|CONTROL-COMMENT-PREFIX|}SILENCE WARNINGS: UNUSED` may be used to turn off
warnings about unused entities while compiling the parts.  Currently no other
warnings are supported.

It is recommended to place this control comment nearby the `PARTS` table so it
is easy to find, and that placement indicates it is a global command.  In
reality this comment may be placed anywhere.

### Turning Off Line Directives

Normally (when generating parts) the script places
`#line <number> "file_name.xt.cpp"` directives into the output (part) files so
every compiler warning/error message, and every run-time `ASSERT` message will
refer back to the original `.xt.cpp` file.  The problem arises when a compiler
error or warning is not caused by the original code, but because code is
missing from the part; or it may be caused by a fault in the script that
generates broken C++.

The issue is that in such cases the compiler error/warning will not refer to
the part file being compiled, so during a build it may be very hard to figure
out which part actually has the error.  (Since compilations are usually run in
parallel.)

`{|CONTROL-COMMENT-PREFIX|}LINE DIRECTIVES: OFF` will turn off the generation of said
directives so the messages will refer to the actual file being compiled.  That
makes it easy to go to said file and find out why the error occurs.

It is recommended to place this control comment nearby the `PARTS` table so it
is easy to find, and that placement indicates it is a global command.  In
reality this comment may be placed anywhere.

This command is a debugging tool.  Do not ever propose code for the main branch
that contains `{|CONTROL-COMMENT-PREFIX|}LINE DIRECTIVES: OFF`.

There is also a `{|CONTROL-COMMENT-PREFIX|}LINE DIRECTIVES: ON` variation, which may make
sense together with the `--[no-]line-directives` command line flag mentioned
below.

The command also has corresponding script command line flags.  The comment
in the file, if exists, overrides the `--[no-]line-directives` command line
flags.

## Type List Expansion Process

The script uses heuristics to avoid the complexities of having to include a
full-featured C preprocessor.  The process expects macro names to be
BDE-compliant.

The expansion process works on the value of the macro defined immediately
following the `{|CONTROL-COMMENT-PREFIX|}SLICING TYPELIST / n` control comment.

The process expands those names in the list that it deems are macros by their
spelling, and if the expansion result contains further macros they are
expanded, too.  Note that the type list macro itself is not looked up by this
process, it is simply the macro definiton below the control-comment.

Macro names are names that start with an uppercase letter, and are followed by
at least two characters that may be uppercase letter, decimal digit, or the
underscore character.

The heuristic process does not work with the `#include` directives.  It instead
reads the names of *all* component from `.mem` files of "normal" BDE packages
and creates a list of possible macro prefixes.  For example the component
`bsltf_templatetestfacility` adds the `BSLTF_TEMPLATETESTFACILITY_` prefix.
The macro prefixes map to the header files.

When a macro is found that matches a macro prefix it is also looked up in the
header of the matching component.

All macros are always looked up in the *complete* test driver source code
itself.  Note that this heuristic means the script may find a macro that is
defined *after* its use!

Finding more than one definiton for a macro is a hard error.  Since the script
does not support preprocessor conditionals, the `#undef` directive, or include
directives, this rules is used to detect (well-enough) if those are present.

No two definitions are allowed, period.  Not just within a file.  So if a macro
is defined in both the .xt.cpp and the header of a matching component that is
an error.

The script has a "groups path".  The 'groups' directory of the input file is
added to this path automatically, if it exists.  In case the input file does
not reside in a '.../groups/grp/grppkg/' BDE-standard directory it may be
necessary to specify 'groups' path, which can be done using the `-o` command
line arguments to the script.  However this is something that the build system
has to do, it is mentioned here for completeness only.

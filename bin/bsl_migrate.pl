#!/bb/bin/perl

$|++;

my $ct="/usr/atria/bin/cleartool";

while (0 <= $#ARGV) {

    my $filename = shift(@ARGV);
    my $path = $filename;
    $path =~ s/(.*)\/(.*?)$/$1/;

    # In case it's the same directory
    if ($path eq $filename) {
        $path = ".";
    }

    open (MODFILE, ">>$path/modified.txt");
    open (NOTMATCHFILE, ">>$path/notmatched.txt");
    open (PROBLEMFILE, ">>$path/problem.txt");

    print "Processing ".$filename." with bsl_migrate.pl\n";

    # TASK 0: Read the whole file in '@lines' for easier processing and
    # backtracking if necessary.

    open (FILE, "<$filename");
    my (@lines) = <FILE>;
    close(FILE);

    my $numLines = $#lines;

    # TASK 1:  Replace include files

    my $foundIncludes = 0;
    my $found = 0;

    my $skiplevel = 0;
    LINE:
    for ($i = 0; $i <= $numLines; ++$i) {
        chomp $lines[$i];

        # Skip the section that's labelled transitive include
        if ($lines[$i] =~ /BDE_DONT_ALLOW_TRANSITIVE_INCLUDES/) {
            ++$skipLevel;

            while ($skipLevel != 0) {
                ++$i;
                chomp $lines[$i];
                if ($lines[$i] =~ /#if/) {
                    ++$skipLevel;
                }

                if ($lines[$i] =~ /#endif/) {
                    --$skipLevel;
                }
            }
            next LINE;
        }

        if ($lines[$i] =~ /^\s*#\s*ifndef\s*INCLUDED/) {

            # special case for limits.h, string.h, locale.h
            if ($lines[$i] =~ /INCLUDED_(LIMITS|STRING|LOCALE)/x) {
                my $count = $i + 1;
                my $guard = $1;
                while (!($lines[$count] =~ /^\s*#\s*include/)) {
                    ++$count;
                }
                if ($lines[$count] =~ /<(limits|string|locale)\.h>/x) {
                    $lines[$i] =~ s/INCLUDED_.*/INCLUDED_BSL_C_$guard/;
                }
                elsif ($lines[$count] =~ /<(limits|string|locale)>/x) {
                    $lines[$i] =~ s/INCLUDED_LIMITS/INCLUDED_BSL_$guard/;
                }
                else {
                    print PROBLEMFILE "$filename: problem with INCLUDED_$guard";
                }
                $found = 1;
            }

            # changing include guards for STL headers
            if ($lines[$i] =~ s/INCLUDED_
                                    (ALGORITHM
                                    |BITSET
                                    |CASSERT
                                    |CCTYPE
                                    |CERRNO
                                    |CFLOAT
                                    |CISO646
                                    |CLIMITS
                                    |CLOCALE
                                    |CMATH
                                    |COMPLEX
                                    |CSETJMP
                                    |CSIGNAL
                                    |CSTDARG
                                    |CSTDDEF
                                    |CSTDIO
                                    |CSTDLIB
                                    |CSTRING
                                    |CTIME
                                    |CWCHAR
                                    |CWCTYPE
                                    |DEQUE
                                    |EXCEPTION
                                    |FSTREAM
                                    |FUNCTIONAL
                                    |HASH_MAP
                                    |HASH_SET
                                    |IOMANIP
                                    |IOS
                                    |IOSFWD
                                    |IOSTREAM
                                    |ISTREAM
                                    |ITERATOR
                                    |LIST
                                    |LOCALE
                                    |MAP
                                    |MEMORY
                                    |NEW
                                    |NUMERIC
                                    |OSTREAM
                                    |QUEUE
                                    |SET
                                    |SLIST
                                    |SSTREAM
                                    |STACK
                                    |STDEXCEPT
                                    |STREAMBUF
                                    |STRING
                                    |STRSTREAM
                                    |TYPEINFO
                                    |UTILITY
                                    |VALARRAY
                                    |VECTOR)\s*$
                              /INCLUDED_BSL_\1/x) {
                $found = 1;
                next LINE;
            }

            if ($lines[$i] =~ s/INCLUDED_
                                 (ASSERT
                                 |CTYPE
                                 |ERRNO
                                 |FLOAT
                                 |ISO646
                                 |LOCALE
                                 |MATH
                                 |SETJMP
                                 |SIGNAL
                                 |STDARG
                                 |STDDEF
                                 |STDIO
                                 |STDLIB
                                 |STRING
                                 |TIME
                                 |WCHAR
                                 |WCTYPE)\s*$
                              /INCLUDED_BSL_C_\1/x) {
                $found = 1;
                next LINE;
            }


            # changing include guards for BDE headers
            if ($lines[$i] =~ s/INCLUDED_BDE
                                    (ALG_ARRAYDESTRUCTIONPRIMITIVES
                                    |ALG_ARRAYPRIMITIVES
                                    |ALG_AUTOARRAYDESTRUCTOR
                                    |ALG_AUTOARRAYMOVEDESTRUCTOR
                                    |ALG_AUTOSCALARDESTRUCTOR
                                    |ALG_BITWISEEQPASSTHROUGHTRAIT
                                    |ALG_CONSTRUCTORPROXY
                                    |ALG_HASTRAIT
                                    |ALG_PASSTHROUGHTRAIT
                                    |ALG_RANGECOMPARE
                                    |ALG_SCALARDESTRUCTIONPRIMITIVES
                                    |ALG_SCALARPRIMITIVES
                                    |ALG_SELECTTRAIT
                                    |ALG_TYPETRAITS
                                    |ALG_TYPETRAITBITWISECOPYABLE
                                    |ALG_TYPETRAITBITWISEEQUALITYCOMPARABLE
                                    |ALG_TYPETRAITBITWISEMOVEABLE
                                    |ALG_TYPETRAITHASPOINTERSEMANTICS
                                    |ALG_TYPETRAITHASSTLITERATORS
                                    |ALG_TYPETRAITHASTRIVIALDEFAULTCONSTRUCTOR
                                    |ALG_TYPETRAITPAIR
                                    |ALG_TYPETRAITSGROUPPOD
                                    |ALG_TYPETRAITSGROUPSTLORDERED
                                    |ALG_TYPETRAITSGROUPSTLSEQUENCE
                                    |ALG_TYPETRAITSGROUPSTLUNORDERED
                                    |MA_ALLOCATOR
                                    |MA_AUTODEALLOCATOR
                                    |MA_AUTODESTRUCTOR
                                    |MA_BUFFERALLOCATOR
                                    |MA_DEFAULT
                                    |MA_DEFAULTALLOCATORGUARD
                                    |MA_MANAGEDALLOCATOR
                                    |MA_NEWDELETEALLOCATOR
                                    |MA_PLACEMENTNEW
                                    |MA_TESTALLOCATOR
                                    |MA_TESTALLOCATOREXCEPTION
                                    |MF_ANYTYPE
                                    |MF_ARRAYTOPOINTER
                                    |MF_ASSERT
                                    |MF_FORWARDINGTYPE
                                    |MF_FUNCTIONPOINTERTRAITS
                                    |MF_IF
                                    |MF_ISARRAY
                                    |MF_ISBITWISE
                                    |MF_ISCLASS
                                    |MF_ISCONVERTIBLE
                                    |MF_ISENUM
                                    |MF_ISFUNDAMENTAL
                                    |MF_ISPOINTER
                                    |MF_ISPOINTERTOMEMBER
                                    |MF_ISPOLYMORPHIC
                                    |MF_ISSAME
                                    |MF_MEMBERFUNCTIONPOINTERTRAITS
                                    |MF_NIL
                                    |MF_OR
                                    |MF_REMOVECVQ
                                    |MF_REMOVEREFERENCE
                                    |MF_SWITCH
                                    |MF_TYPELIST
                                    |S_ALIGNEDBUFFER
                                    |S_ALIGNMENT
                                    |S_ASSERT
                                    |S_BUILDTARGET
                                    |S_LENGTHERROR
                                    |S_LOGICERROR
                                    |S_OBJECTBUFFER
                                    |S_OUTOFRANGE
                                    |S_PLATFORM
                                    |S_PLATFORMUTIL
                                    |S_STDEXCEPTIONTRANSLATOR
                                    |S_STOPWATCH
                                    |STL_ALLOCATOR
                                    |STL_ALLOCATORPROXY
                                    |STL_CONTAINERBASE
                                    |STL_DEQUE
                                    |STL_DEQUEIMPUTIL
                                    |STL_ITERATOR
                                    |STL_ITERATOR2
                                    |STL_MOVE
                                    |STL_PAIR
                                    |STL_STRING
                                    |STL_STRINGIMPUTIL
                                    |STL_UTIL
                                    |STL_VECTOR
                                    |STL_VECTORIMPUTIL
                                    )\s*$
                              /INCLUDED_BSL\1/x) {
                $found = 1;
                next LINE;
            }

            # special case for bslma
            if ($lines[$i] =~ s/INCLUDED_BDEALG_TYPETRAITUSESBDEMAALLOCATOR
                               /INCLUDED_BSLALG_TYPETRAITUSESBSLMAALLOCATOR/x) {
                $found = 1;
                next LINE;
            }

            # special case for bdemf_metavalue
            if ($lines[$i] =~ s/INCLUDED_BDEMF_METAVALUE
                               /INCLUDED_BSLMF_METAINT/x) {
                $found = 1;
                next LINE;
            }

        }

        # changing actual headers
        if ($lines[$i] =~ /^\s*#\s*include/) {

            # STL headers
            if ($lines[$i] =~ s/<(algorithm
                                 |bitset
                                 |cassert
                                 |cctype
                                 |cerrno
                                 |cfloat
                                 |ciso646
                                 |climits
                                 |clocale
                                 |cmath
                                 |complex
                                 |csetjmp
                                 |csignal
                                 |cstdarg
                                 |cstddef
                                 |cstdio
                                 |cstdlib
                                 |cstring
                                 |ctime
                                 |cwchar
                                 |cwctype
                                 |deque
                                 |exception
                                 |fstream
                                 |functional
                                 |hash_map
                                 |hash_set
                                 |iomanip
                                 |ios
                                 |iosfwd
                                 |iostream
                                 |istream
                                 |iterator
                                 |limits
                                 |list
                                 |locale
                                 |map
                                 |memory
                                 |new
                                 |numeric
                                 |ostream
                                 |queue
                                 |set
                                 |slist
                                 |sstream
                                 |stack
                                 |stdexcept
                                 |streambuf
                                 |string
                                 |strstream
                                 |typeinfo
                                 |utility
                                 |valarray
                                 |vector
                                 )>
                               /<bsl_\1.h>/x) {
                $found = 1;
                next LINE;
            }

            # C headers
            if ($lines[$i] =~ s/<(assert\.h
                                 |ctype\.h
                                 |errno\.h
                                 |float\.h
                                 |iso646\.h
                                 |limits\.h
                                 |locale\.h
                                 |math\.h
                                 |setjmp\.h
                                 |signal\.h
                                 |stdarg\.h
                                 |stddef\.h
                                 |stdio\.h
                                 |stdlib\.h
                                 |string\.h
                                 |time\.h
                                 |wchar\.h
                                 |wctype\.h
                                 )>
                               /<bsl_c_\1>/x) {
                $found = 1;
                next LINE;
            }

            # special case for sys/time.h
            if ($lines[$i] =~ s/<sys\/time\.h>/<bsl_c_sys_time.h>/) {
                $found = 1;
                next LINE;
            }

            # BDE Headers
            if ($lines[$i] =~ s/<bde(alg_arraydestructionprimitives
                                   |alg_arrayprimitives
                                   |alg_autoarraydestructor
                                   |alg_autoarraymovedestructor
                                   |alg_autoscalardestructor
                                   |alg_bitwiseeqpassthroughtrait
                                   |alg_constructorproxy
                                   |alg_hastrait
                                   |alg_passthroughtrait
                                   |alg_rangecompare
                                   |alg_scalardestructionprimitives
                                   |alg_scalarprimitives
                                   |alg_selecttrait
                                   |alg_typetraitbitwisecopyable
                                   |alg_typetraitbitwiseequalitycomparable
                                   |alg_typetraitbitwisemoveable
                                   |alg_typetraithaspointersemantics
                                   |alg_typetraithasstliterators
                                   |alg_typetraithastrivialdefaultconstructor
                                   |alg_typetraitpair
                                   |alg_typetraitsgrouppod
                                   |alg_typetraitsgroupstlordered
                                   |alg_typetraitsgroupstlsequence
                                   |alg_typetraitsgroupstlunordered
                                   |alg_typetraits
                                   |ma_allocator
                                   |ma_autodeallocator
                                   |ma_autodestructor
                                   |ma_bufferallocator
                                   |ma_default
                                   |ma_defaultallocatorguard
                                   |ma_managedallocator
                                   |ma_newdeleteallocator
                                   |ma_placementnew
                                   |ma_testallocator
                                   |ma_testallocatorexception
                                   |mf_anytype
                                   |mf_arraytopointer
                                   |mf_assert
                                   |mf_forwardingtype
                                   |mf_functionpointertraits
                                   |mf_if
                                   |mf_isarray
                                   |mf_isbitwise
                                   |mf_isclass
                                   |mf_isconvertible
                                   |mf_isenum
                                   |mf_isfundamental
                                   |mf_ispointer
                                   |mf_ispointertomember
                                   |mf_ispolymorphic
                                   |mf_issame
                                   |mf_memberfunctionpointertraits
                                   |mf_nil
                                   |mf_or
                                   |mf_removecvq
                                   |mf_removereference
                                   |mf_switch
                                   |mf_typelist
                                   |s_alignedbuffer
                                   |s_alignment
                                   |s_assert
                                   |s_buildtarget
                                   |s_lengtherror
                                   |s_logicerror
                                   |s_objectbuffer
                                   |s_outofrange
                                   |s_platform
                                   |s_platformutil
                                   |s_stdexceptiontranslator
                                   |s_stopwatch
                                   |stl_allocator
                                   |stl_allocatorproxy
                                   |stl_containerbase
                                   |stl_deque
                                   |stl_dequeimputil
                                   |stl_iterator
                                   |stl_iterator2
                                   |stl_move
                                   |stl_pair
                                   |stl_string
                                   |stl_stringimputil
                                   |stl_util
                                   |stl_vector
                                   |stl_vectorimputil
                                   )
                                 /<bsl\1/x) {
                 $found = 1;
                 next LINE;
             }

            # special case for bslma
            if ($lines[$i] =~ s/bdealg_typetraitusesbdemaallocator/bslalg_typetraitusesbslmaallocator/) {
                $found = 1;
                next LINE;
            }

            # special case for bslma
            if ($lines[$i] =~ s/bdemf_metavalue/bslmf_metaint/) {
                $found = 1;
                next LINE;
            }

        }

        # ignoring current #define statements for std headers
        if ($lines[$i] =~ /#\s*define\s*INCLUDED_[A-Z_]+$/) {
            if (   $lines[$i] =~ /\#\s*define\s*INCLUDED_
                                 (?:ALGORITHM
                                  | BITSET
                                  | CASSERT
                                  | CCTYPE
                                  | CERRNO
                                  | CFLOAT
                                  | CISO646
                                  | CLIMITS
                                  | CLOCALE
                                  | CMATH
                                  | COMPLEX
                                  | CSETJMP
                                  | CSIGNAL
                                  | CSTDARG
                                  | CSTDDEF
                                  | CSTDIO
                                  | CSTDLIB
                                  | CSTRING
                                  | CTIME
                                  | CWCHAR
                                  | CWCTYPE
                                  | DEQUE
                                  | EXCEPTION
                                  | FSTREAM
                                  | FUNCTIONAL
                                  | HASH_MAP
                                  | HASH_SET
                                  | IOMANIP
                                  | IOS
                                  | IOSFWD
                                  | IOSTREAM
                                  | ISTREAM
                                  | ITERATOR
                                  | LIMITS
                                  | LIST
                                  | LOCALE
                                  | MAP
                                  | MEMORY
                                  | NEW
                                  | NUMERIC
                                  | OSTREAM
                                  | QUEUE
                                  | SET
                                  | SLIST
                                  | SSTREAM
                                  | STACK
                                  | STDEXCEPT
                                  | STREAMBUF
                                  | STRING
                                  | STRSTREAM
                                  | TYPEINFO
                                  | UTILITY
                                  | VALARRAY
                                  | VECTOR
                                  | ASSERT
                                  | CTYPE
                                  | ERRNO
                                  | FLOAT
                                  | ISO646
                                  | LIMITS
                                  | LOCALE
                                  | MATH
                                  | SETJMP
                                  | SIGNAL
                                  | STDARG
                                  | STDDEF
                                  | STDIO
                                  | STDLIB
                                  | STRING
                                  | TIME
                                  | WCHAR
                                  | WCTYPE
                                  )\s*$/x) {
                $lines[$i] = "my pointless string place holder";
            }
        }

    }
    $foundIncludes |= $found;

    # TASK 2: Change qualifiers.
    my $foundQualifiers = 0;
    $found = 0;
    for ($i = 0; $i <= $numLines; ++$i) {

        if ($lines[$i] =~ /^(\s*using\s*namespace\s*std\s*;)/) {
            print PROBLEMFILE $filename."\n";
            if ($lines[$i+1] =~ /^using namespace bsl;/) {
                $lines[$i] = "my pointless string place holder";
            }
            else {
                $lines[$i] =~ s/std/bsl/;
                $found = 1;
            }
        }

        if ($lines[$i] =~ s/([^\w]+|^)std(\s*)::/\1bsl\2::/g) {
            $found = 1;
        }

        # bde
        while ($lines[$i] =~ s/([^\w]+|^)bde
                               (ma_Allocator
                               |ma_AutoDeallocator
                               |ma_AutoDestructor
                               |ma_BufferAllocator
                               |ma_Default
                               |ma_DefaultAllocatorGuard
                               |ma_ManagedAllocator
                               |ma_NewDeleteAllocator
                               |ma_Placement
                               |ma_TestAllocator
                               |ma_TestAllocatorException
                               |s_AlignedBuffer
                               |s_AlignmentToType
                               |s_Alignment
                               |s_AlignmentOf
                               |s_Assert
                               |s_AssertFailureHandlerGuard
                               |s_ExcBuildTarget
                               |s_MtBuildTarget
                               |s_64BitBuildTarget
                               |s_LengthError
                               |s_LogicError
                               |s_ObjectBuffer
                               |s_OutOfRange
                               |s_Platform
                               |s_PlatformUtil
                               |s_StdExceptionTranslator
                               |s_Stopwatch
                               |alg_ArrayDestructionPrimitives
                               |alg_ArrayPrimitives
                               |alg_AutoArrayDestructor
                               |alg_AutoArrayMoveDestructor
                               |alg_AutoScalarDestructor
                               |alg_BitwiseEqPasstroughTrait
                               |alg_ConstructorProxy
                               |alg_HasTrait
                               |alg_PassthroughTrait
                               |alg_PassthroughTraitBdemaAllocator
                               |alg_RangeCompare
                               |alg_ScalarDestructionPrimitives
                               |alg_ScalarPrimitives
                               |alg_SelectTrait
                               |alg_TypeTraitBitwiseCopyable
                               |alg_TypeTraitBitwiseEqualityComparable
                               |alg_TypeTraitBitwiseMoveable
                               |alg_TypeTraitHasPointerSemantics
                               |alg_TypeTraitHasStlIterators
                               |alg_TypeTraitHasTrivialDefaultConstructor
                               |alg_TypeTraitPair
                               |alg_HasTrait
                               |alg_SelectTrait
                               |alg_PassthroughTrait
                               |alg_Passthrough_BdemaAllocator
                               |alg_PassthroughTraitBdemaAllocator
                               |alg_TypeTraits
                               |alg_TypeTraitsGroupPod
                               |alg_TypeTraitsGroupStlSequence
                               |alg_TypeTraitsGroupStlOrdered
                               |alg_TypeTraitsGroupStlHashed
                               |alg_TypeTraitsGroupStlUnordered
                               |alg_TypeTraitsGroupPod
                               |alg_TypeTraitsGroupStlOrdered
                               |alg_TypeTraitsGroupStlSequence
                               |alg_TypeTraitsGroupStlHashed
                               |alg_TypeTraitsGroupStlUnordered
                               |mf_AnyType
                               |mf_TypeRep
                               |mf_ArrayToPointer
                               |mf_ArrayToConstPointer
                               |mf_ForwardingType
                               |mf_ConstForwardingType
                               |mf_FunctionPointerTraits
                               |mf_IsFunctionPointer
                               |mf_If
                               |mf_IsArray
                               |mf_IsBitwiseCopyable
                               |mf_IsBitwiseMoveable
                               |mf_IsClass
                               |mf_IsConvertible
                               |mf_IsEnum
                               |mf_IsFundamental
                               |mf_IsPointer
                               |mf_IsPointerToMemberFunction
                               |mf_IsPointerToMemberData
                               |mf_IsPointerToMember
                               |mf_IsPolymorphic
                               |mf_IsSame
                               |mf_MemberFunctionPointerTraits
                               |mf_IsMemberFunctionPointer
                               |mf_Tag
                               |mf_MetaInt
                               |mf_Nil
                               |mf_Or
                               |mf_RemoveCvq
                               |mf_RemoveReference
                               |mf_Switch
                               |mf_Tag
                               |mf_TypeListNil
                               |mf_TypeList
                               |mf_TypeListTypeOf
                               |mf_TypeList0
                               |mf_TypeList1
                               |mf_TypeList2
                               |mf_TypeList3
                               |mf_TypeList4
                               |mf_TypeList5
                               |mf_TypeList6
                               |mf_TypeList7
                               |mf_TypeList8
                               |mf_TypeList9
                               |mf_TypeList10
                               |mf_TypeList11
                               |mf_TypeList12
                               |mf_TypeList13
                               |mf_TypeList14
                               |mf_TypeList15
                               |mf_TypeList16
                               |mf_TypeList17
                               |mf_TypeList18
                               |mf_TypeList19
                               |mf_TypeList20
                               |stl_Allocator
                               |stl_AllocatorTypeTraits
                               |stl_AllocatorProxy
                               |stl_AllocatorProxyBdemaBase
                               |stl_AllocatorProxyNonBdemaBase
                               |stl_ContainerBase
                               |stl_Deque
                               |stl_DequeImpUtil
                               |stl_InputIteratorTag
                               |stl_OutputIteratorTag
                               |stl_ForwardIteratorTag
                               |stl_BidirectionalIteratorTag
                               |stl_RandomAccessIteratorTag
                               |stl_IteratorTraits
                               |stl_ReverseIterator
                               |stl_IteratorUtil
                               |stl_ForwardIterator
                               |stl_BidirectionalIterator
                               |stl_RandomAccessIterator
                               |stl_IntegralIterator
                               |stl_MoveUtil
                               |stl_Move
                               |stl_Pair
                               |stl_String_Base
                               |stl_String
                               |stl_StringImpUtil
                               |stl_Util
                               |stl_Vector
                               |stl_VectorImpUtil
                               )([^\w]+|$)/\1bsl\2\3/gx) {
            $found = 1;
        }

        # bde
        while ($lines[$i] =~ s/([^\w]+|^)BDE
                               (_ASSERT_H
                               |_ASSERT_CPP
                               |S_PLATFORM__OS_UNIX
                               |S_PLATFORM__OS_WINDOWS
                               |S_PLATFORM__OS_VER_MAJOR
                               |S_PLATFORM__OS_VER_MINOR
                               |S_PLATFORM__OS_AIX
                               |S_PLATFORM__OS_CYGWIN
                               |S_PLATFORM__OS_DGUX
                               |S_PLATFORM__OS_HPUX
                               |S_PLATFORM__OS_LINUX
                               |S_PLATFORM__OS_SOLARIS
                               |S_PLATFORM__OS_SUNOS
                               |S_PLATFORM__OS_WIN2K
                               |S_PLATFORM__OS_WIN9X
                               |S_PLATFORM__OS_WINNT
                               |S_PLATFORM__OS_WINXP
                               |S_PLATFORM__CMP_VER_MAJOR
                               |S_PLATFORM__CMP_VER_MINOR
                               |S_PLATFORM__CMP_AIX
                               |S_PLATFORM__CMP_EDG
                               |S_PLATFORM__CMP_EPC
                               |S_PLATFORM__CMP_GNU
                               |S_PLATFORM__CMP_HP
                               |S_PLATFORM__CMP_MSVC
                               |S_PLATFORM__CMP_SUN
                               |S_PLATFORM__CPU_VER_MAJOR
                               |S_PLATFORM__CPU_VER_MINOR
                               |S_PLATFORM__CPU_64_BIT
                               |S_PLATFORM__CPU_32_BIT
                               |S_PLATFORM__CPU_88000
                               |S_PLATFORM__CPU_ALPHA
                               |S_PLATFORM__CPU_HPPA
                               |S_PLATFORM__CPU_IA64
                               |S_PLATFORM__CPU_INTEL
                               |S_PLATFORM__CPU_MIPS
                               |S_PLATFORM__CPU_POWERPC
                               |S_PLATFORM__CPU_SPARC
                               |S_PLATFORM__CPU_SPARC_32
                               |S_PLATFORM__CPU_SPARC_V9
                               |S_PLATFORM__CPU_X86
                               |S_PLATFORM__CPU_X86_64
                               |S_PLATFORMUTIL__IS_LITTLE_ENDIAN
                               |S_PLATFORMUTIL__IS_BIG_ENDIAN
                               |S_PLATFORMUTIL__HTONL
                               |S_PLATFORMUTIL__HTONS
                               |S_PLATFORMUTIL__NTOHL
                               |S_PLATFORMUTIL__NTOHS
                               |MF_ASSERT
                               |MF_TAG_TO_INT
                               |MF_TAG_TO_BOOL
                               |ALG_DECLARE_NESTED_TRAITS
                               |ALG_DECLARE_NESTED_TRAITS2
                               |ALG_DECLARE_NESTED_TRAITS3
                               |ALG_DECLARE_NESTED_TRAITS4
                               |ALG_DECLARE_NESTED_TRAITS5
                               |ALG_IMPLIES_TRAIT
                               |ALG_CHECK_IMPLIED_TRAIT
                               )([^\w]+|$)/\1BSL\2\3/gx) {
            $found = 1;
        }

        # special cases
        if ($lines[$i] =~ s/bdealg_TypeTraitUsesBdemaAllocator/bslalg_TypeTraitUsesBslmaAllocator/g) {
            $found = 1;
        }

        if ($lines[$i] =~ s/BDEMF_METAVALUE_TO_INT/BSLMF_METAINT_TO_INT/g) {
            $found = 1;
        }

        if ($lines[$i] =~ s/BDEMF_METAVALUE_TO_BOOL/BSLMF_METAINT_TO_BOOL/g) {
            $found = 1;
        }

        if ($lines[$i] =~ s/([^\w]+|^)bdemf_if([^\w]+|$)/\1bslmf_If\2/g) {
            $found = 1;
        }
    }
    $foundQualifiers |= $found;

    # OUTPUT:
    if (0 != $foundIncludes || $foundQualifiers) {

        print MODFILE $filename."\n";

        # checkout the file
        system("$ct co -c 'Migrating to BDE 2.0, change all 'std::' to 'bsl::'' $filename");
        if ($?) {
            print "Cannot checkout $filename, error $?\n";
        }
        else {
            system("chmod 644 $filename");
            system("cp $filename $filename.old");
            open (OUTFILE, ">$filename");

            my $fwdIncl = -1;
            for ($i = 0; $i <= $numLines; ++$i) {
                if ($lines[$i] ne "my pointless string place holder") {
                    print OUTFILE $lines[$i]."\n";
                }
            }

            close(OUTFILE);
        }
    }

#    print "Finished processing ".$filename."\n";

    close(MODFILE);
    close(NOTMATCHFILE);
    close(PROBLEMFILE);
}

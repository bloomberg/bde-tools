// csabbg_bslovrdstl.cpp                                              -*-C++-*-

#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/PrettyPrinter.h>
#include <clang/AST/RecursiveASTVisitor.h>
#include <clang/AST/Type.h>
#include <clang/Basic/IdentifierTable.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Lex/MacroInfo.h>
#include <clang/Lex/PPCallbacks.h>
#include <clang/Lex/Token.h>
#include <clang/Tooling/Refactoring.h>
#include <csabase_analyser.h>
#include <csabase_config.h>
#include <csabase_debug.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_filenames.h>
#include <csabase_location.h>
#include <csabase_ppobserver.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <csabase_visitor.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/ADT/Twine.h>
#include <llvm/Support/Casting.h>
#include <llvm/Support/Regex.h>
#include <llvm/Support/raw_ostream.h>
#include <stddef.h>
#include <cctype>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <vector>
#include <tuple>
namespace clang { class FileEntry; }
namespace clang { class MacroArgs; }
namespace clang { class Module; }
namespace csabase { class Visitor; }

using namespace csabase;
using namespace clang::ast_matchers;
using namespace clang::ast_matchers::internal;
using namespace clang::tooling;
using namespace clang;

// ----------------------------------------------------------------------------

static std::string const check_name("bsl-overrides-std");

// ----------------------------------------------------------------------------

namespace clang {
namespace ast_matchers {

const internal::VariadicDynCastAllOfMatcher<Stmt, UnresolvedLookupExpr>
unresolvedLookupExpr;

}
}

namespace
{

enum FileType { e_UNK = -1, e_NIL, e_BSL, e_STD, e_SPC };

struct file_info {
    const char *bsl;
    const char *bsl_guard;
    const char *std;
    const char *std_guard;
};

const char bsl_ns[] = "namespace bsl { }";

struct data
    // Data attached to analyzer for this check.
{
    data();
        // Create an object of this type.

    std::vector<std::string>                             d_file_stack;
    std::vector<FileID>                                  d_fileid_stack;
    bool                                                 d_in_bsl;
    bool                                                 d_in_std;
    bool                                                 d_bsl_overrides_std;
    llvm::StringRef                                      d_guard;
    SourceLocation                                       d_guard_pos;
    std::set<std::pair<std::string, SourceLocation>>     d_std_names;
    std::map<std::string, std::string>                   d_file_map;
    std::map<FileID, std::map<std::string, SourceLocation>>
                                                         d_once;
    std::map<FileID,
             std::vector<std::tuple<std::string, SourceLocation, bool> > >
                                                         d_includes;
    std::map<std::string, std::pair<std::vector<const file_info *>, FileType>>
                                                         d_file_info;
    std::map<FileID, SourceLocation>                     d_top_for_insert;
    std::map<FileID, llvm::StringRef>                    d_guards;
    std::vector<bool>                                    d_ovr_stack;
    bool                                                 d_insert_extcpp;
    bool                                                 d_insert_guard;
    std::map<SourceLocation, bool>                       d_noinc;
    std::map<std::tuple<FileID, FileID, SourceLocation>, SourceLocation>
                                                         d_fid_map;
};

data::data()
: d_in_bsl(false)
, d_in_std(false)
, d_ovr_stack(1)
{
}

const file_info include_pairs[] = {
    { "bsl_algorithm.h",     "INCLUDED_BSL_ALGORITHM",
      "algorithm",           "INCLUDED_ALGORITHM"          },
    { "bsl_bitset.h",        "INCLUDED_BSL_BITSET",
      "bitset",              "INCLUDED_BITSET"             },
    { "bsl_cassert.h",       "INCLUDED_BSL_CASSERT",
      "cassert",             "INCLUDED_CASSERT"            },
    { "bsl_cctype.h",        "INCLUDED_BSL_CCTYPE",
      "cctype",              "INCLUDED_CCTYPE"             },
    { "bsl_cerrno.h",        "INCLUDED_BSL_CERRNO",
      "cerrno",              "INCLUDED_CERRNO"             },
    { "bsl_cfloat.h",        "INCLUDED_BSL_CFLOAT",
      "cfloat",              "INCLUDED_CFLOAT"             },
    { "bsl_ciso646.h",       "INCLUDED_BSL_CISO646",
      "ciso646",             "INCLUDED_CISO646"            },
    { "bsl_climits.h",       "INCLUDED_BSL_CLIMITS",
      "climits",             "INCLUDED_CLIMITS"            },
    { "bsl_clocale.h",       "INCLUDED_BSL_CLOCALE",
      "clocale",             "INCLUDED_CLOCALE"            },
    { "bsl_cmath.h",         "INCLUDED_BSL_CMATH",
      "cmath",               "INCLUDED_CMATH"              },
    { "bsl_complex.h",       "INCLUDED_BSL_COMPLEX",
      "complex",             "INCLUDED_COMPLEX"            },
    { "bsl_csetjmp.h",       "INCLUDED_BSL_CSETJMP",
      "csetjmp",             "INCLUDED_CSETJMP"            },
    { "bsl_csignal.h",       "INCLUDED_BSL_CSIGNAL",
      "csignal",             "INCLUDED_CSIGNAL"            },
    { "bsl_cstdarg.h",       "INCLUDED_BSL_CSTDARG",
      "cstdarg",             "INCLUDED_CSTDARG"            },
    { "bsl_cstddef.h",       "INCLUDED_BSL_CSTDDEF",
      "cstddef",             "INCLUDED_CSTDDEF"            },
    { "bsl_cstdio.h",        "INCLUDED_BSL_CSTDIO",
      "cstdio",              "INCLUDED_CSTDIO"             },
    { "bsl_cstdlib.h",       "INCLUDED_BSL_CSTDLIB",
      "cstdlib",             "INCLUDED_CSTDLIB"            },
    { "bsl_cstring.h",       "INCLUDED_BSL_CSTRING",
      "cstring",             "INCLUDED_CSTRING"            },
    { "bsl_ctime.h",         "INCLUDED_BSL_CTIME",
      "ctime",               "INCLUDED_CTIME"              },
    { "bsl_cwchar.h",        "INCLUDED_BSL_CWCHAR",
      "cwchar",              "INCLUDED_CWCHAR"             },
    { "bsl_cwctype.h",       "INCLUDED_BSL_CWCTYPE",
      "cwctype",             "INCLUDED_CWCTYPE"            },
    { "bsl_deque.h",         "INCLUDED_BSL_DEQUE",
      "deque",               "INCLUDED_DEQUE"              },
    { "bsl_exception.h",     "INCLUDED_BSL_EXCEPTION",
      "exception",           "INCLUDED_EXCEPTION"          },
    { "bsl_fstream.h",       "INCLUDED_BSL_FSTREAM",
      "fstream",             "INCLUDED_FSTREAM"            },
    { "bsl_functional.h",    "INCLUDED_BSL_FUNCTIONAL",
      "functional",          "INCLUDED_FUNCTIONAL"         },
    { "bsl_hash_map.h",      "INCLUDED_BSL_HASH_MAP",
      "hash_map",            "INCLUDED_HASH_MAP"           },
    { "bsl_hash_set.h",      "INCLUDED_BSL_HASH_SET",
      "hash_set",            "INCLUDED_HASH_SET"           },
    { "bsl_iomanip.h",       "INCLUDED_BSL_IOMANIP",
      "iomanip",             "INCLUDED_IOMANIP"            },
    { "bsl_ios.h",           "INCLUDED_BSL_IOS",
      "ios",                 "INCLUDED_IOS"                },
    { "bsl_iosfwd.h",        "INCLUDED_BSL_IOSFWD",
      "iosfwd",              "INCLUDED_IOSFWD"             },
    { "bsl_iostream.h",      "INCLUDED_BSL_IOSTREAM",
      "iostream",            "INCLUDED_IOSTREAM"           },
    { "bsl_istream.h",       "INCLUDED_BSL_ISTREAM",
      "istream",             "INCLUDED_ISTREAM"            },
    { "bsl_iterator.h",      "INCLUDED_BSL_ITERATOR",
      "iterator",            "INCLUDED_ITERATOR"           },
    { "bsl_limits.h",        "INCLUDED_BSL_LIMITS",
      "limits",              "INCLUDED_LIMITS"             },
    { "bsl_list.h",          "INCLUDED_BSL_LIST",
      "list",                "INCLUDED_LIST"               },
    { "bsl_locale.h",        "INCLUDED_BSL_LOCALE",
      "locale",              "INCLUDED_LOCALE"             },
    { "bsl_map.h",           "INCLUDED_BSL_MAP",
      "map",                 "INCLUDED_MAP"                },
    { "bsl_memory.h",        "INCLUDED_BSL_MEMORY",
      "memory",              "INCLUDED_MEMORY"             },
    { "bsl_new.h",           "INCLUDED_BSL_NEW",
      "new",                 "INCLUDED_NEW"                },
    { "bsl_numeric.h",       "INCLUDED_BSL_NUMERIC",
      "numeric",             "INCLUDED_NUMERIC"            },
    { "bsl_ostream.h",       "INCLUDED_BSL_OSTREAM",
      "ostream",             "INCLUDED_OSTREAM"            },
    { "bsl_queue.h",         "INCLUDED_BSL_QUEUE",
      "queue",               "INCLUDED_QUEUE"              },
    { "bsl_set.h",           "INCLUDED_BSL_SET",
      "set",                 "INCLUDED_SET"                },
    { "bsl_slist.h",         "INCLUDED_BSL_SLIST",
      "slist",               "INCLUDED_SLIST"              },
    { "bsl_sstream.h",       "INCLUDED_BSL_SSTREAM",
      "sstream",             "INCLUDED_SSTREAM"            },
    { "bsl_stack.h",         "INCLUDED_BSL_STACK",
      "stack",               "INCLUDED_STACK"              },
    { "bsl_stdexcept.h",     "INCLUDED_BSL_STDEXCEPT",
      "stdexcept",           "INCLUDED_STDEXCEPT"          },
    { "bsl_streambuf.h",     "INCLUDED_BSL_STREAMBUF",
      "streambuf",           "INCLUDED_STREAMBUF"          },
    { "bsl_string.h",        "INCLUDED_BSL_STRING",
      "string",              "INCLUDED_STRING"             },
    { "bsl_strstream.h",     "INCLUDED_BSL_STRSTREAM",
      "strstream",           "INCLUDED_STRSTREAM"          },
    { "bsl_typeinfo.h",      "INCLUDED_BSL_TYPEINFO",
      "typeinfo",            "INCLUDED_TYPEINFO"           },
    { "bsl_unordered_map.h", "INCLUDED_BSL_UNORDERED_MAP",
      "unordered_map",       "INCLUDED_UNORDERED_MAP"      },
    { "bsl_unordered_set.h", "INCLUDED_BSL_UNORDERED_SET",
      "unordered_set",       "INCLUDED_UNORDERED_SET"      },
    { "bsl_utility.h",       "INCLUDED_BSL_UTILITY",
      "utility",             "INCLUDED_UTILITY"            },
    { "bsl_valarray.h",      "INCLUDED_BSL_VALARRAY",
      "valarray",            "INCLUDED_VALARRAY"           },
    { "bsl_vector.h",        "INCLUDED_BSL_VECTOR",
      "vector",              "INCLUDED_VECTOR"             },

    // bsl_ versions of standard C headers

    { "bsl_c_assert.h",      "INCLUDED_BSL_C_ASSERT",
      "assert.h",            "_ASSERT_H"                   },
    { "bsl_c_ctype.h",       "INCLUDED_BSL_C_CTYPE",
      "ctype.h",             "_CTYPE_H"                    },
    { "bsl_c_errno.h",       "INCLUDED_BSL_C_ERRNO",
      "errno.h",             "_ERRNO_H"                    },
    { "bsl_c_float.h",       "INCLUDED_BSL_C_FLOAT",
      "float.h",             "_FLOAT_H"                    },
    { "bsl_c_iso646.h",      "INCLUDED_BSL_C_ISO646",
      "iso646.h",            "_ISO646_H"                   },
    { "bsl_c_limits.h",      "INCLUDED_BSL_C_LIMITS",
      "limits.h",            "_LIBC_LIMITS_H_"             },
    { "bsl_c_locale.h",      "INCLUDED_BSL_C_LOCALE",
      "locale.h",            "_LOCALE_H"                   },
    { "bsl_c_math.h",        "INCLUDED_BSL_C_MATH",
      "math.h",              "_MATH_H"                     },
    { "bsl_c_setjmp.h",      "INCLUDED_BSL_C_SETJMP",
      "setjmp.h",            "_SETJMP_H"                   },
    { "bsl_c_signal.h",      "INCLUDED_BSL_C_SIGNAL",
      "signal.h",            "_SIGNAL_H"                   },
    { "bsl_c_stdarg.h",      "INCLUDED_BSL_C_STDARG",
      "stdarg.h",            "_STDARG_H"                   },
    { "bsl_c_stddef.h",      "INCLUDED_BSL_C_STDDEF",
      "stddef.h",            "_STDDEF_H"                   },
    { "bsl_c_stdio.h",       "INCLUDED_BSL_C_STDIO",
      "stdio.h",             "_STDIO_H"                    },
    { "bsl_c_stdlib.h",      "INCLUDED_BSL_C_STDLIB",
      "stdlib.h",            "_STDLIB_H"                   },
    { "bsl_c_string.h",      "INCLUDED_BSL_C_STRING",
      "string.h",            "_STRING_H"                   },
    { "bsl_c_sys_time.h",    "INCLUDED_BSL_C_SYS_TIME",
      "sys/time.h",          "_SYS_TIME_H"                 },
    { "bsl_c_time.h",        "INCLUDED_BSL_C_TIME",
      "time.h",              "_TIME_H"                     },
    { "bsl_c_wchar.h",       "INCLUDED_BSL_C_WCHAR",
      "wchar.h",             "_WCHAR_H"                    },
    { "bsl_c_wctype.h",      "INCLUDED_BSL_C_WCTYPE",
      "wctype.h",            "_WCTYPE_H"                   },

    // GCC has some cross-includes that cause problems.  For example, <ios>
    // includes <stl_algobase.h> without going through <algorithm>, so the
    // replacement of std::max with bsl::max fails when <ios> is replaced with
    // <bsl_ios.h>.  This section will include these sepcial non-standard
    // headers.

    { "bsl_algorithm.h",  "INCLUDED_BSL_ALGORITHM",
      "stl_algo.h",       "_ALGO_H"                  },
    { "bsl_algorithm.h",  "INCLUDED_BSL_ALGORITHM",
      "stl_algobase.h",   "_ALGOBASE_H"              },
    { "bsl_functional.h", "INCLUDED_BSL_FUNCTIONAL",
      "stl_function.h",   "_FUNCTION_H"              },
    { "bsl_utility.h",    "INCLUDED_BSL_UTILITY",
      "stl_pair.h",       "_PAIR_H"                  },
    { "bsl_ios.h",        "INCLUDED_BSL_IOS",
      "postypes.h",       "_GLIBCXX_POSTYPES_H"      },
    { "bsl_ios.h",        "INCLUDED_BSL_IOS",
      "ios_base.h",       "_IOS_BASE_H"              },
    { "bsl_memory.h",     "INCLUDED_BSL_MEORY",
      "auto_ptr.h",       "_BACKWARD_AUTO_PTR_H"     },

    // 'bsl_' equivalents for 'bslstl_' files
    { "bsl_algorithm.h",                  "INCLUDED_BSL_ALGORITHM",
      "bslstl_algorithmworkaround.h",  "INCLUDED_BSLSTL_ALGORITHMWORKAROUND" },
    { "bsl_memory.h",                     "INCLUDED_BSL_MEMORY",
      "bslstl_allocator.h",               "INCLUDED_BSLSTL_ALLOCATOR"        },
    { "bsl_memory.h",                     "INCLUDED_BSL_MEMORY",
      "bslstl_allocatortraits.h",         "INCLUDED_BSLSTL_ALLOCATORTRAITS"  },
    { "bsl_memory.h",                     "INCLUDED_BSL_MEMORY",
      "bslstl_badweakptr.h",              "INCLUDED_BSLSTL_BADWEAKPTR"       },
    { "bsl_iterator.h",                   "INCLUDED_BSL_ITERATOR",
      "bslstl_bidirectionaliterator.h",
                                     "INCLUDED_BSLSTL_BIDIRECTIONALITERATOR" },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_bidirectionalnodepool.h",
                                     "INCLUDED_BSLSTL_BIDIRECTIONALNODEPOOL" },
    { "bsl_bitset.h",                     "INCLUDED_BSL_BITSET",
      "bslstl_bitset.h",                  "INCLUDED_BSLSTL_BITSET"           },
    { "bsl_deque.h",                      "INCLUDED_BSL_DEQUE",
      "bslstl_deque.h",                   "INCLUDED_BSLSTL_DEQUE"            },
    { "bsl_functional.h",                 "INCLUDED_BSL_FUNCTIONAL",
      "bslstl_equalto.h",                 "INCLUDED_BSLSTL_EQUALTO"          },
    { "bsl_iterator.h",                   "INCLUDED_BSL_ITERATOR",
      "bslstl_forwarditerator.h",         "INCLUDED_BSLSTL_FORWARDITERATOR"  },
    { "bsl_functional.h",                 "INCLUDED_BSL_FUNCTIONAL",
      "bslstl_hash.h",                    "INCLUDED_BSLSTL_HASH"             },
    { "bsl_unordered_map.h",              "INCLUDED_BSL_UNORDERED_MAP",
      "bslstl_hashtable.h",               "INCLUDED_BSLSTL_HASHTABLE"        },
    { "bsl_unordered_map.h",              "INCLUDED_BSL_UNORDERED_MAP",
      "bslstl_hashtablebucketiterator.h",
                                   "INCLUDED_BSLSTL_HASHTABLEBUCKETITERATOR" },
    { "bsl_unordered_map.h",              "INCLUDED_BSL_UNORDERED_MAP",
      "bslstl_hashtableiterator.h",      "INCLUDED_BSLSTL_HASHTABLEITERATOR" },
    { "bsl_iosfwd.h"                      "INCLUDED_BSL_IOSFWD",
      "bslstl_iosfwd.h",                  "INCLUDED_BSLSTL_IOSFWD"           },
    { "bsl_sstream.h",                    "INCLUDED_BSL_SSTREAM",
      "bslstl_istringstream.h",           "INCLUDED_BSLSTL_ISTRINGSTREAM"    },
    { "bsl_iterator.h",                   "INCLUDED_BSL_ITERATOR",
      "bslstl_iterator.h",                "INCLUDED_BSLSTL_ITERATOR"         },
    { "bsl_unordered_set.h",              "INCLUDED_BSL_UNORDERED_SET",
      "bslstl_iteratorutil.h",            "INCLUDED_BSLSTL_ITERATORUTIL"     },
    { "bsl_list.h",                       "INCLUDED_BSL_LIST",
      "bslstl_list.h",                    "INCLUDED_BSLSTL_LIST"             },
    { "bsl_map.h",                        "INCLUDED_BSL_MAP",
      "bslstl_map.h",                     "INCLUDED_BSLSTL_MAP"              },
    { "bsl_map.h",                        "INCLUDED_BSL_MAP",
      "bslstl_mapcomparator.h",           "INCLUDED_BSLSTL_MAPCOMPARATOR"    },
    { "bsl_map.h",                        "INCLUDED_BSL_MAP",
      "bslstl_multimap.h",                "INCLUDED_BSLSTL_MULTIMAP"         },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_multiset.h",                "INCLUDED_BSLSTL_MULTISET"         },
    { "bsl_sstream.h",                    "INCLUDED_BSL_SSTREAM",
      "bslstl_ostringstream.h",           "INCLUDED_BSLSTL_OSTRINGSTREAM"    },
    { "bsl_utility.h",                    "INCLUDED_BSL_UTILITY",
      "bslstl_pair.h",                    "INCLUDED_BSLSTL_PAIR"             },
    { "bsl_queue.h",                      "INCLUDED_BSL_QUEUE",
      "bslstl_queue.h",                   "INCLUDED_BSLSTL_QUEUE"            },
    { "bsl_iterator.h",                   "INCLUDED_BSL_ITERATOR",
      "bslstl_randomaccessiterator.h",
                                      "INCLUDED_BSLSTL_RANDOMACCESSITERATOR" },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_set.h",                     "INCLUDED_BSLSTL_SET"              },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_setcomparator.h",           "INCLUDED_BSLSTL_SETCOMPARATOR"    },
    { "bsl_memory.h",                     "INCLUDED_BSL_MEMORY",
      "bslstl_sharedptr.h",               "INCLUDED_BSLSTL_SHAREDPTR"        },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_simplepool.h",              "INCLUDED_BSLSTL_SIMPLEPOOL"       },
    { "bsl_sstream.h",                    "INCLUDED_BSL_SSTREAM",
      "bslstl_sstream.h",                 "INCLUDED_BSLSTL_SSTREAM"          },
    { "bsl_stack.h",                      "INCLUDED_BSL_STACK",
      "bslstl_stack.h",                   "INCLUDED_BSLSTL_STACK"            },
    { "bsl_bitset.h",                     "INCLUDED_BSL_BITSET",
      "bslstl_stdexceptutil.h",           "INCLUDED_BSLSTL_STDEXCEPTUTIL"    },
    { "bsl_string.h",                     "INCLUDED_BSL_STRING",
      "bslstl_string.h",                  "INCLUDED_BSLSTL_STRING"           },
    { "bsl_sstream.h",                    "INCLUDED_BSL_SSTREAM",
      "bslstl_stringbuf.h",               "INCLUDED_BSLSTL_STRINGBUF"        },
    { "bsl_string.h",                     "INCLUDED_BSL_STRING",
      "bslstl_stringref.h",               "INCLUDED_BSLSTL_STRINGREF"        },
    { "bsl_string.h",                     "INCLUDED_BSL_STRING",
      "bslstl_stringrefdata.h",           "INCLUDED_BSLSTL_STRINGREFDATA"    },
    { "bsl_sstream.h",                    "INCLUDED_BSL_SSTREAM",
      "bslstl_stringstream.h",            "INCLUDED_BSLSTL_STRINGSTREAM"     },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_treeiterator.h",            "INCLUDED_BSLSTL_TREEITERATOR"     },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_treenode.h",                "INCLUDED_BSLSTL_TREENODE"         },
    { "bsl_set.h",                        "INCLUDED_BSL_SET",
      "bslstl_treenodepool.h",            "INCLUDED_BSLSTL_TREENODEPOOL"     },
    { "bsl_unordered_map.h",              "INCLUDED_BSL_UNORDERED_MAP",
      "bslstl_unorderedmap.h",            "INCLUDED_BSLSTL_UNORDEREDMAP"     },
    { "bsl_unordered_map.h",              "INCLUDED_BSL_UNORDERED_MAP",
      "bslstl_unorderedmapkeyconfiguration.h",
                              "INCLUDED_BSLSTL_UNORDEREDMAPKEYCONFIGURATION" },
    { "bsl_unordered_map.h",              "INCLUDED_BSL_UNORDERED_MAP",
      "bslstl_unorderedmultimap.h",      "INCLUDED_BSLSTL_UNORDEREDMULTIMAP" },
    { "bsl_unordered_set.h",              "INCLUDED_BSL_UNORDERED_SET",
      "bslstl_unorderedmultiset.h",      "INCLUDED_BSLSTL_UNORDEREDMULTISET" },
    { "bsl_unordered_set.h",              "INCLUDED_BSL_UNORDERED_SET",
      "bslstl_unorderedset.h",            "INCLUDED_BSLSTL_UNORDEREDSET"     },
    { "bsl_unordered_set.h",              "INCLUDED_BSL_UNORDERED_SET",
      "bslstl_unorderedsetkeyconfiguration.h",
                              "INCLUDED_BSLSTL_UNORDEREDSETKEYCONFIGURATION" },
    { "bsl_vector.h",                     "INCLUDED_BSL_VECTOR",
      "bslstl_vector.h",                  "INCLUDED_BSLSTL_VECTOR"           },

    // 'bsl_' equivalents for 'bslstp_' files
    { "bsl_algorithm.h",       "INCLUDED_BSL_ALGORITHM",      
      "bslstp_exalgorithm.h",  "INCLUDE_BSLSTP_EXALGORITHM"   }, 
    { "bsl_functional.h",      "INCLUDED_BSL_FUNCTIONAL",     
      "bslstp_exfunctional.h", "INCLUDE_BSLSTP_EXFUNCTIONAL"  }, 
    { "bsl_cstddef.h",         "INCLUDED_BSL_CSTDDEF",        
      "bslstp_hash.h",         "INCLUDE_BSLSTP_HASH"          }, 
    { "bsl_functional.h",      "INCLUDED_BSL_FUNCTIONAL",     
      "bslstp_hashmap.h",      "INCLUDE_BSLSTP_HASHMAP"       }, 
    { "bsl_functional.h",      "INCLUDED_BSL_FUNCTIONAL",     
      "bslstp_hashset.h",      "INCLUDE_BSLSTP_HASHSET"       }, 
    { "bsl_algorithm.h",       "INCLUDED_BSL_ALGORITHM",      
      "bslstp_hashtable.h",    "INCLUDE_BSLSTP_HASHTABLE"     }, 
    { "bsl_functional.h",      "INCLUDED_BSL_FUNCTIONAL",     
      "bslstp_hashtable.h",    "INCLUDE_BSLSTP_HASHTABLE"     }, 
    { "bsl_iterator.h",        "INCLUDED_BSL_ITERATOR",       
      "bslstp_hashtable.h",    "INCLUDE_BSLSTP_HASHTABLE"     }, 
    { "bsl_cstddef.h",         "INCLUDED_BSL_CSTDDEF",        
      "bslstp_iterator.h",     "INCLUDE_BSLSTP_ITERATOR"      }, 
    { "bsl_algorithm.h",       "INCLUDED_BSL_ALGORITHM",      
      "bslstp_slist.h",        "INCLUDE_BSLSTP_SLIST"         }, 
    { "bsl_cstddef.h",         "INCLUDED_BSL_CSTDDEF",        
      "bslstp_slist.h",        "INCLUDE_BSLSTP_SLIST"         }, 
    { "bsl_iterator.h",        "INCLUDED_BSL_ITERATOR",       
      "bslstp_slist.h",        "INCLUDE_BSLSTP_SLIST"         }, 
    { "bsl_cstddef.h",         "INCLUDED_BSL_CSTDDEF",        
      "bslstp_slistbase.h",    "INCLUDE_BSLSTP_SLISTBASE"     }, 

    // There are some bsls_ files that include headers transitively in override
    // mode only, so if we see those headers we may need to include the
    // transitive header explicitly.

    { "bsl_cstddef.h",          "INCLUDED_BSL_CSTDDEF",
      "bsls_alignment.h",       "INCLUDED_BSLS_ALIGNMENT"        },
    { "bsl_limits.h",           "INCLUDED_BSL_LIMITS",
      "bsls_alignmentutil.h",   "INCLUDED_BSLS_ALIGNMENTUTIL"    },
    { "bsl_cstddef.h",          "INCLUDED_BSL_CSTDDEF",
      "bsls_platformutil.h",    "INCLUDED_BSLS_PLATFORMUTIL"     },
    { "bsl_iosfwd.h",           "INCLUDED_BSL_IOSFWD",
      "bsls_systemclocktype.h", "INCLUDED_BSLS_SYSTEMCLOCK_TYPE" },
    { "bsl_ostream.h",          "INCLUDED_BSL_OSTREAM",
      "bsls_timeinterval.h",    "INCLUDED_BSLS_TIMEINTERVAL"     },
    { "bsl_cstddef.h",          "INCLUDED_BSL_CSTDDEF",
      "bsls_types.h",           "INCLUDED_BSLS_TYPES"            },
    { "bslalg_typetraits.h",    "INCLUDED_BSLALG_TYPETRAITS",
      "bsl_string.h",           "INCLUDED_BSL_STRING"            },
    { "bsls_atomic.h",          "INCLUDED_BSLS_ATOMIC",
      "bslma_sharedptrrep.h",   "INCLUDED_BSLMA_SHAREDPTRREP"    },
    { "bslma_managedptr.h",     "INCLUDED_BSLMA_MANAGEDPTR",
      "bslalg_swaputil.h",      "INCLUDED_BSLALG_SWAPUTIL"       },
    { "bsls_types.h",           "INCLUDED_BSLS_TYPES",
      "bdet_packedcalendar.h",  "INCLUDED_BDET_PACKEDCALENDAR"   },
};

const char *good_bsl[] = {
    "baea_",    "baecs_",   "baedb_",   "baejsn_",  "bael_",    "baelu_",   
    "baem_",    "baenet_",  "baescm_",  "baesu_",   "baet_",    "baetzo_",  
    "baexml_",  "bbedc_",   "bbescm_",  "bcec_",    "bcecs_",   "bcef_",    
    "bcefi_",   "bcefr_",   "bcefu_",   "bcem_",    "bcema_",   "bcemt_",   
    "bcep_",    "bces_",    "bcesb_",   "bcescm_",  "bdea_",    "bdealg_",  
    "bdeat_",   "bdec_",    "bdec2_",   "bdeci_",   "bdecs_",   "bdede_",   
    "bdef_",    "bdefi_",   "bdefr_",   "bdefu_",   "bdeimp_",  "bdem_",    
    "bdema_",   "bdemf_",   "bdempu_",  "bdepcre_", "bdepu_",   "bdes_",    
    "bdesb_",   "bdescm_",  "bdesu_",   "bdet_",    "bdetst_",  "bdetu_",   
    "bdeu_",    "bdeut_",   "bdex_",    "bsl_",     "bslalg_",  "bslfwd_",  
    "bslh_",    "bslim_",   "bslma_",   "bslmf_",   "bsls_",    "bslscm_",  
    "bsltf_",   "bsttst_",  "btemt_",   "btes_",    "btes5_",   "btesc_",   
    "btescm_",  "bteso_",   "btesos_",  
};

// The following files are not rewritten.
const char *special_case[] = {
    "otl/otlv4.h",
    "otlv4.h",
};

struct report : public RecursiveASTVisitor<report>
{
    report(Analyser& analyser,
           PPObserver::CallbackType type = PPObserver::e_None);
        // Create an object of this type, that will use the specified
        // 'analyser'.  Optionally specify a 'type' to identify the callback
        // that will be invoked, for preprocessor callbacks that have the same
        // signature.

    FileType classify(llvm::StringRef name,
                      const std::vector<const file_info *> **pfvi = 0);
        // Return one of the 'FileType' enumerators describing the specified
        // 'name'.  Optionally specify 'pfvi' to receive the corresponding file
        // data.

    llvm::StringRef filetype_tag(FileType ft);
        // Return a string representation of the specified 'ft'.

    void classify_stack();
        // Set the location flags in the associated data using the lowest
        // classifiable file on the include stack.

    void clear_guard();
        // Clear the current include guard info.

    void set_guard(llvm::StringRef guard, SourceLocation where);
        // Set the guard info to the specified 'guard' and 'where'.

    void push_include(FileID fid, llvm::StringRef name, SourceLocation sl);
        // Mark that the specified 'name' is included at the specified 'sl'
        // in the specified 'fid', and in files which include it if not
        // dependent on BSL_OVERRIDES_STD.

    void change_include(FileID fid, llvm::StringRef name);
        // Change the file name added most recently by push_include for the
        // specified 'fid', and in files which include it if not dependent on
        // BSL_OVERRIDES_STD, to the specified 'name'.

    void operator()(SourceLocation   where,
                    const Token&     inc,
                    llvm::StringRef  name,
                    bool             angled,
                    CharSourceRange  namerange,
                    const FileEntry *entry,
                    llvm::StringRef  path,
                    llvm::StringRef  relpath,
                    const Module    *imported);
        // Preprocessor callback for included file.

    void map_file(std::string name);
        // Find a possibly different file to include that includes the
        // specified 'name'.

    void operator()(SourceLocation                now,
                    PPCallbacks::FileChangeReason reason,
                    SrcMgr::CharacteristicKind    type,
                    FileID                        prev);
        // Preprocessor callback for file changed.

    bool is_named(Token const& token, llvm::StringRef name);
        // Return 'true' iff the specified 'token' is the specified 'name'.

    void operator()(Token const&          token,
                    MacroDirective const *md);
        // Preprocessor callback for macro definition.

    void operator()(Token const&          token,
                    MacroDirective const *md,
                    SourceRange           range,
                    MacroArgs const      *);
        // Preprocessor callback for macro expanding.

    void operator()(SourceLocation        where,
                    const Token&          token,
                    const MacroDirective *md);
        // Preprocessor callback for 'ifdef'/'ifndef'.

    void operator()(const Token&          token,
                    const MacroDirective *md,
                    SourceRange           range);
        // Preprocessor callback for 'defined(.)'.

    void operator()(SourceRange range);
        // Preprocessor callback for skipped ranges.

    void operator()(SourceLocation where,
                    SourceRange    condition,
                    bool           value);
        // Preprocessor callback for 'if'.

    void operator()(SourceLocation where,
                    SourceRange    condition,
                    bool           value,
                    SourceLocation ifloc);
        // Preprocessor callback for 'elif'.

    void operator()(SourceLocation     where,
                    SourceLocation     ifloc);
        // Preprocessor callback for 'else'.

    bool in_noinc_region(SourceLocation sl);
        // Return whether the specified 'sl' is in an extern "C" linkage spec.

    void
    add_include(FileID fid, const std::string &name, SourceLocation before);
        // Include the file specified by 'name' in the file specified by 'fid'
        // before the specified 'before' in the translation unit.

    void require_file(std::string     name,
                      SourceLocation  sl,
                      llvm::StringRef symbol);
        // Indicate that the specified file 'name' is needed at the specified
        // 'sl' in order to obtain the specified 'symbol'.

    void inc_for_std_decl(llvm::StringRef  r,
                          SourceLocation   sl,
                          const Decl      *ds);
        // For the specified name 'r' at location 'sl' referenced by the
        // specified declaration 'ds', determine which header file, if any, is
        // needed.

    const NamedDecl *look_through_typedef(const Decl *ds);
        // If the specified 'ds' is a typedef for a record, return the
        // definition for the record if it exists.  Return null otherwise.

    void operator()();
        // Callback for end of main file.

    bool is_guard(llvm::StringRef guard);
    bool is_guard(const Token& token);
        // Return true if the specified 'guard' or 'token' looks like a header
        // guard ("INCLUDED_...").

    bool is_guard_for(llvm::StringRef guard, llvm::StringRef file);
    bool is_guard_for(const Token& token, llvm::StringRef file);
    bool is_guard_for(llvm::StringRef guard, SourceLocation sl);
    bool is_guard_for(const Token& token, SourceLocation sl);
        // Return true if the specified 'guard' or 'token' is a header guard
        // for the specified 'file' or 'sl'.

    bool VisitDeclRefExpr(DeclRefExpr *expr);
    bool VisitCXXConstructExpr(CXXConstructExpr *expr);
    bool VisitTypeLoc(TypeLoc tl);
    bool VisitUnresolvedLookupExpr(UnresolvedLookupExpr *expr);
        // Return true after processing the specified 'tl' and 'expr'.

    Analyser&                d_analyser;
    data&                    d_data;
    PPObserver::CallbackType d_type;
};

report::report(Analyser& analyser, PPObserver::CallbackType type)
: d_analyser(analyser)
, d_data(analyser.attachment<data>())
, d_type(type)
{
}

FileType report::classify(llvm::StringRef name,
                          const std::vector<const file_info *> **pfvi)
{
    FileName fn(name);

    // Special case sys/time.h vs. time.h
    if (name != "sys/time.h") {
        name = fn.name();
    }

    if (d_data.d_file_info.find(name) == d_data.d_file_info.end()) {
        d_data.d_file_info[name].second = e_UNK;
    }
    auto& p = d_data.d_file_info[name];
    if (pfvi) {
        *pfvi = &p.first;
    }
    if (p.second != e_UNK) {
        return p.second;                                              // RETURN
    }

    if (name.startswith("bsl_stdhdrs_")) {
        return p.second = e_NIL;                                      // RETURN
    }

    for (llvm::StringRef spc : special_case) {
        if (name == spc) {
            return p.second = e_SPC;                                  // RETURN
        }
    }

    for (const char *prefix : good_bsl) {
        if (name.startswith(prefix)) {
            return p.second = e_BSL;                                  // RETURN
        }
    }

    for (const file_info *f : p.first) {
        if (name == f->std) {
            return p.second = e_STD;                                  // RETURN
        }
    }

    return p.second = e_NIL;
}

llvm::StringRef report::filetype_tag(FileType ft)
{
    switch (ft) {
      case e_UNK: return "UNK";                                       // RETURN
      case e_BSL: return "BSL";                                       // RETURN
      case e_STD: return "STD";                                       // RETURN
      case e_SPC: return "SPC";                                       // RETURN
      case e_NIL: return "   ";                                       // RETURN
      default:    return "???";                                       // RETURN
    }
}

void report::classify_stack()
{
    d_data.d_in_bsl = false;
    d_data.d_in_std = false;
    for (const auto& file : d_data.d_file_stack) {
        switch (classify(file)) {
          case FileType::e_BSL:
            d_data.d_in_bsl = true;
            return;                                                   // RETURN
          case FileType::e_STD:
            d_data.d_in_std = true;
            return;                                                   // RETURN
          case FileType::e_SPC:
          case FileType::e_NIL:
          case FileType::e_UNK:
            break;
        }
    }
}

void report::clear_guard()
{
    d_data.d_guard = "";
    d_data.d_guard_pos = SourceLocation();
}

void report::set_guard(llvm::StringRef guard, SourceLocation where)
{
    d_data.d_guard = guard;
    d_data.d_guard_pos = d_analyser.get_line_range(where).getBegin();
}

void report::push_include(FileID fid, llvm::StringRef name, SourceLocation sl)
{
    SourceManager& m = d_analyser.manager();
    for (FileID f : d_data.d_fileid_stack) {
        if (f == fid) {
            d_data.d_includes[f].push_back(std::make_tuple(
                name, d_analyser.get_line_range(sl).getBegin(), true));
        }
        else if (!d_data.d_ovr_stack.back()) {
            SourceLocation sfl = sl;
            auto t = std::make_tuple(fid, f, sl);
            auto i = d_data.d_fid_map.find(t);
            if (i != d_data.d_fid_map.end()) {
                sfl = i->second;
            }
            else {
                FileID flid;
                while (sfl.isValid()) {
                    flid = m.getFileID(sfl);
                    if (flid == f) {
                        break;
                    }
                    sfl = m.getIncludeLoc(flid);
                }
                if (sfl.isValid()) {
                    unsigned offset = m.getFileOffset(sfl);
                    unsigned line = m.getLineNumber(flid, offset);
                    if (line > 1) {
                        SourceLocation prev =
                            m.translateLineCol(flid, line - 1, 0);
                        llvm::StringRef p = d_analyser.get_source_line(prev);
                        static llvm::Regex guard("^ *# *ifn?def  *INCLUDED_");
                        if (guard.match(p)) {
                            sfl = prev;
                        }
                    }
                }
                d_data.d_fid_map[t] = sfl;
            }
            d_data.d_includes[f].push_back(std::make_tuple(
                name, d_analyser.get_line_range(sfl).getBegin(), false));
        }
    }
}

void report::change_include(FileID fid, llvm::StringRef name)
{
    for (FileID f : d_data.d_fileid_stack) {
        if (f == fid || !d_data.d_ovr_stack.back()) {
            std::get<0>(d_data.d_includes[f].back()) = name;
        }
    }
}

// InclusionDirective
void report::operator()(SourceLocation   where,
                        const Token&     inc,
                        llvm::StringRef  name,
                        bool             angled,
                        CharSourceRange  namerange,
                        const FileEntry *entry,
                        llvm::StringRef  path,
                        llvm::StringRef  relpath,
                        const Module    *imported)
{
    SourceManager& m = d_analyser.manager();
    Location loc(m, where);
    FileName fnw(loc.file());
    FileName fnn(name);

    if (name.endswith("_version.h") || name.endswith("_ident.h") ||
        (d_analyser.is_header(name) && fnw.component() == fnn.component())) {
        d_data.d_top_for_insert[m.getFileID(where)] =
            d_analyser.get_line_range(d_analyser.get_line_range(where)
                                          .getEnd()
                                          .getLocWithOffset(1)).getBegin();
    }

    FileType ft = classify(loc.file());
    FileID fid = m.getFileID(where);
    if (d_data.d_guard_pos.isValid() &&
        fid != m.getFileID(d_data.d_guard_pos)) {
        clear_guard();
    }

    push_include(
        fid, name, d_data.d_guard_pos.isValid() ? d_data.d_guard_pos : where);

    const std::vector<const file_info *> *pfvi;

    if (!d_data.d_in_bsl &&
        !d_data.d_in_std &&
        ft == e_NIL &&
        !m.isInSystemHeader(where) &&
        classify(name, &pfvi) == e_STD) {
        for (const file_info *fi : *pfvi) {
            if (d_data.d_guard == fi->std_guard) {
                SourceRange r = d_analyser.get_line_range(d_data.d_guard_pos);
                llvm::StringRef s = d_analyser.get_source(r);
                size_t pos = s.find(d_data.d_guard);
                if (pos != s.npos) {
                    d_analyser.report(r.getBegin(), check_name, "SB02",
                                      "Replacing include guard %0 with %1")
                        << fi->std_guard
                        << fi->bsl_guard;
                    d_analyser.ReplaceText(
                        getOffsetRange(r, pos, d_data.d_guard.size()),
                        fi->bsl_guard);
                }
            }
            d_analyser.report(where, check_name, "SB01",
                              "Replacing header %2%0%3 with <%1>")
                << fi->std
                << fi->bsl
                << (angled ? "<" : "\"")
                << (angled ? ">" : "\"");
            SourceRange r = d_analyser.get_trim_line_range(where);
            std::string s = "#include <" + std::string(fi->bsl) + ">";
            if (d_data.d_insert_extcpp && d_analyser.is_header(loc.file())) {
                s = "extern \"C++\" {\n" + s + "\n}";
            }
            d_analyser.ReplaceText(r, s);
            change_include(fid, fi->bsl);
            if (d_data.d_guard == fi->std_guard) {
                SourceRange r = d_analyser.get_line_range(d_data.d_guard_pos);
                r = d_analyser.get_line_range(
                    r.getEnd().getLocWithOffset(1));
                r = d_analyser.get_line_range(
                    r.getEnd().getLocWithOffset(1));
                llvm::StringRef s = d_analyser.get_source(r);
                size_t pos = s.find("#define " + d_data.d_guard.str());
                if (pos != s.npos) {
                    d_analyser.report(r.getBegin(), check_name, "SB03",
                             "Removing include guard definition of %0")
                        << d_data.d_guard;
                    d_analyser.RemoveText(r);
                }
            }
        }
    }

    clear_guard();
}

void report::map_file(std::string name)
{
    if (d_data.d_file_map.find(name) == d_data.d_file_map.end()) {
        std::string file = name;
        for (const auto& s : d_data.d_file_stack) {
            auto c = classify(s);
            if (c != e_NIL || d_analyser.is_component(s)) {
                file = s;
            }
        }
        d_data.d_file_map[name] = file;
    }
}

// FileChanged
void report::operator()(SourceLocation                now,
                        PPCallbacks::FileChangeReason reason,
                        SrcMgr::CharacteristicKind    type,
                        FileID                        prev)
{
    std::string name = d_analyser.manager().getPresumedLoc(now).getFilename();
    if (reason == PPCallbacks::EnterFile) {
        d_data.d_file_stack.push_back(name);
        d_data.d_fileid_stack.push_back(d_analyser.manager().getFileID(now));
    } else if (reason == PPCallbacks::ExitFile) {
        if (d_data.d_file_stack.size() > 0) {
            d_data.d_file_stack.pop_back();
        }
        if (d_data.d_fileid_stack.size() > 0) {
            d_data.d_fileid_stack.pop_back();
        }
    }

    classify_stack();

    if (d_data.d_in_std || d_data.d_in_bsl) {
        map_file(name);
    }
}

bool report::is_named(Token const& token, llvm::StringRef name)
{
    return token.isAnyIdentifier() &&
           token.getIdentifierInfo()->getName() == name;
}

// MacroDefined
// MacroUndefined
void report::operator()(Token const&          token,
                        MacroDirective const *md)
{
    if (d_type == PPObserver::e_MacroUndefined) {
        if (is_named(token, "std")) {
            d_data.d_bsl_overrides_std = false;
        }
        return;                                                       // RETURN
    }

    SourceManager& m = d_analyser.manager();
    SourceLocation sl = token.getLocation();
    FileID fid = m.getFileID(sl);
    if (is_guard(token) &&
        d_data.d_guards.find(fid) != d_data.d_guards.end() &&
        d_data.d_guards[fid] == token.getIdentifierInfo()->getName()) {
        d_data.d_top_for_insert[m.getFileID(sl)] =
            d_analyser.get_line_range(d_analyser.get_line_range(sl)
                                          .getEnd()
                                          .getLocWithOffset(1)).getBegin();
    }

    if (md) {
        if (const MacroInfo *mi = md->getMacroInfo()) {
            Location loc(m, mi->getDefinitionLoc());
            FileType ft = classify(loc.file());
            if (loc) {
                map_file(loc.file());
            }
            int nt = mi->getNumTokens();
            if (is_named(token, "std") &&
                mi->isObjectLike() &&
                nt == 1 &&
                is_named(mi->getReplacementToken(0), "bsl")) {
                d_data.d_bsl_overrides_std = true;
            }
            else if (d_data.d_bsl_overrides_std &&
                     ft == e_NIL &&
                     !m.isInSystemHeader(mi->getDefinitionLoc())) {
                for (int i = 0; i < nt; ++i) {
                    const Token &token = mi->getReplacementToken(i);
                    if (is_named(token, "std")) {
                        if (!d_analyser.ReplaceText(
                                 token.getLocation(), 3, "bsl")) {
                            d_analyser.report(token.getLocation(),
                                              check_name, "SB07",
                                              "Replacing 'std' with 'bsl' in "
                                              "macro definition");
                        }
                        for (int j = i + 1; j < nt; ++j) {
                            const Token &name = mi->getReplacementToken(j);
                            if (name.isAnyIdentifier()) {
                                d_data.d_std_names.insert(std::make_pair(
                                    name.getIdentifierInfo()->getName().str(),
                                    name.getLocation()));
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}

// MacroExpands
void report::operator()(Token const&          token,
                        MacroDirective const *md,
                        SourceRange           range,
                        MacroArgs const      *)
{
    llvm::StringRef macro = token.getIdentifierInfo()->getName();
    const MacroInfo *mi = md->getMacroInfo();
    SourceManager& m = d_analyser.manager();
    Location loc(m, range.getBegin());
    FileType ft = classify(loc.file());

    if (macro.endswith("_IDENT_RCSID") || macro.endswith("_PRAGMA_ONCE")) {
        d_data.d_top_for_insert[m.getFileID(token.getLocation())] =
            d_analyser.get_line_range(
                           d_analyser.get_line_range(token.getLocation())
                               .getEnd()
                               .getLocWithOffset(1)).getBegin();
    }

    if (!d_data.d_in_bsl && !d_data.d_in_std &&
        ft == e_NIL &&
        !token.getLocation().isMacroID() &&
        !m.isInSystemHeader(range.getBegin()) &&
        (is_named(token, "std") ||
         is_named(token, "BloombergLP_std")) &&
        mi->isObjectLike() &&
        mi->getNumTokens() == 1 &&
        is_named(mi->getReplacementToken(0), "bsl")) {
        SourceLocation loc = m.getFileLoc(range.getBegin());
        FileID fid = m.getFileID(loc);
        llvm::StringRef buf = m.getBufferData(fid);
        unsigned offset = m.getFileOffset(range.getBegin());
        static llvm::Regex qname("^std *:: *([_[:alpha:]][_[:alnum:]]*)");
        llvm::SmallVector<llvm::StringRef, 7> matches;
        if (qname.match(buf.substr(offset), &matches)) {
            d_data.d_std_names.insert(std::make_pair(matches[1].str(), loc));
        }
        inc_for_std_decl(
            "bsl", range.getBegin(), d_analyser.lookup_name("bsl::"));
        d_analyser.ReplaceText(range.getBegin(), token.getLength(), "bsl");
        d_analyser.report(loc, check_name, "SB04",
                          "Replacing macro '%0' with 'bsl'")
            << macro;
    }
    else {
        Location loc(m, mi->getDefinitionLoc());
        if (loc && !range.getBegin().isMacroID()) {
            require_file(loc.file(), range.getBegin(), macro);
        }
    }
}

bool report::is_guard(llvm::StringRef guard)
{
    return guard.startswith("INCLUDED_");
}

bool report::is_guard(const Token& token)
{
    return token.isAnyIdentifier() &&
           is_guard(token.getIdentifierInfo()->getName());
}

bool report::is_guard_for(llvm::StringRef guard, llvm::StringRef file)
{
    if (!is_guard(guard)) {
        return false;                                                 // RETURN
    }

    FileName fn(file);
    std::string s = "INCLUDED_" + fn.component().upper();
    for (char& c : s) {
        if (!std::isalnum(c)) {
            c = '_';
        }
    }
    return s == guard || s + "_" + fn.extension().substr(1).upper() == guard;
}

bool report::is_guard_for(const Token& token, llvm::StringRef file)
{
    return token.isAnyIdentifier() &&
           is_guard_for(token.getIdentifierInfo()->getName(), file);
}

bool report::is_guard_for(llvm::StringRef guard, SourceLocation sl)
{
    return is_guard_for(guard, d_analyser.manager().getFilename(sl));
}

bool report::is_guard_for(const Token& token, SourceLocation sl)
{
    return is_guard_for(token, d_analyser.manager().getFilename(sl));
}

// Ifdef
// Ifndef
void report::operator()(SourceLocation        where,
                        const Token&          token,
                        const MacroDirective *)
{
    clear_guard();

    SourceManager& m = d_analyser.manager();
    FileID fid = m.getFileID(where);
    llvm::StringRef tn = token.getIdentifierInfo()->getName();

    d_data.d_ovr_stack.push_back(d_data.d_ovr_stack.back() ||
                                 tn == "BSL_OVERRIDES_STD");

    if (is_guard(token) &&
        d_data.d_guards.find(fid) == d_data.d_guards.end()) {
        d_data.d_guards[fid] = tn;
        d_data.d_top_for_insert[m.getFileID(where)] =
            d_analyser.get_line_range(where).getBegin();
    }

    if (!d_data.d_in_bsl &&
        !d_data.d_in_std &&
        !m.isInSystemHeader(where) &&
        is_guard(token)) {
        set_guard(tn, where);
    }
}

// Defined
void report::operator()(const Token&          token,
                        const MacroDirective *,
                        SourceRange           range)
{
    clear_guard();

    llvm::StringRef tn = token.getIdentifierInfo()->getName();
    if (tn == "BSL_OVERRIDES_STD") {
        d_data.d_ovr_stack.back() = true;
    }

    if (!d_data.d_in_bsl &&
        !d_data.d_in_std &&
        !d_analyser.manager().isInSystemHeader(range.getBegin()) &&
        is_guard(token)) {
        set_guard(token.getIdentifierInfo()->getName(), range.getBegin());
    }
}

// SourceRangeSkipped
void report::operator()(SourceRange range)
{
    SourceManager& m = d_analyser.manager();
    Location loc(m, range.getBegin());
    FileType ft = classify(loc.file());
    if (d_data.d_guard.size() > 0 &&
        ft == e_NIL &&
        !m.isInSystemHeader(range.getBegin())) {
        std::string gs = d_data.d_guard.str();
        llvm::StringRef g = gs;
        std::string rs("def +(" + g.str() + ")[[:space:]]+" +
                       "# *include +<(" + g.drop_front(9).lower() +
                       "[.]?h?)>[[:space:]]+(# *define +" + g.str() +
                       "[[:space:]]*)?");
        llvm::Regex r(rs);
        llvm::StringRef source = d_analyser.get_source(range);
        llvm::SmallVector<llvm::StringRef, 7> matches;
        if (r.match(source, &matches)) {
            FileID fid = m.getFileID(range.getBegin());
            push_include(fid,
                         matches[2],
                         d_data.d_guard_pos.isValid() ? d_data.d_guard_pos :
                                                        range.getBegin());
            const std::vector<const file_info *> *pfvi;
            FileType ft = classify(matches[2], &pfvi);
            if (ft == e_STD) {
                for (const file_info *fi : *pfvi) {
                    std::pair<size_t, size_t> m;
                    SourceLocation rbm =
                        range.getBegin().getLocWithOffset(m.first);
                    if (d_data.d_guard == fi->std_guard) {
                        m = mid_match(source, matches[1]);
                        d_analyser.report(rbm, check_name, "SB02",
                                          "Replacing include guard %0 with %1")
                            << fi->std_guard
                            << fi->bsl_guard;
                        d_analyser.ReplaceText(
                            getOffsetRange(range, m.first, matches[1].size()),
                            fi->bsl_guard);
                    }
                    m = mid_match(source, matches[2]);
                    rbm = range.getBegin().getLocWithOffset(m.first);
                    d_analyser.report(rbm, check_name, "SB01",
                                      "Replacing header <%0> with <%1>")
                        << matches[2]
                        << fi->bsl;
                    std::string s = "#include <" + std::string(fi->bsl) + ">";
                    if (d_data.d_insert_extcpp &&
                        d_analyser.is_header(loc.file())) {
                        s = "extern \"C++\" {\n" + s + "\n}";
                    }
                    d_analyser.ReplaceText(
                        d_analyser.get_trim_line_range(rbm), s);
                    change_include(fid, fi->bsl);
                    if (matches[3].size() > 0) {
                        m = mid_match(source, matches[3]);
                        rbm = range.getBegin().getLocWithOffset(m.first);
                        d_analyser.report(rbm, check_name, "SB03",
                                     "Removing include guard definition of %0")
                            << d_data.d_guard;
                        d_analyser.RemoveText(d_analyser.get_line_range(rbm));
                    }
                }
            }
            else if (ft == e_BSL) {
                push_include(
                    fid,
                    matches[2],
                    d_analyser.get_line_range(range.getBegin()).getBegin());
            }
        }
        clear_guard();
    }
}

// If
void report::operator()(SourceLocation where,
                        SourceRange    condition,
                        bool           value)
{
    clear_guard();
    d_data.d_ovr_stack.push_back(d_data.d_ovr_stack.back());
}

// Elif
void report::operator()(SourceLocation where,
                        SourceRange    condition,
                        bool           value,
                        SourceLocation ifloc)
{
    clear_guard();
}

// Else/Endif
void report::operator()(SourceLocation where, SourceLocation ifloc)
{
    if (d_type == PPObserver::e_Else) {
        clear_guard();
    }
    else {
        d_data.d_ovr_stack.pop_back();
    }
}

bool report::in_noinc_region(SourceLocation sl)
{
    auto i = d_data.d_noinc.find(sl);
    if (i != d_data.d_noinc.end()) {
        return i->second;                                             // RETURN
    }
    SourceManager& m = d_analyser.manager();
    DeclContext *dc = TranslationUnitDecl::castToDeclContext(
        d_analyser.context()->getTranslationUnitDecl());
    DeclContext::decl_iterator b = dc->decls_begin();
    DeclContext::decl_iterator e = dc->decls_end();
    for (; b != e; ++b) {
        LinkageSpecDecl *lsd = llvm::dyn_cast<LinkageSpecDecl>(*b);
        if (lsd && lsd->getLanguage() == lsd->lang_c &&
            m.isBeforeInTranslationUnit(
                lsd->getSourceRange().getBegin(), sl) &&
            m.isBeforeInTranslationUnit(sl, lsd->getSourceRange().getEnd())) {
            return d_data.d_noinc[sl] = true;                         // RETURN
        }
        NamespaceDecl *nd = llvm::dyn_cast<NamespaceDecl>(*b);
        if (nd &&
            m.isBeforeInTranslationUnit(
                nd->getSourceRange().getBegin(), sl) &&
            m.isBeforeInTranslationUnit(sl, nd->getSourceRange().getEnd())) {
            return d_data.d_noinc[sl] = true;                         // RETURN
        }
    }
    return d_data.d_noinc[sl] = false;
}

void report::add_include(FileID             fid,
                         const std::string& name,
                         SourceLocation     before)
{
    SourceManager& m = d_analyser.manager();
    SourceLocation sl = d_data.d_top_for_insert[fid];
    if (!sl.isValid()) {
        sl = d_analyser.get_line_range(m.getLocForStartOfFile(fid)).getBegin();
    }

    Location loc(m, sl);
    const std::vector<const file_info *> *pfvi_name;
    classify(name, &pfvi_name);
    std::string guard;
    if (d_analyser.is_header(loc.file())) {
        for (const file_info *fi_name : *pfvi_name) {
            if (name == fi_name->std) {
                guard = fi_name->std_guard;
                break;
            }
            if (name == fi_name->bsl) {
                guard = fi_name->bsl_guard;
                break;
            }
        }
        if (!guard.size()) {
            guard = llvm::StringRef("INCLUDED_" +
                                    name.substr(0, name.rfind("."))).upper();
        }
    }
    SourceLocation ip = sl;
    for (const auto& p : d_data.d_includes[fid]) {
        const std::vector<const file_info *> *pfvi_inc;
        llvm::StringRef pn = std::get<0>(p);
        SourceLocation pl = std::get<1>(p);
        bool local = std::get<2>(p);
        classify(pn, &pfvi_inc);
        if (pfvi_name == pfvi_inc &&
            pl.isValid() &&
            !m.isBeforeInTranslationUnit(before, pl)) {
            return;                                                   // RETURN
        }
        if (ip != sl ||
            !local ||
            !pl.isValid() ||
            m.isBeforeInTranslationUnit(before, pl) ||
            in_noinc_region(pl)) {
            continue;
        }
        llvm::StringRef inc = pfvi_inc->size() ? pfvi_inc->front()->bsl : pn;
        if (!d_analyser.is_component_header(inc) &&
            !inc.endswith("_version.h") &&
            !inc.endswith("_ident.h") &&
            (pfvi_inc->size() && pfvi_name->size() ?
                 pfvi_inc->front()->bsl > pfvi_name->front()->bsl :
                 inc > name)) {
            ip = pl;
        }
    }
    ip = d_analyser.get_line_range(ip).getBegin();
    Location li(m, ip);
    FileType ft = classify(li.file());
    if (ip.isValid() && ft == e_NIL && !m.isInSystemHeader(ip)) {
        std::string text;
        if (name == bsl_ns) {
            text = "\n" + name + "\n";
        }
        else {
            text = "\n#include <" + name + ">\n";
            if (guard.size()) {
                if (d_data.d_insert_extcpp) {
                    text = "\nextern \"C++\" {" + text + "}\n";
                }
                if (d_data.d_insert_guard) {
                    text = "\n#ifndef " + guard + text + "#endif\n";
                }
            }
        }
        // Insert the include before the newline of the previous line.  This is
        // a fixed character that we have not replaced (if the line has an
        // include that was changed, we changed up to but not including the
        // newline).  Otherwise the rewriting system can produce mangled text.
        SourceLocation ia = ip.getLocWithOffset(-1);
        if (ia.isValid()) {
            ip = ia;
        }
        d_analyser.report(ip, check_name, "IS02", "Inserting %0") << text;
        d_analyser.InsertTextBefore(ip, text);
    }
}

const NamedDecl *report::look_through_typedef(const Decl *ds)
{
    const TypedefDecl *td;
    const CXXRecordDecl *rd;
    if ((td = llvm::dyn_cast<TypedefDecl>(ds)) &&
        (rd = td->getUnderlyingType().getTypePtr()->getAsCXXRecordDecl()) &&
        rd->hasDefinition()) {
        return rd->getDefinition();
    }
    return 0;
}

void report::require_file(std::string     name,
                          SourceLocation  sl,
                          llvm::StringRef symbol)
{
    SourceManager& m = d_analyser.manager();

    if (classify(name) == e_SPC) {
        return;
    }

    sl = m.getExpansionLoc(sl);

    FileID fid = m.getFileID(sl);
    while (classify(m.getFileEntryForID(fid)->getName()) == e_SPC) {
        sl = m.getIncludeLoc(fid);
        fid = m.getDecomposedIncludedLoc(fid).first;
    }

    FileName fn(name);
    name = fn.name();

    const std::vector<const file_info *> *pfvi;
    FileType ft = classify(name, &pfvi);
    if (ft == e_STD) {
        for (const file_info *fi : *pfvi) {
            name = fi->bsl;
        }
    }

    for (const auto& p : d_data.d_includes[fid]) {
        if (std::get<0>(p) == name &&
            (!std::get<1>(p).isValid() ||
             !m.isBeforeInTranslationUnit(sl, std::get<1>(p)))) {
            return;
        }
    }

    if (!d_data.d_once[fid].count(name) ||
        m.isBeforeInTranslationUnit(sl, d_data.d_once[fid][name])) {

        if (ft != e_NIL) {
            d_data.d_once[fid][name] = sl;
            d_analyser.report(sl, check_name, "IS01",
                              "Need #include <%0> for symbol %1")
                << name
                << symbol;
        }
        else if (symbol == "bsl") {
            d_data.d_once[fid][bsl_ns] = sl;
            d_analyser.report(sl, check_name, "IS01", "Need %0 for symbol %1")
                << bsl_ns
                << symbol;
        }
    }
}

void report::inc_for_std_decl(llvm::StringRef  r,
                              SourceLocation   sl,
                              const Decl      *ds)
{
    SourceManager& m = d_analyser.manager();
    sl = m.getExpansionLoc(sl);

    for (const Decl *decl = ds; decl; decl = look_through_typedef(decl)) {
        bool skip = false;
        for (const Decl *p = decl; !skip && p; p = p->getPreviousDecl()) {
            Location loc(d_analyser.manager(), p->getLocation());
            FileName fn(loc.file());
            Decl::redecl_iterator rb = p->redecls_begin();
            Decl::redecl_iterator re = p->redecls_end();
            for (; !skip && rb != re; ++rb) {
                if (rb->getLocation().isValid() &&
                    d_analyser.manager().isBeforeInTranslationUnit(
                        rb->getLocation(), sl)) {
                    Location loc(d_analyser.manager(), rb->getLocation());
                    if (!skip && loc) {
                        require_file(loc.file(), sl, r);
                        skip = true;
                    }
                }
            }
            const UsingDecl *ud = llvm::dyn_cast<UsingDecl>(p);
            if (!skip && ud) {
                auto sb = ud->shadow_begin();
                auto se = ud->shadow_end();
                for (; !skip && sb != se; ++sb) {
                    const UsingShadowDecl *usd = *sb;
                    for (auto u = usd; !skip && u;
                         u = u->getPreviousDecl()) {
                        inc_for_std_decl(r, sl, u);
                    }
                }
            }
        }
    }
}

bool isNamespace(const DeclContext *dc, llvm::StringRef ns)
{
    for (;;) {
        if (!dc->isNamespace()) {
            return false;
        }
        const NamespaceDecl *nd = llvm::cast<NamespaceDecl>(dc);
        if (nd->isInline()) {
            dc = nd->getParent();
        } else if (!dc->getParent()->getRedeclContext()->isTranslationUnit()) {
            return false;
        } else {
            const IdentifierInfo *ii = nd->getIdentifier();
            return ii && ii->getName() == ns;
        }
    }
}

bool report::VisitDeclRefExpr(DeclRefExpr *expr)
{
    SourceLocation sl = expr->getExprLoc();
    if (sl.isValid() && !d_analyser.manager().isInSystemHeader(sl)) {
        const NamedDecl *ds = expr->getFoundDecl();
        const DeclContext *dc = ds->getDeclContext();
        std::string name = expr->getNameInfo().getName().getAsString();
        while (dc->isRecord()) {
            name = llvm::dyn_cast<NamedDecl>(dc)->getNameAsString();
            dc = dc->getParent();
        }
        if (dc->isTranslationUnit() ||
            dc->isExternCContext() ||
            dc->isExternCXXContext()) {
            d_data.d_std_names.insert(std::make_pair(name, sl));
        }
        else if (isNamespace(dc, "std")) {
            d_data.d_std_names.insert(std::make_pair(name, sl));
        }
        else if (isNamespace(dc, "bsl")) {
            inc_for_std_decl(name, sl, ds);
        }
    }
    return true;
}

bool report::VisitCXXConstructExpr(CXXConstructExpr *expr)
{
    SourceLocation sl = expr->getExprLoc();
    if (sl.isValid() && !d_analyser.manager().isInSystemHeader(sl)) {
        const NamedDecl *ds = expr->getConstructor()->getParent();
        const DeclContext *dc = ds->getDeclContext();
        std::string name =
            expr->getConstructor()->getParent()->getNameAsString();
        while (dc->isRecord()) {
            name = llvm::dyn_cast<NamedDecl>(dc)->getNameAsString();
            dc = dc->getParent();
        }
        if (isNamespace(dc, "std")) {
            d_data.d_std_names.insert(std::make_pair(name, sl));
        }
        else if (isNamespace(dc, "bsl")) {
            inc_for_std_decl(name, sl, ds);
        }
    }
    return true;
}

bool report::VisitTypeLoc(TypeLoc tl)
{
    const Type *type = tl.getTypePtr();
    if (type->getAs<TypedefType>() || !type->isBuiltinType()) {
        SourceLocation sl =
            d_analyser.manager().getExpansionLoc(tl.getBeginLoc());
        PrintingPolicy pp(d_analyser.context()->getLangOpts());
        pp.SuppressTagKeyword = true;
        pp.SuppressInitializers = true;
        pp.TerseOutput = true;
        std::string r = QualType(type, 0).getAsString(pp);
        NamedDecl *ds = d_analyser.lookup_name(r);
        if (!ds) {
            if (const TypedefType *tt = type->getAs<TypedefType>()) {
                ds = tt->getDecl();
            }
            else {
                tl.getTypePtr()->isIncompleteType(&ds);
            }
        }
        if (ds &&
            sl.isValid() &&
            !d_analyser.manager().isInSystemHeader(sl)) {
            inc_for_std_decl(r, sl, ds);
        }
    }
    return true;
}

bool report::VisitUnresolvedLookupExpr(UnresolvedLookupExpr *expr)
{
    SourceLocation sl = expr->getExprLoc();
    NestedNameSpecifier *nns = expr->getQualifier();
    if (sl.isValid() &&
        !d_analyser.manager().isInSystemHeader(sl) &&
        nns &&
        nns->getKind() == NestedNameSpecifier::Namespace &&
        nns->getAsNamespace()->getNameAsString() == "bsl") {
        std::string r = "bsl::" + expr->getName().getAsString();
        if (const Decl *ds = d_analyser.lookup_name(r)) {
            inc_for_std_decl(r, sl, ds);
        }
    }
    return true;
}

// TranslationUnitDone
void report::operator()()
{
    TraverseDecl(d_analyser.context()->getTranslationUnitDecl());

    for (const auto& rp : d_data.d_std_names) {
        llvm::StringRef r = rp.first;
        SourceLocation sl = rp.second;
        Location loc(d_analyser.manager(), sl);
        FileType ft = classify(loc.file());

        if (ft != e_NIL || d_analyser.manager().isInSystemHeader(sl)) {
            continue;
        }

        if (const Decl *ds = d_analyser.lookup_name(("std::" + r).str())) {
            inc_for_std_decl(r, sl, ds);
        }
    }

    for (const auto& fp : d_data.d_once) {
        for (const auto& p : fp.second) {
            add_include(fp.first, p.first, p.second);
        }
    }
}

void subscribe(Analyser& analyser, Visitor&, PPObserver& observer)
    // Hook up the callback functions.
{
    data &d = analyser.attachment<data>();
    for (const auto& f : include_pairs) {
        d.d_file_info[f.std].first.push_back(&f);
        d.d_file_info[f.std].second = e_UNK;
        d.d_file_info[f.bsl].first.push_back(&f);
        d.d_file_info[f.bsl].second = e_UNK;
    }
    d.d_insert_guard =
        llvm::StringRef(analyser.config()->value("bslovrstd_guard")) == "on";
    d.d_insert_extcpp =
        llvm::StringRef(analyser.config()->value("bslovrstd_extcpp")) == "on";

    observer.onPPInclusionDirective += report(analyser,
                                                observer.e_InclusionDirective);
    observer.onPPFileChanged        += report(analyser,
                                                       observer.e_FileChanged);
    observer.onPPMacroDefined       += report(analyser,
                                                      observer.e_MacroDefined);
    observer.onPPMacroUndefined     += report(analyser,
                                                    observer.e_MacroUndefined);
    observer.onPPMacroExpands       += report(analyser,
                                                      observer.e_MacroExpands);
    observer.onPPIfdef              += report(analyser, observer.e_Ifdef);
    observer.onPPIfndef             += report(analyser, observer.e_Ifndef);
    observer.onPPDefined            += report(analyser, observer.e_Defined);
    observer.onPPSourceRangeSkipped += report(analyser,
                                                observer.e_SourceRangeSkipped);
    observer.onPPIf                 += report(analyser,  observer.e_If);
    observer.onPPElif               += report(analyser, observer.e_Elif);
    observer.onPPElse               += report(analyser, observer.e_Else);
    observer.onPPEndif              += report(analyser, observer.e_Endif);
    analyser.onTranslationUnitDone  += report(analyser);
}

}  // close anonymous namespace

// ----------------------------------------------------------------------------

static RegisterCheck c1(check_name, &subscribe);

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------

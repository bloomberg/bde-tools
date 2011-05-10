#!/bbs/opt/bin/perl-5.8.8 -w
##!/opt/swt/bin/perl -w
use strict;
#use diagnostics;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../lib/perl";
use lib "$FindBin::Bin/../lib/perl/site-perl";

use Carp;
use Data::Dumper;
use English;
use File::Basename;
use File::Find;
use File::Spec;
use Getopt::Long;
use IO::File;
use Storable;
use Template;
use Text::Wrap;
use XML::Simple;

use constant RELEASE => 'BLP_BAS_CODEGEN_3.4.x';
use constant VERSION => 'BLP_BAS_CODEGEN_3.4.x_DEV';

use constant BDENS  => 'http://bloomberg.com/schemas/BdeSchemaX';
use constant XMLNS  => 'http://www.w3.org/2001/XMLSchema';
use constant WSDLNS => 'http://schemas.xmlsoap.org/wsdl/';

use constant NESTED_ENUM_TYPE => 'Value';

use constant CPP_KEYWORDS => [qw(
and and_eq bitand bitor bool break case catch char class compl const
const_cast continue default delete do double dynamic_cast else enum
explicit extern false float for friend goto if inline int long mutable
namespace new not not_eq operator or or_eq private protected public
register reinterpret_cast return short signed sizeof static static_cast
struct switch template this throw true try typedef typeid typename union
unsigned using virtual void volatile wchar_t while xor xor_eq)];

use constant CPPTYPE_PRIMITIVE => {
    'bool'           => 1,
  , 'char'           => 1,
  , 'short'          => 1,
  , 'int'            => 1,
  , 'long'           => 1,
  , 'float'          => 1,
  , 'double'         => 1,
  , 'unsigned char'  => 1,
  , 'unsigned short' => 1,
  , 'unsigned int'   => 1,
  , 'unsigned long'  => 1,
};

use constant TYPE_INFO => {
    'boolean' => {
        cpptype => 'bool',
        formattingMode => 'text',
    },
    'byte' => {
        cpptype => 'char',
        formattingMode => 'dec',
    },
    'date' => {
        cpptype => 'bdet_DateTz',
    },
    'dateTime' => {
        cpptype => 'bdet_DatetimeTz',
    },
    'decimal' => {
        cpptype => 'double',
    },
    'double' => {
        cpptype => 'double',
    },
    'float' => {
        cpptype => 'float',
    },
    'int' => {
        cpptype => 'int',
        formattingMode => 'dec',
    },
    'integer' => {
        cpptype => 'bdes_PlatformUtil::Int64',
        formattingMode => 'dec',
    },
    'long' => {
        cpptype => 'bdes_PlatformUtil::Int64',
        formattingMode => 'dec',
    },
    'negativeInteger' => {
        cpptype => 'bdes_PlatformUtil::Int64',
        formattingMode => 'dec',
    },
    'nonNegativeInteger' => {
        cpptype => 'bdes_PlatformUtil::Uint64',
        formattingMode => 'dec',
    },
    'nonPositiveInteger' => {
        cpptype => 'bdes_PlatformUtil::Int64',
        formattingMode => 'dec',
    },
    'normalizedString' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'positiveInteger' => {
        cpptype => 'bdes_PlatformUtil::Uint64',
        formattingMode => 'dec',
    },
    'short' => {
        cpptype => 'short',
        formattingMode => 'dec',
    },
    'string' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'normalizedString' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'token' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'language' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'Name' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'NMTOKEN' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'NCName' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'NMTOKENS' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'ID' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'IDREF' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'ENTITY' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'IDREFS' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'ENTITIES' => {
        cpptype => 'bsl::string',
        formattingMode => 'text',
    },
    'time' => {
        cpptype => 'bdet_TimeTz',
    },
    'unsignedByte' => {
        cpptype => 'unsigned char',
        formattingMode => 'dec',
    },
    'unsignedInt' => {
        cpptype => 'unsigned int',
        formattingMode => 'dec',
    },
    'unsignedLong' => {
        cpptype => 'bdes_PlatformUtil::Uint64',
        formattingMode => 'dec',
    },
    'unsignedShort' => {
        cpptype => 'unsigned short',
        formattingMode => 'dec',
    },
    'base64Binary' => {
        cpptype => 'bsl::vector<char>',
        formattingMode => 'base64',
        noListSupport => 1,
    },
    'hexBinary' => {
        cpptype => 'bsl::vector<char>',
        formattingMode => 'hex',
        noListSupport => 1,
    },
    'bdeut_BigEndianInt16' => {
        cpptype => 'bdeut_BigEndianInt16',
        formattingMode => 'dec',
    },
    'bdeut_BigEndianUint16' => {
        cpptype => 'bdeut_BigEndianUint16',
        formattingMode => 'dec',
    },
    'bdeut_BigEndianInt32' => {
        cpptype => 'bdeut_BigEndianInt32',
        formattingMode => 'dec',
    },
    'bdeut_BigEndianUint32' => {
        cpptype => 'bdeut_BigEndianUint32',
        formattingMode => 'dec',
    },
    'bdeut_BigEndianInt64' => {
        cpptype => 'bdeut_BigEndianInt64',
        formattingMode => 'dec',
    },
    'bdeut_BigEndianUint64' => {
        cpptype => 'bdeut_BigEndianUint64',
        formattingMode => 'dec',
    },
};

use constant CPPTYPE_ALLOCATES_MEMORY => {
    'bool'                      => ''
  , 'int'                       => ''
  , 'char'                      => ''
  , 'short'                     => ''
  , 'bdes_PlatformUtil::Int64'  => ''
  , 'unsigned int'              => ''
  , 'unsigned char'             => ''
  , 'unsigned short'            => ''
  , 'bdes_PlatformUtil::Uint64' => ''
  , 'float'                     => ''
  , 'double'                    => ''
  , 'bdet_Date'                 => ''
  , 'bdet_DateTz'               => ''
  , 'bdet_Time'                 => ''
  , 'bdet_TimeTz'               => ''
  , 'bdet_Datetime'             => ''
  , 'bdet_DatetimeTz'           => ''
  , 'bdeut_BigEndianInt16'      => ''
  , 'bdeut_BigEndianUint16'     => ''
  , 'bdeut_BigEndianInt32'      => ''
  , 'bdeut_BigEndianUint32'     => ''
  , 'bdeut_BigEndianInt64'      => ''
  , 'bdeut_BigEndianUint64'     => ''
  , 'bsl::string'               => 'allocates memory'
  , 'bsl::vector'               => 'allocates memory'
};

use constant CPPTYPE_PASSBYVAL => {
    'bool'                      => 'pass by value'
  , 'int'                       => 'pass by value'
  , 'char'                      => 'pass by value'
  , 'short'                     => 'pass by value'
  , 'int'                       => 'pass by value'
  , 'bdes_PlatformUtil::Int64'  => 'pass by value'
  , 'unsigned int'              => 'pass by value'
  , 'unsigned char'             => 'pass by value'
  , 'unsigned short'            => 'pass by value'
  , 'bdes_PlatformUtil::Uint64' => 'pass by value'
  , 'float'                     => 'pass by value'
  , 'double'                    => 'pass by value'
  , 'bdeut_BigEndianInt16'      => 'pass by value'
  , 'bdeut_BigEndianUint16'     => 'pass by value'
  , 'bdeut_BigEndianInt32'      => 'pass by value'
  , 'bdeut_BigEndianUint32'     => 'pass by value'
  , 'bdeut_BigEndianInt64'      => 'pass by value'
  , 'bdeut_BigEndianUint64'     => 'pass by value'
};

use constant CPPTYPE_HEADER => {
    'bool'                         =>  ''
  , 'int'                          =>  ''
  , 'char'                         => ''
  , 'short'                        => ''
  , 'bdes_PlatformUtil::Int64'     => 'bdes_platformutil.h'
  , 'unsigned int'                 => ''
  , 'unsigned char'                => ''
  , 'unsigned short'               => ''
  , 'bdes_PlatformUtil::Uint64'    => 'bdes_platformutil.h'
  , 'float'                        => ''
  , 'double'                       => ''
  , 'bdet_Date'                    => 'bdet_date.h'
  , 'bdet_DateTz'                  => 'bdet_datetz.h'
  , 'bdet_Time'                    => 'bdet_time.h'
  , 'bdet_TimeTz'                  => 'bdet_timetz.h'
  , 'bdet_Datetime'                => 'bdet_datetime.h'
  , 'bdet_DatetimeTz'              => 'bdet_datetimetz.h'
  , 'bsl::string'                  => 'bsl_string.h'
  , 'bsl::vector'                  => 'bsl_vector.h'
  , 'bdeut_NullableValue'          => 'bdeut_nullablevalue.h'
  , 'bdeut_NullableAllocatedValue' => 'bdeut_nullableallocatedvalue.h'
  , 'bdeut_BigEndianInt16'         => 'bdeut_bigendian.h'
  , 'bdeut_BigEndianUint16'        => 'bdeut_bigendian.h'
  , 'bdeut_BigEndianInt32'         => 'bdeut_bigendian.h'
  , 'bdeut_BigEndianUint32'        => 'bdeut_bigendian.h'
  , 'bdeut_BigEndianInt64'         => 'bdeut_bigendian.h'
  , 'bdeut_BigEndianUint64'        => 'bdeut_bigendian.h'
};

use constant CPPTYPE_NATIVE => {
    'bool'                      => 'native'
  , 'char'                      => 'native'
  , 'short'                     => 'native'
  , 'int'                       => 'native'
  , 'float'                     => 'native'
  , 'double'                    => 'native'
  , 'unsigned char'             => 'native'
  , 'unsigned short'            => 'native'
  , 'unsigned int'              => 'native'
  , 'bdes_PlatformUtil::Int64'  => 'native'
  , 'bdes_PlatformUtil::Uint64' => 'native'
  , 'bdet_Date'                 => 'native'
  , 'bdet_DateTz'               => 'native'
  , 'bdet_Time'                 => 'native'
  , 'bdet_TimeTz'               => 'native'
  , 'bdet_Datetime'             => 'native'
  , 'bdet_DatetimeTz'           => 'native'
  , 'bsl::string'               => 'native'
  , 'bdeut_BigEndianInt16'      => 'native'
  , 'bdeut_BigEndianUint16'     => 'native'
  , 'bdeut_BigEndianInt32'      => 'native'
  , 'bdeut_BigEndianUint32'     => 'native'
  , 'bdeut_BigEndianInt64'      => 'native'
  , 'bdeut_BigEndianUint64'     => 'native'
};

use constant AGGREGATE_VALUE_ACCESSOR => {
    'boolean'            => 'asBool'
  , 'byte'               => 'asChar'
  , 'date'               => 'asDateTz'
  , 'dateTime'           => 'asDatetimeTz'
  , 'decimal'            => 'asDouble'
  , 'double'             => 'asDouble'
  , 'float'              => 'asFloat'
  , 'int'                => 'asInt'
  , 'integer'            => 'asInt64'
  , 'long'               => 'asInt64'
  , 'negativeInteger'    => 'asInt64'
  , 'nonNegativeInteger' => 'asInt64'
  , 'nonPositiveInteger' => 'asInt64'
  , 'normalizedString'   => 'asString'
  , 'positiveInteger'    => 'asInt64'
  , 'short'              => 'asShort'
  , 'string'             => 'asString'
  , 'normalizedString'   => 'asString'
  , 'token'              => 'asString'
  , 'language'           => 'asString'
  , 'Name'               => 'asString'
  , 'NMTOKEN'            => 'asString'
  , 'NCName'             => 'asString'
  , 'NMTOKENS'           => 'asString'
  , 'ID'                 => 'asString'
  , 'IDREF'              => 'asString'
  , 'ENTITY'             => 'asString'
  , 'ENTITIES'           => 'asString'
  , 'time'               => 'asTimeTz'
  , 'unsignedByte'       => 'asChar'
  , 'unsignedInt'        => 'asInt'
  , 'unsignedLong'       => 'asInt64'
  , 'unsignedShort'      => 'asShort'
};

use constant XML_ENTITY_MAP => {
    '&quot;' => '"'
  , '&amp;'  => '&'
  , '&apos;' => '\''
  , '&lt;'   => '<'
  , '&gt;'   => '>'
};

use constant SYMBOL_TRANSLATION => {
    ' '  => '_'
  , '!'  => 'EXCLAMATION'
  , '"'  => 'QUOTE'
  , '#'  => 'POUND'
  , '$'  => 'DOLLAR'
  , '%'  => 'PERCENT'
  , '&'  => 'AMPERSAND'
  , '\'' => 'TICK'
  , '('  => 'LPAREN'
  , ')'  => 'RPAREN'
  , '*'  => 'STAR'
  , '+'  => 'PLUS'
  , ','  => 'COMMA'
  , '-'  => 'DASH'
  , '.'  => 'DOT'
  , '/'  => 'SLASH'
  , ':'  => 'COLON'
  , ';'  => 'SEMICOLON'
  , '<'  => 'LESS'
  , '='  => 'EQUAL'
  , '>'  => 'GREATER'
  , '?'  => 'QUESTION'
  , '@'  => 'AT'
  , '['  => 'LBRACKET'
  , '\\' => 'BACKSLASH'
  , ']'  => 'RBRACKET'
  , '^'  => 'CARET'
  , '`'  => 'BACKTICK'
  , '{'  => 'LBRACE'
  , '|'  => 'PIPE'
  , '}'  => 'RBRACE'
  , '~'  => 'TILDE'
};

use constant TARGETS => {
    'h' => {
        'cmp' => {
            'template' => 'component_h.t',
            'key'      => 'package',
            'suffix'   => '.h',
        },
    },
    'cpp' => {
        'cmp' => {
            'template' => 'component_cpp.t',
            'key'      => 'package',
            'suffix'   => '.cpp',
        },
    },
    't' => {
#       'noOverwrite' => 1,
        'cmp' => {
            'template' => 'component_t.t',
            'key'      => 'package',
            'suffix'   => '.t.cpp',
        },
    },
    'configschema.h' => {
        'cfg' => {
            'template' => 'configschema_h.t',
            'key'      => 'package',
            'suffix'   => '_configschema.h',
        },
    },
    'configschema.cpp' => {
        'cfg' => {
            'template' => 'configschema_cpp.t',
            'key'      => 'package',
            'suffix'   => '_configschema.cpp',
        },
    },
    'configschema.t.cpp' => {
        'isTestDriver' => '1',
        'cfg' => {
            'template' => 'configschema_t.t',
            'key'      => 'package',
            'suffix'   => '_configschema.t.cpp',
        },
    },
#   'flat.cfg.xsd' => {
#       'cfg' => {
#           'template' => 'schema.t',
#           'key'      => 'serviceName',
#           'suffix'   => '_flat_cfg.xsd',
#       },
#   },
    'cfg' => {
        'warnServiceName' => 1,
        'checkServiceName' => 1,
        'noOverwrite' => 1,
        'app' => {
            'template' => 'svccfg_xml.t',
            'key'      => 'serviceName',
            'suffix'   => '.cfg',
        },
    },
    'cfg.xsd' => {
        'warnServiceName' => 1,
        'noOverwrite' => 1,
        'app' => {
            'template' => 'svccfg_xsd.t',
            'key'      => 'serviceName',
            'suffix'   => '_cfg.xsd',
        },
    },
    'flat.xsd' => {
        'checkTopLevelTypes' => 0,
        'warnPackageName'    => 0,
        'svc' => {
            'template' => 'schema.t',
            'key'      => 'serviceName',
            'suffix'   => '_flat.xsd',
        },
    },
    'wsdl.xsd' => {
        'requiresWsdl' => 1,
        'svc' => {
            'template' => 'schema.t',
            'key'      => 'serviceName',
            'suffix'   => '.wsdl.xsd',
        },
    },
    'requestcontext.h' => {
        'checkTopLevelTypes' => 1,
        'merge' => \&mergeRequestContext_h,
        'svc' => {
            'template' => 'requestcontext_h.t',
            'key'      => 'package',
            'suffix'   => '_requestcontext.h',
        },
    },
    'requestcontext.cpp' => {
        'checkTopLevelTypes' => 1,
        'merge' => \&mergeRequestContext_cpp,
        'svc' => {
            'template' => 'requestcontext_cpp.t',
            'key'      => 'package',
            'suffix'   => '_requestcontext.cpp',
        },
    },
    'requestcontext.t.cpp' => {
        'checkTopLevelTypes' => 1,
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'requestcontext_t.t',
            'key'      => 'package',
            'suffix'   => '_requestcontext.t.cpp',
        },
    },
    'requestrouter.h' => {
        'checkTopLevelTypes' => 1,
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'requestrouter_h.t',
            'key'      => 'package',
            'suffix'   => '_requestrouter.h',
        },
    },
    'requestrouter.cpp' => {
        'checkTopLevelTypes' => 1,
        'merge' => \&mergeRequestRouter_cpp,
        'svc' => {
            'template' => 'requestrouter_cpp.t',
            'key'      => 'package',
            'suffix'   => '_requestrouter.cpp',
        },
    },
    'requestrouter.t.cpp' => {
        'checkTopLevelTypes' => 1,
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'requestrouter_t.t',
            'key'      => 'package',
            'suffix'   => '_requestrouter.t.cpp',
        },
    },
    'requestprocessor.h' => {
        'checkTopLevelTypes' => 1,
        'merge' => \&mergeRequestProcessor_h,
        'svc' => {
            'template' => 'requestprocessor_h.t',
            'key'      => 'package',
            'suffix'   => '_requestprocessor.h',
        },
    },
    'requestprocessor.cpp' => {
        'checkTopLevelTypes' => 1,
        'merge' => \&mergeRequestProcessor_cpp,
        'svc' => {
            'template' => 'requestprocessor_cpp.t',
            'key'      => 'package',
            'suffix'   => '_requestprocessor.cpp',
        },
    },
    'requestprocessor.t.cpp' => {
        'checkTopLevelTypes' => 1,
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'requestprocessor_t.t',
            'key'      => 'package',
            'suffix'   => '_requestprocessor.t.cpp',
        },
    },
    'entry.h' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'entry_h.t',
            'key'      => 'package',
            'suffix'   => '_entry.h',
        },
    },
    'entry.cpp' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'entry_cpp.t',
            'key'      => 'package',
            'suffix'   => '_entry.cpp',
        },
    },
    'entry.t.cpp' => {
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'entry_t.t',
            'key'      => 'package',
            'suffix'   => '_entry.t.cpp',
        },
    },
    'manifest.h' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'manifest_h.t',
            'key'      => 'package',
            'suffix'   => '_manifest.h',
        },
    },
    'manifest.cpp' => {
#       'merge' => \&mergeManifest_cpp,
        'svc' => {
            'template' => 'manifest_cpp.t',
            'key'      => 'package',
            'suffix'   => '_manifest.cpp',
        },
    },
    'manifest.t.cpp' => {
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'manifest_t.t',
            'key'      => 'package',
            'suffix'   => '_manifest.t.cpp',
        },
    },
    'baslet.mk' => {
        'warnServiceName' => 1,
        'merge' => \&mergeMakefile,
        'svc' => {
            'template' => 'baslet_mk.t',
            'prefix'   => 'lib',
            'key'      => 'package',
            'suffix'   => '.mk',
        },
    },
    'buildopts.h' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'buildopts_h.t',
            'key'      => 'package',
            'suffix'   => '_buildopts.h',
        },
    },
    'buildopts.cpp' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'buildopts_cpp.t',
            'key'      => 'package',
            'suffix'   => '_buildopts.cpp',
        },
    },
    'buildopts.t.cpp' => {
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'buildopts_t.t',
            'key'      => 'package',
            'suffix'   => '_buildopts.t.cpp',
        },
    },
    'versiontag.h' => {
#       'noOverwrite' => 1,
        'merge' => \&mergeVersionTag_h,
        'svc' => {
            'template' => 'versiontag_h.t',
            'key'      => 'package',
            'suffix'   => '_versiontag.h',
        },
    },
    'versiontag.cpp' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'versiontag_cpp.t',
            'key'      => 'package',
            'suffix'   => '_versiontag.cpp',
        },
    },
    'versiontag.t.cpp' => {
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'versiontag_t.t',
            'key'      => 'package',
            'suffix'   => '_versiontag.t.cpp',
        },
    },
    'version.h' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'version_h.t',
            'key'      => 'package',
            'suffix'   => '_version.h',
        },
    },
    'version.cpp' => {
        'noOverwrite' => 1,
        'svc' => {
            'template' => 'version_cpp.t',
            'key'      => 'package',
            'suffix'   => '_version.cpp',
        },
    },
    'version.t.cpp' => {
        'noOverwrite' => 1,
        'isTestDriver' => '1',
        'svc' => {
            'template' => 'version_t.t',
            'key'      => 'package',
            'suffix'   => '_version.t.cpp',
        },
    },
    'start_script' => {
        'warnServiceName' => 1,
        'checkServiceName' => 1,
        'noOverwrite' => 1,
        'fileMode' => 0774,
        'app' => {
            'template' => 'start_svc.t',
            'prefix'   => 'start_',
            'key'      => 'serviceName',
        },
    },
    'pstart_script' => {
        'warnServiceName' => 1,
        'checkServiceName' => 1,
        'noOverwrite' => 1,
        'fileMode' => 0774,
        'app' => {
            'template' => 'pstart_svc.t',
            'prefix'   => 'pstart_',
            'key'      => 'serviceName',
        },
    },
    'stop_script' => {
        'warnServiceName' => 1,
        'checkServiceName' => 1,
        'noOverwrite' => 1,
        'fileMode' => 0774,
        'app' => {
            'template' => 'stop_svc.t',
            'prefix'   => 'stop_',
            'key'      => 'serviceName',
        },
    },
    'service.m.cpp' => {
        'noOverwrite' => 1,
        'merge' => \&mergeMain,
        'app' => {
            'template' => 'service_cpp.t',
            'key'      => 'serviceName',
            'suffix'   => '.m.cpp',
        },
    },
    'service.mk' => {
        'warnServiceName' => 1,
        'checkServiceName' => 1,
        'merge' => \&mergeMakefile,
        'app' => {
            'template' => 'service_mk.t',
            'key'      => 'serviceName',
            'suffix'   => '.mk',
        },
    },
    'service_dum.c' => {
        'noOverwrite' => 1,
        'requiresBBEnv' => 1,
        'app' => {
            'template' => 'make_dums.t',
            'key'      => 'serviceName',
            'suffix'   => '_dum.c',
        },
    },
    'service_refs.c' => {
        'noOverwrite' => 1,
        'requiresBBEnv' => 1,
        'app' => {
            'template' => 'make_refs.t',
            'key'      => 'serviceName',
            'suffix'   => '_refs.c',
        },
    },
    'client.m.cpp' => {
        'noOverwrite' => 1,
        'app' => {
            'template' => 'client_cpp.t',
            'name'     => 'test',
            'key'      => 'serviceName',
            'suffix'   => '.m.cpp',
        },
    },
    'client.mk' => {
        'warnServiceName' => 1,
        'merge' => \&mergeMakefile,
        'app' => {
            'template' => 'client_mk.t',
            'name'     => 'client.mk',
        },
    },
    'client_dum.c' => {
        'noOverwrite' => 1,
        'requiresBBEnv' => 1,
        'plink' => {
            'template' => 'make_dums.t',
            'name'     => 'client',
            'suffix'   => '_dum.c',
        },
    },
    'client_refs.c' => {
        'noOverwrite' => 1,
        'requiresBBEnv' => 1,
        'plink' => {
            'template' => 'make_refs.t',
            'name'     => 'client',
            'suffix'   => '_refs.c',
        },
    },
};

use constant MODES => {
    'validate' => {
        'priority' => '0',
        'warnPackageName' => 0,
        'inline' => 1,
        'extended' => 1,
    },
    'cmp' => {
        # This is an artificial mode that allows you to build components
        # without enforcing service namespace rules.
        'priority' => '10',
        'checkServiceName' => 0,
        'warnServiceName' => 0,
        'warnPackageName' => 0,
        'checkPackageName' => 0,
        'useExtension' => 0,    # only enabled in 'msg' mode
    },
    'msg' => {
        'priority' => '40',
        'warnServiceName' => 0,
        'warnPackageName' => 1,
        'checkPackageName' => 0,
        'extended' => 1,
        'inline' => 1, # enabled for flat.xsd in 'all' mode (DRQS 8564385)
        'target' => [
            'h',
            'cpp',
            't',
        ],
    },
    'svc' => {
        'priority' => '20',
        'warnServiceName' => 1,
        'warnPackageName' => 1,
        'checkServiceName' => 1,
        'checkTopLevelTypes' => 1,
        'checkPackageName' => 1,
        'inline' => 1,
        'extended' => 1,
        'target' => [
            'buildopts.h',
            'buildopts.cpp',
            'buildopts.t.cpp',
            'versiontag.h',
            'versiontag.cpp',
            'versiontag.t.cpp',
            'version.h',
            'version.cpp',
            'version.t.cpp',
            'requestcontext.h',
            'requestcontext.cpp',
            'requestcontext.t.cpp',
            'requestrouter.h',
            'requestrouter.cpp',
            'requestrouter.t.cpp',
            'requestprocessor.h',
            'requestprocessor.cpp',
            'requestprocessor.t.cpp',
            'manifest.h',
            'manifest.cpp',
            'manifest.t.cpp',
            'entry.h',
            'entry.cpp',
            'entry.t.cpp',
            'flat.xsd',
            'baslet.mk',
        ],
    },
    'app' => {
        'priority' => '30',
        'warnServiceName' => 1,
        'warnPackageName' => 1,
        'checkServiceName' => 1,
#       'checkTopLevelTypes' => 1,
        'checkPackageName' => 1,
        'inline' => 1,
        'extended' => 1,
        'target' => [
            'service.m.cpp',
            'client.m.cpp',
            'cfg.xsd',
            'configschema.h',
            'configschema.cpp',
            'configschema.t.cpp',
            'cfg',
            'start_script',
            'pstart_script',
            'stop_script',
            'service.mk',
            'service_dum.c',
            'service_refs.c',
            'client.mk',
        ],
    },
    'cfg' => {
        'priority' => '40',
        'warnServiceName' => 0,
        'warnPackageName' => 1,
        'checkPackageName' => 1,
        'inline' => 1,
        'recurse' => 0,
        'extended' => 1,
        'strip' => 0,
        'target' => [
            'configschema.h',
            'configschema.cpp',
            'configschema.t.cpp',
            'cfg',
        ],
    },
};

use constant CUSTOMIZEDTYPE_CONVERT_FUNCTIONS =>
  {
   'bool'                      => {
                                   'from' => 'fromBool',
                                   'to'   => 'toBool',
                                  },
   'int'                       => {
                                   'from' => 'fromInt',
                                   'to'   => 'toInt',
                                  },
   'char'                      => {
                                   'from' => 'fromChar',
                                   'to'   => 'toChar',
                                  },
   'short'                     => {
                                   'from' => 'fromShort',
                                   'to'   => 'toShort',
                                  }
   ,
   'bdes_PlatformUtil::Int64'  => {
                                   'from' => 'fromInt64',
                                   'to'   => 'toInt64',
                                  },
   'unsigned int'              => {
                                   'from' => 'fromUnsignedInt',
                                   'to'   => 'toUnsignedInt',
                                  },
   'unsigned char'             => {
                                   'from' => 'fromUnsignedChar',
                                   'to'   => 'toUnsignedChar',
                                  },
   'unsigned short'            => {
                                   'from' => 'fromUnsignedShort',
                                   'to'   => 'toUnsignedShort',
                                  },
   'bdes_PlatformUtil::Uint64' => {
                                   'from' => 'fromUnsignedInt64',
                                   'to'   => 'toUnsignedInt64',
                                  },
   'float'                     => {
                                   'from' => 'fromFloat',
                                   'to'   => 'toFloat',
                                  },
   'double'                    => {
                                   'from' => 'fromDouble',
                                   'to'   => 'toDouble',
                                  },
   'bdet_Date'                 => {
                                   'from' => 'fromDate',
                                   'to'   => 'toDate',
                                  },
   'bdet_DateTz'               => {
                                   'from' => 'fromDateTz',
                                   'to'   => 'toDateTz',
                                  },
   'bdet_Time'                 => {
                                   'from' => 'fromTime',
                                   'to'   => 'toTime',
                                  },
   'bdet_TimeTz'               => {
                                   'from' => 'fromTimeTz',
                                   'to'   => 'toTimeTz',
                                  },
   'bdet_Datetime'             => {
                                   'from' => 'fromDatetime',
                                   'to'   => 'toDatetime',
                                  },
   'bdet_DatetimeTz'           => {
                                   'from' => 'fromDatetimeTz',
                                   'to'   => 'toDatetimeTz',
                                  },
   'bsl::string'               => {
                                   'from' => 'fromString',
                                   'to'   => 'toString',
                                  },
  };

use constant DEFAULT_FILE_MODE => 0664;

#==============================================================================
#                         GLOBAL TYPES AND VARIABLES

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

SCHEMAPARSER: {
  package SchemaParser;
  our @ISA = qw(XML::Simple);

  my $verbose        = 0;
  my $schemaComplete = 0;
  my @elementStack;

  sub start_element {
    my $self    = shift;
    my $element = shift;

    $self->SUPER::start_element($element);
    push @elementStack, $element;
  }

  sub end_element {
    my $self    = shift;
    my $element = shift;

    my $currentElement = pop @elementStack;
    die "** ERR: element stack mismatch" unless
      ((defined $currentElement) and
       ($currentElement->{Name}  eq $element->{Name}));

    my $curlist = $self->{curlist};

    $self->{curlist} = pop @{ $self->{lists} };
    $self->{schemaComplete} = 1 if $element->{Name} =~ /schema$/;
    return if $self->{schemaComplete};

    die "** ERR: Fatal Error: is source file an XSD or WSDL?\n"
        if $#{$self->{lists}} < 0;

    my $parentName = $elementStack[$#elementStack]->{Name};
    return unless defined $parentName;

    # Make anonymous choices and sequences look like nested element types.
    if ($parentName =~ /\bsequence\b|\bchoice\b/
    and $element->{Name} =~ /(\bsequence\b|\bchoice\b)/) {
      # splice off 'choice' or 'sequence' and its list representation, and push
      # on a nested element with the (anonymous) choice or sequence type.
      splice(@{$self->{curlist}}, $#{@{$self->{curlist}}} - 1);

      my $elementTag = 'element';
      my $traitTag   = $1;
      my $typeTag    = 'complexType';
      if ($self->{opt}->{nsexpand} and $element->{NamespaceURI}) {
        $elementTag = "{$$element{NamespaceURI}}element";
        $traitTag   = "{$$element{NamespaceURI}}$traitTag";
        $typeTag    = "{$$element{NamespaceURI}}complexType";
      }

      push(@{$self->{curlist}},
           $elementTag, [ {%{$curlist->[0]}}, 0, '',
                          $typeTag, [ {}, 0, '', $traitTag, $curlist ]]);
    }
  }

  sub end_document {
    my $self = shift;
    my $tree = $self->SUPER::end_document(@_);

    $self->{schemaComplete} = 0;

    die "** ERR: invalid element stack" unless ($#elementStack == -1);

    print main::Dumper($tree) if $self->{verbose};
    return $tree;
  }

  sub new {
    my $class = shift;
    my %options = @_;
    my $verbosity = delete $options{verbose} || 0;

    my $self = $class->SUPER::new(%options);
    $self->{verbose} = $verbosity;
    return $self;
  }
}

my $parser = new SchemaParser(verbose => 0);  # global parser instance
my $authorInfo;                               # cached across schema instances
my $timestamp = localtime();                  # cached across schema instances

# remap CPP_KEYWORDS constant array ref into a hash table for faster lookups
my %cpp_keywords;
$cpp_keywords{$_}=undef foreach @{CPP_KEYWORDS()};

#==============================================================================

sub usage(;$)
{
    print STDERR "!! @_\n" if @_;

    my $prog = basename $0;

    my $targets = join('|', (sort keys(%{(TARGETS)})));
    my $modes = join('|', sort grep !/cmp/, keys(%{(MODES)}));

    print <<_USAGE_END;
Usage: bas_codegen.pl ( -m <all|$modes> )*
                      [ -s <serviceName:serviceId> ]
                      [ <options> ]*
                      schema.<xsd|wsdl>

  --help          | -h             usage information (this text)
  --version       | -v             display version and exit
  --package       | -p <name>      use specified package name prefix
  --serviceInfo   | -s <info>      specify the service information
  --msgComponent  | -C <component> specify the (single) message component
  --msgExpand     | -E             generate multiple message components
  --msgPrefix     | -P <prefix>    prefix each message type with prefix
  --msgLibrary    | -L <library>   use specified message library
  --mode          | -m <mode>      use the specified mode
  --component     | -c <component> generate specified components only
  --target        | -g <target>    generate the specified target
  --exclude       | -x <target>    do not generate the specified target
  --author        | -a <author>    use specified author name
  --force         | -f             force overwriting of "user-owned" files
  --print         | -o             send generated text to stdout
  --recurse       | -r             generate included schemas
  --inline        | -i             expand included schema (no generation)
  --includedir    | -I <path>      search path for included schema files
  --strip         | -S             strip converted schema of bdem-specific
                                   elements and attributes
  --destination   | -D <directory> output files in the specified directory
  --noValidation  | -V             alias for --noRapidValidation (deprecated)
  --noRapidValidation              do not perform RAPID schema validation
  --allowInvalidSchema             only warn about schema syntax errors
  --showFlatSchema                 write flat schema to standard out
  --noSchema                       no schema is specified (use raw messages)
  --noTimestamps                   do not encode timestamps in generated files
  --noWarnings                     suppress warnings
  --omitIntrospection              omit introspection support
  --noAggregateConversion          omit aggregate conversion support
  --configSchema      <y|n>        generate separate configschema component
  --dualSTL           <y|n>        generate standard-STL compatible code
  --ignoreCase        <y|n>        specify case sensitivity of message types
  --testDrivers       <y|n>        generate test drivers for component
  --requestType       <type>       specify top-level request type
  --responseType      <type>       specify top-level response type

Modes all, app, cfg, and svc require the --serviceInfo option.  The <info>
argument has the following form:

 [ serviceName : ] serviceId [ - majorVersion [ . minorVersion ] ] ]

The only required field of <info> is the serviceId.  This value should match
the serviceId under which the service is registered in the {PWHO<GO>}
database.

In practice, the optional <serviceName> should also be specified since this
name is required by various generated files.  The service name is used to
identify the service to the execution environment.  The service name should
match the ProcMgr name under which the service is registered in the
{PWHO<GO>} database.  This name is used to derive the name of the service
executable as well as corresponding scripts and configuration files.  It is
common practice to embed this value into the service schema, which also helps
to document which service the schema describes.

See 'perldoc $prog' for more information.

_USAGE_END
}

#------------------------------------------------------------------------------

sub parseServiceName(\%$)
{
  # Parse the value of the '--serviceName' option or 'bdem:serviceName'
  # attribute and load into the specified 'data' hash reference the component
  # values.  Return 0 on success and a non-zero value otherwise.

  my ($data, $serviceName) = @_;

  if (defined $serviceName) {
    if ($serviceName =~ m/^([A-Za-z]\w*)(:(\d+)(-(\d+)(\.(\d+))?)?)?$/) {
      $data->{serviceName}         = $1;
      $data->{serviceId}           = $3;
      $data->{serviceVersionMajor} = $5 || 1;
      $data->{serviceVersionMinor} = $7 || 0;
    }
    else {
      return -1;
    }
  }

  return 0;
}

sub parseServiceInfo(\%$)
{
  # Parse the value of the '--serviceInfo' option or 'bdem:serviceInfo'
  # attribute and load into the specified 'data' hash reference the component
  # values.  Return 0 on success and a non-zero value otherwise.

  my ($data, $serviceInfo) = @_;

  if (defined $serviceInfo) {
    if ($serviceInfo =~ m/^(([A-Za-z]\w*):)?(\d+)(-(\d+)(\.(\d+))?)?$/) {
      $data->{serviceName}         = $2;
      $data->{serviceId}           = $3;
      $data->{serviceVersionMajor} = $5 || 1;
      $data->{serviceVersionMinor} = $7 || 0;
    }
    else {
      return -1;
    }
  }

  return 0;
}

#------------------------------------------------------------------------------

sub getoptions()
{
  my %opts;

  Getopt::Long::Configure("bundling");
  unless (GetOptions(\%opts, qw[
           help|h
           version|v
           serviceName=s
           serviceInfo|s=s
           package|p=s
           msgComponent|C=s
           msgPrefix|P=s
           msgExpand|E
           msgLibrary|L=s
           mode|m=s@
           component|c=s@
           target|g=s@
           exclude|x=s@
           author|a=s
           force|f
           print|o
           recurse|r
           inline|i
           includedir|I=s@
           strip|S
           destination|D=s
           noRapidValidation|V
           noValidation
           allowInvalidSchema
           showFlatSchema
           noSchema
           noTimestamps
           noWarnings|W
           noAggregateConversion
           omitIntrospection
           parameterizedConstructors
           configSchema=s
           dualSTL=s
           ignoreCase=s
           testDrivers=s
           requestType=s
           responseType=s

           noComments
           noEmptySimpleTypes
           validateFlatSchema
           debug|d=s
          ])) {

    usage();
    exit 1;
  }

  # help
  usage() and exit 0 if $opts{help};

  # version
  print VERSION, "\n" and exit 0 if $opts{version};

  $opts{cache}             = {};  # schema file cache
  $opts{extended}          = 1;
  $opts{useExtension}      = 1;
  $opts{debug}             = 0 unless defined $opts{debug};
  $opts{recurse}           = 0 unless defined $opts{recurse};
  $opts{noSchema}          = 0 unless defined $opts{noSchema};
  $opts{msgExpand}         = 0 unless defined $opts{msgExpand};
  $opts{msgPrefix}         = '' unless defined $opts{msgPrefix};
  $opts{noTimestamps}      = 0 unless defined $opts{noTimestamps};
  $opts{noWarnings}        = 0 unless defined $opts{noWarnings}
                                   or defined $opts{noValidation};
  $opts{destination}       = '.' unless defined $opts{destination};
  $opts{target}            = [] unless defined $opts{target};
  $opts{exclude}           = [] unless defined $opts{exclude};
  $opts{noRapidValidation} = 0 unless defined $opts{noRapidValidation};
  $opts{genOverride}       = defined $opts{target} ? scalar @{$opts{target}}
                                                   : 0;

  if (defined $opts{noValidation}) {
      $opts{noRapidValidation} = $opts{noValidation};
  }

  if (defined $opts{serviceName}) {
#   warn "* WARN: The program option '--serviceName' is deprecated\n"
#      . "  HINT: Use '--serviceInfo' instead\n"
#   unless defined $opts{noWarnings};

    if (defined $opts{serviceInfo}) {
      die "** ERR: The options '--serviceName' and '--serviceInfo' are "
        . "mutually exclusive\n";
    }

    if (0 != parseServiceName(%opts, $opts{serviceName})) {
      die "** ERR: Invalid value for option '--serviceName'\n"
        . "Value '$opts{serviceName}' does not match the format\n"
        . "serviceName [ : serviceId [ - majorVersion [ . minorVersion ] ] ]"
        . "\n";
    }
  }
  elsif (defined $opts{serviceInfo}) {
    if (0 != parseServiceInfo(%opts, $opts{serviceInfo})) {
      die "** ERR: Invalid value for option '--serviceInfo'\n"
        . "Value '$opts{serviceInfo}' does not match the format\n"
        . "[ serviceName : ] serviceId [ - majorVersion [ . minorVersion ] ] ]"
        . "\n";
    }
  }

  if (defined $opts{configSchema}) {
      $opts{configSchema} = ($opts{configSchema} =~ /[yY](es|ES)?/);
  } else {
      # By default, the configuration schema is inlined into application 'main'
      $opts{configSchema} = 0;
  }

  if (defined $opts{dualSTL}) {
      $opts{dualSTL} = ($opts{dualSTL} =~ /[yY](es|ES)?/);
  } else {
      # Generated code cannot be mixed with native STL by default
      $opts{dualSTL} = 0;
  }

  # Remove configuration schema from target list
  push(@{$opts{exclude}}, 'cfg.xsd') unless $opts{configSchema};

  if (defined $opts{ignoreCase}) {
      $opts{ignoreCase} = ($opts{ignoreCase} =~ /[yY](es|ES)?/);
  } else {
      # Generated message types are case-sensitive by default
      $opts{ignoreCase} = 0;
  }

  if (defined $opts{testDrivers}) {
      $opts{testDrivers} = ($opts{testDrivers} =~ /[yY](es|ES)?/);
  } else {
      # Test drivers are not generated by default
      $opts{testDrivers} = 0;
  }

  if (0 == $opts{testDrivers}) {
      my @testDrivers = grep /\.t\.cpp/, keys %{TARGETS()};
      push @{$opts{exclude}}, @testDrivers;
  }

  $opts{msgPrefix} = MixedMixed($opts{msgPrefix});
  if (defined $opts{msgComponent}) {
    if ($opts{msgExpand}) {
      warn "* WARN: Specified message component name being ignored\n"
         . "  Hint: Did you specify --msgComponent and --msgExpand "
         . "options?\n"
         unless $opts{noWarnings};
    } elsif (0 < length $opts{msgPrefix}) {
      warn "* WARN: Specified message component name being ignored\n"
         . "  Hint: Did you specify --msgComponent and --msgPrefix "
         . "options?\n"
         unless $opts{noWarnings};
      $opts{msgComponent} = lc mixedMixed($opts{msgPrefix});
    } else {
      $opts{msgComponent} = lc mixedMixed($opts{msgComponent});
    }
  } else {
    $opts{msgComponent} = (0 < length $opts{msgPrefix})
                        ? lc $opts{msgPrefix}
                        : 'messages';
  }

  if (0 == scalar @{$opts{target}}) {
  if (!defined $opts{mode}) {
      $opts{mode} = [ 'validate' ];
  } elsif (grep(/all/, @{$opts{mode}})) {
      $opts{mode} = [];
      push(@{$opts{mode}}, 'svc', 'app');
      push(@{$opts{mode}}, 'msg') unless defined $opts{msgLibrary};
  }}

  # Validate the exclusion list
  foreach my $excludedTarget (@{$opts{exclude}}) {
    die "** ERR: Invalid target '$excludedTarget'\n"
      unless defined TARGETS->{$excludedTarget};
  }

  # Remove explicitly specified targets from exclusion list
  foreach my $t (@{$opts{target}}) {
      $opts{exclude} = [ grep { !/$t/ } @{$opts{exclude}} ];
  }

  $opts{warnServiceName} = scalar grep { $_ !~ m/msg|cmp|cfg/ } @{$opts{mode}};

  # Always enable schema validation. --noRapidValidation is processed locally
  # within 'validateSchema'
  push @{$opts{mode}}, 'validate';

  push(@{$opts{target}}, ('h', 'cpp', 't')) and $opts{genOverride} = 1
      if defined $opts{component} and !$opts{genOverride};

  # Merge options from overridden target list
  if ($opts{genOverride}) {
    my %mergedOpts;
    foreach my $gen (@{$opts{target}}) {
      my $target = TARGETS->{$gen};
      die "** ERR: Unsupported target: $gen\n"
        . "   see 'perldoc bas_codegen.pl'\n"
        unless defined $target;

      foreach my $key (keys %$target) {
        if ("HASH" eq ref $target->{$key} and !$opts{$key}) {
          push @{$opts{mode}}, $key;
          $opts{$key} = 1;
        } else {
          $mergedOpts{$key} = $target->{$key};
        }
      }
      foreach my $key (keys %opts) {
        if ("ARRAY" eq ref $opts{$key}) {
          push(@{$mergedOpts{$key}}, @{$opts{$key}});
        } else {
          $mergedOpts{$key} = $opts{$key};
        }
      }
      %opts = %mergedOpts;
    }
  }

  if (defined $opts{msgLibrary} and grep(/cmp|msg/, @{$opts{mode}})) {
      die "** ERR: Option --msgLibrary may not be combined with 'msg' mode\n"
        . "        or targets 'h', 'cpp', or 't'\n";
  }

  # Enable debug without modes
  $opts{mode} = [ 'cmp' ] if $opts{debug} and $#{@{$opts{mode}}} < 0;

  # Remove duplicates in mode array.
  {
    my %modes;
    foreach my $mode (@{$opts{mode}}) {
      next if 'all' eq $mode;
      die "** ERR: Unsupported mode: $mode\n"
        . "   see 'perldoc bas_codegen.pl'\n"
        unless defined MODES->{$mode};
      $modes{$mode}++;
    }
    delete $modes{cmp} if exists $modes{msg};
    @{$opts{mode}} = sort { MODES->{$a}->{priority} <=> MODES->{$b}->{priority}
                          } keys %modes;
  }

  # Set individual mode flags
  foreach my $mode (@{$opts{mode}}) {
      $opts{$mode . 'ModeFlag'} = 1;
  }

  # Remove duplicates in target and component arrays
  foreach my $key ('target', 'component') {
    my %unique;
    map { $unique{$_} = 1 } @{$opts{$key}};
    @{$opts{$key}} = keys %unique;
  }

  unless ($opts{noSchema}) {
  if (scalar (@ARGV) != 1) {
    usage("Unexpected number of arguments");
    exit 1;
  }}

  @{$opts{schemaFile}} = @ARGV;

  my $commandLineOptions = \%opts;
  %{$opts{commandLineOptions}} = %$commandLineOptions;

  print Dumper \%opts if 6 < $opts{debug};

  return \%opts;
}

sub adjustOpts(\%$)
{
  my ($opts, $mode) = @_;

  unless (defined MODES->{$mode}) {
    usage("Unrecognized mode: $mode");
    exit 1;
  }

  my @genOpts = @{$opts->{target}} if $opts->{genOverride};

  # Reset 'opts'.
  my $commandLineOptions = $opts->{commandLineOptions};
  my $cache = $opts->{cache};
  my $includedir = $opts->{includedir};

  my $omode = $opts->{mode};
  my $recurse = $opts->{recurse};
  my $genOverride = $opts->{genOverride};
  my $appModeFlag = $opts->{appModeFlag};
  my $msgModeFlag = $opts->{msgModeFlag};
  my $schemaFile = $opts->{schemaFile};

  my $serviceName = $opts->{serviceName};
  my $serviceId = $opts->{serviceId};
  my $serviceVersionMajor = $opts->{serviceVersionMajor};
  my $serviceVersionMinor = $opts->{serviceVersionMinor};

  %$opts = %{$opts->{commandLineOptions}};
  $opts->{commandLineOptions} = $commandLineOptions;
  $opts->{cache} = $cache;
  $opts->{includedir} = $includedir;

  $opts->{mode} = $omode;
  $opts->{recurse} = $recurse;
  $opts->{genOverride} = $genOverride;
  $opts->{appModeFlag} = $appModeFlag;
  $opts->{msgModeFlag} = $msgModeFlag;
  $opts->{schemaFile} = $schemaFile;

  $opts->{serviceName} = $serviceName;
  $opts->{serviceId} = $serviceId;
  $opts->{serviceVersionMajor} = $serviceVersionMajor;
  $opts->{serviceVersionMinor} = $serviceVersionMinor;

  $opts->{$mode} = 1 unless $opts->{genOverride} and $mode ne 'validate';

  my %mergedOpts = %{MODES->{$mode}};
  foreach my $key (keys %mergedOpts) {
    unless (defined $opts->{$key}) {
      $opts->{$key} = $mergedOpts{$key};
    }
  }

  $opts->{target} = MODES->{$mode}->{target}
      unless $opts->{genOverride};

  # Command line target list overrides target list derived from modes
  @{$opts->{target}} = @genOpts if scalar(@genOpts);
  foreach my $gen (@{$opts->{target}}) {
    if (! defined TARGETS->{$gen}) {
      usage("Unsupported target: $gen");
      exit 1;
    }
  }

  # Remove excluded targets.
  my %h;
  @h{@{$opts->{target}}} = undef;
  delete @h{@{$opts->{exclude}}};
  @{$opts->{target}} = sort keys %h;
}

#------------------------------------------------------------------------------

sub splitName($)
{
    my $name   = shift;
    my @pieces = split(/[\W_]/, $name);
    my $nelem  = @pieces;

    if (1 == $nelem
    &&  $pieces[0] =~ m/[a-z]/
    &&  $pieces[0] =~ m/[A-Z]/)
    {
        @pieces = $pieces[0] =~ /.[^A-Z]*/g;
    };

    if (1 < $nelem) {
        @pieces = map { splitName($_) } @pieces;
    }

    return @pieces;
}

#------------------------------------------------------------------------------

sub getAuthorInfo(\%)
{
  my ($opts) = @_;

  my $login = getpwuid($>);
  my $result;

  my $BIN = '/bb/bin';

  if (! -e "$BIN/unixinfo") {
    warn "* WARN: Failed to get Bloomberg employee record for $login\n"
        unless $opts->{noWarnings};
    return;                                                            # RETURN
  }

  my $uinf = `$BIN/unixinfo $login 2>/dev/null`;

  if ($? >> 8 == 0) {
    my ($code, $first, $last) = split /\|/, $uinf;
    if ($code eq 'SUCCESS_OK') {
      $result = "$first $last";
      $result =~ s/\B(\w+)/lc $1/eg;
    }
  }

  unless (defined $result) {
    warn "* WARN: Failed to get Bloomberg employee record for $login\n"
        unless $opts->{noWarnings};
    return;                                                            # RETURN
  }

  my $email = `$BIN/unixinfo -e $login 2>/dev/null`;

  if ($? >> 8 == 0 && length $email > 0) {
    chomp $email;
    $result = "$result ($email)";
    return $result;
  }

  print STDERR "Failed to get Bloomberg e-mail address for $login/$result\n";
  return;
}

#----

sub UPPER_UPPER($)
{
  my ($name) = @_;

  $name =~ s/^([^a-zA-Z]*)//;
  my @pieces = splitName($name);
  if ($1) {
    unshift(@pieces, 'X' . sprintf("%*vx", "", $1) . 'X');
  }
  return join('_', map {uc $_} @pieces);
# return join('_', map {uc $_} splitName($name));
}

#----

sub MixedMixed($)
{
  my ($name) = @_;

  $name =~ s/^([^a-zA-Z]*)//;
  my @pieces = splitName($name);
  if ($1) {
    unshift(@pieces, 'X' . sprintf("%*vx", "", $1) . 'X');
  }
  return join('', map {ucfirst lc $_} @pieces);
# return join('', map {ucfirst lc $_} splitName($name));
}

#----

sub mixedMixed($)
{
  my ($name) = @_;

  return unless $name;

  $name =~ s/^([^a-zA-Z]*)//;
  my @pieces = splitName($name);
  if ($1) {
    unshift(@pieces, 'X' . sprintf("%*vx", "", $1) . 'X');
  }
  return lcfirst join('', map {ucfirst lc $_} @pieces);
# return lcfirst join('', map {ucfirst lc $_} splitName($name));
}

#----

sub c_str($)
{
  my ($text) = @_;

  $text =~ s/\\/\\\\/sg;
  $text =~ s/"/\\"/sg;
  $text =~ s/^(.*)$/"$1\\n"/mg;

  return $text;
}

#----

sub escapeQuotes($)
{
  my ($text) = @_;

  $text =~ s/\\\\\\/\\\\\\\\/sg;
  $text =~ s/^"/\\"/sg;
  $text =~ s/([^\\])"/$1\\"/sg;

  return $text;
}

#----

sub isPrimitiveType($%)
{
  # Return true if the specified (C++) 'type' is a primitive type

  my ($type, $element) = @_;
# my $type = shift;

  my $rc = CPPTYPE_PASSBYVAL->{$type} ? 1 : 0;
  if (!$rc && exists $element->{typeref}->{trait}) {
#     $rc = ( $element->{typeref}->{trait} eq 'customizedType'
#         || $element->{typeref}->{isEmptyType};
      $rc = ( $element->{typeref}->{trait} eq 'enumeration')
          && !$element->{isVectorFlag};
  }
  return $rc;
# return CPPTYPE_PASSBYVAL->{$type} ? 1 : 0;
}

#----

sub isBuiltinType($)
{
  # Return true if the specified 'xsdType' is a built-in type in XSD

  my $xsdType = shift;
  return defined AGGREGATE_VALUE_ACCESSOR->{$xsdType} ? 1 : 0;
}

#----

sub formatComment($$)
{
  my ($annotation, $width) = @_;

  my $spaces   = ' ' x $width;
  my $prefix   = $spaces . "// ";
  my $document = '';

  $Text::Wrap::columns = 80;
  $Text::Wrap::unexpand = 0;

  my $leadingWhitespace = undef;
  my $formatFlag  = 1;
  my $text = '';
  foreach (split "\n", $annotation) {
    s:\t:    :g;
    if (/^$/) {
      $text .= "\n";
    }
    elsif (/^[\s]*\.\.$/) {
      if ($formatFlag) {
        $text =~ s:\.[ ]([^ .]):.  $1:g;  # Two spaces after period.
      }
      $text .= $formatFlag ? "\n..\n" : "..\n";
      $formatFlag = not $formatFlag;
      $document .= $text;
      $text = '';
    }
    else {
      if ($formatFlag) {
        chomp;
        s:(^[ ]*)(//)? ::;
        if (!defined $leadingWhitespace) {
          if (defined $1) { $leadingWhitespace = ' ' x length($1) }
          else            { $leadingWhitespace = '' }
        }
        s:^$leadingWhitespace:: if defined $leadingWhitespace;
        $text .= $_ . ' ';
      }
      else {
        s:^$leadingWhitespace:: if defined $leadingWhitespace;
        $text .= $_ . "\n";
      }
    }
  }

  $text =~ s:\.[ ]([^ .]):.  $1:g;  # Two spaces after period.
  $document .= $text;
  chop($document);

  # Strip leading whitespace.
  $document =~ s:^[\s]+::;

  my $formattedText = Text::Wrap::wrap($prefix, $prefix, $document);
  my @formattedLines = split "\n", $formattedText;
  foreach (@formattedLines) {
    if (m:// \.\.:) {
      s:// ://:;
      $formatFlag = 1 - $formatFlag;
    }
    else {
      s:// ://: unless $formatFlag;
    }

    s:.*//:$spaces . '//':e;
  }
  $formattedText = join "\n", @formattedLines;
  return $formattedText;
}

#------------------------------------------------------------------------------

sub uniqueIncludes(\@$)
{
  my ($array, $deleteKey) = @_;

  return @$array unless @$array;

  my %elements;
  map { $_->{file} && ($elements{$_->{file}} = $_) } @$array;
  delete $elements{$deleteKey};
  return sort { $a->{file} cmp $b->{file} } values %elements;
}

#------------------------------------------------------------------------------

sub encloseTemplateArgs($)
{
  my ($args) = @_;

  if (substr($args, -1) eq '>') {
    return '<' . $args . ' >';
  } else {
    return '<' . $args . '>';
  }
}

#-----------------------------------------------------------------------------
# Rule Enforcement
#-----------------------------------------------------------------------------

{ my $warnedCheckServiceName = 0;
sub checkServiceName(\%\%)
{
  my ($data, $opts) = @_;

  unless ($data->{serviceName} && $data->{serviceId}) {
    die "** ERR: Use --serviceInfo option to specify the service name and "
      . "serviceId\n";
  }

  $opts->{serviceName} = $data->{serviceName};

  warn "* WARN: Service name is too long ($data->{serviceName})\n"
     . "  Hint: Service name should be the same as the ProcMgr name\n"
     and $warnedCheckServiceName = 1
     if  8 < length($data->{serviceName})
     and ! $warnedCheckServiceName
     and  ! $opts->{noWarnings};
}}

{ my $warnedCheckPackageName = 0;
sub checkPackageName(\%\%)
{
  # Ensure that the specified 'data{packageName}' satisfies the naming
  # requirements.

  my ($data, $opts) = @_;

  warn "* WARN: Service package name '$$data{package}' should begin with 's_': "
     . "try --package\n"
     . "\n"
      and $warnedCheckPackageName = 1
      if  (! $warnedCheckPackageName
      and  ! $opts->{noWarnings}
      and    $opts->{checkPackageName} and $data->{package} !~ m/^s_/);
}}

sub checkTopLevelTypes(\%\%\%)
{
  my ($data, $elementTypes, $opts) = @_;

  return unless $opts->{checkTopLevelTypes};
  return if $opts->{noSchema} || $data->{WSDL};

  my $reqType = $data->{requestType};
  my $rspType = $data->{responseType};
  my $requestType  = $opts->{msgPrefix} . MixedMixed($reqType);
  my $responseType = $opts->{msgPrefix} . MixedMixed($rspType);

  # Check for top-level request and response types.  These must be defined
  # as 'complexType's.
  {
    die "** ERR: Failed to identify top-level request type '$reqType': "
      . "try --requestType\n"
        unless grep { $requestType  eq $_->{name} and
                      'complexType' eq $_->{typeCategory} }
                    values %$elementTypes;
    warn "*WARN: top-level request type '$reqType' must be a choice\n"
        unless defined $elementTypes->{$requestType}->{choice};

    die "** ERR: Failed to identify top-level response type '$rspType': "
      . "try --responseType\n"
        unless grep { $responseType eq $_->{name} and
                      'complexType' eq $_->{typeCategory} }
                    values %$elementTypes;
  }
}

#sub enforcePackageNameRestrictions($) {

#  # Note that at present, illegal package names only result in a warning.
#  # TBD: See DRQS 8225107 and determine what, if any, restrictions should be
#  # placed upone package names.

#  my ($packageName) = @_;

#  warn "* WARN: Package name must begin with 's_'\n"
#        if $packageName !~ m/^s_/;
#}

##----

#sub enforceServiceNameRestrictions($) {
#  # Ensure that the specified 'serviceName' satisfies the naming requirements.

#  my ($serviceName) = @_;

#  die "** ERR: Service name cannot start with 's_'\n"
#        if $serviceName =~ m/^s_/;
#}

#------------------------------------------------------------------------------

sub buildSearchTree_CheckChar($);
sub buildSearchTree_CheckChar($)
{
  my ($data) = @_;

  my $numElements = scalar(@$data);

  # establish len
  $numElements > 0 or croak 'cannot build an empty tree';
  my $len = length($data->[0]->{key});

  if ($len == 0) {
    die "Cannot build a tree with duplicates"
      . ": the type contains elements with duplicate names"
      . ": type = "    . $data->[0]->{type}
      . ", element = " . $data->[0]->{val}->{name}
      . "\n"
      unless 1 == $numElements;

    return { type => 'val', val => $data->[0]->{val} };
  } else {

    # collect first chars
    my %m;
    foreach my $item (@$data) {
      length($item->{key})==$len or
        croak 'varying length elements encountered';

      my $firstChar = substr($item->{key},0,1);
      push(@{$m{$firstChar}}, { type => $item->{type}
                              , key  => substr($item->{ key },1)
                              , val  => $item->{val}
                              });
    }

    # sort
    my @keys = sort { $a cmp $b } keys(%m);

    if (scalar(@keys) == 1) {

      my $k = $keys[0];
      my $node = buildSearchTree_CheckChar($m{$k});

      if ($node->{type} eq 'matchText') {
        return { type => 'matchText',
                 text => $k . $node->{text},
                 node => $node->{node} };
      } else {
        return { type => 'matchText',
                 text => $k,
                 node => $node };
      }
    } else {
      my $branches = [];
      foreach my $k (@keys) {
        push @$branches,
             { char => $k, node => buildSearchTree_CheckChar($m{$k})}
      }

      return { type => 'checkChar', branches => $branches };
    }
  }
}

#----

sub buildSearchTreeNode_CheckLen($)
{
  my ($data) = @_;

  # bucket by length
  my %b;
  foreach my $item (@$data) {
    push @{ $b{ length($item->{key}) } }, $item;
  };

  my $branches = [];
  foreach my $k (sort { $a <=> $b} keys(%b)) {
    push @$branches, { len => $k, node => buildSearchTree_CheckChar($b{$k}) };
  }

  return { type => 'checkLen', branches => $branches };
}

#----

sub buildSearchTree($)
{
  my ($data) = @_;

  return buildSearchTreeNode_CheckLen($data);
}

#------------------------------------------------------------------------------

sub preprocessSchema($);
sub preprocessSchema($)
{
  my ($data) = @_;

  my $xmlns = XMLNS;

  my $type = ref $data;
  if (defined $type) {
    if ($type eq 'HASH') {
      my $updated = {};
      while (my ($k, $v) = each %$data) {
        # Eliminate all occurances of the 'id' attribute'.  This attribute is
        # has no meaning to the code generator and causes ambiguity when
        # processing 'bdem:id'.
        next if ($k =~ m/^((\{$xmlns})?id)/);

        $k =~ s/^(\{.*?\})(.+)/$2/;
        $updated->{$k} = preprocessSchema($v);
      }
      return $updated;
    } elsif ($type eq 'ARRAY') {
      my $updated = [];
      foreach my $v (@$data) {
        push @$updated, preprocessSchema($v);
      }
      return $updated;
    } else {
      return $data;
    }
  } else {
    return $data;
  }
}

#------------------------------------------------------------------------------

sub configureIncludes($\@)
{
  my ($elem, $includeFiles) = @_;

  my @incs;

  my @incFiles = @$includeFiles;

  # TBD: 'extraIncludes' is not referenced anywhere else.
  if (defined $elem->{extraIncludes}) {
    push @incFiles, split(/\s+/, $elem->{extraIncludes});
  }

  foreach my $includeFile (@incFiles) {
    my $inc = {};
    $inc->{file} = $includeFile;
    $inc->{guard} = deduceIncludeGuard($includeFile);
    $inc->{defineGuardExternally} =
      deduceIncludeDefineGuardExternallyFlag($includeFile);
    push @incs, $inc;
  }

  push(@{$elem->{include}}, @incs);
}

# -----------------------------------------------------------------------------
# Deduction and Derivation ----------------------------------------------------
# -----------------------------------------------------------------------------

#----

sub derivePackageNameFromSchemaFile($) {
  # Return the derived package name from the specified 'schemaFile'.

  my ($schemaFile) = @_;
  my ($name, $dir, $ext) = fileparse($schemaFile, qr/\..*/);
  #my ($name, $dir, $ext) = fileparse($opts->{schemaFile}->[0], qr/\..*/);
  $name =~ m/^(s_)?(.+)/;
  return 's_' . lc($2);
}

#----

sub derivePackageNameFromServiceName($) {
  # Return the derived package name from the specified 'serviceName'.

  my ($serviceName) = @_;
  return 's_' . lc $serviceName;
}

#----

sub deduceIncludeFile($$);
sub deduceIncludeFile($$) {
  # Return the include file in which the specified 'cpptype' type name resides.
  # TBD: Document 'defaultPackage'.

  my ($cpptype, $defaultPackage) = @_;

  $cpptype =~ s/^\s*(.*\S)\s*$/$1/; # trim spaces

  my @includeFiles;

  my $nested_enum_type = NESTED_ENUM_TYPE;
  if (defined CPPTYPE_HEADER->{$cpptype}) {
    my $header = CPPTYPE_HEADER->{$cpptype};
    if ($header) {
      push @includeFiles, $header;
    }
  } elsif (my ($template, $args) =
              ($cpptype =~ /^([^<]+)<(.*)>$/ ))
  {
    push @includeFiles, deduceIncludeFile($template, $defaultPackage);
    my @argList = split(/,/, $args); # todo: more sophisticated parsing
    foreach my $arg (@argList) {
      push @includeFiles, deduceIncludeFile($arg, $defaultPackage);
    }
  } elsif (my ($wrapperType) = ($cpptype =~ /^(.*)\:\:$nested_enum_type$/)) {
    # enumeration
    push @includeFiles, deduceIncludeFile($wrapperType, $defaultPackage);
  } else {
    my $header = $cpptype;
    $header =~ s/\:\:/_/g;
    if (! ($header =~ /_/)) {
      $header = $defaultPackage . '_' .  $header;
    }
    $header = lc $header;
    $header = $header . '.h';
    push @includeFiles, $header;
  }

  return @includeFiles;
}

#----

sub deduceIncludeGuard($) {
  # Return the BDE-style include guard symbol for the specified 'file'.

  my ($file) = @_;

  my $guard = $file;
  $guard =~ s/\..*//;
  $guard = 'INCLUDED_' . $guard;
  $guard = uc $guard;
  return $guard;
}

#----

sub deduceIncludeDefineGuardExternallyFlag($) {
  # Return true if the specified 'file' requires an external include guard.

  my ($file) = @_;

  my $defineGuardExternally = 0;
  if (! ($file =~ /\./)) {
    $defineGuardExternally = 1;
  }

  return $defineGuardExternally;
}

#------------------------------------------------------------------------------

sub adjustDocumentation(\$);

sub adjustDocumentation(\$)
{
  my ($documentation) = @_;

  my $refType = ref(${$documentation});

  if ($refType eq "HASH") {
    ${$documentation} = ${$documentation}->{content} || '';
  } elsif ($refType eq "ARRAY") {
    ${$documentation} = join("\n\n ", map { adjustDocumentation($_); $_ }
                                          @${$documentation});
  }
}

sub adjustAnnotation($)
{
  my ($element) = @_;

  if (!exists $element->{annotation}) {
    $element->{annotation} = { documentation => [ "" ],
                               purpose       => "TBD: Provide a purpose",
                             };
    return;
  }

  my %annotation;
  foreach my $ann (@{$element->{annotation}}) {
    push(@{$annotation{appinfo}}, @{$ann->{appinfo}})
        if exists $ann->{appinfo};

    push(@{$annotation{documentation}}, @{$ann->{documentation}})
        if exists $ann->{documentation} and !ref $ann->{documentation}->[0];
#       if exists $ann->{documentation} and scalar @{$ann->{documentation}};

    if (exists $ann->{purpose}) {
        if (exists $annotation{purpose}) {
            die "** ERR: Multiple <purpose> tags detected\n";
        }
        $annotation{purpose} = $ann->{purpose};
    }
  }

  $element->{annotation} = \%annotation;
}

sub adjustAppInfo($)
{
  my ($element) = @_;

  if(! defined $element->{appInfoConstants}) {

    $element->{appInfoConstants} = [];

    if (defined $element->{annotation}->{appinfo}) {
      my $appinfo = $element->{annotation}->{appinfo};

      foreach my $ai (@$appinfo) {
      foreach my $c (keys %{$ai}) {
        if ($c eq 'source' || $c =~ /rawCpp/) {
          next;
        }

        my $value = $ai->{$c};

        my $cppValue = $value;
        $cppValue =~ s/"/\\"/g;
        $cppValue = '"' . $cppValue . '"';

        push (@{ $element->{appInfoConstants} }, {
                                                  name => $c,
                                                  value => $value,
                                                  cppValue => $cppValue,
                                                 });
      }}
    }
  }
}

#------------------------------------------------------------------------------

sub adjustElementType($$\%\%);

sub adjustCpptype($$\%\%)
{
  my ($package, $member, $elementTypes, $opts) = @_;

  if (!defined $member->{cpptype}) {

    my (undef, $t) = $member->{type} =~ m/^(\w+:)?(.+)/;

    $member->{noNamespaceFlag} = 0;

    if (defined TYPE_INFO->{$t}) {
      $member->{cpptype} = TYPE_INFO->{$t}->{cpptype};
      $member->{noNamespaceFlag} = 1;

      if ('hexBinary' eq $t or 'base64Binary' eq $t) {
          $member->{isVectorFlag} = 1;
      }
    } elsif (defined $elementTypes->{$t}) {
      my $elemType = $elementTypes->{$t};
      adjustElementType($package, $elemType, %$elementTypes, %$opts);

      my $cpptype;

      if (defined $elemType->{cpptype}) {
        $cpptype = $elemType->{cpptype};
      } else {
        $cpptype = MixedMixed($elemType->{name});
      }

      if ($elemType->{trait} eq 'enumeration') {
        $cpptype = $cpptype . '::' . NESTED_ENUM_TYPE;
      }

      $cpptype =~ s/[^\$]+\$\$//;
      {
        my (undef, $type) = $cpptype =~ m/(\w+::)?(\w+)/;

        $cpptype = MixedMixed($cpptype)
            unless defined TYPE_INFO->{$type}
                or 'enumeration' eq $elemType->{trait}
                or 'list'        eq $elemType->{trait};

        if ($elemType->{external} and !$elemType->{noNamespaceFlag}) {
          $member->{cpptype} = $elemType->{package} . '::' . $cpptype;
        } else {
          $member->{cpptype} = $cpptype;
        }
      }
    } else {
      $t =~ s/[^\$]+\$\$//;
      $member->{cpptype} = MixedMixed($t);
    }
  }
  else {
    if (defined $member->{cpptype} and $member->{cpptype} =~ m/^([^:]+)::/) {
      $member->{explicitPackage} = $1;
    }
  }
}

sub adjustListType($$\%\%)
{
  my ($package, $member, $elementTypes, $opts) = @_;

  if (!defined $member->{cpptype}) {

    my (undef, $t) = $member->{list}->{itemType} =~ m/^(\w+:)?(.+)/;

    $member->{noNamespaceFlag} = 0;

    if (defined TYPE_INFO->{$t}) {
      $member->{cpptype} = TYPE_INFO->{$t}->{cpptype};
      $member->{noNamespaceFlag} = 1;
    } elsif (defined $elementTypes->{$t}) {
      my $elemType = $elementTypes->{$t};
      adjustElementType($package, $elemType, %$elementTypes, %$opts);

      my $cpptype;

      if (defined $elemType->{cpptype}) {
        $cpptype = $elemType->{cpptype};
      } else {
        $cpptype = MixedMixed($elemType->{name});
      }

      if ($elemType->{trait} eq 'enumeration') {
        $cpptype = $cpptype . '::' . NESTED_ENUM_TYPE;
      }

      $cpptype =~ s/[^\$]+\$\$//;
      {
        my (undef, $type) = $cpptype =~ m/(\w+::)?(\w+)/;

        $cpptype = MixedMixed($cpptype)
            unless defined TYPE_INFO->{$type}
                or 'enumeration' eq $elemType->{trait};

        if ($elemType->{external}) {
          $member->{cpptype} = $elemType->{package} . '::' . $cpptype;
        } else {
          $member->{cpptype} = $cpptype;
        }
      }
    } else {
      $t =~ s/[^\$]+\$\$//;
      $member->{cpptype} = MixedMixed($t);
    }

    if (!defined TYPE_INFO->{$t} or TYPE_INFO->{$t}->{noListSupport}) {
        die "** ERR: Unsupported list type '$t' for simpleType "
          . "'$$member{name}'\n";
    }
  }
  else {
    if (defined $member->{cpptype} and $member->{cpptype} =~ m/^([^:]+)::/) {
      $member->{explicitPackage} = $1;
    }
  }
}

sub enumerationNeedsDefault(\%)
{
    my ($enumeration) = @_;

    return 0 unless defined $enumeration->{restriction}->{base}
                and $enumeration->{restriction}->{base} =~ m/(\w+:)?string/;

    foreach (@{$enumeration->{restriction}->{enumeration}}) {
        if (0 == $_->{id}) {
            return 0;
        }
    }
    return 1;
}

sub adjustMember($$$\%\%\%)
{
  my ($package,
      $member,
      $currentMemberId,
      $element,
      $elementTypes,
      $opts) = @_;

  adjustAnnotation ($member);

  my $nestedEnumType = NESTED_ENUM_TYPE;

  if (!defined $member->{name}) {
    if (!defined $member->{ref}) {
      die "** ERR: Unnamed complex type element\n";
    }

    my (undef, $ref) = $member->{ref} =~ m/^(\w+:)?(.+)/;
    $member->{name} = $ref;
    $member->{type} = 'element$$' . $opts->{msgPrefix} . MixedMixed($ref);
  }

  if (!defined $member->{origName}) {
      $member->{origName} = $member->{name};
  }

  if (!defined $member->{memberName}) {
    # TBD: Can we apply 'mixedMixed' at the end? Regression test for this!
    my $name = mixedMixed($member->{name});
    my $isKeyword = exists $cpp_keywords{$name};
    if ($isKeyword) {
      $member->{memberName} = $name . 'Value';
    }
    else {
      $member->{memberName} = $member->{name};
    }
  }

  if (!defined $member->{type} && defined $member->{ref}) {
    my $ref = $member->{ref};
    $ref =~ s/^\w+\://; # strip namespace prefix (e.g., "xs:")
    $member->{type} = 'element$$' . $ref;
  }

  if (!defined $member->{type}) {
    if (exists $member->{simpleType}
    and exists $member->{simpleType}->[0]->{list}->{itemType})
  {
      my $t = $member->{simpleType}->[0]->{list}->{itemType};
      $t =~ s/^\w+\://; # strip namespace prefix (e.g., "xs:")

      if (!defined TYPE_INFO->{$t}
       or (defined TYPE_INFO->{$t}->{noListSupport}
      and  TYPE_INFO->{$t}->{noListSupport}))
      {
          die "** ERR: Unsupported list type '$t' for member '$$member{name}' "
            . "of type '$$element{name}'\n";
      }

      if (!defined $member->{formattingMode}) {
        $member->{formattingMode} = 'is_list';
      }

      if (!defined $member->{cpptype}) {
        $member->{cpptype} = 'bsl::vector'
                           . encloseTemplateArgs(TYPE_INFO->{$t}->{cpptype});
        $member->{allocatesMemory} = 1;
        $member->{isVectorFlag} = 1;
        $member->{noNamespaceFlag} = 1;
        $member->{requiresDestruction} = 1;
      }
    }
    else {
      die "** ERR: List type '$$member{name}' must specify 'itemType'\n";
    }
  }
  elsif (exists $member->{typeref}->{list}) {
      $member->{formattingMode} = 'is_list';
  }
  else {
    my (undef, $t) = $member->{type} =~ m/^(\w+:)?(.+)/;

    if (!defined $member->{formattingMode}) {
      if (defined TYPE_INFO->{$t}) {
        $member->{formattingMode} = TYPE_INFO->{$t}->{formattingMode};
      }
    }
  }

  adjustCpptype($package, $member, %$elementTypes, %$opts);

  if (!defined $member->{cpptype}) {
    $member->{cpptype} = 'PleaseSpecifyType';
  }

  if ($opts->{noEmptySimpleTypes}
  and exists $member->{typeref}->{isEmptySimpleType})
  {
      my $cpptype = TYPE_INFO->{$member->{typeref}->{cpptype}}->{cpptype};
      $member->{cpptype} = $cpptype;
  }

  if (!defined $member->{requiresDestruction}) {

    (my $adjustedCppType = $member->{cpptype}) =~ s/([^<]+).*/$1/;
    if (defined CPPTYPE_ALLOCATES_MEMORY->{$adjustedCppType}
    and !CPPTYPE_ALLOCATES_MEMORY->{$adjustedCppType})
    {
      $member->{requiresDestruction} = 0;
    }
    else {
      $member->{requiresDestruction} = 1;
    }
  }

  if (!defined $member->{formattingMode}) {
    $member->{formattingMode} = 'default';
  }

  if (!defined $member->{minOccurs}) {
    $member->{minOccurs} = '1';
  }

  if (!defined $member->{maxOccurs}) {
    $member->{maxOccurs} = '1';
  }

  if (!defined $member->{defaultCppVal}) {
    if (defined $member->{default}) {
      if ($member->{cpptype} =~ m/string/
       or %{$member->{typeref}}  # autovivified by 'exists' so check "size"
      and $member->{typeref}->{trait} eq 'customizedtype'
      and $member->{typeref}->{typeCategory} eq 'simpleType'
      and $member->{typeref}->{restriction}->{base} =~ /string/)
      {
        my $defaultStr = $member->{default};
        $defaultStr =~ s/"/\\"/g;
        $defaultStr = '"' . $defaultStr . '"';
        $member->{defaultCppVal} = $defaultStr;
      }
      elsif (my ($enumWrapper) =
                ($member->{cpptype} =~ /^((\w+)::)+$nestedEnumType$/))
      {
        my $packageScope = ($package eq $member->{typeref}->{package})
                         ? ''
                         : $member->{typeref}->{package} . '::';
        my $baseName = $member->{default};
        $member->{defaultCppVal} = $packageScope
                                 . $enumWrapper
                                 . adjustEnumeratorName(\$baseName);
      }
      else {
        $member->{defaultCppVal} = $member->{default} || "0";
      }
    }
    elsif (($member->{maxOccurs} eq '1'
        and $member->{minOccurs} != 0     # REMOVE FOR DRQS 12612139
        and exists $member->{typeref}->{restriction}->{enumeration}
        and enumerationNeedsDefault(%{$member->{typeref}}))
       and my ($enumWrapper) =
                ($member->{cpptype} =~ /^(\w+)::$nestedEnumType$/))
    {
      my $defaultEnumerator =
                         $member->{typeref}->{restriction}->{enumeration}->[0];

      warn "* WARN: No default value defined for element '"
         . $member->{name} . "' of enumerated\n"
         . "        type '"
         . $member->{typeref}->{name} . "', assuming default value of '"
         . $defaultEnumerator->{value} . "'\n"
         unless $opts->{noWarnings};

      $member->{defaultCppVal} = $enumWrapper
                               . '::'
                               . $defaultEnumerator->{name};
    }
  }

  if (!defined $member->{isNullable}) {
    # Note: a default value of '0' is interpreted as 'false'
    my $dcvIndicator = defined $member->{defaultCppVal}
                             ? $member->{defaultCppVal} || 'zero'
                             : 0;
    if (!$dcvIndicator
    and ($member->{isNillable}# or $member->{minOccurs} == 0))
     or  ($member->{minOccurs} == 0 and $member->{maxOccurs} eq '1')))
    {
      $member->{isNullable} = 1;
    } else {
      $member->{isNullable} = 0;
    }

    warn "* WARN: Elements of a choice may neither be nillable "
       . "nor have minOccurs = 0:\n"
       . "        type = $$element{name}, element = $$member{name}\n"
        if   defined $element->{choice}
        and !$opts->{noWarnings}
        and ($member->{isNullable}
         or  ($member->{minOccurs} == 0 and $member->{maxOccurs} ne '1'));
  }

  if ($member->{minOccurs} != 0 && $member->{minOccurs} != 1) {
    die "** ERR: Unsupported minOccurs value: $member->{minOccurs}\n";
  }

  if ($member->{isNullable}) {
    if ($member->{typeref}->{isAllocated}
     && $element->{component} eq $member->{typeref}->{component}
     && $element->{level} <= $member->{typeref}->{level})
    {
      $member->{allocatedType} = undef;
      $member->{cpptype} = 'bdeut_NullableAllocatedValue'
                         . encloseTemplateArgs($member->{cpptype});
      $member->{noNamespaceFlag} = 1;
    } elsif ($member->{isNullable}) {
      $member->{cpptype} = 'bdeut_NullableValue'
                         . encloseTemplateArgs($member->{cpptype});
      $member->{noNamespaceFlag} = 1;
    }
  }

  if (exists $member->{typeref}->{trait}
  and $member->{typeref}->{trait} eq 'list')
  {
    $member->{isListFlag} = 1
  }

  if ($member->{maxOccurs} eq 'unbounded'
   or $member->{maxOccurs} > 1
   or $member->{isListFlag})
  {
    my $templateArg = $member->{cpptype};
    if ($package ne $opts->{msgLibrary}
    and !exists CPPTYPE_NATIVE->{$templateArg}
    and !$member->{isListFlag}
    and exists $member->{typeref}
    and (!$member->{typeref}->{external} or $opts->{recurse}))
    {
      $templateArg = $opts->{msgLibrary} . '::' . $templateArg;
    }

    $member->{cpptype} = 'bsl::vector' . encloseTemplateArgs($templateArg);
    $member->{allocatesMemory} = 1;
    $member->{isVectorFlag} = 1;
    $member->{noNamespaceFlag} = 1;
    $member->{requiresDestruction} = 1;
  } elsif ($member->{maxOccurs} !=  1) {
    die "** ERR: Unsupported maxOccurs value: $member->{maxOccurs}\n";
  }

  if ($member->{typeref}->{isAllocated}
   && !$member->{isVectorFlag}
   && !$member->{isNullable}
   && $element->{component} eq $member->{typeref}->{component})
  {
    $member->{allocatedType} = $member->{cpptype};
  }

  my $nested_enum_type = NESTED_ENUM_TYPE;
  if (!defined $member->{cppargtype}) {

    if (defined CPPTYPE_PASSBYVAL->{$member->{cpptype}}
     && CPPTYPE_PASSBYVAL->{$member->{cpptype}}) {
      $member->{cppargtype} = $member->{cpptype};
    } elsif (my ($wrapperType) =
           ($member->{cpptype} =~ /^(.*)\:\:$nested_enum_type$/)) {
      $member->{cppargtype} = $member->{cpptype};
    } else {
      if ($member->{allocatedType}) {
        $member->{cppargtype} = 'const ' . $member->{allocatedType} . '&';
      } else {
        $member->{cppargtype} = 'const ' . $member->{cpptype} . '&';
      }
    }
  }

  if (!defined $member->{id}) {
    $member->{id} = ${ $currentMemberId };
  } else {
    ${ $currentMemberId } = $member->{id}
  }

  if (!defined $member->{bdexVersion}) {
    $member->{bdexVersion} = 1;
  }

  if (!defined $member->{allowsDirectManipulation}) {
    $member->{allowsDirectManipulation} = 1;
  }

  if (defined $member->{defineAssociatedType}) {
    $member->{defineAssociatedType} = 1;
  }

  # Add type reference to 'member'.
  if (! exists $member->{typeref}) {
    if (defined $member->{type}
     && !exists $cpp_keywords{$member->{type}})
    {
      $member->{typeref} = $elementTypes->{$2}
          if $member->{type} =~ /(\w+:)?([^:].+)/;
    }
  }

  my $xsdType = exists $member->{typeref}->{restriction}->{base}
              ? $member->{typeref}->{restriction}->{base}
              : $member->{type};

  $xsdType =~ s/^\w+\://;

  my $memberType = $member->{type};
  $memberType =~ s/^\w+\://;

  $member->{isBuiltinType}          = isBuiltinType($memberType);
  $member->{aggregateValueAccessor} = AGGREGATE_VALUE_ACCESSOR->{$xsdType};
}

#----

# Generated types never contain pointers to member functions.
use constant MAXIMUM_ALIGNMENT => 8;

use constant CPPTYPE_ALIGNMENT => {
    'bool'                         => '1'
  , 'int'                          => '4'
  , 'char'                         => '1'
  , 'short'                        => '2'
  , 'bdes_PlatformUtil::Int64'     => '8'
  , 'unsigned int'                 => '4'
  , 'unsigned char'                => '1'
  , 'unsigned short'               => '2'
  , 'bdes_PlatformUtil::Uint64'    => '8'
  , 'float'                        => '4'
  , 'double'                       => '8'
  , 'bdet_Date'                    => '8'
  , 'bdet_DateTz'                  => '8'
  , 'bdet_Time'                    => '8'
  , 'bdet_TimeTz'                  => '8'
  , 'bdet_Datetime'                => '8'
  , 'bdet_DatetimeTz'              => '8'
  , 'bsl::string'                  => '8'
  , 'bsl::vector'                  => '8'
  , 'bdeut_NullableValue'          => '0'  # Calculated from template parameter
  , 'bdeut_NullableAllocatedValue' => '8'
  , 'bdeut_BigEndianInt16'         => '2'
  , 'bdeut_BigEndianUint16'        => '2'
  , 'bdeut_BigEndianInt32'         => '4'
  , 'bdeut_BigEndianUint32'        => '4'
  , 'bdeut_BigEndianInt64'         => '8'
  , 'bdeut_BigEndianUint64'        => '8'
};

sub cppTypeAlignment($) {
  my ($cpptype) = @_;

  if (defined CPPTYPE_ALIGNMENT->{$cpptype}) {
      return  CPPTYPE_ALIGNMENT->{$cpptype};
  }

  return MAXIMUM_ALIGNMENT;
}

#----

sub adjustComplexType($$\%\%)
{
  my ($package, $complex, $elementTypes, $opts) = @_;

  my $trait = $complex->{trait};

  adjustAnnotation($complex);
# adjustAppInfo($complex);

  if (!defined $complex->{package}) {
    $complex->{package} = $package;
  }

  if (!defined $complex->{cpptype}) {
    $complex->{cpptype} = MixedMixed($complex->{name});
  }

  if (!defined $complex->{bdexVersion}) {
    $complex->{bdexVersion} = 1;
  }

  if (!defined $complex->{omitIntrospection}) {
    $complex->{omitIntrospection} = $opts->{omitIntrospection} || 0;
  }

  if (!defined $complex->{noAggregateConversion}) {
    $complex->{noAggregateConversion} = $opts->{noAggregateConversion} || 0;
  }

  if (!defined $complex->{parameterizedConstructor}) {
    $complex->{parameterizedConstructor} = $opts->{parameterizedConstructors}
                                        || 0;
  }

  my $currentMemberId = 0;

  if (ref ($complex->{$trait}) ne 'ARRAY') {
    die "** ERR: Unsupported or ill-formed element type "
      . "\"$complex->{name}\"\n";
  }

  my $maxCpptypeLength = 0;
  my $hasAllocatedMemberFlag = 0;
  foreach my $member (@{$complex->{$trait}}) {
    adjustMember($package, $member, \$currentMemberId,
                 %$complex, %$elementTypes, %$opts);
    ++$currentMemberId;
    if ($member->{allocatedType} && 'choice' eq $complex->{trait}) {
        $hasAllocatedMemberFlag = 1;
        next;
    }
    if ($maxCpptypeLength < length $member->{cpptype}) {
      $maxCpptypeLength = length $member->{cpptype};
    }
    if ($member->{allocatedType}) {
      $complex->{allocatesMemory} = 1;
      $complex->{holdsAllocator}  = 1;
    }
    if ($member->{typeref}->{external}) {
      $member->{noNamespaceFlag} = 1;
    }
  }
  $complex->{maxCpptypeLength} = $maxCpptypeLength + $hasAllocatedMemberFlag;

  if (!defined $complex->{include}) {

    my @includeFiles;

    foreach my $member (@{$complex->{$trait}}) {
      if (defined $member->{cppheader}) {
        push @includeFiles, $member->{cppheader};
      } else {
        push @includeFiles, deduceIncludeFile($member->{cpptype}, $package);

        if (exists $member->{typeref}->{component}
        and exists $member->{typeref}->{package}
        and $package eq $member->{typeref}->{package}
        and !defined $member->{explicitPackage})
        {
          my $component = $member->{typeref}->{component};
          pop @includeFiles;
          push @includeFiles, $package . '_' . $component . '.h';
        }
      }
    }

    # remove duplicates
    my %seenInclude;
    @includeFiles=grep !$seenInclude{$_}++,@includeFiles;

    $complex->{include} = [] unless defined $complex->{include};
    configureIncludes($complex, @includeFiles);
  }
}

#----

sub adjustEnumeratorName
{
  my ($name) = @_;

  if ($$name =~ m/^[0-9]+/) {
    $$name = "VALUE_" . $$name;
  }

  my $hash = SYMBOL_TRANSLATION;
  my $regex = ' !"#$%&\'()*+,-./:;<=>?@[\\]^`{|}~';
  $$name =~ s/([\Q$regex\E])/_$hash->{$1}_/go;

  $$name =~ s/^_+//g;

  $$name = UPPER_UPPER($$name);
}

sub adjustEnumerator($$$$)
{
  my ($enumeration, $enumerator, $currentEnumeratorId, $elementTypes) = @_;

  adjustAnnotation ($enumerator);

  if (!defined $enumerator->{id}) {
    $enumerator->{id} = $$currentEnumeratorId;
  } else {
    $$currentEnumeratorId = $enumerator->{id}
  }

  if ((!defined $enumerator->{value}) || ($enumerator->{value} eq "")) {
    die "** ERR: Provide a value for enumerator of type '"
      . $enumeration->{name} . "'";
  }

  if (!defined $enumerator->{name}) {
    $enumerator->{name} = $enumerator->{value};
  }

  adjustEnumeratorName(\$enumerator->{name});
}

#----

sub adjustEnumeration($$\%\%)
{
  my ($package, $enum, $elementTypes, $opts) = @_;

  adjustAnnotation($enum);
# adjustAppInfo($enum);

  my $trait = $enum->{trait};

  if (!defined $enum->{package}) {
    $enum->{package} = $package;
  }

  if (!defined $enum->{cpptype}) {
    $enum->{cpptype} = MixedMixed($enum->{name});
  }

  $enum->{cpptypeAlignment} = 4;

  if (!defined $enum->{bdexVersion}) {
    $enum->{bdexVersion} = 1;
  }

  if (!defined $enum->{omitIntrospection}) {
    $enum->{omitIntrospection} = $opts->{omitIntrospection} || 0;
  }

  if (!defined $enum->{noAggregateConversion}) {
    $enum->{noAggregateConversion} = $opts->{noAggregateConversion} || 0;
  }

  if (!defined $enum->{allocatesMemory}) {
    $enum->{allocatesMemory} = 0;
  }

  my $numValues   = @{$enum->{restriction}->{enumeration}};
  my $declaredIds = grep /1/, map { exists $_->{id} }
                                  @{$enum->{restriction}->{enumeration}};

  if (!$enum->{preserveEnumOrder} && $numValues != $declaredIds) {
    warn "* WARN: Enumerated values may be re-ordered in the generated code\n"
       . "  HINT: Set bdem:preserveEnumOrder='1' for type $$enum{name}\n"
       . "        defined in $$enum{schemaFile}\n"
       unless $opts->{noWarnings};

    my @sortedEnumerators = sort { $a->{value} cmp $b->{value} }
                                 @{ $enum->{restriction}->{enumeration} };
    $enum->{restriction}->{enumeration} = \@sortedEnumerators;
  }

  my $currentEnumeratorId = 0;
  foreach my $enumerator (@{ $enum->{restriction}->{enumeration} }) {
    adjustEnumerator($enum, $enumerator, \$currentEnumeratorId, $elementTypes);
    ++$currentEnumeratorId;
  }
}

#----

sub parseDateTzString($)
{
  my ($dateTzString) = @_;
  my ($year, $month, $day, $tzSign, $tzHours, $tzMinutes);

  # The entire data portion is always expected.
  if ($dateTzString =~ m/^(\d+)-(\d+)-(\d+)(([+-])(\d+)(:(\d+))?)?$/) {
    $year      = $1;
    $month     = $2;
    $day       = $3;
    $tzSign    = (!defined $5) ? 1 : ($5 eq "-") ? -1 : +1;
    $tzHours   = (!defined $6) ? 0 : $6;
    $tzMinutes = (!defined $8) ? 0 : $8;
  }

  return ($year, $month, $day, $tzSign * (60 * $tzHours + $tzMinutes));
}

sub adjustCustomizedTypeEnumerator($$$$)
{
  my ($enumeration, $enumeratorIndex, $enumerator, $base) = @_;

  adjustAnnotation($enumerator);

  if (!defined $enumerator->{value}) {
    die "** ERR: enumeration has no value!\n";
  }

  my $baseXsdType = $base;
  $baseXsdType =~ s/^\w+\://; # strip namespace prefix (e.g., "xs:")

  if (!defined $enumerator->{cppValue}) {
    if ($baseXsdType eq "float") {
      if ("INF" eq $enumerator->{value}) {
        $enumerator->{cppValue} = "std::numeric_limits<float>::infinity()";
      }
      elsif ("-INF" eq $enumerator->{value}) {
        $enumerator->{cppValue} = "-std::numeric_limits<float>::infinity()";
      }
      elsif ("NaN" eq $enumerator->{value}) {
        $enumerator->{cppValue} = "std::numeric_limits<float>::quiet_NaN()";
      }
      else {
        $enumerator->{cppValue} = $enumerator->{value} . "f";
      }
    }
    elsif ($baseXsdType eq "date") {

      if (!defined $enumeration->{localConstants}) {
        $enumeration->{localConstants} = [];
      }

      my $localConstantName  = UPPER_UPPER($enumeration->{name})
                             . "_ENUMERATOR_"
                            . $enumeratorIndex;

      my ($y, $m, $d, $tz) = parseDateTzString($enumerator->{value});

      my $localConstantValue = "bdet_DateTz(bdet_Date($y, $m, $d), $tz)";

      push @{$enumeration->{localConstants}},
           "const bdet_DateTz $localConstantName = $localConstantValue;";

      $enumerator->{cppValue} = $localConstantName;
    }
    else {
      $enumerator->{cppValue} = $enumerator->{value};
    }
  }
}

#----

sub resolvePredefinedEntities($)
{
  my ($text) = @_;

  my $result = $text;

  my $hash = XML_ENTITY_MAP;
  while (my ($key, $value) = each %{$hash}) {
    $result =~ s/$key/$value/g;
  }

  return $result;
}

sub adjustCustomizedType($$\%\%)
{
  my ($package, $customizedtype, $elementTypes, $opts) = @_;

  adjustAnnotation($customizedtype);
# adjustAppInfo($customizedtype);

  my $trait = $customizedtype->{trait};

  if (!defined $customizedtype->{package}) {
    $customizedtype->{package} = $package;
  }

  if (!defined $customizedtype->{baseType}) {
    my $t = $customizedtype->{restriction}->{base};
    $t =~ s/^\w+\://; # strip namespace prefix (e.g., "xs:")

    if (defined TYPE_INFO->{$t}) {
        $customizedtype->{baseType} = TYPE_INFO->{$t}->{cpptype};
    } else {
      die "** ERR: Invalid base type '$t' for '$customizedtype->{name}'\n";
    }
  }

  if (!defined $customizedtype->{cpptype}) {
    if ($opts->{noEmptySimpleTypes}) {
    if (1 < scalar keys %{$customizedtype->{restriction}}) {
      $customizedtype->{cpptype} = MixedMixed($customizedtype->{name});
    } else {
#     $customizedtype->{cpptype} = $customizedtype->{baseType};
      my $cpptype = $customizedtype->{restriction}->{base};
      $cpptype =~ s/^\w+\://;
      $customizedtype->{cpptype} = $cpptype;
      $customizedtype->{noNamespaceFlag} = 1;
    }
    } else {
      $customizedtype->{cpptype} = MixedMixed($customizedtype->{name});
    }
  }

  if (!defined $customizedtype->{baseArgType}) {
    $customizedtype->{baseArgType} = 'const '
                                   . $customizedtype->{baseType} . '&';
  }

  if (!defined $customizedtype->{fromFunction}) {
    my $t = $customizedtype->{restriction}->{base};
    my $bt = $customizedtype->{baseType};

    if (defined CUSTOMIZEDTYPE_CONVERT_FUNCTIONS->{$bt}) {
      $customizedtype->{fromFunction} =
        CUSTOMIZEDTYPE_CONVERT_FUNCTIONS->{$bt}->{from};
    } else {
      die "** ERR: Unsupported base type '$t' for '$customizedtype->{name}'. "
        . "You must specify 'fromFunction'.\n";
    }
  }

  if (!defined $customizedtype->{toFunction}) {
    my $t = $customizedtype->{restriction}->{base};
    my $bt = $customizedtype->{baseType};

    if (defined CUSTOMIZEDTYPE_CONVERT_FUNCTIONS->{$bt}) {
      $customizedtype->{toFunction} =
        CUSTOMIZEDTYPE_CONVERT_FUNCTIONS->{$bt}->{to};
    } else {
      die "** ERR: Unsupported base type '$t' for '$customizedtype->{name}'. "
        . "You must specify 'toFunction'.\n";
    }
  }

  if (!defined $customizedtype->{bdexVersion}) {
    $customizedtype->{bdexVersion} = 1;
  }

  if (!defined $customizedtype->{omitIntrospection}) {
    $customizedtype->{omitIntrospection} = $opts->{omitIntrospection} || 0;
  }

  if (!defined $customizedtype->{noAggregateConversion}) {
    $customizedtype->{noAggregateConversion} = $opts->{noAggregateConversion}
                                            || 0;
  }

  if (!defined $customizedtype->{allocatesMemory}) {

    my $bt = $customizedtype->{baseType};

    if (defined CPPTYPE_ALLOCATES_MEMORY->{$bt} &&
        CPPTYPE_ALLOCATES_MEMORY->{$bt}) {
      $customizedtype->{allocatesMemory} = 1;
    }
    else {
      $customizedtype->{allocatesMemory} = 0;
    }
  }

  if (!defined $customizedtype->{allowsDirectManipulation}) {
    $customizedtype->{allowsDirectManipulation} = 1;
  }

  if (defined $customizedtype->{defineAssociatedType}) {
    $customizedtype->{defineAssociatedType} = 1;
  }

  if (defined $customizedtype->{restriction}->{enumeration}
   && scalar(@{ $customizedtype->{restriction}->{enumeration} }) != 0) {

    my $enumeratorIndex = 0;
    foreach my $enumerator
                    (@{ $customizedtype->{restriction}->{enumeration} }) {
      adjustCustomizedTypeEnumerator($customizedtype,
                                     $enumeratorIndex++,
                                     $enumerator,
                                     $customizedtype->{restriction}->{base});
    }
  }

  if (defined $customizedtype->{restriction}->{maxLength}
   && !defined $customizedtype->{restriction}->{maxLength}->{value}) {
      die "** ERR: Max length has no value!\n";
  }

  if (defined $customizedtype->{restriction}->{mimLength}
   && !defined $customizedtype->{restriction}->{mimLength}->{value}) {
      die "** ERR: Min length has no value!\n";
  }

  if (defined $customizedtype->{restriction}->{length}
   && !defined $customizedtype->{restriction}->{length}->{value}) {
      die "** ERR: Length has no value!\n";
  }

  if (defined $customizedtype->{restriction}->{minInclusive}
   && !defined $customizedtype->{restriction}->{minInclusive}->{value}) {
      die "** ERR: Min inclusive has no value!\n";
  }

  if (defined $customizedtype->{restriction}->{maxInclusive}
   && !defined $customizedtype->{restriction}->{maxInclusive}->{value}) {
      die "** ERR: Max inclusive has no value!\n";
  }

  if (defined $customizedtype->{restriction}->{minExclusive}
   && !defined $customizedtype->{restriction}->{minExclusive}->{value}) {
      die "** ERR: Min exclusive has no value!\n";
  }

  if (defined $customizedtype->{restriction}->{maxExclusive}
   && !defined $customizedtype->{restriction}->{maxExclusive}->{value}) {
      die "** ERR: Max exclusive has no value!\n";
  }

  if (!defined $customizedtype->{include}) {

    my @includeFiles;

    push @includeFiles, deduceIncludeFile($customizedtype->{baseType},
                                          $package);
    if (defined $customizedtype->{restriction}->{pattern}) {
      foreach (@{$customizedtype->{restriction}->{pattern}}) {

        $_->{value} = resolvePredefinedEntities($_->{value});
        $_->{value} =~ s/\\([^\\])/\\\\$1/g;
      }
      push @includeFiles, 'bdepcre_regex.h';
      push @includeFiles, 'sstream';
    }

    if (($customizedtype->{baseType} eq "float") ||
        ($customizedtype->{baseType} eq "double"))
    {
      push @includeFiles, "limits";
    }

    configureIncludes($customizedtype, @includeFiles);
  }

  my $xsdType = $customizedtype->{restriction}->{base};
  $xsdType =~ s/^\w+\://;

  $customizedtype->{isBuiltinType}          = 0;
  $customizedtype->{aggregateValueAccessor} =
                                          AGGREGATE_VALUE_ACCESSOR->{$xsdType};

  if (!defined $customizedtype->{aggregateValueAccessor}) {
    die "No aggregate value accessor for type '" . $xsdType . "'!\n";
  }

  $customizedtype->{cpptypeAlignment} =
                       cppTypeAlignment($customizedtype->{baseType});
}

#----

sub adjustAlias($$\%\%)
{
  my ($package, $alias, $elementTypes, $opts) = @_;

  if (!defined $alias->{package}) {
    $alias->{package} = $package;
  }

  adjustCpptype($package, $alias, %$elementTypes, %$opts);
  adjustAnnotation($alias);
}

#----

sub deduceAllocatesMemory(\%\%)
{
  my ($opts, $elementTypes) = @_;

  my @edges;

  foreach my $elementType (values %$elementTypes) {
    my $members;

    if ($elementType->{typeCategory} eq 'complexType') {
      $members = $elementType->{$elementType->{trait}};
    }
    elsif ($elementType->{typeCategory} eq 'alias') {
      $members = [ $elementType ];
    }
    else {
      next;
    }

    foreach my $member (@$members) {

      if (!defined $elementType->{allocatesMemory}) {
        # If member allocates so does container.
        push @edges, [$member, $elementType];
      }

      if (!defined $member->{allocatesMemory}) {
        my $cpptype = $member->{cpptype};
        if ($cpptype =~ m/^\s*bdeut_Nullable(Allocated)?Value\s*
                          <\s*(.*\S)\s*>\s*$/x)
        {
          $cpptype = $2;
        }

        (my $adjustedCppType = $cpptype) =~ s/([^<]+).*/$1/;
        if (defined CPPTYPE_ALLOCATES_MEMORY->{$adjustedCppType}) {
          if (CPPTYPE_ALLOCATES_MEMORY->{$adjustedCppType}) {
            $member->{allocatesMemory} = 1;
          } else {
            $member->{allocatesMemory} = 0;
          }
        } else {
          if (defined $member->{maxOccurs}
          and $member->{maxOccurs} eq 'unbounded')
          {
            $member->{allocatesMemory} = 1;
          } elsif (defined $member->{type}) {
            my $t = $member->{type};
            $t =~ s/^\w+://;     # strip the namespace alias
#           $t = $opts->{msgPrefix} . MixedMixed($t);
            if (defined $elementTypes->{$t}) {
              push @edges, [$elementTypes->{$t}, $member];
            } else {
              # The type is not defined in the base schema nor in any of the
              # included schemas.
            }
          }
        }
      }
    }
  }

  while (1) {
    my $deductionCount = 0;
    my $index = 0;

    while ($index < scalar(@edges)) {
      if (defined $edges[$index]->[1]->{allocatesMemory}) {
        splice @edges, $index, 1;
      } else {
        if (defined $edges[$index]->[0]->{allocatesMemory}) {
          if ($edges[$index]->[0]->{allocatesMemory}) {
            $edges[$index]->[1]->{allocatesMemory} = 1;
            ++$deductionCount;
            splice @edges, $index, 1;
          } else {
            ++$index;
          }
        } else {
          ++$index;
        }
      }
    }

    last if 0 == $deductionCount;
  }

  foreach my $edge (@edges) {
    if (!defined $edge->[0]->{allocatesMemory}) {
      $edge->[0]->{allocatesMemory} = 0;
    }
  }
}

#----

sub adjustElementTypeFieldOrder($\%);

sub adjustComplexTypeFieldOrder($\%) {

  my ($complex, $opts) = @_;

  return if (!defined $complex->{sequence});

  my $maxMemberAlignment = 0;
  foreach my $member (@{$complex->{sequence}}) {
    my $memberAlignment;
    if ((defined $member->{typeref}) &&
        (defined $member->{typeref}->{cpptypeAlignment}))
    {
      $memberAlignment = $member->{typeref}->{cpptypeAlignment};
    }
    elsif ($member->{cpptype} =~ m/bdeut_NullableValue<(.+)>/) {
      $memberAlignment = cppTypeAlignment($1);
    }
    else {
      $memberAlignment = cppTypeAlignment($member->{cpptype});
    }

    $member->{cpptypeAlignment} = $memberAlignment;

    if ($memberAlignment > $maxMemberAlignment) {
      $maxMemberAlignment = $memberAlignment;
    }
  }

  if ((!defined $complex->{preserveElementOrder}) ||
              (($complex->{preserveElementOrder} ne "1") &&
               ($complex->{preserveElementOrder} ne "true")))
  {
    my @sortedMembers = sort {
        ($b->{cpptypeAlignment} <=> $a->{cpptypeAlignment}) ||
        ($b->{cpptype}          cmp $a->{cpptype})
    } @{$complex->{sequence}};
    $complex->{sortedMembers} = \@sortedMembers;
  }
  else {
    $complex->{sortedMembers} = $complex->{sequence};
  }

  $complex->{cpptypeAlignment} = $maxMemberAlignment;
}

#----

sub adjustElementTypeFieldOrder($\%)
{
  my ($elementType, $opts) = @_;

  if (defined $elementType->{elementTypeFieldOrderAdjustmentCompleted}) {
    return;
  }

  $elementType->{elementTypeFieldOrderAdjustmentCompleted} = 0;

  if (($elementType->{typeCategory} eq 'complexType') &&
      (defined $elementType->{sequence}))
  {
    adjustComplexTypeFieldOrder($elementType, %$opts);
  }

  $elementType->{elementTypeFieldOrderAdjustmentCompleted} = 1;
}

#----

sub adjustElementType($$\%\%)
{

  my ($package, $elementType, $elementTypes, $opts) = @_;

  if (defined $elementType->{elementTypeAdjustmentCompleted}) {
    return;
  }

  $elementType->{elementTypeAdjustmentCompleted} = 0;

  if ($elementType->{typeCategory} eq 'complexType') {

    if (defined $elementType->{sequence}) {
      $elementType->{trait} = 'sequence';
      adjustComplexType($package, $elementType, %$elementTypes, %$opts);
    } elsif (defined $elementType->{choice}) {
      $elementType->{trait} = 'choice';
      adjustComplexType($package, $elementType, %$elementTypes, %$opts);
    } else {
      $elementType->{trait} = 'unsupported';
    }

  } elsif ($elementType->{typeCategory} eq 'simpleType') {

    if (defined $elementType->{restriction}->{base}) {
      if ($elementType->{restriction}->{base} =~ /^(\w+:)?string/
          && defined $elementType->{restriction}->{enumeration}) {
        $elementType->{trait} = 'enumeration';
        adjustEnumeration($package, $elementType, %$elementTypes, %$opts);
      } else {
        $elementType->{trait} = 'customizedtype';
        adjustCustomizedType($package, $elementType, %$elementTypes, %$opts);
      }
    } elsif (defined $elementType->{list}) {
      $elementType->{trait} = 'list';
      adjustListType($package, $elementType, %$elementTypes, %$opts);
    } else {
      $elementType->{trait} = 'unsupported';
    }
  } elsif ($elementType->{typeCategory} eq 'alias') {
    $elementType->{trait} = 'alias';
    adjustAlias($package, $elementType, %$elementTypes, %$opts);
  }

  $elementType->{elementTypeAdjustmentCompleted} = 1;
}

#------------------------------------------------------------------------------

sub assignComponentLocations_visit($\@\$\@);

sub assignComponentLocations_visit($\@\$\@)
{
  my ($v, $stack, $rank, $components) = @_;

  $$rank++;

  $v->{component__componentRoot} = $v;
  $v->{component__visitRank} = $$rank;
  $v->{component__inComponent} = 0;

  my $level = 0;

  push(@$stack, $v);

  my $trait = $v->{trait};
  foreach my $member (@{$v->{$trait}}) {
    my $w = $member->{typeref};
    if (defined $w) {
      if (defined $w->{typeCategory} && $w->{typeCategory} eq 'complexType') {
        if (!$w->{component__visitRank}) {
          assignComponentLocations_visit($w, @$stack,
                                         $$rank, @$components);
        }
        if (!$w->{component__inComponent} &&
            ($w->{component__componentRoot}->{component__visitRank} <
             $v->{component__componentRoot}->{component__visitRank}))
          {
            $v->{component__componentRoot} = $w->{component__componentRoot};
          }
      }
      else {
        $w->{component__level} = 1;
      }

      if (defined $w->{component__level} && $w->{component__level} > $level) {
        $level = $w->{component__level}
      }
    }
  }

  $v->{component__level} = $level + 1;

  if ($v->{component__componentRoot} == $v) {
    my @component;
    while(1) {
      my $w = pop(@$stack);
      @component = ($w, @component);
      $w->{component__componentRoot} = $v;
      $w->{component__level} = $v->{component__level};
      $w->{component__inComponent} = 1;
      if ($w == $v) { last };
    }

    push(@$components, \@component);
  }
}

sub hackNullableValue(\%\%)
{
  my ($member, $type) = @_;

  if (!defined $member->{minOccurs}) {
    $member->{minOccurs} = '1';
  }

  if (!defined $member->{maxOccurs}) {
    $member->{maxOccurs} = '1';
  }

  if (!defined $member->{isNullable}) {
    if (!$member->{defaultCppVal}
    and ($member->{isNillable}
      or $member->{minOccurs} == 0 and $member->{maxOccurs} eq '1'))
    {
      $member->{isNullable} = 1;
    } else {
      $member->{isNullable} = 0;
    }
  }
}

sub assignComponentLocations(\@\%\%)
{
  my ($complexTypes, $elementTypes, $opts) = @_;

  my @visitStack = ();
  my $visitRank = 0;
  my @components;
  my $reverseIndex = {};

  foreach my $complexType (@$complexTypes) {
    my $trait = 'undefined';
    $trait = 'sequence' if defined $complexType->{sequence};
    $trait = 'choice'   if defined $complexType->{choice};
    $complexType->{trait} = $trait;

    # Add type reference to each 'member' of 'complexType'
    foreach my $member (@{$complexType->{$trait}}) {
      my (undef, $memberType) = $member->{type} =~ m/^(\w+:)?(.+)/;
      if (defined $memberType
      and !exists TYPE_INFO()->{$memberType})
      {
        my (undef, $baseType) = $memberType =~ m/($opts->{msgPrefix})(.+)/;
        next unless defined $baseType;

        my $typeName = $opts->{msgPrefix} . $baseType;

        $member->{typeref} = $elementTypes->{$memberType};
        push @{$reverseIndex->{$memberType}},
             { member => $member, type => $complexType };

        if ($memberType eq $complexType->{name}) {
          # self-reference
          $member->{typeref} = $complexType;
          $complexType->{isAllocated} = 1;
          hackNullableValue(%$member, %$complexType);
        }
      }
    }
  }

  foreach my $complexType (@$complexTypes) {
    if (!$complexType->{component__visitRank}) {
      assignComponentLocations_visit($complexType, @visitStack,
                                     $visitRank, @components);
    }
  }

  foreach my $component (@components) {
    my $name;
    my $root;
    my @named = grep { $_->{component} } @$component;
    if (@named) {
      $root = $named[0];
      $name = $root->{component};

      foreach (@named) {
        if ($name ne $_->{component}) {
          die "** ERR: Elements '$$root{name}' and '$$_{name}' ",
              "have conflicting component names\n";
        }
      }
    }
    else {
      $root = $component->[0];
      $name = lc MixedMixed($root->{name});
    }
    foreach my $type (@$component) {
      $type->{component} = $type->{component} || $name;
      $type->{isAllocated} = 1 if $#{@$component};# only multi-class components
      $type->{level} = $type->{component__level};
      if ($type->{isAllocated}) {
        foreach (@{$reverseIndex->{$type->{name}}}) {
          hackNullableValue(%{$_->{member}}, %{$_->{type}});
        }
      }
    }
  }
}

#------------------------------------------------------------------------------

sub loadComponents(\%\%\%)
{
  my ($components, $elementTypes, $opts) = @_;

  foreach my $type (values %{$elementTypes}) {
    next if $opts->{noEmptySimpleTypes} and $type->{isEmptySimpleType};

    if (!$type->{component}) {
      $type->{component} = lc $type->{cpptype};
    }

    if (!defined $type->{level}) {
      $type->{level} = 1;
    }

    my $component = $type->{component};
    if (!defined $components->{$component}) {
      $components->{$component} = [];
    }

    push (@{$components->{$component}}, $type);
  }

  foreach my $c (keys %$components) {
    my @levelized = sort { $a->{level} <=> $b->{level} } @{$components->{$c}};
    $components->{$c} = \@levelized;
  }

  return $components;
}

#------------------------------------------------------------------------------

# Assert all the members of the specified 'elementType' with the specified
# collection of all 'elementTypes' do not define the specified 'flagName'.
sub assertMembersDoNotDefineFlag(\%\%$);
sub assertMembersDoNotDefineFlag(\%\%$)
{
  my ($elementTypes, $elementType, $flagName) = @_;

  my $typeName = $elementType->{name};

  return if (defined $elementType->{$flagName . "Checked"});

  $elementType->{$flagName . "Checked"} = 1;

  my $indicator = defined $elementType->{sequence}
                ? "sequence"
                : defined $elementType->{choice}
                ? "choice"
                : undef;

  return if !defined $indicator;

  if (defined $elementType->{$flagName}) {
    if (($elementType->{$flagName} eq "1")
     || ($elementType->{$flagName} eq "true"))
    {
      die "** ERR: Type '$typeName' may not define the flag '$flagName'\n";
    }
  }

  foreach my $element (@{$elementType->{$indicator}}) {
    my $memberTypeName = $element->{type};
    $memberTypeName =~ s/(.+):(.+)/$2/;

    next if (defined TYPE_INFO->{$memberTypeName}); # member type is primitive

    my $memberCppTypeName;
    if ($memberTypeName =~ m/\$\$/) { # type synthesized from wsdl:message
      $memberCppTypeName = $memberTypeName;
    }
    else {
      $memberCppTypeName = MixedMixed($memberTypeName);
    }

    my $memberType = $elementTypes->{$memberCppTypeName};

#   print Dumper $elementTypes, $memberType, $flagName and
    die "** ERR: Undefined type '$memberTypeName'\n"
      unless (defined $memberType);

    assertMembersDoNotDefineFlag(%$elementTypes, %$memberType, $flagName);
  }
}

#------------------------------------------------------------------------------

# Check consistent usage of the specified 'flagName' in the type hierarchy
# defined by the specified 'elementTypes'. Example uses of 'flagName' are
# "omitIntrospection" and "noAggregateConversion".
sub checkFlagUsage(\%$)
{
  my ($elementTypes, $flagName) = @_;

  foreach my $elementType (values %$elementTypes) {
    next if ((defined $elementType->{$flagName}) &&
             (($elementType->{$flagName} eq "1") ||
              ($elementType->{$flagName} eq "true")));

    assertMembersDoNotDefineFlag(%$elementTypes, %$elementType, $flagName);
  }
}

#------------------------------------------------------------------------------

{ my $warnedServiceName = 0;
  my $warnedPackage  = 0;
  my $warnedCheckin  = 0;
sub adjustData(\%\%\%$$)
{
  my ($data, $elementTypes, $opts, $schemaFile, $external) = @_;
  $external = 0 if $opts->{recurse};

  unless ($authorInfo) {
    $authorInfo = $opts->{author}
               || getAuthorInfo(%$opts)
               || sprintf('Author Unknown (Unix login: %s)', getpwuid($>));
  }
  $data->{author} = $authorInfo;
  $opts->{author} = $data->{author};

  if ($opts->{currentMode} =~ /cmp|msg|cfg/) {
      if (! defined $opts->{package}) {
          $opts->{package} = $opts->{basePackage};
      }
      die "** ERR: Use --package to specify package name\n"
          unless defined $opts->{package};
  }
  else {
      if (defined $opts->{serviceName}) {
        $data->{serviceName} = $opts->{serviceName};
      } elsif (!defined $data->{serviceName} and !$external) {
        die "** ERR: Use --serviceInfo to specify service name\n";
      }

      unless ($external) {
        $opts->{serviceName} = $data->{serviceName};
        warn "* WARN: Service name '$$data{serviceName}' should not contain "
           . "'_': "
           . "try --serviceInfo\n"
            if   $data->{serviceName} =~ m/_/
            and !$opts->{noWarnings};
      }
  }

  my $derivePackageFlag = not defined $data->{package};
  if ($opts->{package}) {
    if (!$external || $external && $opts->{configuration}) {
      $data->{package} = lc($opts->{package});
      $derivePackageFlag = 0;
    }
  }

  if ($derivePackageFlag) {
    $data->{package} = derivePackageNameFromServiceName($opts->{serviceName});
#   $opts->{basePackage} = $data->{package};  # TBD: WHY NOT HERE?

    warn "* WARN: Deriving package name from service name: "
       . "$$data{serviceName}\n"
        and $warnedPackage = 1
        if  (! $warnedPackage
        and  ! $opts->{noWarnings}
        and  ! $opts->{genOverride}
        and    $opts->{warnPackageName});
  }

  unless (defined $opts->{msgLibrary}) {
      $opts->{msgLibrary} = $opts->{basePackage};
#     $opts->{msgLibrary} = "UNSPECIFIED";
  }

  my $schema = $data->{types}->{schema} || $data;
  my @elementTypesArray;
  my $defaultRequestType  = 'UNSPECIFIED';#'Request';
  my $defaultResponseType = 'UNSPECIFIED';#'Response';

  $data->{WSDL} = 0;
  if (defined $data->{types}->{schema}) {
    $data->{WSDL} = 1;

    if (!defined $data->{portType}) {
      die "** ERR: Undefined portType\n";
    }
    if (1 != scalar @{$data->{portType}}) {
      die "** ERR: Only one portType definition is allowed\n";
    }

    $defaultRequestType  = MixedMixed($data->{portType}->[0]->{name})
                         . 'Request';
    $defaultResponseType = MixedMixed($data->{portType}->[0]->{name})
                         . 'Response';
  }

  my $requestType = $opts->{requestType}
                 || $data->{requestType}
                 || $defaultRequestType;
  $data->{requestType} = $requestType;

  my $responseType = $opts->{responseType}
                  || $data->{responseType}
                  || $defaultResponseType;
  $data->{responseType} = $responseType;

  if ($data->{requestType} eq $data->{responseType}
  and $data->{requestType} ne $defaultRequestType)
  {
    warn "* WARN: Request and response elements have the same type\n";
  }

  foreach my $type (@{$schema->{simpleType}}) {
    $type->{name} = $opts->{msgPrefix} . MixedMixed($type->{name})
        unless $type->{name} =~ m/\$\$/;
    $type->{typeCategory} = 'simpleType';
    $type->{refname} = $type->{name};
    $type->{schemaFile} = $schemaFile;
    push(@elementTypesArray, $type);
  }

  my $alias = {};
  foreach my $type (@{$schema->{alias}}) {
#   $type->{name} = $opts->{msgPrefix} . MixedMixed($type->{name})
#       unless $type->{name} =~ m/\$\$/ or defined TYPE_INFO->{$type->{name}};
    $type->{typeCategory} = 'alias';
    $type->{refname} = $type->{name};
    $type->{schemaFile} = $schemaFile;
    my (undef, $t) = $type->{type} =~ m/^(\w+:)?(.+)/;
    unless ($type->{name} =~ m/\$\$/ or defined TYPE_INFO->{$t}) {
      $type->{type} = $opts->{msgPrefix} . MixedMixed($t);
    } else {
      $type->{type} = $t;
    }
    $alias->{$type->{name}} = $type;
  }

  foreach my $type (@{$schema->{complexType}}) {
    if ((!defined $type->{sequence}) and (!defined $type->{choice})) {
      # Type is neither a sequence nor a choice. Assume that this type
      # is an anonymous empty complex type, and add an empty sequence
      # so that it is no longer empty.
      $type->{sequence} = [];
      $type->{isEmptyType} = 1;
    }

    $type->{name} = $opts->{msgPrefix} . MixedMixed($type->{name})
        unless $type->{name} =~ m/\$\$/;
    $type->{typeCategory} = 'complexType';
    $type->{refname} = $type->{name};
    $type->{schemaFile} = $schemaFile;

    my $trait = 'undefined';
    $trait = 'sequence' if defined $type->{sequence};
    $trait = 'choice'   if defined $type->{choice};

    # Transform 'ref' attributes to 'type' attributes.
    if (defined $type->{$trait}) {
      foreach (@{$type->{$trait}}) {
        if (defined $_->{ref}) {
          my (undef, $ref) = $_->{ref} =~ m/^(\w+:)?(.+)/;
          my $typename = $opts->{msgPrefix} . MixedMixed($ref);
#         my $typename = 'element$$' . $opts->{msgPrefix} . MixedMixed($ref);
          if (defined $alias->{$typename}) {
            $_->{type} = $alias->{$typename}->{type};
          } else {
            $_->{type} = 'element$$' . $typename;
#           $_->{type} = $typename;
          }
          $_->{name} = $ref;
        }
      }
    }

    if (defined $type->{$trait}) {
      foreach (@{$type->{$trait}}) {
        next if (defined $_->{ref} || $external);
        if ($_->{type} =~ m/^(\w+:)?(.+)/) {
          my $ns = $1 || '';
          $_->{type} = $ns . $opts->{msgPrefix} . MixedMixed($2)
              unless scalar grep /$2/, keys %{TYPE_INFO()};
        }
      }
    } else {
      # TBD: Empty complexTypes should already be supported...
      die "** ERR: Type '$$type{name}' is neither a sequence nor a choice\n"
        . "  HINT: Empty complexTypes are not supported\n";
    }

    push(@elementTypesArray, $type);
  }

  if ($data->{WSDL}) {
    foreach my $message (@{$data->{message}}) {
      my %gen = %$message;
      delete $gen{part};
      $gen{sequence} = [];
      die "** ERR: WSDL does not fit WS-I Basic Profile\n"
        . "  Hint: Message $$message{name} can have only one 'part' element\n"
          if 1 < @{$message->{part}};
      foreach my $part (@{$message->{part}}) {
        my %element = %$part;
        if (defined $element{element}) {
          my (undef, $t) = $element{element} =~ m/^(\w+:)?(.+)/;
          my $baseType = $opts->{msgPrefix} . MixedMixed($t);
          $element{name} = $t;
          $element{type} = (defined $alias->{$baseType})
                         ? $alias->{$baseType}->{type}
                         : 'element$$' . $baseType;
        }
        push @{$gen{sequence}}, \%element;
      }
      $gen{typeCategory} = 'complexType';
      $gen{name}    = $opts->{msgPrefix} . MixedMixed($gen{name});
      $gen{refname} = 'message$$'
                    . $opts->{msgPrefix}
                    . MixedMixed($message->{name});
      $gen{schemaFile} = $schemaFile;
      push(@elementTypesArray, \%gen);
      push(@{$schema->{complexType}}, \%gen);
    }

    foreach my $portType (@{$data->{portType}}) {
      my %gen = %$portType;
      delete $gen{operation};
      $gen{choice} = [];
      foreach my $op (@{$portType->{operation}}) {
        my %element = %$op;
        my (undef, $t) = $element{input}->{message} =~ m/^(\w+:)?(.+)/;
        $element{type} = 'message$$' . $opts->{msgPrefix} . MixedMixed($t);
        push @{$gen{choice}}, \%element;
      }
      $gen{typeCategory} = 'complexType';
      $gen{name} = $opts->{msgPrefix}
                 . MixedMixed($portType->{name})
                 . "Request";
      $gen{refname} = 'request$$'
                    . $opts->{msgPrefix}
                    . MixedMixed($data->{requestType});
      $gen{schemaFile} = $schemaFile;
      push(@elementTypesArray, \%gen);
      push(@{$schema->{complexType}}, \%gen);
    }

    foreach my $portType (@{$data->{portType}}) {
      my %gen = %$portType;
      delete $gen{operation};
      $gen{choice} = [];
      foreach my $op (@{$portType->{operation}}) {
        my %element = %$op;
        my (undef, $t) = $element{output}->{message} =~ m/^(\w+:)?(.+)/;
        $element{type} = 'message$$' . $opts->{msgPrefix} . MixedMixed($t);
        push @{$gen{choice}}, \%element;
      }
      $gen{typeCategory} = 'complexType';
      $gen{name} = $opts->{msgPrefix}
                 . MixedMixed($portType->{name})
                 . "Response";
      $gen{refname} = 'response$$'
                    . $opts->{msgPrefix}
                    . MixedMixed($data->{responseType});
      $gen{schemaFile} = $schemaFile;
      push(@elementTypesArray, \%gen);
      push(@{$schema->{complexType}}, \%gen);
    }
  }

  foreach my $elementType (@elementTypesArray) {
    if (defined $elementTypes->{$elementType->{refname}}) {
      die "** ERR: duplicate type definition: $elementType->{name}\n";
    }

    # The element's package name is the package in which is is defined unless
    # that schema is inlined, in which case it is the base schema's package.
    if ($opts->{recurse}) {
        $elementType->{package} = $opts->{basePackage};
    }
    else {
      $elementType->{package} = $data->{package};
    }

    $elementType->{external} = $external;
    $elementTypes->{$elementType->{refname}} = $elementType;
  }

  if ($data->{WSDL}) {
    my %schemaElements = ();
    foreach my $element (@{$schema->{element}}) {
      my (undef, $type) = $element->{type} =~ m/(^\w+:)?(.+)/;
      my $elementName = 'element$$'
                      . $opts->{msgPrefix}
                      . MixedMixed($element->{name});
      $schemaElements{$elementName} = $type;
    }

    # Validate "message" member types.
    foreach my $msgType (grep /message\$\$/, keys %$elementTypes) {
      my $memberType = $elementTypes->{$msgType}->{sequence}->[0]->{type};
      my ($adjustedMemberType) = $memberType =~ m/element\$\$(.+)/;

      next if defined TYPE_INFO->{$memberType};

      if (! defined $elementTypes->{$memberType}) {
        if (! defined $elementTypes->{$adjustedMemberType}) {
          die "** ERR: Failed to resolve type $memberType\n";
        }
        $elementTypes->{$msgType}->{sequence}->[0]->{type} =
            $adjustedMemberType;
      }
    }
  }

  resolveDuplicateTypeNames(\@elementTypesArray);

  if (!defined $opts->{omitIntrospection}) {
    checkFlagUsage(%$elementTypes, "omitIntrospection");
  }

  if (!defined $opts->{noAggregateConversion}) {
    checkFlagUsage(%$elementTypes, "noAggregateConversion");
  }

  unless ($opts->{msgExpand} or defined $data->{configuration}) {
      map { $_->{component} = $opts->{msgComponent} }
          values %$elementTypes;
  }

  my $verbose = $opts->{debug} || 0;
  print Dumper('##########', $data, '##########') if 5 < $verbose;

  die "opts author ($$opts{author}) != data author ($$data{author})\n"
      unless $opts->{author} eq $data->{author};
}}

#------------------------------------------------------------------------------

sub loadIncludes(\%\%\%$);
sub modifySchemaElementLists(\@\@\@\@\%);
sub resetSchemaAttributes(\%\%);
sub uniqueName($$);
sub adjustSchema(\%\%);
sub resolveDuplicateTypeNames(\@);
sub modifyTypeNames(\@);
sub modifyEmptyComplexTypes(\@);
sub modifyEmptySimpleTypes(\@);
sub modifyNillableTypes(\@);
sub modifySimpleContent(\@);
sub modifyComplexContent(\@);
sub modifyAttributes(\@);
sub modifyElementTypes(\@\@\@\@\%);
sub modifyNestedType(\@\@\@\@$\@\%);
sub modifyNestedTypes(\@\@\@\%);
sub modifyWsdlElements(\%\%);

sub loadSchemaFile(\%\%\%$$)
{
  # Load the specified 'schemaFile', recursively loading each included schema,
  # and build the specified 'elementTypes', 'includes', and 'opts'.

  my ($elementTypes, $includes, $opts, $schemaFile, $external) = @_;

  my $xsd  = XMLNS;
  my $wsdl = WSDLNS;

  my $schemaText;
  {
      local $/ = undef;    # enable "slurp" mode

      my $schemaFileHandle = new IO::File "< $schemaFile"
          || die "** ERR: Failed to open $schemaFile for reading\n";

      $schemaText = <$schemaFileHandle>;

      $schemaFileHandle->close();
  }

  # Strip any carriage return characters.
  $schemaText =~ s/\r//g;

  my $data = $parser->XMLin($schemaText,
                   NSExpand => 1,
                   ForceArray => [
                       "\{$xsd\}annotation",
                       "\{$xsd\}appinfo",
                       "\{$xsd\}documentation",
                       "\{$xsd\}complexType",
                       "\{$xsd\}simpleType",
                       "\{$xsd\}enumeration",
                       "\{$xsd\}pattern",
#                      "\{$xsd\}sequence",      # intentionally commented out
#                      "\{$xsd\}all",           # intentionally commented out
                       "\{$xsd\}choice",
                       "\{$xsd\}attribute",
                       "\{$xsd\}element",
                       "\{$xsd\}include",
                       "\{$wsdl\}message",
                       "\{$wsdl\}part",
                       "\{$wsdl\}portType",
                       "\{$wsdl\}operation",
                   ],
                   KeyAttr => [],
                   GroupTags => {},
                  );

  $data = preprocessSchema($data);
  my $schema = $data->{types}->{schema} || $data;

  if (defined $data->{serviceName}) {
      if (defined $data->{serviceInfo}) {
          die "** ERR: Attributes 'bdem:serviceName' and 'bdem:serviceInfo' "
            . "are mutually exclusive\n";
      }

      if (0 != parseServiceName(%$data, $data->{serviceName})) {
          die "** ERR: Invalid value for attribute 'bdem:serviceName'\n";
      }
  }
  elsif (defined $data->{serviceInfo}) {
      if (0 != parseServiceInfo(%$data, $data->{serviceInfo})) {
          die "** ERR: Invalid value for attribute 'bdem:serviceInfo'\n";
      }
  }

  my $bsn = "bdem:serviceName";
  if (defined $opts->{serviceName}) {
    warn "* WARN: Overriding service name specified in '$bsn'\n"
      if defined $data->{serviceName} && !defined $opts->{basePackage};
    $data->{serviceName} = $opts->{serviceName};
  }

  if (defined $opts->{serviceId}) {
    warn "* WARN: Overriding service ID specified in '$bsn'\n"
      if defined $data->{serviceId} && !defined $opts->{basePackage};
    $data->{serviceId} = $opts->{serviceId};
  }

  if (defined $opts->{serviceVersionMajor}) {
    warn "* WARN: Overriding service major version specified in '$bsn'\n"
      if defined $data->{serviceVersionMajor} && !defined $opts->{basePackage};
    $data->{serviceVersionMajor} = $opts->{serviceVersionMajor};
  }

  if (defined $opts->{serviceVersionMinor}) {
    warn "* WARN: Overriding service minor version specified in '$bsn'\n"
      if defined $data->{serviceVersionMinor} && !defined $opts->{basePackage};
    $data->{serviceVersionMinor} = $opts->{serviceVersionMinor};
  }

  # The service name is used to derive the package name of types found in
  # recursed schemas.
  $opts->{serviceName} = $data->{serviceName};

  die "** ERR: Multiple <schema> elements defined\n"
    unless ("HASH" eq ref $schema);

  warn "* WARN: A namespace cannot be inferred for types defined in "
     . $schemaFile . "\n"
     . "  HINT: Either specify the bdem:package attribute or use the "
     .         "--recurse flag\n"
     if  $external
      && ! exists $opts->{configuration}
      && ! exists $data->{package}
      && ! $opts->{recurse}
      && ! exists $opts->{noWarnings};

  my $schemaAttributes = {};
  foreach (keys %$schema) {
    $schemaAttributes->{$_} = $schema->{$_} if "" eq ref $schema->{$_};
  }

  if (exists $schemaAttributes->{configuration}) {
      $opts->{configuration} = $schemaAttributes->{configuration};
      $opts->{package}       = $schemaAttributes->{package}
          unless defined $opts->{package};
      $opts->{serviceName}   = $schemaAttributes->{serviceName}
          unless defined $opts->{serviceName};
  }

  if (!defined $opts->{basePackage}) {
    # Discover the package name from the root schema.

    if (defined $opts->{package}) {
      $opts->{basePackage} = $opts->{package};
    }
    elsif (!$external and defined $data->{package}) {
      $opts->{basePackage} = $data->{package};
    }
    elsif (defined $opts->{serviceName} || defined $data->{serviceName}) {
      my $serviceName = $opts->{serviceName} || $data->{serviceName};
      $opts->{basePackage} = derivePackageNameFromServiceName($serviceName);
    }
    $opts->{commandLineOptions}->{basePackage} = $opts->{basePackage};
  }

  loadIncludes(%$elementTypes, %$includes, %$opts, $schema);
  resetSchemaAttributes(%$schema, %$schemaAttributes);

  return {} if $opts->{doValidation};                                  # RETURN

  my $verbose = $opts->{debug} || 0;
  print Dumper('--------->', $schema, '<---------') if 3 < $verbose;

  $schema->{element}     = [] unless defined $schema->{element};
  $schema->{simpleType}  = [] unless defined $schema->{simpleType};
  $schema->{complexType} = [] unless defined $schema->{complexType};
  $schema->{alias}       = [] unless defined $schema->{alias};

  modifySchemaElementLists(@{$schema->{element}},
                           @{$schema->{simpleType}},
                           @{$schema->{complexType}},
                           @{$schema->{alias}},
                           %$opts);

  print Dumper('+++++++++>', $data, '<+++++++++') if -4 == $verbose;

  modifyWsdlElements(%$data, %$opts)
      if defined $data->{types}->{schema};  # WSDL only

  adjustSchema(%$schema, %$opts);

  print Dumper('>>>>>>>>>>', $data, '<<<<<<<<<<') if 4 < $verbose;

  die "** ERR: Use --package to specify package name\n"
      unless exists  $opts->{basePackage}
          or        !$opts->{warnPackageName};

  adjustData(%$data, %$elementTypes, %$opts, $schemaFile, $external)
      if scalar $opts->{target};

  return $data;
}

sub modifySchemaElementLists(\@\@\@\@\%)
{
  my ($elements, $simpleTypes, $complexTypes, $aliases, $opts) = @_;

  modifyTypeNames(@$simpleTypes);
  modifyTypeNames(@$complexTypes);

  modifyEmptyComplexTypes(@$complexTypes);
  modifyEmptySimpleTypes(@$simpleTypes);

  if ($opts->{extended}) {
  modifyElementTypes(@$elements,
                     @$simpleTypes,
                     @$complexTypes,
                     @$aliases,
                     %$opts);
  }
  modifySimpleContent(@$complexTypes);
  modifyComplexContent(@$complexTypes);
  modifyNillableTypes(@$complexTypes);

  modifyAttributes(@$complexTypes);
  modifyNestedTypes(@$simpleTypes, @$complexTypes, @$aliases, %$opts);
}

sub resetSchemaAttributes(\%\%)
{
  my ($schema, $schemaAttributes) = @_;

  foreach (keys %$schema) {
    delete $schema->{$_} if "" eq ref $schema->{$_};
  }
  foreach (keys %$schemaAttributes) {
    $schema->{$_} = $schemaAttributes->{$_};
  }
}

sub uniqueName($$)
{
  my ($typeName, $typeHash) = @_;
  my $baseName = $typeName;
  my $counter  = 1;

  while (exists $typeHash->{$typeName}) {
    $typeName = $baseName . $counter++;
  }
  if ($baseName ne $typeName) {
    warn "* WARN: substituting '$typeName' "
       . "for duplicate typename '$baseName'\n";
  }
  return $typeName;
}

sub adjustSchema(\%\%)
{
  my ($schema, $opts) = @_;

  foreach my $type (@{$schema->{complexType}}) {
    if (defined $type->{all}) {
      $type->{sequence} = $type->{all};
      delete $type->{all};
    }
    if (defined $type->{sequence}) {
      die "** ERR: $$type{name}: expecting sequence to have HASH type\n"
          unless "HASH" eq ref($type->{sequence});
      my $hashRef = $type->{sequence};
      $type->{sequence} = $type->{sequence}->{element};
    } elsif (defined $type->{choice}) {
      die "** ERR: $$type{name}: expecting a choice of one\n"
          unless 1 == scalar @{$type->{choice}};
      $type->{choice} = $type->{choice}[0]->{element};
    }
  }
}
sub resolveDuplicateTypeNames(\@)
{
  my $typeList = shift;

  my %typeHash = ();

  # Make all (non-element) names unique.
  foreach my $type (@$typeList) {
    my $typeName = MixedMixed($type->{name});
    if (exists $typeHash{$typeName}) {
      $typeName = uniqueName($typeName, \%typeHash);
      $type->{name} = $typeName;
      $type->{refname} = $typeName;
    }
    $typeHash{$typeName} = undef;
  }

  # Find all element types, and store a unique name (generated, if necessary)
  # for each in the 'elementTypeHash'.
  my %elementTypeHash;
  foreach my $type (@$typeList) {
    my $typeName = $type->{name};
    if ($typeName =~ s/^element\$\$(.+)/$1Element/) {
      if (exists $typeHash{$typeName}) {
        $typeName = uniqueName($typeName, \%typeHash);
        $elementTypeHash{$type->{name}} = $typeName;
      }
      $type->{name} = $typeName;
      $type->{refname} = $typeName;
      $typeHash{$typeName} = undef;
    }
  }

  # Resolve all references from element 'type' attributes to element types
  # through the 'elementType' attribute.
  foreach my $type (@$typeList) {
    next if defined $type->{restriction};

    my $trait = undef;
    $trait = 'choice'   if defined $type->{choice};
    $trait = 'sequence' if defined $type->{sequence};

    next unless defined $trait;
    map {$_->{type} = $elementTypeHash{$_->{type}}
             if defined $_->{type} and defined $elementTypeHash{$_->{type}}}
         @{$type->{$trait}};
  }
}

sub modifyTypeNames(\@)
{
  my ($typeList) = @_;

  foreach my $type (@$typeList) {
    $type->{name} = MixedMixed($type->{name});
  }
}

sub modifyEmptyComplexTypes(\@)
{
  my ($typeList) = @_;

  # Make empty complex types look like sequences of a single element
  # with minOccurs='0' and a default value.

  foreach my $type (@$typeList) {
    next if defined $type->{choice} or
            defined $type->{sequence} or
            defined $type->{all};

    $type->{sequence}    = { element => [] };
    $type->{isEmptyType} = 1;
  }
}

sub modifyEmptySimpleTypes(\@)
{
  my ($typeList) = @_;

  # Mark simpleType restrictions with no restrictions

  foreach my $type (@$typeList) {
    next if 1 < values %{$type->{restriction}};

    $type->{isEmptySimpleType} = 1;
  }
}

sub modifyNillableTypes(\@)
{
  my $typeList = shift @_;

  foreach my $type (@$typeList) {
    next unless defined $type->{sequence};

    foreach my $element (@{$type->{sequence}->{element}}) {
      if (defined $element->{nillable} and 'true' eq $element->{nillable}) {
        $element->{isNillable} = 1;
        $element->{minOccurs}  = 0;
        delete $element->{nillable}
      }
    }
  }
}

sub modifySimpleContent(\@)
{
  my $typeList = shift @_;

  foreach my $type (@$typeList) {
    next unless defined $type->{simpleContent};

    $type->{sequence} =
        { element  => [ { isSimpleContent => 1,
                          name => 'TheContent',
                          type => $type->{simpleContent}->{extension}->{base},
                        }]};
    $type->{attribute} = $type->{simpleContent}->{extension}->{attribute};
    delete $type->{simpleContent};
  }
}

sub modifyComplexContent(\@)
{
  my $typeList = shift @_;

  foreach my $type (@$typeList) {
    next unless defined $type->{complexContent};

    if ((  defined $type->{complexContent}->{mixed}) &&
        ("true" eq $type->{complexContent}->{mixed}))
    {
      die "** ERR: Mixed content is not supported\n";
    }

    if (defined $type->{complexContent}->{restriction}) {
      die "** ERR: Restrictions on a complex type are not supported\n";
    }

    if (!defined $type->{complexContent}->{extension}) {
      die "** ERR: complexContent must define <extension>\n";
    }

    if (defined $type->{complexContent}->{extension}->{choice} ||
        defined $type->{complexContent}->{extension}->{all})
    {
      die "** ERR: extension by <choice> is not supported\n";
    }

    # Fixup implicit sequences.
    if (!defined $type->{sequence}) {
      $type->{sequence} = {};
      $type->{sequence}->{element} = [];
    }

    # Fixup implicit sequences.
    if (!defined $type->{complexContent}->{extension}->{sequence}) {
      $type->{complexContent}->{extension}->{sequence} = {};
      $type->{complexContent}->{extension}->{sequence}->{element} = [];
    }

    my $baseTypeName = $type->{complexContent}->{extension}->{base};
    $baseTypeName =~ s/^\w+?://;
    $baseTypeName = MixedMixed($baseTypeName);

    foreach (@$typeList) {
      next if ($baseTypeName ne $_->{name});

      my $baseType = $_;

      if (exists $baseType->{complexContent}
      &&  exists $baseType->{complexContent}->{extension}
      && (exists $baseType->{complexContent}->{extension}->{choice}
      ||  exists $baseType->{complexContent}->{extension}->{all}))
      {
        die "** ERR: extension of <choice> is not supported\n";
      }

      if (!defined $baseType->{sequence}) {
        $baseType->{sequence} = {};
        $baseType->{sequence}->{element} = [];
      }

      my @arrayCopy = @{
        Storable::dclone($baseType->{sequence}->{element}) };
      push @{$type->{sequence}->{element}}, @arrayCopy;

      if (defined $baseType->{attribute}) {
        if (!defined $type->{attribute}) {
          $type->{attribute} = [];
        }
        my @arrayCopy = @{ Storable::dclone($baseType->{attribute}) };
        push @{$type->{attribute}}, @arrayCopy;
      }

      last;
    }

    push @{$type->{sequence}->{element}},
         @{$type->{complexContent}->{extension}->{sequence}->{element}};

    if (defined $type->{complexContent}->{extension}->{attribute}) {
      if (!defined $type->{attribute}) {
        $type->{attribute} = [];
      }
      push @{$type->{attribute}},
        @{$type->{complexContent}->{extension}->{attribute}};
    }

    delete $type->{complexContent};
  }
}

sub modifyAttributes(\@)
{
  my $typeList = shift @_;

  # Modify 'data' to support attributes
  foreach my $type (@$typeList) {
    next unless defined $type->{attribute};

    my @attributes;
    foreach my $attribute (@{$type->{attribute}}) {
      $attribute->{isAttribute} = 1;
      $attribute->{minOccurs} = 0;

      if (defined $attribute->{fixed}) {
        $attribute->{default} = $attribute->{fixed};
        delete $attribute->{minOccurs};
      }
      if (defined $attribute->{use}) {
        if ('prohibited' eq $attribute->{use}) {next }
        if ('required'   eq $attribute->{use}) {delete $attribute->{minOccurs}}
      }

      push(@attributes, $attribute);
    }

    $type->{sequence} = {} unless defined $type->{sequence};
    $type->{sequence}->{element} = []
         unless defined $type->{sequence}->{element};

##  # Sort attribute lexicographically.
##  @attributes = sort { $a->{name} cmp $b->{name} } @attributes;

    # Attributes appear before elements.
    unshift(@{$type->{sequence}->{element}}, @attributes);

    # Add choices
    if (defined $type->{choice}) {
      push(@{$type->{sequence}->{element}},
           { complexType => [ { choice => $type->{choice} } ] });
      delete $type->{choice};
    }
    delete $type->{attribute};
  }
}

sub modifyElementTypes(\@\@\@\@\%)
{
  my ($elementList, $simpleTypes, $complexTypes, $aliases, $opts) = @_;

  foreach my $element (@{$elementList}) {
    if(defined $element->{complexType} or defined $element->{simpleType}) {
      my $typetype = (defined $element->{complexType}) ? 'complexType'
                                                       : 'simpleType';
      my $typeRef;
      if ("HASH" eq ref $element->{$typetype}) {
        $typeRef = $element->{$typetype};
      } else {
        die "** ERR: expected 1 element, found ",
            scalar(@{$element->{$typetype}}), "\n"
            unless 1 == scalar(@{$element->{$typetype}});
        $typeRef = $element->{$typetype}[0];
      }

      if (defined $typeRef->{typeName}) {
        $typeRef->{name} = $typeRef->{typeName};
        $element->{type} = $typeRef->{name};
      }
      else {
        $element->{type} = 'element$$' . $opts->{msgPrefix}
                                       . MixedMixed($element->{name});
        $typeRef->{name} = $element->{type};
      }

      my $typeList = ('complexType' eq $typetype)
                   ? $complexTypes : $simpleTypes;

      push(@$typeList, $typeRef);
      delete $element->{$typetype};
    } else {
      # The element has an explicitly defined type.

      my $typeName = $opts->{msgPrefix} . MixedMixed($element->{name});
      my $typeRef = {
          name => $typeName,
          type => $element->{type},
      };
      push(@$aliases, $typeRef);
    }
  }
}

sub modifyNestedType(\@\@\@\@$\@\%)
{
  my ($simpleTypes,
      $complexTypes,
      $aliases,
      $elemList,
      $parentTypeName,
      $newElemList,
      $opts) = @_;

  # Modify 'data' to support nested types.
  my $counter = 0;
  foreach my $element (@$elemList) {

    unless (defined $element->{complexType} or defined $element->{simpleType})
    {
      push(@$newElemList, $element);
      next;
    }

    my $typetype = (defined $element->{complexType}) ? 'complexType'
                                                     : 'simpleType';

    # Simple types with 'list' item type are special cases.
    if ('simpleType' eq $typetype
        and defined $element->{$typetype}->[0]->{list})
    {
      push(@$newElemList, $element);
      next;
    }

    die "** ERR: expected 1 type, found ",
        scalar(@{$element->{$typetype}}),
        "\n"
        unless 1 == scalar(@{$element->{$typetype}});
    my $typeRef = $element->{$typetype}[0];

    my $isUntaggedFlag = 0;
    my $elemName;
    my $typeName;
    if (defined $element->{name}) {
      $elemName = $element->{name};
      $typeName = $element->{name};
    } else {

      my $trait;
      $trait = 'choice'   if defined $typeRef->{choice};
      $trait = 'sequence' if defined $typeRef->{sequence};

      # TBD: supported by validator?
#     die "** ERR: anonymous $trait in '$parentTypeName' "
#       . "is not supported\n";

      my $incrementCounterFlag = 0;

      my $typeinfo = ('sequence' eq $trait) ? $typeRef->{$trait}
                                            : $typeRef->{$trait}->[0];
      if (defined $typeinfo->{elementName}) {
        $elemName = $typeinfo->{elementName};
      } else {
        $elemName = ucfirst $trait;
        $elemName .= '-' . $counter if 0 < $counter;
        $incrementCounterFlag = 1;
      }

      if (defined $typeinfo->{cpptype}) {
        $typeRef->{name} = $typeinfo->{cpptype};
      } else {
        $typeName = ucfirst $trait;
        $typeName .= '-' . $counter if 0 < $counter;
        $incrementCounterFlag = 1;
      }
      $isUntaggedFlag = 1;
      ++$counter if $incrementCounterFlag;
    }

    if (defined $typeRef->{name}) {
      $typeName = $typeRef->{name};
    } else {
      $typeName = $parentTypeName . MixedMixed($typeName);
    }
    $typeName =~ s/^element\$\$(.+)/$1Element/;
    $typeRef->{name} = $typeName;

    $element->{origName} = $elemName;
    $element->{name} = mixedMixed($elemName);
#   $element->{type} = $opts->{msgPrefix} . $typeRef->{name};
    $element->{type} = $typeRef->{name};
    $element->{isUntagged} = $isUntaggedFlag;
    # TBD: This should probably be done, but it's not backward compatible.
#   if ($isUntaggedFlag) {
#     $element->{name} = $parentTypeName . MixedMixed($element->{name});
#   }
    delete $element->{$typetype};

    my $newElements = [ $element ];
    my $newSimpleTypes = [];
    my $newComplexTypes = [];
    my $newAliases = [];

    if ('simpleType' eq $typetype) {
        push(@$newSimpleTypes, $typeRef);
    } else {
        push(@$newComplexTypes, $typeRef);
    }
    modifySchemaElementLists(@$newElements,
                             @$newSimpleTypes,
                             @$newComplexTypes,
                             @$newAliases,
                             %$opts);
    push(@$newElemList,  @$newElements);
    push(@$simpleTypes,  @$newSimpleTypes);
    push(@$complexTypes, @$newComplexTypes);
    push(@$aliases,      @$newAliases);
  }
}

sub modifyNestedTypes(\@\@\@\%)
{
  my ($simpleTypes, $complexTypes, $aliases, $opts) = @_;

  if ("ARRAY" ne ref($complexTypes)) {
    die "** ERR: invalid type: '$$complexTypes{name}'\n"
      . "  Hint: Is '$$complexTypes{name}' in the correct namespace?\n";
  }

  foreach my $type (@$complexTypes) {
    next unless defined $type->{sequence}
             or defined $type->{choice}
             or defined $type->{all};

    my $typeRef;
    if (defined $type->{sequence}) {
      $typeRef = $type->{sequence};
    }
    elsif (defined $type->{all}) {
      $typeRef = $type->{all};
    } else {
      die "** ERR: expected 1 element, found ",
          scalar(@{$type->{choice}}), "\n"
          unless 1 == scalar(@{$type->{choice}});
      $typeRef = $type->{choice}[0];
    }

    $typeRef->{element} = [] unless defined $typeRef->{element};
    $typeRef->{element} = [ $typeRef->{element} ]
      unless "ARRAY" eq ref $typeRef->{element};
    my $newElemList = [];
    my $typename = ($type->{name} =~ m/(.+\$\$)(.+)/)
                 ? $1 . MixedMixed($2) : $type->{name};
    modifyNestedType(@$simpleTypes,
                     @$complexTypes,
                     @$aliases,
                     @{$typeRef->{element}},
                     $typename,
                     @$newElemList,
                     %$opts);
    $typeRef->{element} = $newElemList;
  }
}

sub modifyWsdlElements(\%\%)
{
  my ($data, $opts) = @_;

  # Modify portType operations.
  my $messageElement = {};
  foreach my $message (@{$data->{message}}) {
    foreach my $part (@{$message->{part}}) {
      my $element = $part->{element};
      $element =~ s/^\w+?://;
      $messageElement->{$message->{name}} = $element;
    }
  }

  foreach (@{$data->{portType}}) {
    foreach (@{$_->{operation}}) {
      { # input
        my $io = $_->{input};
        my $message = $io->{message};
        $message =~ s/^\w+?://;
        $io->{requestElement} = $messageElement->{$message};

        # TBD: This should be tied to validateSchema.
        my $requestElement = $io->{requestElement} || '';
        warn "* WARN: WSDL does not fit WS-I Basic Profile\n"
           . "  Hint: operation '$$_{name}' must be the same name "
           . "as the input message element\n"
            unless $_->{name} eq $requestElement
                or $opts->{noWarnings};
      }
      { # output
        my $io = $_->{output};
        my $message = $io->{message};
        $message =~ s/^\w+?://;
        $io->{responseElement} = $messageElement->{$message};
      }
    }
  }

  # Modify binding operations.
  my $operations = {};

  die "** ERR: Multiple <wsdl:binding> elements are not supported\n"
    if ("ARRAY" eq ref $data->{binding});

  die "** ERR: Multiple <wsdl:port> elements are not supported\n"
    if ("ARRAY" eq ref $data->{service}->{port});

  foreach (@{$data->{binding}->{operation}}) {
    $operations->{$_->{name}} = $_;
  }
  $data->{binding}->{operation} = $operations;
}

sub loadIncludes(\%\%\%$)
{
  my ($elementTypes, $includes, $opts, $schema) = @_;

  die "** ERR: Multiple <schema> elements are not supported\n"
      unless 'HASH' eq ref $schema;

  die "** ERR: <import> is not supported\n"
      if defined $schema->{import};

  if (defined $schema->{include}) {
    foreach my $inc (@{$schema->{include}}) {
      my $fullpath = '';

      if (File::Spec->file_name_is_absolute($inc->{schemaLocation})) {
        if (-r $inc->{schemaLocation}) {
          $fullpath = $inc->{schemaLocation};
        }
      }
      else {
        foreach my $dir (@{$opts->{includedir}}) {
          my $trypath = File::Spec->catfile($dir, $inc->{schemaLocation});
          if (-r $trypath) {
            $fullpath = $trypath;
            last;
          }
        }
      }

      if (! $fullpath) {
        die "** ERR: Failed to find $inc->{schemaLocation}\n";
      }

      if (defined $includes->{$fullpath}) {
        print "Skipping $fullpath -- already included\n"
            unless $opts->{doValidation};
      }
      else {
        $includes->{$fullpath} = {};
        print "Including $fullpath\n" unless $opts->{doValidation};
        my $includedSchema =
          loadSchemaFile(%$elementTypes, %$includes, %$opts, $fullpath, 1);
        $includes->{$fullpath} = $includedSchema;
      }
    }
  }
}

#------------------------------------------------------------------------------

sub collectNsTags(\%\%$)
{

  my ($nsTags, $nsTagsReversed, $schema) = @_;

  # process default namespace
  if (defined $schema->{xmlns}) {

    if (defined $nsTags->{xmlns} && $nsTags->{xmlns} ne $schema->{xmlns}) {
      die "** ERR: default namespace mismatch\n";
    }
    else {
      $nsTags->{xmlns} = $schema->{xmlns};
      $nsTagsReversed->{ $schema->{xmlns} } = '';
    }
  }

  my @nstags = grep /^(xmlns):?/, keys %$schema;

  foreach my $tag (@nstags) {
    my $k = $tag;

    if ((defined $nsTags->{$tag}) and (defined $schema->{$k})) {
      if ($nsTags->{$tag} ne $schema->{$k}) {
        die "** ERR: namespace $tag mismatch: "
          . "Value of $tag must match value of $k\n"
          . "$tag = $nsTags->{$tag}, "
          . "$k = $schema->{$k}\n";
      }
    }
    else {
      $nsTags->{$tag} = $schema->{$k};
      $nsTagsReversed->{ $schema->{$k} } = $tag;
    }
  }
}

#----

sub bsl2bde(\$)
{
    my ($text) = @_;

    # fix STL inlcudes and namespaces
    $$text =~ s/INCLUDED_BSL_/INCLUDED_/g;
    $$text =~ s/<bsl_([^.]+).h>/<$1>/g;
    $$text =~ s/bsl::/std::/g;

    # fix allocators
    $$text =~ s/BSLMA_(DEFAULT|ALLOCATOR)/BDEMA_$1/g;
    $$text =~ s/bslma_([Dd]efault|[Aa]llocator)/bdema_$1/g;

#   # fix BSL_ASSEERT and BSLS_PLATFORM
#   $$text =~ s/BSLS_/BDES_/g;
#   $$text =~ s/bsls_/bdes_/g;
#   $$text =~ s/BSL_ASSERT/BDE_ASSERT/g;
#
#   # fix traits and bslalg
#   $$text =~ s/BSLALG_/BDEALG_/g;
#   $$text =~ s/bslalg_(.+)/bdealg_$1/g;
#   $$text =~ s/BSLMAALLOCATOR/BDEMAALLOCATOR/g;
#   $$text =~ s/([Bb])slma([Aa]llocator)/$1dema$2/g;
}

sub wsdl2xsd($\%\%\%\%)
{
  my ($text, $namespace, $reverseNs, $schema, $opts) = @_;

  unless ($text =~ m/<((\w+):)?schema\s?(.+?)>(.+)<\/((\w+):)?schema>/s) {
      return 0;
  }

  my $schemaNamespace = $2;
  my $schemaAttributes = $3;
  my $schemaText = $4;

  # Hash of schema attribute names (including any namespace prefix) to their
  # value.
  my %schemaAttrs;

  map {
    # match 'xmlns:tns' style patterns
    if (m/(\w+(:\w+)?)=('(.+?)'|"(.+?)")/) {
      $schemaAttrs{$1} = $4 || $5;
    }
  }
  split ' ', $schemaAttributes;

  foreach (keys %schemaAttrs) {
    my $ns = $_;
    if (length $ns) {

      # targetNamespace is redefined.
      if ((defined $namespace->{targetNamespace}) and
          ($ns eq "targetNamespace") and
          ($namespace->{targetNamespace} ne $schemaAttrs{$_}))
        {
          die "** ERR: WSDL targetNamespace must match the schema "
            . "targetNamespace\n";
        }

      $namespace->{$ns} = $schemaAttrs{$_};
    }
  }

  my $bdem = $reverseNs->{'http://bloomberg.com/schemas/bdem'};
  unless (defined $bdem) {
    $namespace->{"xmlns:bdem"} = 'http://bloomberg.com/schemas/bdem';
    $bdem = 'bdem';
  }
  else {
    $bdem =~ s/xmlns:?//;
  }

  my $tns = '';
  foreach (keys %$namespace) {
    next if $_ eq 'targetNamespace';
    $tns = $_ and last if $namespace->{$_} eq $namespace->{targetNamespace};
  }
  $tns =~ s/xmlns:?//;

  if (length $tns) {
    $tns .= ':';
  } else {
    die "** ERR: Mismatch between default namespace and target namespace\n"
       . " Hint: Default namespace (xmlns) and targetNamespace must have the\n"
       . "       same definition, or an alias for targetNamespace must be "
       . "defined.\n"
        unless defined $namespace->{xmlns};
  }

  my $xs = $schemaNamespace;
  if (defined $xs) {
    unless (defined $namespace->{"xmlns:" . $xs}) {
      $namespace->{"xmlns:" . $xs} = 'http://www.w3.org/2001/XMLSchema';
    }
    $xs .= ':';
  } else {
    $xs = '';
  }

  # Ensure 'bdem:requestType' and 'bdem:responseType' appear in the xsd.
  die "** ERR: Multiple <wsdl:portType> elements are not supported\n"
    if ("ARRAY" eq ref $schema->{portType});
  $namespace->{"$bdem:requestType"}  = $schema->{portType}->{name} . "Request";
  $namespace->{"$bdem:responseType"} = $schema->{portType}->{name} . "Response";

  my $sn = "$bdem:serviceName";
  unless (defined $namespace->{$sn}) {
    my $serviceName = $opts->{serviceName}
                   || $schema->{serviceName}
                   || undef;
    $namespace->{$sn} = $serviceName if defined $serviceName;
  }

  my $si = "$bdem:serviceInfo";
  unless (defined $namespace->{$si}) {
    my $serviceInfo = $opts->{serviceInfo}
                   || $schema->{serviceInfo}
                   || undef;
    $namespace->{$si} = $serviceInfo if defined $serviceInfo;
  }

  if (defined $namespace->{$sn} && defined $namespace->{$si}) {
     delete $namespace->{$sn};
  }

  # Add both schema attributes and wsdl:definition attributes to the schema
  # element.
  $text = "<?xml version='1.0' encoding='utf-8'?>\n"
        . "<$xs"."schema";

  # Output schema attributes in reverse lexicographical order.  This heuristic
  # avoids a bug in XML::Simple that ignores attributes unless the alias was
  # already defined.  In particular, this heuristic ensures that in most cases,
  # the 'bdem' namespace alias, 'xmlns:bdem' is defined before it is used.
  foreach my $key (sort { $b cmp $a } keys %$namespace) {
    $text .= "\n        " . $key . "='" . $namespace->{$key} . "'";
  }
  $text .= ">\n$schemaText";

  # Add message types.
  my $message = $schema->{message};
  foreach (@{$message}) {
    my $element = $_->{part}->{element};
    $text .= "\n"
           . "  <$xs"."complexType name='$$_{name}Message'>\n"
           . "    <$xs"."sequence>\n"
           . "      <$xs"."element ref='$element'/>\n"
           . "    </$xs"."sequence>\n"
           . "  </$xs"."complexType>\n";
  }

  # Add top-level types.
  my $portType  = $schema->{portType};
  my $operation = $portType->{operation};

  $text .= "\n"
        .  "  <$xs"."complexType name=\'$$portType{name}Request\'>\n"
        .  "    <$xs"."choice>\n";
  foreach (@{$operation}) {
    my $messageType = $_->{input}->{message} . 'Message';
    $text .= "      <$xs"."element name=\'$$_{name}\' "
          .  "type=\'$messageType\'/>\n";
  }
  $text .= "    </$xs"."choice>\n"
        .  "  </$xs"."complexType>\n";

  $text .= "\n"
        .  "  <$xs"."complexType name=\'$$portType{name}Response\'>\n"
        .  "    <$xs"."choice>\n";
  foreach (@{$operation}) {
    my $messageType = $_->{output}->{message} . 'Message';
    $text .= "      <$xs"."element name=\'$$_{name}\' "
          .  "type=\'$messageType\'/>\n";
  }
  $text .= "    </$xs"."choice>\n"
        .  "  </$xs"."complexType>\n";

  # Add top-level elemenets
  $text .= "\n"
         . "  <$xs"."element name=\'$$portType{name}Request\'\n"
         . "              type=\'$tns$$portType{name}Request\'/>\n"
         . "\n"
         . "  <$xs"."element name=\'$$portType{name}Response\'\n"
         . "              type=\'$tns$$portType{name}Response\'/>\n";

  $text =~ s/<\/$xs"."schema>\n//s;
  $text .= "</$xs"."schema>\n";

  return $text;
}

sub processSchemaFile(\%$$)
{
    my ($opts, $schemaFile, $forceInlineFlag) = @_;

    my $schema = new IO::File "< $schemaFile";
    if (!defined $schema) {
      die "** ERR: Failed to open '$schemaFile' for reading\n";
    }

    local $/ = undef;    # enable "slurp" mode
    my $schemaText = <$schema>;

    # Strip any carriage return characters.
    $schemaText =~ s/\r//g;

    return processSchemaText($opts, $schemaText, $forceInlineFlag);
}

sub processSchemaText(\%$$)
{
  my ($opts, $schemaText, $forceInlineFlag) = @_;

  my $schemaFile = $opts->{schemaFile}->[0];

  my $schemaParser = new SchemaParser;
  my $schema = $schemaParser->XMLin("$schemaText");
  my %nsTags;
  my %nsTagsReversed;

  # When the default namespace is defined, the target namespace must also be
  # defined.
  if (defined $schema->{xmlns}) {
    if (!defined $schema->{targetNamespace}) {
      die "** ERR: $schemaFile must define targetNamespace " .
          "to use default xmlns\n";
    }
  }

  collectNsTags(%nsTags, %nsTagsReversed, $schema);

  # The 'xmlns:bdem' namespace must be defined correctly.
  die "** ERR: Namespace 'bdem' must be defined as "
     . "'http://bloomberg.com/schemas/bdem'\n"
     if (defined $nsTags{"xmlns:bdem"}
     and 'http://bloomberg.com/schemas/bdem' ne $nsTags{"xmlns:bdem"});

  my $bdem = $nsTagsReversed{'http://bloomberg.com/schemas/bdem'} || 'bdem';
  $bdem =~ s/xmlns://;

  my $wsdlns = WSDLNS;
  $schema = $schemaParser->XMLin($schemaText,
                                 NSExpand => 1,
                                 ForceArray => [
                                     "\{$wsdlns\}message",
                                     "\{$wsdlns\}operation",
                                 ],
                                 KeyAttr => [],
                                 GroupTags => {});
  $schema = preprocessSchema($schema);

  $nsTags{targetNamespace} = $schema->{targetNamespace}
      if defined $schema->{targetNamespace};

  my $text = $schemaText;

  # Extract XSD schema from WSDL.
  if (defined $schema->{types}->{schema}) {
    $opts->{isWSDL} = 1;
    $text = wsdl2xsd($text, %nsTags, %nsTagsReversed, %$schema, %$opts)
    || die "** ERR: Failed to extract XSD schema from WSDL in $schemaFile\n";
  }

  # Remember the namespace attributes of the base-level schema, so that
  # equivalent attributes from included schemas are not duplicated in the
  # final synthesized document.
  my %baseNsTags = %nsTags;

  # Process inline elements
  if ($opts->{inline} or $forceInlineFlag) {
    $schemaFile = File::Spec->catfile('.', $schemaFile)
      unless File::Spec->file_name_is_absolute($schemaFile);
    my @inlineSchemaList = ($schemaFile);

    my $inlineFrameworkSchemas = 1;
    my $frameworkSchemaList = [ 'bascfg.xsd'
                              , 'basapi.xsd'
                              , 'baexml.xsd'
                              , 'bdem.xsd'
                              ];

    # Prevent inlining of framework schemas in configuration schema
    if ('cfg' eq $opts->{currentMode}) {
        my $fullpath = undef;
        foreach my $xsd (@$frameworkSchemaList) {
            foreach my $dir (@{$opts->{includedir}}) {
                my $trypath = File::Spec->catfile($dir, $xsd);
                if (-r $trypath) {
                    $fullpath = $trypath;
                    last;
                }
            }
            push(@inlineSchemaList, $fullpath);
        }

        $inlineFrameworkSchemas = 0;
    }

    my @includes;

    # Strip comments before discovering included schemas
    my $strippedText = $text;
    $strippedText =~ s/<!--.*?-->//sg;

    my $tailComment = "  <!-- $schemaFile -->\n";

    while ($strippedText =~ m{(<(?:\w+:)?include.*?(?:/>|/include>))}sx) {
      my $inc      = $1;
      my $inc_meta = quotemeta($inc);
      # use $inc_meta since $inc might contain regex
      # metacharacters
      my ($head, $tail)=($text=~m{(.*?)$inc_meta(.*)}s);
      my $inline = 1;
      if ($inc =~ m/$bdem:inline=(["'])(.*?)\1/s)
      {
        $inline = $2 || $forceInlineFlag;
      }

      if (($inc =~ m/schemaLocation=(["'])(.*?)\1/s) and $inline) {
        my $incfile  = $2;

        my $fullpath = '';

        if (File::Spec->file_name_is_absolute($incfile)) {
          if (-r $incfile) {
            $fullpath = $incfile;
          }
        }
        else {
          foreach my $dir (@{$opts->{includedir}}) {
            my $trypath = File::Spec->catfile($dir, $incfile);
            if (-r $trypath) {
              $fullpath = $trypath;
              last;
            }
          }
        }

        if (! $fullpath) {
          die "** ERR: Failed to find $incfile\n";
        }

        my $basename = basename($fullpath);
        my $ifx      = grep(/$basename/, @$frameworkSchemaList);

        # Prevent recursive inclusion
        if (grep {$fullpath eq $_}  @inlineSchemaList) {
          if ($ifx && 0 == $inlineFrameworkSchemas) {
            $strippedText =~ s/$inc// if $inline;
            $text = $head . $inc . $tail;
          }
          else {
            $strippedText =~ s/$inc// if $inline;
            $text = $head . $tail;
          }
          next;
        }

        push @inlineSchemaList, $fullpath;

        my $incSchema = $schemaParser->XMLin($fullpath);

        # Target namespace alias used by the included schema
        my $targetNsTag = '';

        if (defined $incSchema->{targetNamespace}) {
          # If the included schema defines a target namespace, it must match
          # the target namespace defined by the including schema.
          if (!defined $schema->{targetNamespace}
              || $schema->{targetNamespace} ne $incSchema->{targetNamespace})
          {
            die "** ERR: targetNamespace mismatch while including $fullpath\n";
          }
        }
        else {
          # The included schema must define a target namespace if it also
          # defines the default namespace
          if (defined $incSchema->{xmlns}) {
            die "** ERR: $fullpath must define targetNamespace " .
              "to use default xmlns\n";
          }
          if (defined $schema->{targetNamespace}
          and defined $nsTagsReversed{$schema->{targetNamespace}})
          {
            # Set the value of the target namespace alias used by the
            # included schema
            $targetNsTag = $nsTagsReversed{$schema->{targetNamespace}};
            $targetNsTag =~ s/xmlns://;
          }
        }

        collectNsTags(%nsTags, %nsTagsReversed, $incSchema);

        my $inchandle = new IO::File "< $fullpath";
        my $inctext = <$inchandle>;

        # Strip the <?xml?> declaration element and the top-level schema
        # element.  The result is the body of the document inside the
        # <schema>...</schema> tags.
        $inctext =~ s/^\s*<\?xml.*?\?>//s;
        $inctext =~ s/\s+<(\w+:)?schema.*?>//s;
        $inctext =~ s/<\/(\w+:)?schema>//s;

        if ($targetNsTag)
        {
          $inctext =~ s/\bbase=(['"])([^:]+?)\1/base=$1$targetNsTag:$2$1/g;
          $inctext =~ s/\btype=(['"])([^:]+?)\1/type=$1$targetNsTag:$2$1/g;
        }

        my $inccomment = "<!-- $incfile -->\n";
        $head =~ s/$tailComment//;
        $text =  $head . $inccomment . $inctext . $tailComment . $tail;
      }
      else {
        push(@includes, $inc);
        $text = $head . $tail;
      }

      $strippedText = $text;
      $strippedText =~ s/<!--.*?-->//sg;
    }

    my ($head, $tail) = ($text =~ m/(.+schema[^>]+>[\n]*)(.+)/s);

    $text = $head . (join "\n", @includes) . "\n\n" . $tail;
  }

  if ($opts->{strip}) {
    $text =~ s/<$bdem:\w+\s*>[^<]*<\/$bdem\:\w+\s*>$//smg;
    $text =~ s/<$bdem:\w+\s*\/>$//smg;
    $text =~ s/([ ]+)?$bdem:\w+='[^']*'(\n)?//sg;
  }

  # Expand namespace declarations
  if (my ($head, $schemaElement, $tail) =
      ($text =~ /(.*)(<(?:\w+:)?schema.*?>)(.*)/s))
  {
    # Remove each key in nsTags that also exists in baseNsTags.
    while (my ($key, $value) = each(%baseNsTags)) {
      delete($nsTags{$key}) if defined $nsTags{$key};
    }

    # The targetNamespace attribute does not need to be reinserted into the
    # schema attributes since it is already defined.
    if (defined $schema->{targetNamespace}) {
      delete($nsTags{targetNamespace}) if defined $nsTags{targetNamespace};
    }

    my $nsDecls = join ("\n",
                        sort map {
                          my $n = $_;
                          "        $n='$nsTags{$_}'"
                        } keys %nsTags);

    # Insert schema attributes just before closing '>' of beginning tag.
    $schemaElement =~ s/>/\n$nsDecls>/s if length $nsDecls;

    $text = $head . $schemaElement . $tail;
  }

  $text =~ s/^\s+$/\n/msg;
  $text =~ s/\n\n\n+/\n\n/msg;

  # Strip any carriage return characters.
  $text =~ s/\r//g;

  return $text;
}

#------------------------------------------------------------------------------

sub generateSchemaComponent($\%\%\@)
{
  my ($componentName, $annotation, $opts, $classes) = @_;

  my $config = {
      INCLUDE_PATH => [ $ENV{BAS_CODEGEN_INCLUDE_PATH}
                      , "$FindBin::Bin/../etc/bas_codegen"
                      , "$FindBin::Bin/" . RELEASE . "/etc/bas_codegen"
                      ],
      INTERPOLATE  => 1,
      EVAL_PERL    => 1,
      FILTERS => {
          UPPER_UPPER  => \&UPPER_UPPER,
          MixedMixed   => \&MixedMixed,
          mixedMixed   => \&mixedMixed,
          c_str        => \&c_str,
          escapeQuotes => \&escapeQuotes,
      },
  };

  my $template = Template->new($config);
  my $package = $classes->[0]->{package};

  my @include;
  defined($_->{include}) && push @include, @{$_->{include}} foreach @$classes;

  my $basename = $package . '_' . $componentName . '.h';
  @include = uniqueIncludes(@include, $basename);

  my $supportsIntrospection =
      scalar(grep {$_->{omitIntrospection}} @$classes) != scalar @$classes;

  my $supportsAggregateConversion =
      scalar(grep {$_->{noAggregateConversion}} @$classes) != scalar @$classes;

  my $component = {
    component                   => $componentName,
    package                     => $package,
    documentation               => $annotation->{documentation},
    purpose                     => $classes->[0]->{annotation}->{purpose},
    author                      => $opts->{author},
    supportsIntrospection       => $supportsIntrospection,
    supportsAggregateConversion => $supportsAggregateConversion,
    allocatesMemory             => scalar(
                                       grep {$_->{allocatesMemory}} @$classes),
    include                     => \@include,
    classes                     => \@$classes,
    hasCustomizedType           => scalar(
                                       grep {$_->{trait} eq 'customizedtype'}
                                                                    @$classes),
    hasEnumeration              => scalar(grep {$_->{trait} eq 'enumeration'}
                                                                    @$classes),
    hasComplexType              => scalar(grep {$_->{trait} eq 'sequence' or
                                          $_->{trait} eq 'choice'}
                                                                    @$classes),
  };

  foreach my $gen (@{$opts->{target}}) {

    if (defined TARGETS->{$gen}->{cmp}) {

      next if 0 == $opts->{testDrivers} and 't' eq $gen;

      my $vars = {
          UPPER_UPPER     => \&UPPER_UPPER,
          MixedMixed      => \&MixedMixed,
          mixedMixed      => \&mixedMixed,
          buildSearchTree => \&buildSearchTree,
          formatComment   => \&formatComment,
          opts            => $opts,
          cmp             => $component,
          timestamp       => $timestamp,
          version         => VERSION,
      };

      my $templateFile = TARGETS->{$gen}->{cmp}->{template};

      if ($opts->{print}) {
        print "Generating $gen\n";

        $template->process($templateFile, $vars)
          || die "** ERR: " . $template->error() . "\n";
      } else {
        my $outputFile = $opts->{destination} . '/';

        $outputFile .= $opts->{TARGETS->{$gen}->{cmp}->{key}} . '_'
            if defined TARGETS->{$gen}->{cmp}->{key};

        $outputFile .= lc $opts->{TARGETS->{$gen}->{cmp}->{ext}} . '_'
            if defined TARGETS->{$gen}->{cmp}->{ext} and $opts->{useExtension};

        $outputFile .= $componentName;

        $outputFile .= TARGETS->{$gen}->{cmp}->{suffix}
            if defined TARGETS->{$gen}->{cmp}->{suffix};

        if (! TARGETS->{$gen}->{noOverwrite}
        or  ! -e $outputFile
        or  $opts->{force})
        {
          print "Generating $outputFile\n";

          my $outputText;
          $template->process($templateFile, $vars, \$outputText)
            || die "** ERR: " . $template->error() . "\n";

          if (!$opts->{dualSTL}) {
              bsl2bde($outputText);
          }

          writeFile($outputFile, $outputText);
          chmod(TARGETS->{$gen}->{fileMode} || DEFAULT_FILE_MODE, $outputFile);
        }
      }
    }
  }
}

#----

sub generateSchemaComponents(\%\%\%)
{
  my ($schemaComponents, $annotation, $opts) = @_;

  if (0 == scalar keys %$schemaComponents and defined $opts->{targets}) {
    die "** ERR: No element types defined in the schema\n";
  }

  # Determine whether a dummy message type is needed.
  {
    if (!$opts->{msgExpand}) {
      my $component = length $opts->{msgPrefix} ? lc $opts->{msgPrefix}
                                                : $opts->{msgComponent};
      my $type = MixedMixed($component);

      $opts->{dummyTypeName} = $type;
      $opts->{needDummyType} = not grep { $type eq $_->{name} }
                                        @{$schemaComponents->{$component}};
    }
  }

  my @selectedComponents;

  my @components = scalar @{$opts->{component}} ? @{$opts->{component}}
                                                : keys %$schemaComponents;
  foreach my $component (@components) {
    $component = lc MixedMixed($component);
    if (! defined $schemaComponents->{$component}) {
      die "** ERR: Component '$component' could not be identified\n"
        . "  Hint: --component must be used with --msgExpand\n";
    }

    my $isExternalFlag = 1;
    map { $isExternalFlag &&= $_->{external} }
        @{$schemaComponents->{$component}};

    if ($opts->{recurse} || !$isExternalFlag) {
      my $classes = $schemaComponents->{$component};
#     if (0 == $opts->{recurse}) {
        # Note: filter class types using the heurisitc that non-schema types do
        # not begin with a capital letter.
        $classes = [ grep { not $_->{external}
                            and 'alias' ne $_->{typeCategory}
                            and 'list'  ne $_->{trait}
                            and $_->{cpptype} =~ m/[A-Z]/o }
                          @{$schemaComponents->{$component}} ];
#     }

      generateSchemaComponent($component, %$annotation, %$opts, @$classes);
    }
  }
}

#----

sub generateConfig(\%\%)
{
  my ($data, $opts) = @_;

  my $config = {
      INCLUDE_PATH => [ $ENV{BAS_CODEGEN_INCLUDE_PATH}
                      , "$FindBin::Bin/../etc/bas_codegen"
                      , "$FindBin::Bin/" . RELEASE . "/etc/bas_codegen"
                      ],
      INTERPOLATE  => 1,
      EVAL_PERL    => 1,
      FILTERS => {
          UPPER_UPPER => \&UPPER_UPPER,
          MixedMixed  => \&MixedMixed,
          mixedMixed  => \&mixedMixed,
          c_str       => \&c_str,
      }
  };

  my $template = Template->new($config);

  foreach my $gen (@{$opts->{target}}) {

    if (defined TARGETS->{$gen}->{cfg}) {

      my $vars = {
          UPPER_UPPER     => \&UPPER_UPPER,
          MixedMixed      => \&MixedMixed,
          mixedMixed      => \&mixedMixed,
          buildSearchTree => \&buildSearchTree,
          formatComment   => \&formatComment,
          schema          => $data,
          svc             => $data,
          opts            => $opts,
          timestamp       => $timestamp,
          version         => VERSION,
      };

      my $templateFile = TARGETS->{$gen}->{cfg}->{template};

      if ($opts->{print}) {
        $template->process($templateFile, $vars)
          || die "** ERR: " . $template->error() . "\n";
      } else {
        my $outputFile = $opts->{destination} . '/';

        $outputFile .= TARGETS->{$gen}->{cfg}->{prefix}
            if defined TARGETS->{$gen}->{cfg}->{prefix};

        $outputFile .= TARGETS->{$gen}->{cfg}->{name}
            if defined TARGETS->{$gen}->{cfg}->{name};

        $outputFile .= lc $opts->{TARGETS->{$gen}->{cfg}->{key}}
            if defined TARGETS->{$gen}->{cfg}->{key};

        $outputFile .= lc '_' . $opts->{TARGETS->{$gen}->{cfg}->{ext}}
            if defined TARGETS->{$gen}->{cfg}->{ext};

        $outputFile .= lc TARGETS->{$gen}->{cfg}->{suffix}
            if defined TARGETS->{$gen}->{cfg}->{suffix};

        print "Generating $outputFile\n";

        $template->process($templateFile, $vars, $outputFile)
          || die "** ERR: " . $template->error() . "\n";

        chmod(TARGETS->{$gen}->{fileMode} || DEFAULT_FILE_MODE, $outputFile);
      }
    }
  }
}

#----

sub generateService(\%\%\%)
{
  my ($components, $data, $opts) = @_;

  # Isolate components in the application namespace
  my @componentNames;
  foreach my $componentName (keys %$components) {
    my $isExternalFlag = 1;
    map { $isExternalFlag &&= $_->{external} }
        @{$components->{$componentName}};

    push(@componentNames, $componentName) unless $isExternalFlag;
  }

  my $config = {
      INCLUDE_PATH => [ $ENV{BAS_CODEGEN_INCLUDE_PATH}
                      , "$FindBin::Bin/../etc/bas_codegen"
                      , "$FindBin::Bin/" . RELEASE . "/etc/bas_codegen"
                      ],
      INTERPOLATE  => 1,
      EVAL_PERL    => 1,
      FILTERS => {
          UPPER_UPPER => \&UPPER_UPPER,
          MixedMixed  => \&MixedMixed,
          mixedMixed  => \&mixedMixed,
          c_str       => \&c_str,
      }
  };

  my $template = Template->new($config);

  foreach my $gen (@{$opts->{target}}) {

    if (defined TARGETS->{$gen}->{svc}) {

      next if TARGETS->{$gen}->{requiresWsdl} and !$data->{WSDL};

#     next if 0 == $opts->{testDrivers} and TARGETS->{$gen}->{isTestDriver};

      my $vars = {
          UPPER_UPPER     => \&UPPER_UPPER,
          MixedMixed      => \&MixedMixed,
          mixedMixed      => \&mixedMixed,
          buildSearchTree => \&buildSearchTree,
          formatComment   => \&formatComment,
          schema          => $data,
          svc             => $data,
          opts            => $opts,
          componentNames  => \@componentNames,
          timestamp       => $timestamp,
          version         => VERSION,
      };

      my $templateFile = TARGETS->{$gen}->{svc}->{template};

      if ($opts->{print}) {
        print "Generating $gen\n";

        $template->process($templateFile, $vars)
          || die "** ERR: " . $template->error() . "\n";
      } else {
        my $outputFile = $opts->{destination} . '/';

        $outputFile .= TARGETS->{$gen}->{svc}->{prefix}
            if defined TARGETS->{$gen}->{svc}->{prefix};

        $outputFile .= TARGETS->{$gen}->{svc}->{name}
            if defined TARGETS->{$gen}->{svc}->{name};

        $outputFile .= lc $opts->{TARGETS->{$gen}->{svc}->{key}}
            if defined TARGETS->{$gen}->{svc}->{key};

        $outputFile .= lc '_' . $opts->{TARGETS->{$gen}->{svc}->{ext}}
            if defined TARGETS->{$gen}->{svc}->{ext};

        $outputFile .= lc (TARGETS->{$gen}->{svc}->{suffix})
            if defined TARGETS->{$gen}->{svc}->{suffix};

        my $doMergeFlag = defined TARGETS->{$gen}->{merge} || 0;

        if (! TARGETS->{$gen}->{noOverwrite}
        or  ! -e $outputFile
        or  $opts->{force}
        or  $doMergeFlag)
        {
          if ($doMergeFlag and ! $opts->{force}) {
            my $outputText = '';
            $template->process($templateFile, $vars, \$outputText)
              || die "** ERR: " . $template->error() . "\n";

            if (!$opts->{dualSTL}) {
                bsl2bde($outputText);
            }

            if (-e $outputFile) {
              print "Merging    $outputFile\n";
            } else {
              print "Generating $outputFile\n";
            }

            # Kludge: 'mergeMakefile' needs to access the list of components,
            # but the "virtual interface" only takes four parameters.
            $opts->{components} = $vars->{componentNames};

            TARGETS->{$gen}->{merge}->($outputFile, $outputText,
                                       $data, $opts);
            delete $opts->{components};
          } else {
            print "Generating $outputFile\n";
            my $outputText;
            $template->process($templateFile, $vars, \$outputText)
              || die "** ERR: " . $template->error() . "\n";

            if (!$opts->{dualSTL}) {
                bsl2bde($outputText);
            }

            writeFile($outputFile, $outputText);
          }

          chmod(TARGETS->{$gen}->{fileMode} || DEFAULT_FILE_MODE, $outputFile);
        }
      }
    }
  }
}

#----

sub generateApplication(\%\%\%)
{
  my ($components, $data, $opts) = @_;

  # Isolate components in the application namespace
  my @componentNames;
  foreach my $componentName (keys %$components) {
    my $isExternalFlag = 1;
    map { $isExternalFlag &&= $_->{external} }
        @{$components->{$componentName}};

    push(@componentNames, $componentName) unless $isExternalFlag;
  }

  my $config = {
      INCLUDE_PATH => [ $ENV{BAS_CODEGEN_INCLUDE_PATH}
                      , "$FindBin::Bin/../etc/bas_codegen"
                      , "$FindBin::Bin/" . RELEASE . "/etc/bas_codegen"
                      ],
      INTERPOLATE  => 1,
      EVAL_PERL    => 1,
      FILTERS => {
          UPPER_UPPER => \&UPPER_UPPER,
          MixedMixed  => \&MixedMixed,
          mixedMixed  => \&mixedMixed,
          c_str       => \&c_str,
      }
  };

  my $template = Template->new($config);

  foreach my $gen (@{$opts->{target}}) {

    if (defined TARGETS->{$gen}->{app}) {

      next if TARGETS->{$gen}->{requiresBBenv} and  $opts->{noBBEnv};
      next if TARGETS->{$gen}->{requiresWsdl}  and !$data->{WSDL};

      my $vars = {
          UPPER_UPPER     => \&UPPER_UPPER,
          MixedMixed      => \&MixedMixed,
          mixedMixed      => \&mixedMixed,
          buildSearchTree => \&buildSearchTree,
          formatComment   => \&formatComment,
          schema          => $data,
          svc             => $data,
          opts            => $opts,
          componentNames  => \@componentNames,
          timestamp       => $timestamp,
          version         => VERSION,
      };

      my $templateFile = TARGETS->{$gen}->{app}->{template};

      if ($opts->{print}) {
        print "Generating $gen\n";

        $template->process($templateFile, $vars)
          || die "** ERR: " . $template->error() . "\n";
      } else {
        my $outputFile = $opts->{destination} . '/';

        $outputFile .= TARGETS->{$gen}->{app}->{prefix}
            if defined TARGETS->{$gen}->{app}->{prefix};

        $outputFile .= TARGETS->{$gen}->{app}->{name}
            if defined TARGETS->{$gen}->{app}->{name};

        $outputFile .= lc $opts->{TARGETS->{$gen}->{app}->{key}}
            if defined TARGETS->{$gen}->{app}->{key};

        $outputFile .= lc '_' . $opts->{TARGETS->{$gen}->{app}->{ext}}
            if defined TARGETS->{$gen}->{app}->{ext};

        $outputFile .= lc (TARGETS->{$gen}->{app}->{suffix})
            if defined TARGETS->{$gen}->{app}->{suffix};

        my $doMergeFlag = defined TARGETS->{$gen}->{merge} || 0;

        if (! TARGETS->{$gen}->{noOverwrite}
        or  ! -e $outputFile
        or  $opts->{force}
        or  $doMergeFlag)
        {
          if ($doMergeFlag and ! $opts->{force}) {
            my $outputText = '';
            $template->process($templateFile, $vars, \$outputText)
              || die "** ERR: " . $template->error() . "\n";

            if (!$opts->{dualSTL}) {
                bsl2bde($outputText);
            }

            if (-e $outputFile) {
              print "Merging    $outputFile\n";
            } else {
              print "Generating $outputFile\n";
            }

            # Kludge: 'mergeMakefile' needs to access the list of components,
            # but the "virtual interface" only takes four parameters.
            $opts->{components} = $vars->{componentNames};

            TARGETS->{$gen}->{merge}->($outputFile, $outputText,
                                       $data, $opts);
            delete $opts->{components};
          } else {
            print "Generating $outputFile\n";

            my $outputText;
            $template->process($templateFile, $vars, \$outputText)
              || die "** ERR: " . $template->error() . "\n";

            if (!$opts->{dualSTL}) {
                bsl2bde($outputText);
            }

            writeFile($outputFile, $outputText);
          }

          chmod(TARGETS->{$gen}->{fileMode} || DEFAULT_FILE_MODE, $outputFile);
        }
      }
    }
  }
}

#----

sub generateMakefiles(\%\%\%)
{
  my ($components, $data, $opts) = @_;

  my $config = {
      INCLUDE_PATH => [ $ENV{BAS_CODEGEN_INCLUDE_PATH}
                      , "$FindBin::Bin/../etc/bas_codegen"
                      , "$FindBin::Bin/" . RELEASE . "/etc/bas_codegen"
                      ],
      INTERPOLATE  => 1,
      EVAL_PERL    => 1,
      FILTERS => {
          UPPER_UPPER => \&UPPER_UPPER,
          MixedMixed  => \&MixedMixed,
          mixedMixed  => \&mixedMixed,
          c_str       => \&c_str,
      }
  };

  my $template = Template->new($config);

  my $componentNames = [];
  foreach my $component (keys %$components) {

    my $isExternalFlag = 1;
    map { $isExternalFlag &&= $_->{external} }
        @{$components->{$component}};

    my $package = $isExternalFlag
                ? ''
                : $data->{package};

    if ($opts->{recurse} || !$isExternalFlag && $package eq $data->{package}) {
      push(@$componentNames, $component)
          if ($data->{package} eq $package
          and !$components->{$component}->[0]->{configuration});
    }
  }

  foreach my $gen (@{$opts->{target}}) {

    if (defined TARGETS->{$gen}->{plink}) {

      my $vars = {
          UPPER_UPPER     => \&UPPER_UPPER,
          MixedMixed      => \&MixedMixed,
          mixedMixed      => \&mixedMixed,
          buildSearchTree => \&buildSearchTree,
          formatComment   => \&formatComment,
          svc             => $data,
          opts            => $opts,
          componentNames  => $componentNames,
          timestamp       => $timestamp,
          version         => VERSION,
      };

      my $templateFile = TARGETS->{$gen}->{plink}->{template};

      if ($opts->{print}) {
        print "Generating $gen\n";

        $template->process($templateFile, $vars)
          || die "** ERR: " . $template->error() . "\n";
      } else {
        my $outputFile = $opts->{destination} . '/';

        $outputFile .= TARGETS->{$gen}->{plink}->{name}
            if defined TARGETS->{$gen}->{plink}->{name};

        $outputFile .= TARGETS->{$gen}->{plink}->{prefix}
            if defined TARGETS->{$gen}->{plink}->{prefix};

        $outputFile .= lc $data->{TARGETS->{$gen}->{plink}->{key}}
            if defined(TARGETS->{$gen}->{plink}->{key});

        $outputFile .= lc '_' . $data->{TARGETS->{$gen}->{plink}->{ext}}
            if defined(TARGETS->{$gen}->{plink}->{ext});

        $outputFile .= lc (TARGETS->{$gen}->{plink}->{suffix})
            if defined(TARGETS->{$gen}->{plink}->{suffix});

        my $doMergeFlag = defined TARGETS->{$gen}->{merge} || 0;

        if (! TARGETS->{$gen}->{noOverwrite}
        or  ! -e $outputFile
        or  $opts->{force}
        or  $doMergeFlag)
        {
          if ($doMergeFlag and ! $opts->{force}) {
            my $outputText = '';
            $template->process($templateFile, $vars, \$outputText)
              || die "** ERR: " . $template->error() . "\n";

            if (-e $outputFile) {
              print "Merging    $outputFile\n";
            } else {
              print "Generating $outputFile\n";
            }

            # Kludge: 'mergeMakefile' needs to access the list of components,
            # but the "virtual interface" only takes four parameters.
            $opts->{components} = $vars->{componentNames};

            TARGETS->{$gen}->{merge}->($outputFile, $outputText,
                                       $data, $opts);
            delete $opts->{components};
          } else {
            print "Generating $outputFile\n";
            $template->process($templateFile, $vars, $outputFile)
              || die "** ERR: " . $template->error() . "\n";
          }

          chmod(TARGETS->{$gen}->{fileMode} || DEFAULT_FILE_MODE, $outputFile);
        }
      }
    }
  }
}

#------------------------------------------------------------------------------

{ my $hasBeenWarned = 0;
  my %seen;
  my $archcode = qx { uname -p }; chomp $archcode;
sub validateSchema($\%)
{
    my ($schemaFile, $opts) = @_;

    my @BIN = ( $ENV{BAS_CODEGEN_BIN} || ""
               , "$FindBin::Bin/" . RELEASE . "/bin/$archcode"
               , "/bbs/bin");

    my $rapi3tool =  $ENV{BAS_XSDVALIDATOR}
                 || "$BIN[0]/rapi3tool";
       $rapi3tool = "$BIN[1]/rapi3tool" unless -e $rapi3tool;
       $rapi3tool = "$BIN[2]/rapi3tool" unless -e $rapi3tool;

    if (! -e $rapi3tool) {
        warn "* WARN: Failed to find $rapi3tool\n"
        unless $hasBeenWarned or $opts->{noWarnings};

        $hasBeenWarned = 1;
        return;
    }

    print "Validating schema $schemaFile...\n";

    my $schema  = processSchemaFile(%$opts, $schemaFile, 1);
    my $verbose = $opts->{debug} || 0;
    my @errorMessages;
    my @includePaths;

    if ($opts->{showFlatSchema} || 1 < $verbose) {
        my $line = 1;
        print join("\n", map { sprintf("%.4d:  %s", $line++, $_) }
                             split("\n", $schema))
            . "\n";
    }

    local $SIG{PIPE} = 'IGNORE';

    my $command =  "$rapi3tool "
                .  "--mode=validate "
                .  join(' ', map { "-I$_" } @{$opts->{includedir}});
       $command .= " --noRapidValidation"
    if ($opts->{noRapidValidation}
    or  not grep {/app|svc/} @{$opts->{mode}}
    or  $schema =~ m/bdem:configuration='true'/);

    if ($opts->{isWSDL} || $opts->{validateFlatSchema}) {
      open(VALIDATE, "|-", $command)
        || die "Failed to execute rapi3tool: $!\n";

      print VALIDATE $schema || die "Failed to write to rapi3tool: $!\n";
    }
    else {
      open(VALIDATE, '|-', "$command $schemaFile")
        || die "Failed to execute rapi3tool: $!";
    }
    close(VALIDATE);

    if ($?) {
      $hasBeenWarned = 1;

      if ($opts->{allowInvalidSchema}) {
        print("Invalid schema: $?\n");
      } else {
        exit 1;
      }
    }
}}

sub loadElementTypes(\%\%\%$)
{
  my ($data, $elementTypes, $opts, $schemaFile) = @_;

  return if ($opts->{noSchema} or $opts->{cache}->{$schemaFile});

  print "Loading schema from $schemaFile...\n";

  my %eltTypes;  # local "elementTypes"
  my %includes;
  my $tree = loadSchemaFile(%eltTypes, %includes, %$opts, $schemaFile, 0);
  {
    foreach my $key (keys %$tree) {
      unless (defined $data->{$key}) {
        if ("ARRAY" eq ref $tree->{$key}) {
          push @{$data->{$key}}, @{$tree->{$key}};
        } else {
          $data->{$key} = $tree->{$key};
        }
      }
    }
  }

  $data->{text}     = processSchemaFile(%$opts, $schemaFile, 0);
  $data->{flatText} = processSchemaText(%$opts, $data->{text}, 1);

  map { $elementTypes->{$_} = $eltTypes{$_};
        $elementTypes->{$_}->{configuration} = 1 if $data->{configuration};
      } keys %eltTypes;

  my $complexTypes = [ grep { 'complexType' eq $_->{typeCategory} }
                            values %$elementTypes ];
  assignComponentLocations(@$complexTypes, %$elementTypes, %$opts);

  foreach my $elementType (values %$elementTypes) {
    adjustElementType($data->{package}, $elementType, %$elementTypes, %$opts);
  }

  foreach my $elementType (values %$elementTypes) {
    adjustElementTypeFieldOrder($elementType, %$opts);
  }

  deduceAllocatesMemory(%$opts, %$elementTypes);

  $opts->{cache}->{$schemaFile} = 1;
  $opts->{package} = $data->{package};
# $opts->{msgLibrary} = $opts->{basePackage}
  $opts->{msgLibrary} = "UNSPECIFIED"
      unless defined $opts->{msgLibrary};
}

sub parseSchema(\%\%\%\%$)
{
  my ($data, $components, $elementTypes, $opts, $schemaFile) = @_;

  unless($opts->{noSchema} or $opts->{cache}->{$schemaFile}) {
    loadElementTypes(%$data, %$elementTypes, %$opts, $schemaFile);
    loadComponents(%$components, %$elementTypes, %$opts);

    adjustAnnotation($data);

    if (0 < $opts->{debug}) {
      foreach my $c (keys %$components) {
        print "Component: $c = ";
        print "[", join(', ', map { "$$_{cpptype} = $$_{level}" }
                                  grep { !$_->{external} }
                                       @{$components->{$c}}), "]\n";
      }
    }
    print Dumper($components) if 2 < $opts->{debug};
  }
  else {
    $opts->{package}     = $data->{package};
    $opts->{msgLibrary}  = $opts->{basePackage}
        unless defined $opts->{msgLibrary};
  }

  if ($data->{configuration}) {
  $opts->{checkPackageName}   and checkPackageName(%$data, %$opts);
  } else {
  $opts->{checkServiceName}   and checkServiceName(%$data, %$opts);
  $opts->{checkPackageName}   and checkPackageName(%$data, %$opts);
  $opts->{checkTopLevelTypes} and checkTopLevelTypes(%$data,
                                                     %$elementTypes,
                                                     %$opts);
  }
}

# Find the request and response elements in the $data hash and add keys to
# the hash such that:
#   assert( defined $data->{requestElement} )
#   assert( defined $data->{responseElement} )
sub populateRequestResponseElements(\%$$$)
{
  my ($data, $msgPrefix, $requestType, $responseType) = @_;

  # Find request and response elements.
  if ($data->{WSDL}) {
    $data->{requestElement}  = $data->{portType}->[0]->{name} . "Request";
    $data->{responseElement} = $data->{portType}->[0]->{name} . "Response";
  }
  else {
    foreach (@{$data->{element}}) {
      my (undef, $type) = $_->{type} =~ m/^(\w+:)?(.+)/;
      $type = $msgPrefix . MixedMixed($type);

      if ($type eq $requestType)  { $data->{requestElement}  = $_->{name}; }
      if ($type eq $responseType) { $data->{responseElement} = $_->{name}; }
    }
  }
}

sub loadRequestData(\%\%\%)
{
  my ($data, $elementTypes, $opts) = @_;

  $data->{requestElement}  = '' unless defined $data->{requestElement};
  $data->{responseElement} = '' unless defined $data->{responseElelement};

  if ($opts->{noSchema}) {
    $data->{requestType}  = 'bcema_Blob';
    $data->{responseType} = 'bcema_Blob';
    return;                                                            # RETURN
  }

  my $requestType  = $opts->{msgPrefix} . MixedMixed($data->{requestType});
  my $responseType = $opts->{msgPrefix} . MixedMixed($data->{responseType});

  if ($data->{WSDL}) {
    $requestType  =~ s/(.+Request)/request\$\$$1/;
    $responseType =~ s/(.+Response)/response\$\$$1/;
  }
  $data->{requestType}  = $requestType;
  $data->{responseType} = $responseType;

  populateRequestResponseElements(%$data,
                                  $opts->{msgPrefix},
                                  $requestType,
                                  $responseType);

  if (defined($elementTypes->{$requestType}) and ! $data->{configuration}) {
    $data->{requests} =
        [ map { my $ipt = isPrimitiveType($_->{cpptype}, $_);
                { name            => MixedMixed($_->{name}),
                  memberName      => $_->{memberName},
                  argumentName    => mixedMixed($_->{argumentName})||'request',
                  type            => $_->{cpptype},
                  isPrimitiveFlag => $ipt,
                  isVectorFlag    => $ipt ? 0 : $_->{isVectorFlag},
                  noNamespaceFlag => $ipt ? 1 : $_->{noNamespaceFlag},
                } } @{$elementTypes->{$requestType}->{choice}} ];
    $data->{numRequests} = scalar @{$data->{requests}};

    { my %h;
      map { $h{$_->{typeref}->{component}} = 1
            if exists $_->{typeref}->{component} }
          @{$elementTypes->{$requestType}->{choice}};
      my $rc = [ sort keys %h ];
      unshift @{$rc}, $elementTypes->{$requestType}->{component}
          if $opts->{msgExpand};
      $data->{requestComponents} = $rc;
    }

    $data->{requestAllocatesMemory} = 0;
    if (defined($elementTypes->{$requestType}->{allocatesMemory})) {
      $data->{requestAllocatesMemory} =
          $elementTypes->{$requestType}->{allocatesMemory};
    }

    $data->{responses} =
        [ map { my $ipt = isPrimitiveType($_->{cpptype}, $_);
                { name            => MixedMixed($_->{name}),
                  memberName      => $_->{memberName},
                  type            => $_->{cpptype},
                  isPrimitiveFlag => $ipt,
                  isVectorFlag    => $ipt ? 0 : $_->{isVectorFlag},
                  noNamespaceFlag => $ipt ? 1 : $_->{noNamespaceFlag},
                } } @{$elementTypes->{$responseType}->{choice}} ];
    $data->{numResponses} = scalar @{$data->{responses}};

    { my %h;
      map { $h{$_->{typeref}->{component}} = 1
            if exists $_->{typeref}->{component} }
          @{$elementTypes->{$responseType}->{choice}};
      my $rc = [ sort keys %h ];
      unshift @{$rc}, $elementTypes->{$responseType}->{component}
          if $opts->{msgExpand};
      $data->{responseComponents} = $rc;
    }

    $data->{responseAllocatesMemory} = 0;
    if (defined($elementTypes->{$responseType}->{allocatesMemory})) {
      $data->{responseAllocatesMemory} =
          $elementTypes->{$responseType}->{allocatesMemory};
    }

    # Adjust top-level types.
    $data->{requestType}  =~ s/^[^\$]+\$\$//;
    $data->{responseType} =~ s/^[^\$]+\$\$//;
  }
}

MAIN:
{
  my $opts = getoptions();
  my $verbose = $opts->{debug} || 0;

  push(@{$opts->{includedir}}, split(/:/, $ENV{BAS_CODEGEN_INCLUDE_PATH}))
      if defined $ENV{BAS_CODEGEN_INCLUDE_PATH};

  # TBD: replace with BDE::Path
  my $BDE_ROOT = $ENV{BDE_ROOT} || '';
  push(@{$opts->{includedir}},
       ("$BDE_ROOT/groups/bde/bdem",
        "$BDE_ROOT/groups/bae/baexml",
        "$BDE_ROOT/groups/bas/basapi",
        "$BDE_ROOT/groups/bas/bascfg",
        "/bbsrc/proot/include/00depbuild",
        "/bbsrc/proot/include/00deployed",
        "/bbsrc/bbinc/Cinclude/bde"
       ));

  my %data;
  my %elementTypes;
  my %components;

  if ($opts->{noSchema}) {
    die "** ERR: Please specify --serviceName option\n"
        unless defined $opts->{serviceName};

    $data{package} =  $opts->{package}
                   || derivePackageNameFromServiceName($opts->{serviceName});

    $opts->{package} = $data{package};

    warn "* WARN: Deriving package name from service name: "
       . "$data{package}\n"
        unless defined $opts->{package} or $opts->{noWarnings};

    $data{serviceName}         = $opts->{serviceName};
    $data{serviceId}           = $opts->{serviceId};
    $data{serviceVersionMajor} = $opts->{serviceVersionMajor};
    $data{serviceVersionMinor} = $opts->{serviceVersionMinor};
    $data{msgLibrary}          = $data{package};
    $data{targetNamespace}     = 'urn:x-bloomberg-com:BAS.services.'
                               . lc $data{serviceName};

    unless ($authorInfo) {
      $authorInfo = $opts->{author}
                 || getAuthorInfo(%$opts)
                 || sprintf('Author Unknown (Unix login: %s)', getpwuid($>));
    }
    $data{author}   = $authorInfo;
    $opts->{author} = $data{author};

    $opts->{msgLibrary} = $data{msgLibrary};
  }

  if ($opts->{noTimestamps}) {
    $timestamp = '';
  }

  while (my $mode = shift @{$opts->{mode}}) {
    adjustOpts(%$opts, $mode);
    $opts->{currentMode} = $mode;

    my $schemaFile = $opts->{schemaFile}->[0];

    # "Switch" on mode:
SWITCH:
    {
      if ($mode eq 'validate') {
        validateSchema($schemaFile, %$opts) unless $opts->{noSchema};
        last;
      }

      if ($mode eq 'cmp') {
        unless ($opts->{noSchema}) {
          warn "* WARN: Generating case-insensitive message components.\n"
             . "        Specify '--ignoreCase=n' if this is not needed.\n"
             . "        See 'perldoc bas_codegen.pl' for more details.\n"
             if ( $opts->{ignoreCase}
              && !$opts->{noWarnings});
          parseSchema(%data, %components, %elementTypes, %$opts, $schemaFile);
          $opts->{validate} = 1;
          generateSchemaComponents(%components, %{$data{annotation}}, %$opts);
          last;
        }
      };

      if ($mode eq 'msg') {
        unless ($opts->{noSchema}) {
          warn "* WARN: Generating case-insensitive message components.\n"
             . "        Specify '--ignoreCase=n' if this is not needed.\n"
             . "        See 'perldoc bas_codegen.pl' for more details.\n"
             if ( $opts->{ignoreCase}
              && !$opts->{noWarnings});
          parseSchema(%data, %components, %elementTypes, %$opts, $schemaFile);
          $opts->{validate} = 1;
          generateSchemaComponents(%components, %{$data{annotation}}, %$opts);
        }

        if ( $opts->{appModeFlag}
        and  $opts->{configSchema}
        and !$opts->{genOverride})
        {
          my $schemaFile = $opts->{destination}
                         . '/'
                         . lc $data{serviceName}
                         . '_cfg.xsd';
          push @{$opts->{mode}}, 'cfg';
          $opts->{target} = [];
          $opts->{schemaFile} = [ $schemaFile ];
          local $opts->{noSchema} = 0;
          %data = ();
        }

        last;
      };

      if ($mode eq 'svc') {
        parseSchema(%data, %components, %elementTypes, %$opts, $schemaFile);
        checkTopLevelTypes(%data, %elementTypes, %$opts);
        loadRequestData(%data, %elementTypes, %$opts);

        generateService(%components, %data, %$opts);
        generateMakefiles(%components, %data, %$opts);

        last;
      }

      if ($mode eq 'app') {
        parseSchema(%data, %components, %elementTypes, %$opts, $schemaFile);
        checkTopLevelTypes(%data, %elementTypes, %$opts);
        loadRequestData(%data, %elementTypes, %$opts);

        # Define 'targetNamespace' and 'tns' so that generated configuration
        # schema file is valid.
        unless (defined $data{targetNamespace} or defined $data{xmlns}) {
          $data{targetNamespace} = "urn:x-bloomberg-com:BAS.services."
                                 . $data{serviceName};
          $data{tns} = $data{targetNamespace} unless defined $data{tns};
        }

        $opts->{msgLibrary}   = lc $opts->{serviceName}
            unless defined $opts->{msgLibrary};
        $opts->{package}      = lc $opts->{serviceName}
            unless defined $opts->{package};
        generateApplication(%components, %data, %$opts);
        generateMakefiles(%components, %data, %$opts);

        if (!$opts->{msgModeFlag}
        and  $opts->{configSchema}
        and !$opts->{genOverride})
        {
          my $schemaFile = $opts->{destination}
                         . '/'
                         . lc $data{serviceName}
                         . '_cfg.xsd';
          push @{$opts->{mode}}, 'cfg';
          $opts->{target} = [];
          $opts->{schemaFile} = [ $schemaFile ];
          local $opts->{noSchema} = 0;
          %data = ();
        }

        last;
      }

      if ($mode eq 'cfg') {
        $opts->{msgPrefix} = '';
        $opts->{validate}  = 1;
        validateSchema($schemaFile, %$opts);
        parseSchema(%data, %components, %elementTypes, %$opts, $schemaFile);
        $opts->{msgLibrary}   = lc $opts->{serviceName}
            unless defined $opts->{msgLibrary};
        $opts->{package}      = lc $opts->{serviceName}
            unless defined $opts->{package};
        generateConfig(%data, %$opts);
        last;
      }
    }
    $opts->{$mode} = 0;
  }
}

#==============================================================================

sub writeFile($$)
{
  my ($filename, $text) = @_;

  $? = 0;
  $SIG{PIPE} = 'IGNORE';
  my $path = dirname($filename);
  `/bin/mkdir -p $path`;
  open(FILE, ">$filename") || die "** ERR: Failed to write $filename: $!\n";
  print FILE $text;
  close(FILE);
  die "** ERR: Failed to write $filename: $!\n" if $?;
}

sub adjustTypeHistory(\%\@\$\$\%)
{
  # Discover new request elements and new request element types.

  my ($history, $data, $numNewRequests, $numNewRequestTypes, $opts) = @_;

  foreach my $element (@$data) {
    # TBD: For some awful reason, msgns is only applied to wrapped types in
    # the generator, and patched for "regular" types in the templates.
    my $msgns = $opts->{msgLibrary} . "::";
       $msgns = '' if $opts->{package} eq $opts->{msgLibrary}
                   or $element->{noNamespaceFlag};
    my $entry = {};

    if (!defined $history->{$element->{name}}) {
      $entry->{prevType}            = undef;
      $entry->{prevTypeIsPrimitive} = undef;
      $entry->{currType}            = $msgns . $element->{type};
      $entry->{currTypeIsPrimitive} = $element->{isPrimitiveFlag};
      $entry->{currTypeIsVector}    = $element->{isVectorFlag};
      $entry->{isNew}               = 1;
      $entry->{hasNewType}          = 0;

      $history->{$element->{name}}  = $entry;

      ++$$numNewRequests;
    }
    else {
      $entry = $history->{$element->{name}};

      $entry->{currType} = $msgns . $element->{type};
      $entry->{currTypeIsPrimitive} = $element->{isPrimitiveFlag};
      $entry->{currTypeIsVector} = $element->{isVectorFlag};
      if ($entry->{prevType} ne $entry->{currType}) {
        $entry->{hasNewType} = 1;
        ++$$numNewRequestTypes;
      }
    }

    if ($entry->{currTypeIsPrimitive}) {
      $entry->{currTypeParam} = $element->{type};
    }
    else {
      $entry->{currTypeParam} = "const $msgns$$element{type}&";
    }
  }
}

sub mergeRequestProcessor_h($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  my $currentText;
  my $mergedText;

  my %history; # map of request element name to request type history

  my $numNewRequests     = 0;
  my $numNewRequestTypes = 0;

  my %newRequestCode;

  # Load the existing file
  local $/ = undef;
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText  = <$current>;
  $currentText = $mergedText;
  $currentText =~ s/^.*    \/\/ Messages//s;

  # Find all the previously generated request types
  while ($currentText =~
         m/void process(\w+)\(\s*((bdema_ManagedPtr<(.+?>?)[ ]?>&)|(unsigned \w+|.+?)&?)[ ]+\w+/gs)
  {
    my $entry  = {};
    my $method = $1;

    $entry->{prevType}            = $4 || $5;
    $entry->{prevTypeIsPrimitive} = defined $3 ? 0 : 1;
    $entry->{prevTypeIsVector}    = $entry->{prevType} =~ m/(std|bsl)::vector/;
    $entry->{currType}            = undef;
    $entry->{currTypeIsPrimitive} = undef;
    $entry->{currTypeIsVector}    = undef;
    $entry->{isNew}               = 0;
    $entry->{hasNewType}          = 0;

    $history{$method} = $entry;
  }

  # Discover new request elements and new request element types
  adjustTypeHistory(%history, @{$data->{requests}},
                    $numNewRequests, $numNewRequestTypes, %$opts);

  return if (($numNewRequests <= 0) && ($numNewRequestTypes <= 0));

  # Map text to new requests
  $newText =~ s/^.*    \/\/ Messages//s;
  while ($newText =~ m/(\n    void process([^\(]+).+?;)/gs) {
    $newRequestCode{$2} = $1 if $history{$2}->{isNew};
  }
  my $mergeText = join "\n", values %newRequestCode;

  # Update request elements with new their types
  while (my ($reqElement, $reqEntry) = each(%history)) {
    next if ($reqEntry->{hasNewType} == 0);

    my $search;
    if ($reqEntry->{prevTypeIsPrimitive}) {
      $search = qr{void process$reqElement\(\n[ ]{12}$$reqEntry{prevType}\s*}s;
    }
    else {
      my $sp = $reqEntry->{prevTypeIsVector} ? ' ' : '';
      $search = qr{void process$reqElement\(\n[ ]{12}bdema_ManagedPtr<$$reqEntry{prevType}$sp>&\s*}s;
    }

    my $replace;
    if ($reqEntry->{currTypeIsPrimitive}) {
      $replace = "void process$reqElement\(\n"
               . "            $$reqEntry{currType} ";
    }
    else {
      my $sp = $reqEntry->{currTypeIsVector} ? ' ' : '';
      $replace = "void process$reqElement\(\n"
               . "            bdema_ManagedPtr<$$reqEntry{currType}$sp>& ";
    }

    my $rc = $mergedText =~ s/$search/$replace/gs;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed function signature of 'process$reqElement'?\n";
      return;
    }
  }

  # Merge the generated code for each new request element
  if ($numNewRequests > 0) {
    my $rc = $mergedText =~ s/(([ ]{8}(\/\/.*?\n)){2,}\};)/$mergeText\n$1/;
    if (0 == $rc) {
        warn "* WARN: Failed to merge $outputFile\n"
           . "  HINT: Malformed block comment?\n";
        return;
    }
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeRequestProcessor_cpp($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  my $currentText;
  my $mergedText;

  my %history; # map of request element name to request type history

  my $numNewRequests     = 0;
  my $numNewRequestTypes = 0;

  my %newRequestCode;

  # Load the existing file
  local $/ = undef;
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText  = <$current>;
  $currentText = $mergedText;
  $currentText =~ s/^.*
                    void\ RequestProcessor::processControlEvent\(.+?\}\n
                    \n
                    void
                   /void/sx;

  # Find all the previously generated request types
  while ($currentText =~
    m/void RequestProcessor::process(\w+)\(\s*((bdema_ManagedPtr<(.+?>?)[ ]?>&)|(unsigned \w+|.+?)&?)[ ]+\w+/gs)
  {
    my $entry  = {};
    my $method = $1;

    $entry->{prevType}            = $4 || $5;
    $entry->{prevTypeIsPrimitive} = defined $3 ? 0 : 1;
    $entry->{prevTypeIsVector}    = $entry->{prevType} =~ m/(std|bsl)::vector/;
    $entry->{currType}            = undef;
    $entry->{currTypeIsPrimitive} = undef;
    $entry->{currTypeIsVector}    = undef;
    $entry->{isNew}               = 0;
    $entry->{hasNewType}          = 0;

    $history{$method} = $entry;
  }

  # Discover new request elements and new request element types
  adjustTypeHistory(%history, @{$data->{requests}},
                    $numNewRequests, $numNewRequestTypes, %$opts);

  return if (($numNewRequests <= 0) && ($numNewRequestTypes <= 0));    # RETURN

  # Update request elements with new their types.
  while (my ($reqElement, $reqEntry) = each(%history)) {
    next if ($reqEntry->{hasNewType} == 0);

    my $search;
    if ($reqEntry->{prevTypeIsPrimitive}) {
      $search = qr{void RequestProcessor::process$reqElement\(\n[ ]{8}$$reqEntry{prevType}\s*}s;
    }
    else {
      my $sp = $reqEntry->{prevTypeIsVector} ? ' ' : '';
      $search = qr{void RequestProcessor::process$reqElement\(\n[ ]{8}bdema_ManagedPtr<$$reqEntry{prevType}$sp>&\s*}s;
    }

    my $replace;
    if ($reqEntry->{currTypeIsPrimitive}) {
      $replace = "void RequestProcessor::process$reqElement\(\n"
               . "        $$reqEntry{currType} ";
    }
    else {
      my $sp = $reqEntry->{currTypeIsVector} ? ' ' : '';
      $replace = "void RequestProcessor::process$reqElement\(\n"
               . "        bdema_ManagedPtr<$$reqEntry{currType}$sp>& ";
    }

    my $rc = $mergedText =~ s/$search/$replace/gs;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed function signature of 'process$reqElement'?\n";
      return;
    }
  }

  # Map text to new requests
  $newText =~ s/^.*
                void\ RequestProcessor::processControlEvent\(.+?\}\n
                \n
                void
               /void/sx;
  while ($newText =~ m/(void RequestProcessor::process([^\(]+).+?\n\}\n)/gs) {
    $newRequestCode{$2} = $1 if $history{$2}->{isNew};
  }

  # Merge the generated code for each new request element
  if ($numNewRequests > 0) {
    my $mergeText = join "\n", values %newRequestCode;
    my $rc = $mergedText =~
                   s/\}\n(\n*\}  \/\/ close namespace)/\}\n\n$mergeText$1/;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed comment for closing package namespace?\n";
      return;
    }
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub max
{
    my ($max) = shift(@_);
    foreach my $param (@_) {
        $max = $param if $param > $max;
    }
    return $max;
}

sub indent
{
  my ($level) = @_;
  my $result = "";
  while ($level-- > 0) {
    $result .= " ";
  }
  return $result;
}

sub alignParam
{
  my ($indentation, $alignmentCol, $paramType, $paramName, $isLast) = @_;
  my $s = "\n"
        . indent($indentation);
  $s .= "$paramType" . indent($alignmentCol - length $paramType) . "$paramName";
  $s .= "," unless $isLast;
  return $s;
}

sub mergeRequestContext_h($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  return if $opts->{noSchema};

  my $currentText;
  my $mergedText;

  my %history; # map of response element name to response type history

  my $numNewResponses     = 0;
  my $numNewResponseTypes = 0;

  my %newResponseCode;

  # Load the existing file
  local $/ = undef;
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText  = <$current>;
  $currentText = $mergedText;

  # Find all the previously generated response types
  while ($currentText =~
      m/int deliver(\w+)\(\s*((const)\s+(\w.+?)&|((unsigned )?\w.+?))[ ]/gs)
  {
    my $entry  = {};
    my $method = $1;

    $entry->{prevType}            = $4 || $5;
    $entry->{prevTypeIsPrimitive} = defined $3 ? 0 : 1;
    $entry->{prevTypeIsVector}    = $entry->{prevType} =~ m/(std|bsl)::vector/;
    $entry->{currType}            = undef;
    $entry->{currTypeIsPrimitive} = undef;
    $entry->{currTypeIsVector}    = undef;
    $entry->{currTypeParam}       = undef;
    $entry->{isNew}               = 0;
    $entry->{hasNewType}          = 0;

    next if  'Error'           eq $method
         and 'bsct::ErrorInfo' eq $entry->{prevType};

    $history{$method} = $entry;
  }

  # Discover new response elements and new response element types
  adjustTypeHistory(%history, @{$data->{responses}},
                    $numNewResponses, $numNewResponseTypes, %$opts);

  return if (($numNewResponses <= 0) && ($numNewResponseTypes <= 0));  # RETURN

  # Update request elements with new their types
  while (my ($rspElement, $rspEntry) = each(%history)) {
    next if ($rspEntry->{hasNewType} == 0);

    my $search;
    if ($rspEntry->{prevTypeIsPrimitive}) {
      $search = qr{int deliver$rspElement\(\n[ ]{12}$$rspEntry{prevType}\s*response,\s*bool\s*isFinal}s;
    }
    else {
      $search = qr{int deliver$rspElement\(\n[ ]{12}const $$rspEntry{prevType}&\s*response,\s*bool\s*isFinal}s;
    }

    my $col     = max(length $rspEntry->{currTypeParam}, length "bool") + 1;
    my $replace = "int deliver$rspElement\("
             . alignParam(12, $col, $rspEntry->{currTypeParam}, "response", 0)
             . alignParam(12, $col, "bool",                     "isFinal",  1);

    my $rc = $mergedText =~ s/$search/$replace/gs;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed function signature of 'deliver$rspElement'?\n";
      return;
    }
  }

  # Merge the generated code for each new response element
  if ($numNewResponses > 0) {
    while ($newText =~ m/(    int deliver([^\(]+).+?;)/gs) {
      $newResponseCode{$2} = $1 if $history{$2}->{isNew};
    }

    my $mergeText = join "\n\n", values %newResponseCode;
    my $insertTarget = "    int deliverResponse";

    $mergedText =~ s/$insertTarget/$mergeText\n\n$insertTarget/;
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeRequestContext_cpp($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  my $currentText;
  my $mergedText;

  my %history; # map of response element name to response type history

  my $numNewResponses     = 0;
  my $numNewResponseTypes = 0;

  my %newResponseCode;

  # Load the existing file
  local $/ = undef;
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText  = <$current>;
  $currentText = $mergedText;

  # Find all the previously generated response types
  while ($currentText =~
  m/int RequestContext::deliver(\w+)\(\s*((const)\s+(\w.+?)&|((unsigned )?\w.+?))[ ]/gs)
  {
    my $entry  = {};
    my $method = $1;

    $entry->{prevType}            = $4 ||$5;
    $entry->{prevTypeIsPrimitive} = defined $3 ? 0 : 1;
    $entry->{prevTypeIsVector}    = $entry->{prevType} =~ m/(std|bsl)::vector/;
    $entry->{currType}            = undef;
    $entry->{currTypeIsPrimitive} = undef;
    $entry->{currTypeIsVector}    = undef;
    $entry->{currTypeParam}       = undef;
    $entry->{isNew}               = 0;
    $entry->{hasNewType}          = 0;

    next if  'Error'           eq $method
         and 'bsct::ErrorInfo' eq $entry->{prevType};

    $history{$method} = $entry;
  }

  # Discover new response elements and new response element types
  adjustTypeHistory(%history, @{$data->{responses}},
                    $numNewResponses, $numNewResponseTypes, %$opts);

  return if (($numNewResponses <= 0) && ($numNewResponseTypes <= 0));  # RETURN

  # Update response elements with their new types
  while (my ($rspElement, $rspEntry) = each(%history)) {
    next if ($rspEntry->{hasNewType} == 0);

    my $search;
    if ($rspEntry->{prevTypeIsPrimitive}) {
      $search = qr{int RequestContext::deliver$rspElement\(\n[ ]{8}$$rspEntry{prevType}\s*response,\s*bool\s*isFinal}s;
    }
    else {
      $search = qr{int RequestContext::deliver$rspElement\(\n[ ]{8}const $$rspEntry{prevType}&\s*response,\s*bool\s*isFinal}s;
    }

    my $col     = max(length $rspEntry->{currTypeParam}, length "bool") + 1;
    my $replace = "int RequestContext::deliver$rspElement\("
              . alignParam(8, $col, $rspEntry->{currTypeParam}, "response", 0)
              . alignParam(8, $col, "bool",                     "isFinal",  1);

    my $rc = $mergedText =~ s/$search/$replace/gs;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed function signature of 'deliver$rspElement'?\n";
      return;
    }
  }

  # Merge the generated code for each new request element
  if ($numNewResponses > 0) {
    while ($newText =~ m/(int RequestContext::deliver([^\(]+).+?\n\}\n)/gs) {
      $newResponseCode{$2} = $1 if $history{$2}->{isNew};
    }

    my $mergeText = join "\n", values %newResponseCode;
    my $insertTarget = "int RequestContext::deliverResponse";

    $mergedText =~ s/$insertTarget/$mergeText\n$insertTarget/;
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeRequestRouter_cpp($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  return if $opts->{noSchema};

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  my $currentText;
  my $mergedText;

  my %history; # map of request element name to request type history

  my $numNewRequests     = 0;
  my $numNewRequestTypes = 0;

  my %newRequestCode;

  # Load the existing file
  local $/ = undef;
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText  = <$current>;
  $currentText = $mergedText;
  my $tag = 'CHANGE\ ONLY\ ARGUMENTS\ TO\ METHOD\ CALLS\ IN\ CODE';
  $currentText =~ s/^.*$tag\ BELOW (.+?) $tag\ ABOVE/$1/sx;
  $currentText = $1;   # why?

  # Find all the previously generated request types
  while ($currentText =~
    m/case Msg::SELECTION_ID_([^:]+): \{\s*((bdema_ManagedPtr<(([^>]+>?)[ ]?>))|((unsigned )?[\w:]+))/gs)
  {

    my $entry  = {};
    my $method = MixedMixed($1);

    $entry->{prevType}            = $5 || $6;
    $entry->{prevTypeIsPrimitive} = defined $5 ? 0 : 1;
    $entry->{prevTypeIsVector}    = $entry->{prevType} =~ m/(std|bsl)::vector/;
    $entry->{currType}            = undef;
    $entry->{currTypeIsPrimitive} = undef;
    $entry->{currTypeIsVector}    = undef;
    $entry->{isNew}               = 0;
    $entry->{hasNewType}          = 0;

    $history{$method} = $entry;
  }

  # Discover new request elements and new request element types
  adjustTypeHistory(%history, @{$data->{requests}},
                    $numNewRequests, $numNewRequestTypes, %$opts);

  return if (($numNewRequests <= 0) && ($numNewRequestTypes <= 0));    # RETURN

  # Update request elements with new their types.
  while (my ($reqElement, $reqEntry) = each(%history)) {
    next if ($reqEntry->{hasNewType} == 0);

    my $search;
    my $accessor = mixedMixed($reqElement);
    if ($reqEntry->{prevTypeIsPrimitive}) {
      $search = qr{\Q$$reqEntry{prevType} requestValue =\E\n
                     [ ]{16}request->$accessor\(\);\n
                     [ ]{8}d_requestProcessor_mp->process$reqElement\(
                             requestValue,\ context\);
                  }sx;
    }
    else {
      my $sp = $reqEntry->{prevTypeIsVector} ? ' ' : '';
      $search = qr{\Qbdema_ManagedPtr<$$reqEntry{prevType}$sp>\E\n
                     [ ]{12}request_mp\(request,\ \&request->$accessor\(\)\);\n
                     [ ]{8}d_requestProcessor_mp->process$reqElement\(
                             request_mp,\ context\);
                  }sx;
    }

    my $replace;
    if ($reqEntry->{currTypeIsPrimitive}) {
      $replace = "$$reqEntry{currType} requestValue =\n"
               . " " x 16 . "request->$accessor();\n"
               . " " x 8  . "d_requestProcessor_mp->process$reqElement("
               .                                     "requestValue, context);";
    }
    else {
      my $sp = $reqEntry->{currTypeIsVector} ? ' ' : '';
      $replace = "bdema_ManagedPtr<$$reqEntry{currType}$sp>\n"
               . " " x 12 . "request_mp(request, &"."request->$accessor());\n"
               . " " x 8  . "d_requestProcessor_mp->process$reqElement("
               .                                       "request_mp, context);";
    }

    my $rc = $mergedText =~ s/$search/$replace/gs;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed function signature of 'process$reqElement'?\n";
      return;
    }
  }

  # Map text to new requests
  $newText =~ s/^.*$tag\ BELOW (.+?) $tag\ ABOVE/$1/sx;
  $newText = $1;   # why?

  while ($newText =~ m/([ ]*case Msg::SELECTION_ID_([^:]+): {.*?}  break;)\n/gs) {
    my $method = MixedMixed($2);
    $newRequestCode{$method} = $1 if $history{$method}->{isNew};
  }

  # Merge the generated code for each new request element
  if ($numNewRequests > 0) {
    my $mergeText = join "\n", values %newRequestCode;
    my $rc = $mergedText =~
                   s/[ ]{6}default: \{\n/$mergeText\n$MATCH/;
    if (0 == $rc) {
      warn "* WARN: Failed to merge $outputFile\n"
         . "  HINT: Malformed comment for closing package namespace?\n";
      return;
    }
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeMakefile($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  # Slurp current text.
  local $/ = undef;    # slurp
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  my $mergedText = <$current>;

  # Merge new component list, and publish.
  my $mergeText = '';
  if (!$opts->{noSchema}) {
  if ($data->{package} eq $opts->{msgLibrary}) {
    $mergeText =
        join "\n", map { $opts->{msgLibrary} . "_" . $_ . ".o \\"}
                       @{$opts->{components}};
    $mergeText .= "\n";
  }}

  $mergedText =~ s/MSGOBJS=\\\n((\w+\.o \\\n)*)\n/MSGOBJS=\\\n$mergeText\n/s;

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeManifest_cpp($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  return if $opts->{noSchema};

  my $currentText;
  my $mergedText;

  local $/ = undef;    # slurp
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  my $schemaString = c_str($data->{text});
  $mergedText = <$current>;
  $mergedText =~ s/const\ char\ SCHEMA\[\]\ =\n(".*?"\n;)
                  /const char SCHEMA[] =\n$schemaString;/sx;

  my $svmaj = $data->{serviceVersionMajor};
  my $svmin = $data->{serviceVersionMinor};

  if (1 != $svmaj || 0 != $svmin) {
  $mergedText =~ s/(const int   Manifest::d_majorVersion\s*=) \d+;/$1 $svmaj;/;
  $mergedText =~ s/(const int   Manifest::d_minorVersion\s*=) \d+;/$1 $svmin;/;
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeVersionTag_h($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  return if $opts->{noSchema};

  my $currentText;
  my $mergedText;

  local $/ = undef;    # slurp
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText = <$current>;

  my $svmaj = $data->{serviceVersionMajor};
  my $svmin = $data->{serviceVersionMinor};

  my ($cmaj, $cmin) = (undef, undef);
  if ($mergedText =~ m/\#define\ [A-Z0-9_]+_VERSION_MAJOR\ (\d+)\n.*\n
                       \#define\ [A-Z0-9_]+_VERSION_MINOR\ (\d+)/sx)
  {
    $cmaj = $1;
    $cmin = $2;
  }

  if (!defined $cmaj || !defined $cmin) {
    warn "* WARN: Failed to merge $outputFile\n"
       . "  HINT: Malformed version macros?\n";
    return;
  }

  if ($svmaj > $cmaj || $svmin > $cmin) {
    $mergedText =~ s/(#define [A-Z0-9_]+_VERSION_MAJOR) \d+/$1 $svmaj/;
    $mergedText =~ s/(#define [A-Z0-9_]+_VERSION_MINOR) \d+/$1 $svmin/;
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

sub mergeMain($$\%\%)
{
  my ($outputFile, $newText, $data, $opts) = @_;

  if (! -e $outputFile) {
    writeFile($outputFile, $newText);
    return;                                                            # RETURN
  }

  return if $opts->{configSchema};

  my $currentText;
  my $mergedText;

  local $/ = undef;    # slurp
  my $current = new IO::File "< $outputFile"
  || die "** ERR: Failed to read $outputFile\n";

  $mergedText = <$current>;

  if ($data->{configuration}) {
      # A real configuration schema file was specified
      my $schemaText = c_str($data->{text});
      $mergedText =~ s/const\ char\ CONFIG_SCHEMA\[\]\ =\s*\n(".*?"\n;)
                      /const char CONFIG_SCHEMA[] =\n$schemaText;/sx;
  }

  my $genInfo = VERSION . " $timestamp";
  $mergedText =~ s/GENERATED BY.*?\n/GENERATED BY $genInfo\n/sm;

  writeFile($outputFile, $mergedText);
}

#==============================================================================

=head1 NAME

B<bas_codegen.pl> - BAS code generator

=head1 SYNOPSIS

 # generate services
 $ bas_codegen.pl sqrtsvc.xsd -m all       # generate full service
 $ bas_codegen.pl sqrtsvc.xsd -m msg       # generate message component
 $ bas_codegen.pl sqrtsvc.xsd -m svc       # generate service components
 $ bas_codegen.pl sqrtsvc.xsd -m validate  # validate schema (default)

 # generate individual files
 $ bas_codegen.pl sqrtsvc.xsd -Ec request  # a single component
 $ bas_codegen.pl sqrtsvc.xsd -g h -g cpp  # all message .h and .cpp files
 $ bas_codegen.pl sqrtsvc.xsd -g cfg.xsd   # a single-file target

 # generate multiple message components
 $ bas_codegen.pl sqrtsvc.xsd -m msg -E    # one component per schema type

 # generate prefixed message types
 $ bas_codegen.pl sqrtsvc.xsd -m msg -P mx # all types in 'mx' component

=head1 DESCRIPTION

B<bas_codegen.pl> parses service message schemas, expressed in XSD or WSDL,
and generates C++ classes representing each application-level message, as well
as a service skeleton to which application programmers add business logic.  A
service may be deployed as a separate process, or in the Big (as a "baslet").
Additionally, the generator produces a test client that can be used to send
messages (expressed in XML) to the service.

Every service consists of a number of core C++ components and files in addition
to message components.  Components are composed of three files: a header file
(C<.h>), an implementation file (C<.cpp>), and a test driver (C<.t.cpp>).  Each
component file is prefixed by the packaged prefix (e.g,
C<s_sqrtsvc_requestprocessor.h>).  Other files are prefixed by the service name
(e.g., C<sqrtsvc.m.cpp>), or by the target name (e.g., C<client.mk>).

  Components
  ----------
  messages         - message types generated from schema
  buildopts        - compiler flag driven typedefs for core types
  manifest         - service metadata (including protocol version)
  entry            - service entry point
  configschema     - the configuration schema
  requestprocessor - business logic
  requestrouter    - interface between framework and application
  requestcontext   - context object for delivering responses
  versiontag       - compile-time software version information
  version          - run-time software version information

  Files:
  ------
  <serviceName>.m.cpp        - service main
  <serviceName>.mk           - service makefile
  <serviceName>.cfg          - service configuration data file
  <serviceName>_flat.xsd     - flat service schema (compatible with RAPID)
  start_<serviceName>        - service start script
  pstart_<serviceName>       - service ProcMgr script
  stop_<serviceName>         - service stop script
  test<serviceName>.m.cpp    - test client main
  client.mk                  - test client makefile
  lib<package>.mk            - baslet library makefile

The fundamental component of a BAS service is the request processor, which
implements the service business logic.  Application developers are encouraged
to change the request processor in any way that suits their application,
including adding additional constructor arguments, and additional parameters to
the processing methods.  Similarly, developers may make corresponding changes
to the service entry point, as well as to the makefiles.  Additionally,
developers may choose to add additional types to the service configuration
schema and XML data file (such as metrics or application-specific configuration
elements).  Generally speaking, developers may change any script, makefile, or
XML data file produced by the generator.  However, developers are *discouraged*
from changing any other generated files.

By default, the generator produces a single message component named
C<messages>, which contains C++ class definitions for each schema type (i.e.,
complexType and simpleType).  The name of this component can be changed by
specifying an additional command-line option, C<-C>.  Alternatively, users can
specify that a separate component be generated for each schema type.  Note
however that if two or more schema types are cyclically dependent, the
corresponding C++ class definitions are rendered in one component having the
name of one of the types in the cycle.  Additionally, users can specify that a
common prefix be added to both the generated component name(s) and class names.

=head1 OPTIONS

There are many command-line options, including options to control the physical
design of the service with respect to how components are packaged, as well as
options to control the link-time dependencies of a service (e.g., whether or
not the service depends on the Bloomberg environment).  These options are
summarized below.

 Usage: bas_codegen.pl --help |
                       [-p <package>]
                       (-m <$modes>)*
                       (<options>)* <schema.xsd | schema.wsdl>

 --help          | -h             usage information (this text)
 --version       | -v             display version and exit
 --package       | -p <name>      use specified package name prefix
 --serviceInfo   | -s <info>      specify the service information
 --msgComponent  | -C <component> specify the (single) message component
 --msgExpand     | -E             generate multiple message components
 --msgPrefix     | -P <prefix>    prepend each message type with prefix
 --msgLibrary    | -L <library>   use specified message library
 --mode          | -m <mode>      use the specified mode
 --component     | -c <component> generate specified components only
 --target        | -g <target>    generate the specified target
 --exclude       | -x <target>    do not generate the specified target
 --author        | -a <author>    use specified author name
 --force         | -f             force overwriting of "user-owned" files
 --print         | -o             send generated text to stdout
 --recurse       | -r             generate included schemas
 --inline        | -i             expand included schema (no generation)
 --includedir    | -I <path>      search path for included schema files
 --strip         | -S             strip converted schema of bdem-specific
                                  elements and attributes
 --destination   | -D <directory> output files in the specified directory
 --noValidation  | -V             alias for --noRapidValidation
 --noRapidValidation              do not perform RAPID schema validation
 --allowInvalidSchema             only warn about schema syntax errors
 --showFlatSchema                 write flat schema to standard out

 --noSchema                  no schema is specified (use raw messages)
 --noTimestamps              do not encode timestamps into generated files
 --noWarnings                suppress warnings
 --omitIntrospection         omit introspection support for all types
 --configSchema      <y|n>   generate separate configschema component
 --dualSTL           <y|n>   generate standard-STL compatible code
 --ignoreCase        <y|n>   specify case sensitivity of message types
 --testDrivers       <y|n>   generate test drivers for component
 --requestType       <type>  specify top-level request type
 --responseType      <type>  specify top-level response type

In some cases (noted below), options may be encoded directly into the service
schema to a default behavior whenever the schema is used to generate
components.  In all cases, command-line options will override options
specified in the schema.  A detailed description of each option follows:

=over 5

=item B<-p> I<name>, B<--package>=I<name>

Set the service package name to the specified I<name>.  All services,
regardless of whether they are deployed as processes or in the Big, should
reside in a package beginning with 's_'.  The package name similarly determines
the namespace of classes defined by the service.  If no package name is
specified, the generator will attempt to derive the package name from the
service schema file name by prefixing it with 's_'.

Note that this package name prefixes the names of all service components.  For
example, given a package name C<s_sqrtsvc>, the generator will produce
components C<s_sqrtsvc_requestprocessor>, C<s_sqrtsvc_entry>, etc.

=item B<-s> I<info>, B<--serviceInfo>=I<info>

Set the service information to the specified <info>, where <info> has the
format

   [ serviceName : ] serviceId [ - majorVersion [ . minorVersion ] ] ]

The only required field of <info> is the serviceId.  This value should match
the serviceId under which the service is registered in the {PWHOC<><GO>}
database.

Optionally specify a I<serviceName>, used to identify the service to the
execution environment.  The service name should match the ProcMgr name under
which the service is registered in the {PWHOC<><GO>} database.  This name is
used to derive the name of the service executable as well as corresponding
scripts and configuration files.  It is common practice to embed this value
into the service schema, which also helps to document which service the schema
describes.

Any component of I<serviceInfo> specified on the command line overrides the
corresponding component of the C<bdem:serviceName> or C<bdem:serviceInfo>
attribute specified within the service schema.  For example, the combination
C<bdem:serviceName='sqrtsvc'> and C<--serviceInfo='foosvc:30190-1.2'> results
in the service assigned the name 'foosvc'.

Optionally specify the service's major and minor version numbers.  Note that
the major and minor version numbers are merged into the generated service
manifest and service configuration file.

=item B<--serviceName>=I<name>

Set the service name to the specified I<name>.  Note that this option is
deprecated; the --serviceInfo option should be used instead.  Also note that
the short option B<s> is now synonymous with the long option --serviceInfo.
In the interest of easing the transition to using the new option, the format of
I<name> is extended to the following format

   serviceName [ : serviceId [ - majorVersion [ . minorVersion ] ] ]

This allows users to extend the --serviceName argument in an existing script
to incorporate the serviceId (and version), and similarly for the
C<bdem:ServiceName> schema attribute (see BDEM ATTRIBUTES below).

=item B<-C> I<component>, B<--msgComponent>=I<component>

Specify that all message types are rendered together in the specified
I<component>.  By default, all message types are generated in a single
component named C<messages>, prefixed by the package name.

=item B<-E>, B<--msgExpand>

Specify that each message type be generated within its own, separate component.
Each message component shall have the same name as the type defined within.  If
two or more types are cyclically dependent, all types in the cycle are defined
in a single component named after one of the types, chosen arbitrarily.  Note
that the message expand (B<-E>) option overrides the message component (B<-C>)
option, but interacts with the message prefix (B<-P>) option.

=item B<-P> I<prefix>, B<--msgPrefix>=I<prefix>

Specify that each message type (i.e., C++ class name) be prefixed by the
specified I<prefix>.  If the B<-E> option is also specified, each component
name will be prefixed by the specified I<prefix> as well.  Otherwise, all
message types are generated in a single component named I<prefix>.  For
example, if the input schema defines a complexType named 'RequestMessage' and
the option C<-P mx> is specified, the generated C++ class will be named
'MxRequestProcessor'.  Note that the B<-C> option, if specified, is ignored.

=item B<-L> I<library>, B<--msgLibrary>=I<library>

Specify that the message components used by this service are defined in the
specified I<library>.  This implies that the message components are packaged in
the library B<lib<library>.a>, and that the message components are scoped in a
like-named namespace.  Note that the generator assumes the message library
contains a single component named C<messages> unless the appropriate
combination of B<-C>, B<-E>, and B<-P> options are specified.

=item B<-m> I<mode>, B<--mode>=I<mode>

Use the specified I<mode> to generate components.  For example, the C<msg> mode
generates message components from schema types, and the C<svc> mode generates
service components and files.  A full description of the available modes is
provided below in the "Modes" section.

=item B<-c> I<component>, B<--component>=I<component>

Generate the specified message I<component>.  Here, I<component> must be
spelled in lower-case without the package-prefix, and it must correspond to a
type defined in the schema.  This option will generate a complete component
(.h, .cpp, and .t.cpp files).  Note that this option requires the B<-E> option
if the specified component is not the name of the single message component.

=item B<-g> I<target>, B<--target>=I<target>

Generate the specified I<target>.  A target may represent either a specific
file, or a class of files.  For example, the I<service.mk> target specifies
the service makefile, while the I<cpp> target specified all (message) .cpp
files.  The available targets are described below in the "Targets"
section.

=item B<-x> I<target>, B<--exclude>=I<target>

Do not generate the specified I<target>.  This option is effectively the
opposite of B<--target>.

=item B<-a> I<name>, B<--author>=I<name>

Set the author information in each generated component to the specified
I<name>.  By default, the generator will attempt to determine the canonical
author information from a database, or from the environment.

=item B<-f>, B<--force>

Force overwriting of "user-owned" files.  The generator reserves the right to
overwrite all message components, and several service skeleton components
(e.g., configschema, requestcontext and requestrouter).  However, the
generator will not overwrite any file that the user might change unless the
B<force> option is specified.  Some files are merged by the generator rather
than overwritten (see "Targets" below).  In such cases, the B<--force> option
causes these files to be overwritten.

=item B<-o>, B<--print>

Send generated output to standard out rather than to a file.

=item B<-r>, B<--recurse>

Recursively generate components from included schemas.  This option will
generate components in the current package.

=item B<-i>, B<--inline>

Recursively expand included schemas, but do not generate components for them.
This option is used most often when a schema depends on types defined in
another schema, but does not need to generate those types.  Typically, the
message types described by the second schema are defined in a different
package or library as is the case for bascfg and basapi.

=item B<-I> I<path>, B<--includedir>=I<path>

Prefix the include path used to search for included schemas with the specified
I<path>.

=item B<-S>, B<--strip>

Remove I<bdem>-specific elements and attributes from the (converted) schema.
The 'bdem' namespace is used within BAS schemas to specify attributes used by
the generator.  This option is used to remove such attributes when generating
a flattened schema (e.g., via the 'flat.xsd' target).  BDEM attributes are
discussed below in the section "BDEM Attributes".

=item B<-D> I<directory>, B<--destination>=I<directory>

Output generated files in the specified I<directory>.

=item B<-V>, B<--noRapidValidation>

=item B<    --noValidation> (deprecated)

Do not perform RAPID schema validation.  This option is required when
generating code from schemas that contain XSD constructs not supported by
RAPID.  At this time, the only such constructs are <attribute> and <extension>
(supported for sequence types only).

=item B<--allowInvalidSchema>

Warn about schema syntax errors, but do not terminate the generator.  By
default, schema syntax errors are treated as fatal errors.  However, some
legacy schemas contain minor syntax violations such as misplaced annotation
tags that may be elided with this flag.

=item B<--showFlatSchema>

Display the flat schema (e.g., with all include tags expanded) to standard
output, with each line prefixed with a line number.  This option provides a
useful debugging aid for identifying syntax errors in WSDL files since the
generator validates a synthesized XSD schema when presented with WSDL.

=item B<--noSchema>

Construct a service with no schema.  This option may be used to generate a
service that speaks a "raw" protocol (e.g., a legacy protocol defined by C
structs and implemented using cast-and-fill).

=item B<--noTimestamps>

Do not encode timestamps in generated files.

=item B<--noWarnings>

Do not output warning diagnostics.

=item B<--omitIntrospection>

Suppress introspection for all generated types.  This option is equivalent to
applying the I<bdem:omitIntrospection> attribute to each XSD type.  See
B<omitIntrospection> in the "BDEM Attributes" section below for further
details.

=item B<--configSchema>=I<y|n>

If specified as 'y' or 'Y', this option causes the generator to render a
separate 'configschema' component, as well as a configuration schema
(_cfg.xsd).  Otherwise, the configuration schema is inlined into the
application 'main' (.m.cpp) file, corresponding to the 'service.m.cpp' target.
This option is only applicable to the mode 'app' and the mode 'all'.  Note that
the default behavior is B<--configSchema=n>.  Also note that generating the
'service.m.cpp' target explicitly using a generated configuration schema will
inline the specified schema file into the application 'main' file.

=item B<--dualSTL>=I<y|n>

If specified as 'y' or 'Y', this option causes the generator to render
standard-STL compatible C++ code.  In particular, this means that all generated
code related to STL, allocators, assertions, and typetraits will use the BSL
package group, rather than the BDE package group.  The most visible consequence
of this rendering is that all generated STL code will appear in the 'bsl'
namespace, allowing application code using the 'stl' namespace to compile and
link against the standard STL library (as opposed to the STL library enhanced
with the BDE allocator model).  Note however that if the generated code is
*not* built against the standard STL library, all types in the 'std' and 'bsl'
namespaces can be used interchangeably.  This means, for example, that message
components generated with the B<--dualSTL=y> option can still be used by BAS
services that use the BDE allocator model without changing any existing code.
Note that the default behavior is B<--dualSTL=n>.

=item B<--ignoreCase>=I<y|n>

If specified as 'y' or 'Y', this option causes the generator to render message
components that are case *in*sensitive with respect to XML encoding.  This
non-standard behavior may be required if existing clients send invalid (with
respect to case) XML-encoded messages.  If this kind of backward-compatibility
is not required, users should specify B<--ignoreCase=n>.  Note that the default
behavior is B<--ignoreCase=n>, which may not be backward compatible with
existing code.

=item B<--testDrivers>=I<y|n>

If specified as 'y' or 'Y', this option causes the generator to render test
drivers for each rendered component (.h,.cpp pair).  However, makefiles for
test drivers are *not* rendered.  Note that the default behavior is
B<--testDrivers=n>.

=item B<--requestType>=I<type>

Set the request type to the specified I<type>.  This type indicates the type
of the top-level request element for a schema defined by an XSD.  Typically,
this option is specified directly in the service schema.  It is not necessary
to specify this option when the schema is defined by a WSDL.

=item B<--responseType>=I<type>

Set the response type to the specified I<type>.  This type indicates the type
of the top-level response element for a schema defined by an XSD.  Typically,
this option is specified directly in the service schema.  It is not necessary
to specify this option when the schema is defined by a WSDL.

=back

=head1 GENERATOR MODES

The generator supports several different "modes" of operation, each of which
produces a different class of files.  Some modes combine other modes in order
to simplify the user experience.  The supported modes are described below.

=over 5

=item B<all>

The I<all> mode combines all of the following modes.  It is the most
straightforward way to build a complete service skeleton.

=item B<msg>

The I<msg> mode is used to generate service message components.  This mode is
useful when creating a library of message components, or for regenerating
components during schema development.  This mode can also be used to simply
generate value-semantic types from an XSD.

=item B<svc>

The I<svc> mode is used to generate the service skeleton components and files,
namely the request processor, manifest, version, and service entry point
components.

=item B<app>

The I<app> mode is used to generate the service offline 'main', configuration
file, scripts for starting and stopping the service, a test client application,
and makefiles.

=item B<cfg>

The I<cfg> mode is used to generate the configuration schema component
(configschema).  It must be invoked with the configuration schema (cfg.xsd
target).  [Note, this mode is deprecated.]

=item B<validate>

The I<validate> mode is used to validate the specified schema files.  These
schemas are not required to be flat (i.e., they may include other schemas).
The I<validate> mode is the default mode for the generator, and is applied in
all cases.  The schema is additionally validated for RAPID compatibility unless
the B<--noValidation> flag is specified.

=back

=head1 GENERATOR TARGETS

Each service skeleton component and file can be generated individually by
specifying an appropriate target, using the B<--target> option.  Similar to
modes, some targets actually specify a class of files rather than a single
file.  The available targets are described below.  Files marked with a C<*>
indicate components which are "user-owned"; once generated, the generator will
not change these files.  However, the I<--force> option may be specified to
regenerate these files.  Files marked with a C<-> also indicate components
which are "user-owned".  However, these files are automatically updated by the
generator if any relevant changes are made to the service schema.  All other
files may be changed by the generator upon the next invocation.

  h                       - Generate all message component .h files
  cpp                     - Generate all message component .cpp files
  t                       - Generate all message component .t.cpp files

 -requestcontext.h        - RequestContext header file
 -requestcontext.cpp      - RequestContext implementation file
 *requestcontext.t.cpp    - RequestContext test driver

 *requestrouter.h         - RequestRouter header file
 -requestrouter.cpp       - RequestRouter implementation file
 *requestrouter.t.cpp     - RequestRouter test driver

 -requestprocessor.h      - RequestProcsesor header file
 -requestprocessor.cpp    - RequestProcessor implementation file
 *requestprocsesor.t.cpp  - RequestProcessor test driver

 *cfg.xsd                 - Generate a service configuration schema
 *cfg                     - Generate a service configuration XML data file

  flat.xsd                - Generate a flattened service schema
                            (compatible with RAPID)

  configschema.h          - ConfigSchema header file
  configschema.cpp        - ConfigSchema implementation file
  configschema.t.cpp      - ConfigSchema test driver

 *version.h               - Version header file
 *version.cpp             - Version implementation file
 *version.t.cpp           - Version test driver

 *buildopts.h             - Build options header file
 *buildopts.cpp           - Build options implementation file
 *buildopts.t.cpp         - Build options test driver

 *entry.h                 - Service entry point header file
 -entry.cpp               - Service entry point implementation file
 *entry.t.cpp             - Service entry point test driver
 -baslet.mk               - Service library makefile

 -service.m.cpp           - Service 'main' entry point
 *service_dum.c           - Service dummies file
 *service_refs.c          - Service refs file
 -service.mk              - Service process makefile

 *client.m.cpp            - Test client 'main' entry point
 *client_dum.c            - Test client dummies file
 *client_refs.c           - Test client refs file
 -client.mk               - Test client makefile

 *start_script            - Generate a ProcMgr start script
 *pstart_script           - Generate a ProcMgr pstart script
 *stop_script             - Generate a ProcMgr stop script

=head1 NAMING CONVENTIONS

As part of the conversion from schema types to C++ classes, the generator
applies several filters to the schema text so that the generated type names,
variable names, and method names comply with the standard BDE naming
conventions.  These conventions are as follows:

=over 5

=item B<1.>

Type names start with an upper-case letter, and each "word" that composes a
type name is capitalized.  The C++ type name C<RequestProcessor> serves as the
canonical example of this convention.  Note that, according to this convention,
C++ type names do not contain underbar characters, so the schema type name
C<division_request> will be rendered as the C++ type C<DivisionRequest>.

=item B<2.>

Data members are prefixed by 'd_', and start with a lower-case letter.  For
example, the schema element C<UserInfo> is rendered as C<d_userInfo>.
Underbars are treated identically as with type names, so the schema element
name C<user_info> is also rendered as C<d_userInfo>.  In cases where the
generator renders a pointer type, the data member is suffixed with '_p', as in
C<d_allocator_p>.

=item B<3.>

A manipulator method and an accessor method is generated for each schema
element.  These methods are named identically to the corresponding data
members, except without the 'd_' prefix.  The manipulator returns a modifiable
reference, whereas the accessor returns a non-modifiable (const) reference.
For example, given the schema element

    <element name='user_id' type='int'/>

the generator renders a manipulator

    int& userId();

and an accessor

    const int& userId() const;

=back

=head1 XSD TO C++ TYPE MAPPING

XSD provides a wide variety of built-in types.  The following table describes
the mapping from schema types to C++ types.

    Schema                   C++
    ------                   ---
    boolean                  bool
    byte                     char
    date                     bdet_DateTz
    dateTime                 bdet_DateTimeTz
    decimal                  double
    double                   double
    float                    float
    int                      int
    integer                  bdes_PlatformUtil::Int64
    long                     bdes_PlatformUtil::Int64
    negativeInteger          bdes_PlatformUtil::Int64
    nonNegativeInteger       bdes_PlatformUtil::Uint64
    nonPositiveInteger       bdes_PlatformUtil::Int64
    normalizedString         std::string
    positiveInteger          bdes_PlatformUtil::Uint64
    short                    short
    string                   std::string
    time                     bdet_TimeTz
    unsignedByte             unsigned char
    unsignedInt              unsigned int
    unsignedLong             bdes_PlatformUtil::Uint64
    unsignedShort            unsigned short
    base64Binary             std::vector<char>
    hexBinary                std::vector<char>

=head1 BDEM ATTRIBUTES

Aside from specifying command-line options, the generator output can be
controlled by adding various attributes in the I<bdem> namespace to the schema
elements.  The bdem namespace is defined by the URI

    xmlns:bdem='http://bloomberg.com/schemas/bdem'

The following provides a description of the supported bdem attributes, and
examples of their use.

=over 5

=item B<serviceInfo>

=item B<requestType>

=item B<responseType>

The I<serviceInfo> attribute specifies the service name, serviceId, and major
and minor version numbers of the service protocol (although only the serviceId
value is required; see I<--serviceInfo> above).  This attribute may be applied
to the <schema> element of an XSD or WSDL.  While the service infomation may be
specified (or overridden) on the command line by passing the B<--serviceInfo>
option, specifying the service information within the schema itself serves as
additional documentation.

The I<requestType> attribute specifies the top-level request type.  This
attribute may be applied to the <schema> element of an XSD.  The top-level
request type must be a choice-type, as opposed to a sequence.  It is not
necessary to specify the request type for WSDL schemas since the top-level
element of a WSDL is derived from the <portType>, and is therefore well-known.

Similarly, the I<responseType> attribute specifies the top-level response type.
This attribute may also be applied to the <schema> element of an XSD.  The
top-level response type must be a choice-type, as opposed to a sequence, and,
like the request type, it is not necessary to specify the response type for
WSDL schemas since the top-level element of a WSDL is derived from the
<portType>, and is therefore well-known.

For example, consider the following <schema> element for the "Square Root"
service:

    <schema xmlns='http://www.w3.org/2001/XMLSchema'
            xmlns:bdem='http://bloomberg.com/schemas/bdem'
            xmlns:tns='urn:x-bloomberg-com:BAS.services.sqrtsvc'
            targetNamespace='urn:x-bloomberg-com:BAS.services.sqrtsvc'
            bdem:requestType='Request'
            bdem:responseType='Response'
            bdem:serviceInfo='sqrtsvc:30190-1.0'
            elementFormDefault='qualified'>

Note that the values of the B<requestType> and B<responseType> attributes are
the names of the corresponding types as they appear in the schema.

=item B<package>

The I<package> attribute specifies the package in which C++ types should be
rendered.  This attribute is typically used in schemas which define a set of
common types that are shared between service schemas via the <include> element.
For example, it is often the case that multiple applications developed for a
specific domain share a common set of data types.  The shared schema types can
either be rendered as C++ in each application, or they can be rendered in a
separate package (i.e., library), which the applications depend on.  In the
latter case, the package name can be encoded into the schema by specifying the
I<package> attribute:

    <xs:schema xmlns:xs='http://www.w3.org/2001/XMLSchema'
               xmlns:bdem='http://bloomberg.com/schemas/bdem'
               bdem:package='bascfg'
               elementFormDefault='qualified'>

      <!-- definitions of bascfg schema types -->

    </xs:schema>

C++ types rendered from this schema will by default be rendered in the bascfg
package.

=item B<id>

The most common use of the I<id> attribute is to specify the ordinal value of
an enumeration.  In this case, the attribute may be applied to the
<enumeration> element of an XSD simpleType restriction.  For example, the
following schema type is rendered as a C++ enumeration class:

    <simpleType name='ProductType'>
      <restriction base='string'>
        <enumeration value='MMKT' bdem:id='6'/>
        <enumeration value='GOVT' bdem:id='7'/>
        <enumeration value='CORP' bdem:id='8'/>
      </restriction>
    </simpleType>

Using the B<id> attribute explicitly specifies the value of each enumeration
value.  It is particularly important to specify the B<id> attribute if an
application requires that the in-core representation of an enumerated type
corresponds to values in a database.  If the B<id> attribute was not used, the
generator would render the enumeration values in an implementation-defined
manner.

Another use of the I<id> attribute is to facilitate backward compatibility
between schema versions when messages are encoded using a binary encoding, such
as BER.  The BER encoding assigns an ID to every element, which must be unique
within the enclosing element.  Typically, schemas are evolved by adding
elements to the bottom of the enclosing XSD element (e.g., choice or sequence
within a complex type).  This process guarantees that new elements have a
different ID value than existing elements because ID values are generated
sequentially based on the order of elements in the schema.  For example,

    <!-- Element 'middleName' is added to the existing type. -->
    <complexType name='Person'>
      <sequence>
        <element name='firstName'  type='string'/>
        <element name='lastName'   type='string'/>
        <element name='middleName' type='string'/>
      </sequence>
    </complexType>

In this case, the three elements are assigned ID value 0, 1, and 2,
respectively.

However, it sometimes makes sense to add a new element into the middle of a
schema, for example, to preserve the logical cohesion of the schema document.
In this case, however, regenerating the particular C++ class corresponding to
the updated schema would cause the element IDs to change, thus breaking
backward compatibility with existing peers.  In this case, the I<id> attribute
can be used to explicitly assign ID values used by the BAS codecs in order to
preserve backward compatibility.  Thus, the previous example may be better
expressed as

    <!-- Element 'middleName' is added to the existing type. -->
    <complexType name='Person'>
      <sequence>
        <element name='firstName'  type='string' bdem:id='0'/>
        <element name='middleName' type='string' bdem:id='2'/>
        <element name='lastName'   type='string' bdem:id='1'/>
      </sequence>
    </complexType>

=item B<preserveEnumOrder>

The I<preserveEnumOrder> attribute specifies that the order of enumerated
values in the rendered enumeration class should be the same as the order
specified in the schema.  For example,

    <xs:simpleType name='IntegralTypes' bdem:preserveEnumOrder='1'>
      <xs:restriction base='xs:string'>
        <xs:enumeration value='CHAR'/>
        <xs:enumeration value='SHORT'/>
        <xs:enumeration value='INT'/>
        <xs:enumeration value='LONG'/>
      </xs:restriction>
    </xs:simpleType>

guarantees that the rendered C++ enumeration class contains the specified
enumerated values in the specified order, starting with the value 0:

    struct IntegralTypes {

      public:
        // TYPES
        enum Value {
            CHAR = 0,
            SHORT = 1,
            INT = 2,
            LONG = 3
        };
      //...
    };

Note that use of the I<preserveEnumOrder> attribute is not compatible with the
ITU-T Rec. X.694 | ISO/IEC 8825-5 standard for converting XML schemas to ASN.1
modules, used for BER encoding.

=item B<preserveElementOrder>

The I<preserveElementOrder> attribute specifies that the order of data fields
in a rendered sequence class should be the same as the order of elements and
attributes specified in the schema.  For example,

    <xs:complexType name='Sequence' bdem:preserveElementOrder='1'>
      <xs:sequence>
        <xs:element name='value1' type='xs:int'/>
        <xs:element name='value2' type='xs:byte'/>
        <xs:element name='value3' type='xs:int'/>
        <xs:element name='value4' type='xs:byte'/>
      </xs:sequence>
    </xs:complexType>

guarantees that the rendered C++ class contains data members corresponding to
the elements of the sequence in the specified order,

class Sequence {

    // INSTANCE DATA
    int   d_value1;
    bool  d_value2;
    int   d_value3;
    bool  d_value4;

    //...
};

If this attribute is false or not present, the data members of the rendered C++
class will be reordered in an effort to minimize the amount of padding inserted
by the compiler to meet the alignment restrictions for each data member of the
class.  For example,

    <xs:complexType name='Sequence'>
      <xs:sequence>
        <xs:element name='value1' type='xs:int'/>
        <xs:element name='value2' type='xs:byte'/>
        <xs:element name='value3' type='xs:int'/>
        <xs:element name='value4' type='xs:byte'/>
      </xs:sequence>
    </xs:complexType>

may render a C++ class that contains data members declared in a different order
than the order listed in the schema.

class Sequence {

    // INSTANCE DATA
    int   d_value1;
    int   d_value3;
    char  d_value2;
    char  d_value4;

    //...
};

It is important to note that the *logical* order of fields within a sequence is
*not* affected by the value of this attribute.

=item B<cpptype>

The I<cpptype> attribute explicitly specifies the C++ type to be rendered for a
particular element.  This attribute may be applied to an XSD <element> element.
For example, consider the following schema type definition:

    <complexType name='RealtimeNode'>
        <sequence>
            <element name='machineNumber' type='int'/>
            <element name='retryInterval' type='double'/>
            <element name='priority'      type='int'/>
        </sequence>
    </complexType>

Whenever this type appears in a service schema, the generator will render the
C++ class 'RealtimeNode' in the specified package.  However, 'RealtimeNode'
classes rendered in different packages are not equivalent because they live in
different namespaces.  Nevertheless, two applications can share a common C++
'RealtimeNode' class by explicitly specifying that type using the B<cpptype>
attribute in their respective schemas:

    <complexType name='RealtimeServer'>
      <sequence>
        <element name='realtimeNode' type='tns:RealtimeNode'
                 bdem:cpptype='apicfg::RealtimeNode'/>
        <element name='salesRegion'  type='string'/>
      </sequence>
    </complexType>

In this case, the generated 'RealtimeServer' C++ class will have a data member
'd_realtimeNode' of type 'apicfg::RealtimeNode'.  Note that the XSD definition
of 'RealtimeNode' must still be present in order to validate the schema (e.g.,
as part of an included or imported schema), but no type corresponding to the
schema type 'RealtimeNode' is generated in the current package.  Rather, the
current package will depend on the apicfg package, or in this case, the api
library.  Also note that the referenced 'apicfg::RealtimeNode' class must be
compatible with the BAS framework, namely in that it is also a generated type.

Note that an alternative approach is to define the 'RealtimeNode' schema type
in a separate schema, apicfg.xsd for example, and include that schema wherever
the 'RealtimeNode' type is needed.  If the apicfg.xsd schema specifies that its
types are part of the apicfg package (by using the I<package> attribute
discussed above), then the I<cpptype> attribute need not be specified:

    <!-- The apicfg.xsd schema element contains the attribute
         bdem:package='apicfg'.
    -->
    <include schemaLocation='apicfg.xsd'/>

    <!-- ... -->

    <complexType name='RealtimeServer'>
      <sequence>
        <!-- The 'realtimeNode' element will be rendered with C++ type
             'apicfg::RealtimeNode'.
        -->
        <element name='realtimeNode' type='tns:RealtimeNode'/>
        <element name='salesRegion'  type='string'/>
      </sequence>
    </complexType>

=item B<cppheader>

The I<cppheader> attribute explicitly specifies the C++ header file to be
rendered in association with a particular element.  This is especially
pertinent to cases where the C++ type is also specified (via the I<cpptype>
attribute).  The default behavior in such cases is to assume that the type is
defined in a like-named component.  However, this may not always be the case.
Returning to the previous example, given an element defined as

        <element name='realtimeNode' type='tns:RealtimeNode'
                 bdem:cpptype='apicfg::RealtimeNode'/>

the generator will render the include statement

    #include <apicfg_realtimenode.h>

However, the RealtimeNode class may be defined in another header file such as
apicfg_messages.h.  In this case, it is possible to override the default
header file for the specified type as

        <element name='realtimeNode' type='tns:RealtimeNode'
                 bdem:cpptype='apicfg::RealtimeNode'
                 bdem:cppheader='apicfg_messages.h'/>

=item B<allowsDirectManipulation>

The I<allowsDirectManipulation> attribute specifies whether or not to render an
explicit "set" manipulator for a given data member.  This attribute may be
applied to an XSD <element> element.  For example, given the XSD definition

    <element name='user_id' type='int'/>

the generator renders a manipulator returning a modifiable reference,

    int& userId();

allowing "direct" manipulation of the corresponding 'd_userId' data member.
However, by specifying the B<allowsDirectManipulation> attribute,

    <element name='user_id' type='int'
             bdem:allowsDirectManipulation='0'/>

the generator produces an explicit "set" manipulator,

    void setUserId(int value);

effectively disallowing direct manipulation of 'd_userInfo'.  This attribute
should only be used for leaf elements, and even then, largely as a matter of
taste.

=item B<omitIntrospection>

The I<omitIntrorspection> attribute specifies whether or not to render various
"introspection" methods for a given schema type.  This attribute may be
applied to XSD complexType and simpleType elements.  Introspection methods are
required for every type sent over the wire via the BAS codecs.  However, it is
sometimes convenient to describe a value-semantic type as XSD and render it
using the generator outside the scope of the BAS framework.  For example, the
schema type

  <complexType name='BinTree' bdem:omitIntrospection='1'>
    <sequence>
      <element name='left'  type='tns:BinTree' minOccurs='0'/>
      <element name='right' type='tns:BinTree' minOccurs='0'/>
      <element name='value' type='int'/>
    </sequence>
  </complexType>

is rendered as a C++ type that supports BDEX streaming, but not the full suite
of BAS introspection methods.

=item B<parameterizedConstructor>

The I<parameterizedConstructor> attribute specifies that the type should be
rendered with a constructor taking parameters for each data members in the
type.

=back

=head1 AUTHOR

David Rubin (drubin6@bloomberg.net)

=cut

#==============================================================================
# vim:set syntax=perl tabstop=4 shiftwidth=4 expandtab:

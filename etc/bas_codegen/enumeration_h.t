[% PROCESS enumeration_util.t -%]
[% BLOCK enumerationClassDeclaration -%]
[% String.new("// $fatline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $fatline").center(79) %]

struct [% Class %] {
[% FOREACH note = enumeration.annotation.documentation -%]
[% NEXT UNLESS note.length -%]
[% formatComment(note, 4) %]
[% END -%]

[% enumeration.annotation.appinfo.rawCppClass -%]
  public:
    // TYPES
    enum Value {
[% SET longestLength = 0 -%]
[% FOREACH enumerator = enumerators -%]
[% IF enumerator.name.length() > longestLength -%]
[% longestLength = enumerator.name.length() -%]
[% END -%]
[% END -%]
[% FOREACH enumerator = enumerators -%]
[% offsetLen = longestLength - enumerator.name.length() -%]
[% offset = String.new(' ').repeat(offsetLen) -%]
      [% loop.first ? '  ' : ', ' -%]
      [%- ENUMERATOR_NAME %] [% offset %]= [% enumerator.id %]
[% SET comment = enumerator.annotation.documentation.0 | collapse | lcfirst -%]
[% IF 0 < comment.length() -%]
[% formatComment("$comment", 12) %]
[% END -%]
[% END -%]
    };

    enum {
        NUM_ENUMERATORS = [% enumerators.size %]
    };

[% IF !enumeration.omitIntrospection -%]
    // CONSTANTS
    static const char CLASS_NAME[];

    static const bdeat_EnumeratorInfo ENUMERATOR_INFO_ARRAY[];

[% ELSIF enumeration.appInfoConstants.length() -%]
    // CONSTANTS
[% END -%]
[% FOREACH appInfoConstant = enumeration.appInfoConstants -%]
    static const char APPINFO_[% appInfoConstant.name | UPPER_UPPER %][];

[% END -%]
    // CLASS METHODS
    static int maxSupportedBdexVersion();
[% UNLESS opts.noComments -%]
        // Return the most current 'bdex' streaming version number supported by
        // this class.  See the 'bdex' package-level documentation for more
        // information on 'bdex' streaming of value-semantic types and
        // containers.
[% END -%]

    static const char *toString(Value value);
[% UNLESS opts.noComments -%]
        // Return the string representation exactly matching the enumerator
        // name corresponding to the specified enumeration 'value'.
[% END -%]

    static int fromString(Value        *result,
                          const char   *string,
                          int           stringLength);
[% UNLESS opts.noComments -%]
        // Load into the specified 'result' the enumerator matching the
        // specified 'string' of the specified 'stringLength'.  Return 0 on
        // success, and a non-zero value with no effect on 'result' otherwise
        // (i.e., 'string' does not match any enumerator).
[% END -%]

    static int fromString(Value              *result,
                          const bsl::string&  string);
[% UNLESS opts.noComments -%]
        // Load into the specified 'result' the enumerator matching the
        // specified 'string'.  Return 0 on success, and a non-zero value with
        // no effect on 'result' otherwise (i.e., 'string' does not match any
        // enumerator).
[% END -%]

    static int fromInt(Value *result, int number);
[% UNLESS opts.noComments -%]
        // Load into the specified 'result' the enumerator matching the
        // specified 'number'.  Return 0 on success, and a non-zero value with
        // no effect on 'result' otherwise (i.e., 'number' does not match any
        // enumerator).
[% END -%]

    template <class STREAM>
    static STREAM& bdexStreamIn(STREAM&  stream,
                                Value&   value,
                                int      version);
[% UNLESS opts.noComments -%]
        // Assign to the specified 'value' the value read from the specified
        // input 'stream' using the specified 'version' format and return a
        // reference to the modifiable 'stream'.  If 'stream' is initially
        // invalid, this operation has no effect.  If 'stream' becomes invalid
        // during this operation, the 'value' is valid, but its value is
        // undefined.  If the specified 'version' is not supported, 'stream' is
        // marked invalid, but 'value' is unaltered.  Note that no version is
        // read from 'stream'.  (See the package-group-level documentation for
        // more information on 'bdex' streaming of container types.)
[% END -%]

    static bsl::ostream& print(bsl::ostream& stream, Value value);
[% UNLESS opts.noComments -%]
        // Write to the specified 'stream' the string representation of
        // the specified enumeration 'value'.  Return a reference to
        // the modifiable 'stream'.
[% END -%]

    template <class STREAM>
    static STREAM& bdexStreamOut(STREAM&  stream,
                                 Value    value,
                                 int      version);
[% UNLESS opts.noComments -%]
        // Write the specified 'value' to the specified output 'stream' and
        // return a reference to the modifiable 'stream'.  Optionally specify
        // an explicit 'version' format; by default, the maximum supported
        // version is written to 'stream' and used as the format.  If 'version'
        // is specified, that format is used but *not* written to 'stream'.  If
        // 'version' is not supported, 'stream' is left unmodified.  (See the
        // package-group-level documentation for more information on 'bdex'
        // streaming of container types).
[% END -%]
};

// FREE OPERATORS
inline
bsl::ostream& operator<<(bsl::ostream& stream, [% Class %]::Value rhs);
[% UNLESS opts.noComments -%]
    // Format the specified 'rhs' to the specified output 'stream' and
    // return a reference to the modifiable 'stream'.
[% END -%]
[% END -%]
[% BLOCK enumerationInlineMethods -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

// CLASS METHODS
inline
int [% Class %]::maxSupportedBdexVersion()
{
    return 1;  // versions start at 1
}

inline
int [% Class %]::fromString(Value *result, const bsl::string& string)
{
    return fromString(result, string.c_str(), string.length());
}

inline
bsl::ostream& [% Class %]::print(bsl::ostream&      stream,
                                 [% Class %]::Value value)
{
    return stream << toString(value);
}

template <class STREAM>
STREAM& [% Class %]::bdexStreamIn(STREAM&             stream,
                                   [% Class %]::Value& value,
                                   int                 version)
{
    switch(version) {
      case 1: {
        int readValue;
        stream.getInt32(readValue);
        if (stream) {
            if (fromInt(&value, readValue)) {
               stream.invalidate();   // bad value in stream
            }
        }
      } break;
      default: {
        stream.invalidate();          // unrecognized version number
      } break;
    }
    return stream;
}

template <class STREAM>
STREAM& [% Class %]::bdexStreamOut(STREAM&              stream,
                                    [% Class %]::Value value,
                                    int                version)
{
    switch (version) {
      case 1: {
        stream.putInt32(value);  // Write the value as an int
      } break;
    }
    return stream;
}

[% END -%]
[% BLOCK enumerationBdexFunctionNamespaces -%]
[% SET offsetlen = namespace.length + Class.length -%]
[% SET offset = String.new(' ').repeat(offsetlen) -%]
namespace bdex_InStreamFunctions {

template <typename STREAM>
inline
STREAM& streamIn(STREAM&[% offset %]  stream,
                 [% namespace %]::[% Class %]::Value& value,
                 int[% offset %]      version)
{
    return [% namespace %]::[% Class %]::bdexStreamIn(stream, value, version);
}

}  // close namespace bdex_InStreamFunctions

namespace bdex_VersionFunctions {

inline
int maxSupportedVersion([% namespace %]::[% Class %]::Value)
{
    return [% namespace %]::[% Class %]::maxSupportedBdexVersion();
}

}  // close namespace bdex_VersionFunctions

namespace bdex_OutStreamFunctions {

template <typename STREAM>
inline
STREAM& streamOut(STREAM& stream,
                  const [% namespace %]::[% Class %]::Value& value,
                  int     version)
{
    return [% namespace %]::[% Class %]::bdexStreamOut(stream, value, version);
}

}  // close namespace bdex_OutStreamFunctions
[% END -%]
[% BLOCK enumerationTraitDeclarations -%]
BDEAT_DECL_ENUMERATION_TRAITS([% namespace %]::[% Class %])
[% END -%]
[% BLOCK enumerationInlineFreeFunctions -%]
inline
bsl::ostream& [% namespace %]::operator<<(
        bsl::ostream& stream,
        [% namespace %]::[% Class %]::Value rhs)
{
    return [% namespace %]::[% Class %]::print(stream, rhs);
}
[% END -%]

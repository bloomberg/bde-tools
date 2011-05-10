[% PROCESS customizedtype_util.t -%]
[% BLOCK customizedtypeClassDeclaration -%]
[% String.new("// $fatline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $fatline").center(79) %]

class [% Class %] {
[% FOREACH note = customizedtype.annotation.documentation -%]
[% NEXT UNLESS note.length -%]
[% formatComment(note, 4) %]
[% END -%]

    // INSTANCE DATA
    [% BaseType %] d_value;[%#  // stored value %]

    // FRIENDS
    friend bool operator==(const [% Class %]& lhs, const [% Class %]& rhs);
    friend bool operator!=(const [% Class %]& lhs, const [% Class %]& rhs);

    // PRIVATE CLASS METHODS
    static int checkRestrictions([% BaseArgType %] value);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Check if the specified 'value' satisfies the restrictions of this class (i.e., \"$Class\").  Return 0 if successful (i.e., the restrictions are satisfied) and non-zero otherwise."), 8) %]
[% END -%]

  public:
    // TYPES
    typedef [% BaseType %] BaseType;

    // CONSTANTS
    static const char CLASS_NAME[];

[% FOREACH appInfoConstant = customizedtype.appInfoConstants -%]
    static const char APPINFO_[% appInfoConstant.name | UPPER_UPPER %][];

[% END -%]
[% IF customizedtype.restriction.enumeration.defined -%]
[% FOREACH enumerator = enumerators -%]
[% IF enumerator.name.defined -%]
    static const [% BaseType %] [% ENUMERATOR_NAME %];
[% SET comment = enumerator.annotation.documentation.0 | collapse | lcfirst -%]
[% IF 0 < comment.length() -%]
[% formatComment("$comment", 8) %]
[% END -%]

[% END -%]
[% END -%]
[% END -%]
    // CREATORS
[% IF customizedtype.allocatesMemory -%]
    explicit [% Class %](bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the default value.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
[% END -%]

[% SET offset = String.new(' ').repeat(Class.length) -%]
    [% Class %](const [% Class %]& original,
    [% offset %]bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
        // Create an object of type '[% Class %]' having the value
        // of the specified 'original' object.  Use the optionally specified
        // 'basicAllocator' to supply memory.  If 'basicAllocator' is 0,
        // the currently installed default allocator is used.
[% END -%]

    explicit [% Class %]([% BaseArgType %] value,
             [% offset %]bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the specified 'value'.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
[% END -%]
[% ELSE -%]
    [% Class %]();
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the default value."), 8) %]
[% END -%]

    [% Class %](const [% Class %]& original);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the value of the specified 'original' object."), 8) %]
[% END -%]

    explicit [% Class %]([% BaseArgType %] value);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the specified 'value'."), 8) %]
[% END -%]
[% END -%]

    ~[% Class %]();
[% UNLESS opts.noComments -%]
        // Destroy this object.
[% END -%]

    // MANIPULATORS
    [% Class %]& operator=(const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
        // Assign to this object the value of the specified 'rhs' object.
[% END -%]

    template <class STREAM>
    STREAM& bdexStreamIn(STREAM& stream, int version);
[% UNLESS opts.noComments -%]
        // Assign to this object the value read from the specified input
        // 'stream' using the specified 'version' format and return a reference
        // to the modifiable 'stream'.  If 'stream' is initially invalid, this
        // operation has no effect.  If 'stream' becomes invalid during this
        // operation, this object is valid, but its value is undefined.  If
        // 'version' is not supported, 'stream' is marked invalid and this
        // object is unaltered.  Note that no version is read from 'stream'.
        // See the 'bdex' package-level documentation for more information on
        // 'bdex' streaming of value-semantic types and containers.
[% END -%]

[% IF !customizedtype.noAggregateConversion -%]
    int fromAggregate(const bcem_Aggregate& aggregate);
[% UNLESS opts.noComments -%]
        // Store the value of the specified 'aggregate' into this object.
        // Return 0 on success, and a non-zero value otherwise.
[% END -%]

[% END -%]
    void reset();
[% UNLESS opts.noComments -%]
        // Reset this object to the default value (i.e., its value upon
        // default construction).
[% END -%]

    int [% customizedtype.fromFunction %]([% BaseArgType %] value);
[% UNLESS opts.noComments -%]
        // Convert from the specified 'value' to this type.  Return 0 if
        // successful and non-zero otherwise.
[% END -%]

    // ACCESSORS
    template <class STREAM>
    STREAM& bdexStreamOut(STREAM& stream, int version) const;
[% UNLESS opts.noComments -%]
        // Write the value of this object to the specified output 'stream'
        // using the specified 'version' format and return a reference to the
        // modifiable 'stream'.  If 'version' is not supported, 'stream' is
        // unmodified.  Note that 'version' is not written to 'stream'.
        // See the 'bdex' package-level documentation for more information
        // on 'bdex' streaming of value-semantic types and containers.
[% END -%]

[% IF !customizedtype.noAggregateConversion -%]
    int toAggregate(bcem_Aggregate *result) const;
[% UNLESS opts.noComments -%]
        // Load the specified 'result' with the value of this object.  Return
        // 0 on success, and a non-zero value otherwise.
[% END -%]

[% END -%]
    int maxSupportedBdexVersion() const;
[% UNLESS opts.noComments -%]
        // Return the most current 'bdex' streaming version number supported by
        // this class.  See the 'bdex' package-level documentation for more
        // information on 'bdex' streaming of value-semantic types and
        // containers.
[% END -%]

    bsl::ostream& print(bsl::ostream& stream,
                        int           level = 0,
                        int           spacesPerLevel = 4) const;
[% UNLESS opts.noComments -%]
        // Format this object to the specified output 'stream' at the
        // optionally specified indentation 'level' and return a reference to
        // the modifiable 'stream'.  If 'level' is specified, optionally
        // specify 'spacesPerLevel', the number of spaces per indentation level
        // for this and all of its nested objects.  Each line is indented by
        // the absolute value of 'level * spacesPerLevel'.  If 'level' is
        // negative, suppress indentation of the first line.  If
        // 'spacesPerLevel' is negative, suppress line breaks and format the
        // entire output on one line.  If 'stream' is initially invalid, this
        // operation has no effect.  Note that a trailing newline is provided
        // in multiline mode only.
[% END -%]

    [% BaseArgType %] [% customizedtype.toFunction %]() const;
[% UNLESS opts.noComments -%]
        // Convert this value to '[% BaseType %]'.
[% END -%]
};

// FREE OPERATORS
inline
bool operator==(const [% Class %]& lhs, const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
    // Return 'true' if the specified 'lhs' and 'rhs' attribute objects have
    // the same value, and 'false' otherwise.  Two attribute objects have the
    // same value if each respective attribute has the same value.
[% END -%]

inline
bool operator!=(const [% Class %]& lhs, const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
    // Return 'true' if the specified 'lhs' and 'rhs' attribute objects do not
    // have the same value, and 'false' otherwise.  Two attribute objects do
    // not have the same value if one or more respective attributes differ in
    // values.
[% END -%]

inline
bsl::ostream& operator<<(bsl::ostream& stream, const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
    // Format the specified 'rhs' to the specified output 'stream' and
    // return a reference to the modifiable 'stream'.
[% END -%]
[% END -%]
[% BLOCK customizedtypeInlineMethods -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

[% IF 1 == customizedtype.restriction.size() -%]
// PRIVATE CLASS METHODS
inline
int [% Class %]::checkRestrictions([% BaseArgType %] value)
{
    return 0;
}

[% END -%]
// CREATORS
[% IF customizedtype.allocatesMemory -%]
inline
[% Class %]::[% Class %](bslma_Allocator *basicAllocator)
: d_value(basicAllocator)
{
}

inline
[% Class %]::[% Class %](const [% Class %]& original, [% -%]
            [%- %]bslma_Allocator *basicAllocator)
: d_value(original.d_value, basicAllocator)
{
}

inline
[% Class %]::[% Class %]([% BaseArgType %] value, [% -%]
            [%- %]bslma_Allocator *basicAllocator)
: d_value(value, basicAllocator)
{
    BSLS_ASSERT(checkRestrictions(value) == 0);
}
[% ELSE -%]
inline
[% Class %]::[% Class %]()
: d_value()
{
}

inline
[% Class %]::[% Class %](const [% Class %]& original)
: d_value(original.d_value)
{
}

inline
[% Class %]::[% Class %]([% BaseArgType %] value)
: d_value(value)
{
    BSLS_ASSERT(checkRestrictions(value) == 0);
}
[% END -%]

inline
[% Class %]::~[% Class %]()
{
}

// MANIPULATORS
inline
[% Class %]& [% Class %]::operator=(const [% Class %]& rhs)
{
    d_value = rhs.d_value;
    return *this;
}

template <class STREAM>
STREAM& [% Class %]::bdexStreamIn(STREAM& stream, int version)
{
    [% BaseType %] temp;

    bdex_InStreamFunctions::streamIn(stream, temp, version);

    if (!stream) {
        return stream;
    }

    if ([% customizedtype.fromFunction %](temp)!=0) {
        stream.invalidate();
    }

    return stream;
}

[% IF !customizedtype.noAggregateConversion -%]
inline
int [% Class %]::fromAggregate(const bcem_Aggregate& aggregate)
{
    return [% customizedtype.fromFunction %](aggregate.[% customizedtype.aggregateValueAccessor %]());
}

[% END -%]
inline
void [% Class %]::reset()
{
    bdeat_ValueTypeFunctions::reset(&d_value);
}

inline
int [% Class %]::[% customizedtype.fromFunction %]([% BaseArgType %] value)
{
    int ret = checkRestrictions(value);
    if (0 == ret) {
        d_value = value;
    }

    return ret;
}

// ACCESSORS
template <class STREAM>
STREAM& [% Class %]::bdexStreamOut(STREAM& stream, int version) const
{
    return bdex_OutStreamFunctions::streamOut(stream, d_value, version);
}

[% IF !customizedtype.noAggregateConversion -%]
inline
int [% Class %]::toAggregate(bcem_Aggregate *result) const
{
    return result->setValue([% customizedtype.toFunction %]()).isError();
}

[% END -%]
inline
int [% Class %]::maxSupportedBdexVersion() const
{
    return bdex_VersionFunctions::maxSupportedVersion(d_value);
}

inline
bsl::ostream& [% Class %]::print(bsl::ostream& stream,
                                 int           level,
                                 int           spacesPerLevel) const
{
    return bdeu_PrintMethods::print(stream, d_value, level, spacesPerLevel);
}

inline
[% BaseArgType %] [% Class %]::[% customizedtype.toFunction %]() const
{
    return d_value;
}

[% END -%]
[% BLOCK customizedtypeTraitDeclarations -%]
[% IF customizedtype.allocatesMemory -%]
BDEAT_DECL_CUSTOMIZEDTYPE_WITH_ALLOCATOR_BITWISEMOVEABLE_TRAITS([% namespace %]::[% Class %])
[%- ELSE -%]
BDEAT_DECL_CUSTOMIZEDTYPE_WITH_BITWISEMOVEABLE_TRAITS([% namespace %]::[% Class %])
[%- END -%]
[% END -%]
[% BLOCK customizedtypeInlineFreeFunctions -%]
inline
bool [% namespace %]::operator==(
        const [% namespace %]::[% Class %]& lhs,
        const [% namespace %]::[% Class %]& rhs)
{
    return lhs.d_value == rhs.d_value;
}

inline
bool [% namespace %]::operator!=(
        const [% namespace %]::[% Class %]& lhs,
        const [% namespace %]::[% Class %]& rhs)
{
    return lhs.d_value != rhs.d_value;
}

inline
bsl::ostream& [% namespace %]::operator<<(
        bsl::ostream& stream,
        const [% namespace %]::[% Class %]& rhs)
{
    return rhs.print(stream, 0, -1);
}
[% END -%]

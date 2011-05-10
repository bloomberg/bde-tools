[% PROCESS sequence_util.t -%]
[% BLOCK sequenceClassDeclaration -%]
[% String.new("// $fatline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $fatline").center(79) %]

class [% Class %] {
[% FOREACH note = sequence.annotation.documentation -%]
[% NEXT UNLESS note.length -%]
[% formatComment(note, 4) %]
[% END -%]

[% sequence.annotation.appinfo.rawCppClass -%]
    // INSTANCE DATA
[% SET offlen = sequence.maxCpptypeLength - 15 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
[% IF sequence.holdsAllocator -%]
    bslma_Allocator[% offset %] *d_allocator_p;
[% SET allocatorTypeLength = String.new("bslma_Allocator").length -%]
[% IF sequence.maxCpptypeLength < allocatorTypeLength -%]
[% SET sequence.maxCpptypeLength = allocatorTypeLength -%]
[% END -%]
[% END -%]
[% FOREACH attribute = sortedAttributes -%]
[% SET offlen = sequence.maxCpptypeLength - attributeType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
[% IF attribute.allocatedType -%]
    [% attributeType %][% offset %] *[% attributeVar %];
[% ELSE -%]
    [% attributeType %][% offset %]  [% attributeVar %];
[% END -%]
[% SET comment = attribute.annotation.documentation.0 | collapse | lcfirst -%]
[% IF 0 < comment.length() -%]
[% formatComment("$comment", 8) %]
[% END -%]
[% END -%]

[% SET maxAttrNameLen = 0 -%]
[% FOREACH attribute = attributes -%]
[% IF ATTRIBUTE_NAME.length() > maxAttrNameLen -%]
[% maxAttrNameLen = ATTRIBUTE_NAME.length() -%]
[% END -%]
[% END -%]
  public:
    // TYPES
[% IF attributes.size -%]
    enum {
[% FOREACH attribute = attributes -%]
[% SET offlen = maxAttrNameLen - ATTRIBUTE_NAME.length() -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
      [% loop.first ? '  ' : ', ' -%]
      [%- %]ATTRIBUTE_ID_[% ATTRIBUTE_NAME %][% offset %] = [% -%]
                    [%- %][% attribute.id %]
[% END -%]
    };

[% END -%]
[% IF !sequence.omitIntrospection -%]
    enum {
        NUM_ATTRIBUTES = [% attributes.size %]
    };

[% IF attributes.size -%]
    enum {
[% FOREACH attribute = attributes -%]
[% SET offlen = maxAttrNameLen - ATTRIBUTE_NAME.length() -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
      [% loop.first ? '  ' : ', ' -%]
      [%- %]ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %][% offset %] = [% -%]
                      [%- loop.index %]
[% END -%]
    };
[% BLOCK IGNORED -%]
[% END -%]
[%- FOREACH attribute = attributes -%]
  [%- IF attribute.defineAssociatedType.defined %]
    typedef [%- String.new(attribute.cpptype) %] [% -%]
            [%- AttributeName | MixedMixed %]Type;
  [% END -%]
[% END -%]
[% END -%]

[% END -%]
    // CONSTANTS
[% IF !sequence.omitIntrospection -%]
    static const char CLASS_NAME[];

[% END -%]
[% FOREACH appInfoConstant = sequence.appInfoConstants -%]
    static const char APPINFO_[% appInfoConstant.name | UPPER_UPPER %][];

[% END -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.defaultCppVal.defined -%]
[% IF attribute.typeref.baseType.defined -%]
[% IF "bsl::string" == attribute.typeref.baseType -%]
    static const char DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %][];
[% ELSE -%]
    static const [% attribute.typeref.baseType %] [% -%]
                                [%- %]DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %];
[% END -%]
[% ELSE -%]
[% IF "bsl::string" == attributeType -%]
    static const char DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %][];
[% ELSE -%]
    static const [% attributeType %] DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %];
[% END -%]
[% END -%]

[% END -%]
[% END -%]
[% IF !sequence.omitIntrospection -%]
[% IF attributes.size > 0 -%]
    static const bdeat_AttributeInfo ATTRIBUTE_INFO_ARRAY[];

[% END -%]
[% END -%]
  public:
    // CLASS METHODS
    static int maxSupportedBdexVersion();
[% UNLESS opts.noComments -%]
        // Return the most current 'bdex' streaming version number supported by
        // this class.  See the 'bdex' package-level documentation for more
        // information on 'bdex' streaming of value-semantic types and
        // containers.
[% END -%]

[% IF !sequence.omitIntrospection -%]
    static const bdeat_AttributeInfo *lookupAttributeInfo(int id);
[% UNLESS opts.noComments -%]
        // Return attribute information for the attribute indicated by the
        // specified 'id' if the attribute exists, and 0 otherwise.
[% END -%]

    static const bdeat_AttributeInfo *lookupAttributeInfo(
                                                    const char *name,
                                                    int         nameLength);
[% UNLESS opts.noComments -%]
        // Return attribute information for the attribute indicated by the
        // specified 'name' of the specified 'nameLength' if the attribute
        // exists, and 0 otherwise.
[% END -%]

[% END -%]
    // CREATORS
[% IF sequence.allocatesMemory -%]
    explicit [% Class %](bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the default value.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
[% END -%]

[% IF sequence.parameterizedConstructor && attributes.size > 0 -%]
[% IF attributes.size == 1 -%]
    explicit
[% END -%]
[% SET maxCppArgLength = 0 -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.cppargtype.length > maxCppArgLength -%]
[% SET maxCppArgLength = attribute.cppargtype.length -%]
[% END -%]
[% END -%]
[% SET paramOffset = 5 + Class.length -%]
[% SET offset = String.new(' ').repeat(paramOffset) -%]
    [% Class %]([% FOREACH attribute = attributes -%]
[% SET paramOffset = maxCppArgLength - attribute.cppargtype.length -%]
[% SET paramVarOffset = String.new(' ').repeat(paramOffset) -%]
[% IF !loop.first %][% offset %][% END %][% attribute.cppargtype -%]  [% paramVarOffset %][% attributeName %],
[% END -%]
[% SET paramOffset = maxCppArgLength - 15 -%]
[% SET paramVarOffset = String.new(' ').repeat(paramOffset) -%]
[% offset %]bslma_Allocator [% paramVarOffset %]*basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' whose value is set from the value of the specified parameters.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
[% END -%]

[% END -%]
[% SET offset = String.new(' ').repeat(Class.length) -%]
    [% Class %](const [% Class %]& original,
    [% offset %] bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the value of the specified 'original' object.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
[% END -%]
[% ELSE -%]
    [% Class %]();
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the default value."), 8) %]
[% END -%]

[% IF sequence.parameterizedConstructor && attributes.size > 0 -%]
[% IF attributes.size == 1 -%]
    explicit
[% END -%]
[% SET maxCppArgLength = 0 -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.cppargtype.length > maxCppArgLength -%]
[% SET maxCppArgLength = attribute.cppargtype.length -%]
[% END -%]
[% END -%]
[% SET paramOffset = 5 + Class.length -%]
[% SET offset = String.new(' ').repeat(paramOffset) -%]
    [% Class %]([% FOREACH attribute = attributes -%]
[% SET paramOffset = maxCppArgLength - attribute.cppargtype.length -%]
[% SET paramVarOffset = String.new(' ').repeat(paramOffset) -%]
[% IF !loop.first %][% offset %][% END %][% attribute.cppargtype -%] [% paramVarOffset %][% attributeName %][% IF !loop.last %],[% ELSE %]);[% END %]
[% END -%]
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' whose value is represented by the specified parameters."), 8) %]
[% END -%]

[% END -%]
    [% Class %](const [% Class %]& original);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the value of the specified 'original' object."), 8) %]
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

[% IF !sequence.noAggregateConversion -%]
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

[% IF !sequence.omitIntrospection -%]
    template<class MANIPULATOR>
    int manipulateAttributes(MANIPULATOR& manipulator);
[% UNLESS opts.noComments -%]
        // Invoke the specified 'manipulator' sequentially on the address of
        // each (modifiable) attribute of this object, supplying 'manipulator'
        // with the corresponding attribute information structure until such
        // invocation returns a non-zero value.  Return the value from the
        // last invocation of 'manipulator' (i.e., the invocation that
        // terminated the sequence).
[% END -%]

    template<class MANIPULATOR>
    int manipulateAttribute(MANIPULATOR& manipulator, int id);
[% UNLESS opts.noComments -%]
        // Invoke the specified 'manipulator' on the address of
        // the (modifiable) attribute indicated by the specified 'id',
        // supplying 'manipulator' with the corresponding attribute
        // information structure.  Return the value returned from the
        // invocation of 'manipulator' if 'id' identifies an attribute of this
        // class, and -1 otherwise.
[% END -%]

    template<class MANIPULATOR>
    int manipulateAttribute(MANIPULATOR&  manipulator,
                            const char   *name,
                            int           nameLength);
[% UNLESS opts.noComments -%]
        // Invoke the specified 'manipulator' on the address of
        // the (modifiable) attribute indicated by the specified 'name' of the
        // specified 'nameLength', supplying 'manipulator' with the
        // corresponding attribute information structure.  Return the value
        // returned from the invocation of 'manipulator' if 'name' identifies
        // an attribute of this class, and -1 otherwise.
[% END -%]

[% END -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.allowsDirectManipulation -%]
    [% attributeType %]& [% attributeName %]();
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Return a reference to the modifiable \"$AttributeName\" attribute of this object."), 8) %]
[% END -%]
[% ELSE -%]
    void set[% AttributeName %]([% attribute.cppargtype %] value);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Set the \"$AttributeName\" attribute of this object to the specified 'value'."), 8) %]
[% END -%]
[% END -%]

[% END -%]
    // ACCESSORS
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
[% IF !sequence.noAggregateConversion -%]

    int toAggregate(bcem_Aggregate *result) const;
[% UNLESS opts.noComments -%]
        // Load the specified 'result' with the value of this object.  Return
        // 0 on success, and a non-zero value otherwise.
[% END -%]
[% END -%]
[% IF !sequence.omitIntrospection -%]

    template<class ACCESSOR>
    int accessAttributes(ACCESSOR& accessor) const;
[% UNLESS opts.noComments -%]
        // Invoke the specified 'accessor' sequentially on each
        // (non-modifiable) attribute of this object, supplying 'accessor'
        // with the corresponding attribute information structure until such
        // invocation returns a non-zero value.  Return the value from the
        // last invocation of 'accessor' (i.e., the invocation that terminated
        // the sequence).
[% END -%]

    template<class ACCESSOR>
    int accessAttribute(ACCESSOR& accessor, int id) const;
[% UNLESS opts.noComments -%]
        // Invoke the specified 'accessor' on the (non-modifiable) attribute
        // of this object indicated by the specified 'id', supplying 'accessor'
        // with the corresponding attribute information structure.  Return the
        // value returned from the invocation of 'accessor' if 'id' identifies
        // an attribute of this class, and -1 otherwise.
[% END -%]

    template<class ACCESSOR>
    int accessAttribute(ACCESSOR&   accessor,
                        const char *name,
                        int         nameLength) const;
[% UNLESS opts.noComments -%]
        // Invoke the specified 'accessor' on the (non-modifiable) attribute
        // of this object indicated by the specified 'name' of the specified
        // 'nameLength', supplying 'accessor' with the corresponding attribute
        // information structure.  Return the value returned from the
        // invocation of 'accessor' if 'name' identifies an attribute of this
        // class, and -1 otherwise.
[% END -%]
[% END -%]
[% FOREACH attribute = attributes -%]

    const [% attributeType %]& [% attributeName %]() const;
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Return a reference to the non-modifiable \"$AttributeName\" attribute of this object."), 8) %]
[% END -%]
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
[% BLOCK sequenceInlineMethods -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

// CLASS METHODS
inline
int [% Class %]::maxSupportedBdexVersion()
{
    return 1;  // versions start at 1.
}

// MANIPULATORS
template <class STREAM>
STREAM& [% Class %]::bdexStreamIn(STREAM& stream, int version)
{
    if (stream) {
        switch (version) {
          case [% sequence.bdexVersion %]: {
[% FOREACH attribute = attributes -%]
[% IF 'enumeration' == attribute.typeref.trait
   && !attribute.isNullable
   && attribute.maxOccurs == '1' -%]
[% SET attpkg = attribute.explicitPackage || attribute.typeref.package -%]
[% SET attpkg = (attpkg == cmp.package)
              ? ""
              : String.new(attpkg).append("::") -%]
            [% attpkg %][% attribute.typeref.cpptype %]::bdexStreamIn([% -%]
                  [%- %]stream, [% -%]
                  [%- %][% attributeVar %], [% -%]
                  [%- %][% attribute.bdexVersion %]);
[% ELSE -%]
[% star = attribute.allocatedType ? '*' : '' -%]
            bdex_InStreamFunctions::streamIn([% -%]
                  [%- %]stream, [% -%]
                  [%- %][% star %][% attributeVar %], [% -%]
                  [%- %][% attribute.bdexVersion %]);
[% END -%]
[% END -%]
          } break;
          default: {
            stream.invalidate();
          }
        }
    }
    return stream;
}

[% IF !sequence.omitIntrospection -%]
template <class MANIPULATOR>
int [% Class %]::manipulateAttributes(MANIPULATOR& manipulator)
{
    int ret[%- 0 == attributes.size ? ' = 0' : '' -%];

[% FOREACH attribute = attributes -%]
[% addr = attribute.allocatedType ? '' : '&' -%]
    ret = manipulator([% addr %][% attributeVar %], [% -%]
            [%- %]ATTRIBUTE_INFO_ARRAY[[% -%]
            [%- %]ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]]);
    if (ret) {
        return ret;
    }

[% END -%]
    return ret;
}

template <class MANIPULATOR>
int [% Class %]::manipulateAttribute(MANIPULATOR& manipulator, int id)
{
    enum { NOT_FOUND = -1 };

    switch (id) {
[% FOREACH attribute = attributes -%]
      case ATTRIBUTE_ID_[% ATTRIBUTE_NAME %]: {
[% addr = attribute.allocatedType ? '' : '&' -%]
        return manipulator([% addr %][% attributeVar %], [% -%]
          [%- %]ATTRIBUTE_INFO_ARRAY[ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]]);
      } break;
[% END -%]
      default:
        return NOT_FOUND;
    }
}

template <class MANIPULATOR>
int [% Class %]::manipulateAttribute(
        MANIPULATOR&  manipulator,
        const char   *name,
        int           nameLength)
{
    enum { NOT_FOUND = -1 };

    const bdeat_AttributeInfo *attributeInfo =
           lookupAttributeInfo(name, nameLength);
    if (0 == attributeInfo) {
        return NOT_FOUND;
    }

    return manipulateAttribute(manipulator, attributeInfo->d_id);
}

[% END -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.allowsDirectManipulation -%]
inline
[% attributeType %]& [% Class %]::[% attributeName %]()
{
[% star = attribute.allocatedType ? '*' : '' -%]
    return [% star %][% attributeVar %];
}
[% ELSE -%]
inline
void [% Class %]::set[% AttributeName %]([% attribute.cppargtype %] value)
{
[% star = attribute.allocatedType ? '*' : '' -%]
    [% star %][% attributeVar %] = value;
}
[% END -%]

[% END -%]
// ACCESSORS
template <class STREAM>
STREAM& [% Class %]::bdexStreamOut(STREAM& stream, int version) const
{
    switch (version) {
      case [% sequence.bdexVersion %]: {
[% FOREACH attribute = attributes -%]
[% star = attribute.allocatedType ? '*' : '' -%]
        bdex_OutStreamFunctions::streamOut([% -%]
                  [%- %]stream, [% -%]
                  [%- %][% star %][% attributeVar %], [% -%]
                  [%- %][% attribute.bdexVersion %]);
[% END -%]
      } break;
    }
    return stream;
}

[% IF !sequence.omitIntrospection -%]
template <class ACCESSOR>
int [% Class %]::accessAttributes(ACCESSOR& accessor) const
{
    int ret[%- 0 == attributes.size ? ' = 0' : '' -%];

[% FOREACH attribute = attributes -%]
[% star = attribute.allocatedType ? '*' : '' -%]
    ret = accessor([% star %][% attributeVar %], [% -%]
            [%- %]ATTRIBUTE_INFO_ARRAY[[% -%]
            [%- %]ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]]);
    if (ret) {
        return ret;
    }

[% END -%]
    return ret;
}

template <class ACCESSOR>
int [% Class %]::accessAttribute(ACCESSOR& accessor, int id) const
{
    enum { NOT_FOUND = -1 };

    switch (id) {
[% FOREACH attribute = attributes -%]
      case ATTRIBUTE_ID_[% ATTRIBUTE_NAME %]: {
[% star = attribute.allocatedType ? '*' : '' -%]
        return accessor([% star %][% attributeVar %], [% -%]
            [%- %]ATTRIBUTE_INFO_ARRAY[ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]]);
      } break;
[% END -%]
      default:
        return NOT_FOUND;
    }
}

template <class ACCESSOR>
int [% Class %]::accessAttribute(
        ACCESSOR&   accessor,
        const char *name,
        int         nameLength) const
{
    enum { NOT_FOUND = -1 };

    const bdeat_AttributeInfo *attributeInfo =
          lookupAttributeInfo(name, nameLength);
    if (0 == attributeInfo) {
       return NOT_FOUND;
    }

    return accessAttribute(accessor, attributeInfo->d_id);
}

[% END -%]
[% FOREACH attribute = attributes -%]
inline
const [% attributeType %]& [% Class %]::[% attributeName %]() const
{
[% star = attribute.allocatedType ? '*' : '' -%]
    return [% star %][% attributeVar %];
}

[% END -%]
[% END -%]
[% BLOCK sequenceTraitDeclarations -%]
[%- IF sequence.allocatesMemory -%]
BDEAT_DECL_SEQUENCE_WITH_ALLOCATOR_BITWISEMOVEABLE_TRAITS([% namespace %]::[% Class %])
[%- ELSE -%]
BDEAT_DECL_SEQUENCE_WITH_BITWISEMOVEABLE_TRAITS([% namespace %]::[% Class %])
[%- END -%]
[% END -%]
[% BLOCK sequenceInlineFreeFunctions -%]
inline
bool [% namespace -%]::operator==(
[% IF 0 == attributes.size -%]
        const [% namespace %]::[% Class %]&,
        const [% namespace %]::[% Class %]&)
{
    return true;
[% ELSE -%]
        const [% namespace %]::[% Class %]& lhs,
        const [% namespace %]::[% Class %]& rhs)
{
    return [% -%]
[% FOREACH attribute = attributes -%]
[% IF loop.first -%]
           [%- %] lhs.[% attributeName %]() == rhs.[% attributeName %]()[% -%]
[% ELSE -%]
         && lhs.[% attributeName %]() == rhs.[% attributeName %]()[% -%]
[% END -%]
[%- loop.last ? ';' : '' %]
[% END -%]
[% END -%]
}

inline
bool [% namespace -%]::operator!=(
[% IF 0 == attributes.size -%]
        const [% namespace %]::[% Class %]&,
        const [% namespace %]::[% Class %]&)
{
    return false;
[% ELSE -%]
        const [% namespace %]::[% Class %]& lhs,
        const [% namespace %]::[% Class %]& rhs)
{
    return [% -%]
[% FOREACH attribute = attributes -%]
[% IF loop.first -%]
           [%- %] lhs.[% attributeName %]() != rhs.[% attributeName %]()[% -%]
[% ELSE -%]
         || lhs.[% attributeName %]() != rhs.[% attributeName %]()[% -%]
[% END -%]
[%- loop.last ? ';' : '' %]
[% END -%]
[% END -%]
}

inline
bsl::ostream& [% namespace -%]::operator<<(
        bsl::ostream& stream,
        const [% namespace %]::[% Class %]& rhs)
{
    return rhs.print(stream, 0, -1);
}
[% END -%]

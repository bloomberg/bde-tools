[% PROCESS choice_util.t -%]
[% BLOCK choiceClassDeclaration -%]
[% String.new("// $fatline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $fatline").center(79) %]

class [% Class %] {
[% FOREACH note = choice.annotation.documentation -%]
[% NEXT UNLESS note.length -%]
[% formatComment(note, 4) %]
[% END -%]

[% choice.annotation.appinfo.rawCppClass -%]
    // INSTANCE DATA
    union {
[% FOREACH selection = selections -%]
[% IF selection.allocatedType -%]
[% SET offlen = choice.maxCpptypeLength + 20 - selectionImplType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        [% selectionType %][% offset %] *[% selectionField %];
[% ELSE -%]
[% SET offlen = choice.maxCpptypeLength - selectionImplType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        bdes_ObjectBuffer< [% selectionImplType %] >[% offset %] [% selectionField %];
[% END -%]
[% SET comment = selection.annotation.documentation.0 | collapse | lcfirst -%]
[% IF 0 < comment.length() -%]
[% formatComment("$comment", 12) %]
[% END -%]
[% END -%]
    };

[% SET bufferTypeLength = String.new("bdes_ObjectBuffer<  >").length() -%]
[% SET offlen = choice.maxCpptypeLength + bufferTypeLength + 1 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
    int[% offset %] d_selectionId;
[% IF choice.allocatesMemory -%]
[% SET allocatorTypeLength = String.new("bslma_Allocator").length() -%]
[% SET offlen = choice.maxCpptypeLength
              + bufferTypeLength
              - allocatorTypeLength
              + 3 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
    bslma_Allocator[% offset %] *d_allocator_p;
[% END -%]

[% SET maxSelNameLen = 0 -%]
[% FOREACH selection = selections -%]
[% IF SELECTION_NAME.length() > maxSelNameLen -%]
[% maxSelNameLen = SELECTION_NAME.length() -%]
[% END -%]
[% END -%]
  public:
    // TYPES
    enum {
[% SET offlen = maxSelNameLen - 9 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        SELECTION_ID_UNDEFINED[% offset %] = -1

[% FOREACH selection = selections -%]
[% SET offlen = maxSelNameLen - SELECTION_NAME.length() -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
      , SELECTION_ID_[% SELECTION_NAME %][% offset %] = [% -%]
                    [%- %][% selection.id %]
[% END -%]
    };

[% IF !choice.omitIntrospection -%]
    enum {
        NUM_SELECTIONS = [% selections.size %]
    };

    enum {
[% FOREACH selection = selections -%]
[% SET offlen = maxSelNameLen - SELECTION_NAME.length() -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
      [% loop.first ? '  ' : ', ' -%]
      [%- %]SELECTION_INDEX_[% SELECTION_NAME %][% offset %] = [% -%]
                      [%- loop.index %]
[% END -%]
    };

[% END -%]
[% IF selections.length() -%]
[% FOREACH selection = selections -%]
  [% IF selection.defineAssociatedType.defined -%]
    typedef [%- String.new(selection.cpptype) -%] [% SelectionName | MixedMixed %]Type;
  [% END -%]
[% END -%]

[% END -%]
[% IF !choice.omitIntrospection -%]
    // CONSTANTS
    static const char CLASS_NAME[];

[% ELSIF choice.appInfoConstants.length() -%]
    // CONSTANTS
[% END -%]
[% FOREACH appInfoConstant = choice.appInfoConstants -%]
    static const char APPINFO_[% appInfoConstant.name | UPPER_UPPER %][];

[% END -%]
[% FOREACH selection = selections -%]
[% IF selection.defaultCppVal.defined -%]
[% IF selection.typeref.baseType.defined -%]
    static const [% selection.typeref.baseType %] [% -%]
                                [%- %]DEFAULT_INITIALIZER_[% SELECTION_NAME %];
[% ELSE -%]
[% IF "bsl::string" == selectionIntfType -%]
    static const char DEFAULT_INITIALIZER_[% SELECTION_NAME %][];
[% ELSE -%]
    static const [% selectionIntfType %] [% -%]
                                [%- %]DEFAULT_INITIALIZER_[% SELECTION_NAME %];
[% END -%]
[% END -%]

[% END -%]
[% END -%]
[% IF !choice.omitIntrospection -%]
    static const bdeat_SelectionInfo SELECTION_INFO_ARRAY[];

[% END -%]
    // CLASS METHODS
    static int maxSupportedBdexVersion();
[% UNLESS opts.noComments -%]
        // Return the most current 'bdex' streaming version number supported by
        // this class.  See the 'bdex' package-level documentation for more
        // information on 'bdex' streaming of value-semantic types and
        // containers.
[% END -%]

[% IF !choice.omitIntrospection -%]
    static const bdeat_SelectionInfo *lookupSelectionInfo(int id);
[% UNLESS opts.noComments -%]
        // Return selection information for the selection indicated by the
        // specified 'id' if the selection exists, and 0 otherwise.
[% END -%]

    static const bdeat_SelectionInfo *lookupSelectionInfo(
                                                    const char *name,
                                                    int         nameLength);
[% UNLESS opts.noComments -%]
        // Return selection information for the selection indicated by the
        // specified 'name' of the specified 'nameLength' if the selection
        // exists, and 0 otherwise.
[% END -%]

[% END -%]
    // CREATORS
[% IF choice.allocatesMemory -%]
    explicit [% Class %](bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the default value.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
[% END -%]

[% SET offset = String.new(' ').repeat(Class.length) -%]
    [% Class %](const [% Class %]& original,
    [% offset %]bslma_Allocator *basicAllocator = 0);
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Create an object of type '$Class' having the value of the specified 'original' object.  Use the optionally specified 'basicAllocator' to supply memory.  If 'basicAllocator' is 0, the currently installed default allocator is used."), 8) %]
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

[% IF !choice.noAggregateConversion -%]
    int fromAggregate(const bcem_Aggregate& aggregate);
[% UNLESS opts.noComments -%]
        // Store the value of the specified 'aggregate' into this object.
        // Return 0 on success, and a non-zero value otherwise.
[% END -%]

[% END -%]
    void reset();
[% UNLESS opts.noComments -%]
        // Reset this object to the default value (i.e., its value upon default
        // construction).
[% END -%]

[% IF !choice.omitIntrospection -%]
    int makeSelection(int selectionId);
[% UNLESS opts.noComments -%]
        // Set the value of this object to be the default for the selection
        // indicated by the specified 'selectionId'.  Return 0 on success, and
        // non-zero value otherwise (i.e., the selection is not found).
[% END -%]

    int makeSelection(const char *name, int nameLength);
[% UNLESS opts.noComments -%]
        // Set the value of this object to be the default for the selection
        // indicated by the specified 'name' of the specified 'nameLength'.
        // Return 0 on success, and non-zero value otherwise (i.e., the
        // selection is not found).
[% END -%]

[% END -%]
[% FOREACH selection = selections -%]
[% IF selection.allocatedType -%]
    [% selectionType %]& make[% SelectionName %]();
    [% selectionType %]& make[% SelectionName %]([% selectionArgType %] value);
[% ELSE -%]
    [% selectionImplType %]& make[% SelectionName %]();
    [% selectionImplType %]& make[% SelectionName %]([% selectionArgType %] value);
[% END -%]
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Set the value of this object to be a \"$SelectionName\" value.  Optionally specify the 'value' of the \"$SelectionName\".  If 'value' is not specified, the default \"$SelectionName\" value is used."), 8) %]
[% END -%]

[% END -%]
[% IF !choice.omitIntrospection -%]
    template<class MANIPULATOR>
    int manipulateSelection(MANIPULATOR& manipulator);
[% UNLESS opts.noComments -%]
        // Invoke the specified 'manipulator' on the address of the modifiable
        // selection, supplying 'manipulator' with the corresponding selection
        // information structure.  Return the value returned from the
        // invocation of 'manipulator' if this object has a defined selection,
        // and -1 otherwise.
[% END -%]

[% END -%]
[% FOREACH selection = selections -%]
[% IF selection.allowsDirectManipulation -%]
    [% selectionIntfType %]& [% selectionName %]();
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Return a reference to the modifiable \"$SelectionName\" selection of this object if \"$SelectionName\" is the current selection.  The behavior is undefined unless \"$SelectionName\" is the selection of this object."), 8) %]
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

[% IF !choice.noAggregateConversion -%]
    int toAggregate(bcem_Aggregate *result) const;
[% UNLESS opts.noComments -%]
        // Load the specified 'result' with the value of this object.  Return
        // 0 on success, and a non-zero value otherwise.
[% END -%]

[% END -%]
    int selectionId() const;
[% UNLESS opts.noComments -%]
        // Return the id of the current selection if the selection is defined,
        // and -1 otherwise.
[% END -%]

[% IF !choice.omitIntrospection -%]
    template<class ACCESSOR>
    int accessSelection(ACCESSOR& accessor) const;
[% UNLESS opts.noComments -%]
        // Invoke the specified 'accessor' on the non-modifiable selection,
        // supplying 'accessor' with the corresponding selection information
        // structure.  Return the value returned from the invocation of
        // 'accessor' if this object has a defined selection, and -1 otherwise.
[% END -%]
[% END -%]
[% FOREACH selection = selections -%]

    const [% selectionIntfType %]& [% selectionName %]() const;
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Return a reference to the non-modifiable \"$SelectionName\" selection of this object if \"$SelectionName\" is the current selection.  The behavior is undefined unless \"$SelectionName\" is the selection of this object."), 8) %]
[% END -%]

[%- END -%]
[% FOREACH selection = selections -%]

    bool is[% SelectionName %]Value() const;
[% UNLESS opts.noComments -%]
[% formatComment(String.new("Return 'true' if the value of this object is a \"$SelectionName\" value, and return 'false' otherwise."), 8) %]
[% END -%]
[% END -%]

    bool isUndefinedValue() const;
[% UNLESS opts.noComments -%]
        // Return 'true' if the value of this object is undefined, and 'false'
        // otherwise.
[% END -%]

    const char *selectionName() const;
[% UNLESS opts.noComments -%]
        // Return the symbolic name of the current selection of this object.
[% END -%]
};

// FREE OPERATORS
inline
bool operator==(const [% Class %]& lhs, const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
    // Return 'true' if the specified 'lhs' and 'rhs' objects have the same
    // value, and 'false' otherwise.  Two '[% Class %]' objects have the same
    // value if either the selections in both objects have the same ids and
    // the same values, or both selections are undefined.
[% END -%]

inline
bool operator!=(const [% Class %]& lhs, const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
    // Return 'true' if the specified 'lhs' and 'rhs' objects do not have the
    // same values, as determined by 'operator==', and 'false' otherwise.
[% END -%]

inline
bsl::ostream& operator<<(bsl::ostream& stream, const [% Class %]& rhs);
[% UNLESS opts.noComments -%]
    // Format the specified 'rhs' to the specified output 'stream' and
    // return a reference to the modifiable 'stream'.
[% END -%]
[% END -%]
[% BLOCK choiceInlineMethods -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

// CLASS METHODS
inline
int [% Class %]::maxSupportedBdexVersion()
{
    return 1;  // versions start at 1.
}

// CREATORS
[% IF choice.allocatesMemory -%]
inline
[% Class %]::[% Class %](bslma_Allocator *basicAllocator)
: d_selectionId(SELECTION_ID_UNDEFINED)
, d_allocator_p(bslma_Default::allocator(basicAllocator))
[% ELSE -%]
inline
[% Class %]::[% Class %]()
: d_selectionId(SELECTION_ID_UNDEFINED)
[% END -%]
{
}

inline
[% Class %]::~[% Class %]()
{
    reset();
}

// MANIPULATORS
template <class STREAM>
STREAM& [% Class %]::bdexStreamIn(STREAM& stream, int version)
{
    if (stream) {
        switch (version) {
          case [% choice.bdexVersion %]: {
            short selectionId;
            stream.getInt16(selectionId);
            if (!stream) {
                return stream;
            }
            switch (selectionId) {
[% FOREACH selection = selections -%]
              case SELECTION_ID_[% SELECTION_NAME %]: {
                make[% SelectionName %]();
[% IF selection.allocatedType -%]
                bdex_InStreamFunctions::streamIn(
                    stream, *[% selectionField %], [% selection.bdexVersion %]);
[% ELSE -%]
[% IF 'enumeration' == selection.typeref.trait
   && !selection.isNullable
   && selection.maxOccurs == '1' -%]
[% SET selpkg = selection.explicitPackage || selection.typeref.package -%]
[% SET selpkg = (selpkg == cmp.package)
              ? ""
              : String.new(selpkg).append("::") -%]
                [% selpkg %][% selection.typeref.cpptype %]::bdexStreamIn(
                    stream, [% -%]
                    [%- %][% selectionVar %], [% -%]
                    [%- %][% selection.bdexVersion %]);
[% ELSE -%]
                bdex_InStreamFunctions::streamIn(
                    stream, [% selectionVar %], [% selection.bdexVersion %]);
[% END -%]
[% END -%]
              } break;
[% END -%]
              case SELECTION_ID_UNDEFINED: {
                reset();
              } break;
              default:
                stream.invalidate();
            }
          } break;
          default: {
            stream.invalidate();
          }
        }
    }
    return stream;
}

[% IF !choice.omitIntrospection -%]
template <class MANIPULATOR>
int [% Class %]::manipulateSelection(MANIPULATOR& manipulator)
{
    switch (d_selectionId) {
[% FOREACH selection = selections -%]
      case [% Class %]::SELECTION_ID_[% SELECTION_NAME %]:
[% IF selection.allocatedType -%]
        return manipulator([% selectionField %],
                SELECTION_INFO_ARRAY[[% -%]
                [%- %]SELECTION_INDEX_[% SELECTION_NAME %]]);
[% ELSE -%]
        return manipulator(&[% selectionVar %],
                SELECTION_INFO_ARRAY[[% -%]
                [%- %]SELECTION_INDEX_[% SELECTION_NAME %]]);
[% END -%]
[% END -%]
      default:
        BSLS_ASSERT([% Class %]::SELECTION_ID_UNDEFINED == d_selectionId);
        return -1;
    }
}

[% END -%]
[% FOREACH selection = selections -%]
[% IF selection.allowsDirectManipulation -%]
inline
[% selectionIntfType %]& [% Class %]::[% selectionName %]()
{
    BSLS_ASSERT(SELECTION_ID_[% SELECTION_NAME %] == d_selectionId);
[% IF selection.allocatedType -%]
    return *[% selectionField %];
[% ELSE -%]
    return [% selectionVar %];
[% END -%]
}

[% END -%]
[% END -%]
// ACCESSORS
template <class STREAM>
STREAM& [% Class %]::bdexStreamOut(STREAM& stream, int version) const
{
    switch (version) {
      case [% choice.bdexVersion %]: {
            stream.putInt16(d_selectionId);
            switch (d_selectionId) {
[% FOREACH selection = selections -%]
              case SELECTION_ID_[% SELECTION_NAME %]: {
[% IF selection.allocatedType -%]
                bdex_OutStreamFunctions::streamOut(
                    stream, *[% selectionField %], [% selection.bdexVersion %]);
[% ELSE -%]
                bdex_OutStreamFunctions::streamOut(
                    stream, [% selectionVar %], [% selection.bdexVersion %]);
[% END -%]
              } break;
[% END -%]
              default:
                BSLS_ASSERT(SELECTION_ID_UNDEFINED == d_selectionId);
            }
      } break;
    }
    return stream;
}

inline
int [% Class %]::selectionId() const
{
    return d_selectionId;
}

[% IF !choice.omitIntrospection -%]
template <class ACCESSOR>
int [% Class %]::accessSelection(ACCESSOR& accessor) const
{
    switch (d_selectionId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]:
[% IF selection.allocatedType -%]
        return accessor(*[% selectionField %],
                SELECTION_INFO_ARRAY[[% -%]
                [%- %]SELECTION_INDEX_[% SELECTION_NAME %]]);
[% ELSE -%]
        return accessor([% selectionVar %],
                SELECTION_INFO_ARRAY[[% -%]
                [%- %]SELECTION_INDEX_[% SELECTION_NAME %]]);
[% END -%]
[% END -%]
      default:
        BSLS_ASSERT(SELECTION_ID_UNDEFINED == d_selectionId);
        return -1;
    }
}

[% END -%]
[% FOREACH selection = selections -%]
inline
const [% selectionIntfType %]& [% Class %]::[% selectionName %]() const
{
    BSLS_ASSERT(SELECTION_ID_[% SELECTION_NAME %] == d_selectionId);
[% IF selection.allocatedType -%]
    return *[% selectionField %];
[% ELSE -%]
    return [% selectionVar %];
[% END -%]
}

[% END -%]
[% FOREACH selection = selections -%]
inline
bool [% Class %]::is[% SelectionName %]Value() const
{
    return SELECTION_ID_[% SELECTION_NAME %] == d_selectionId;
}

[% END -%]
inline
bool [% Class %]::isUndefinedValue() const
{
    return SELECTION_ID_UNDEFINED == d_selectionId;
}
[% END -%]
[% BLOCK choiceTraitDeclarations -%]
[%- IF choice.allocatesMemory -%]
BDEAT_DECL_CHOICE_WITH_ALLOCATOR_BITWISEMOVEABLE_TRAITS([% namespace %]::[% Class %])
[%- ELSE -%]
BDEAT_DECL_CHOICE_WITH_BITWISEMOVEABLE_TRAITS([% namespace %]::[% Class %])
[%- END -%]
[% END -%]
[% BLOCK choiceInlineFreeFunctions -%]
inline
bool [% namespace -%]::operator==(
        const [% namespace %]::[% Class %]& lhs,
        const [% namespace %]::[% Class %]& rhs)
{
    typedef [% namespace %]::[% Class %] Class;
    if (lhs.selectionId() == rhs.selectionId()) {
        switch (rhs.selectionId()) {
[% FOREACH selection = selections -%]
          case Class::SELECTION_ID_[% SELECTION_NAME %]:
            return lhs.[% selectionName %]() == rhs.[% selectionName %]();
[% END -%]
          default:
            BSLS_ASSERT(Class::SELECTION_ID_UNDEFINED == rhs.selectionId());
            return true;
        }
    }
    else {
        return false;
   }
}

inline
bool [% namespace -%]::operator!=(
        const [% namespace %]::[% Class %]& lhs,
        const [% namespace %]::[% Class %]& rhs)
{
    return !(lhs == rhs);
}

inline
bsl::ostream& [% namespace -%]::operator<<(
        bsl::ostream& stream,
        const [% namespace %]::[% Class %]& rhs)
{
    return rhs.print(stream, 0, -1);
}
[% END -%]

[% PROCESS choice_util.t -%]
[% BLOCK ReturnSelectionInfo -%]
return &SELECTION_INFO_ARRAY[SELECTION_INDEX_[% SELECTION_NAME %]];
[%- END -%]
[% BLOCK choiceMethodDefinitions -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

// CONSTANTS

[% IF !choice.omitIntrospection -%]
const char [% Class %]::CLASS_NAME[] = "[% Class %]";

[% END -%]
[% FOREACH appInfoConstant = choice.appInfoConstants -%]
const char [% Class %]::APPINFO_[% appInfoConstant.name | UPPER_UPPER %][][%-%]
       [%- %] = [%- appInfoConstant.cppValue%];

[% END -%]
[% FOREACH selection = selections -%]
[% IF selection.defaultCppVal.defined -%]
[% IF selection.typeref.baseType.defined -%]
[% IF "bsl::string" == selectionIntfType -%]
const char [% Class %]::DEFAULT_INITIALIZER_[% SELECTION_NAME %][] = [% -%]
[% ELSE -%]
const [% selection.typeref.baseType %] [% -%]
      [%- Class %]::DEFAULT_INITIALIZER_[% SELECTION_NAME %] = [% -%]
[% END -%]
      [%- selection.defaultCppVal %];
[% ELSE -%]
[% IF "bsl::string" == selectionIntfType -%]
const char [% Class %]::DEFAULT_INITIALIZER_[% SELECTION_NAME %][] = [% -%]
[% ELSE -%]
const [% selectionType %] [% -%]
           [%- %][% Class %]::DEFAULT_INITIALIZER_[% SELECTION_NAME %] = [% -%]
[% END -%]
                                               [%- selection.defaultCppVal %];
[% END -%]

[% END -%]
[% END -%]
[% IF !choice.omitIntrospection -%]
const bdeat_SelectionInfo [% Class %]::SELECTION_INFO_ARRAY[] = {
[% FOREACH selection = selections -%]
    {
        SELECTION_ID_[% SELECTION_NAME %],
        "[% selection.origName | escapeQuotes %]",
        sizeof("[% selection.origName | escapeQuotes %]") - 1,
        "",
        bdeat_FormattingMode::[% selection.formattingMode | UPPER_UPPER -%]
        [%- IF selection.isAttribute %]
      | bdeat_FormattingMode::IS_ATTRIBUTE
        [%- END %]
        [%- IF selection.isUntagged %]
      | bdeat_FormattingMode::IS_UNTAGGED
        [%- END %]
        [%- IF selection.isSimpleContent %]
      | bdeat_FormattingMode::IS_SIMPLE_CONTENT
        [%- END %]
        [%- IF selection.isNillable %]
      | bdeat_FormattingMode::IS_NILLABLE
        [%- END %]
    }[% loop.last ? '' : ',' %]
[% END -%]
};

[% END -%]
// CLASS METHODS

[% IF !choice.omitIntrospection -%]
const bdeat_SelectionInfo *[% Class %]::lookupSelectionInfo(
        const char *name,
        int         nameLength)
{
[% FILTER indent -%]
[% INCLUDE selectionSearchBlock
    tree=selectionSearchTree depth=0
    visit='ReturnSelectionInfo' name='name' nameLength='nameLength' -%]
return 0;
[% END -%]
}

const bdeat_SelectionInfo *[% Class %]::lookupSelectionInfo(int id)
{
    switch (id) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]:
        return &SELECTION_INFO_ARRAY[SELECTION_INDEX_[% SELECTION_NAME %]];
[% END -%]
      default:
        return 0;
    }
}

[% END -%]
// CREATORS

[% IF choice.allocatesMemory -%]
[% Class %]::[% Class %](
    const [% Class %]& original,
    bslma_Allocator *basicAllocator)
: d_selectionId(original.d_selectionId)
, d_allocator_p(bslma_Default::allocator(basicAllocator))
[% ELSE -%]
[% Class %]::[% Class %](const [% Class %]& original)
: d_selectionId(original.d_selectionId)
[% END -%]
{
    switch (d_selectionId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]: {
[% IF choice.allocatesMemory && selection.allocatesMemory -%]
[% IF selection.allocatedType -%]
        [% selectionField %] = new (*d_allocator_p)
                [% selectionType %](*original.[% selectionField %], d_allocator_p);
[% ELSE -%]
        new ([% selectionBuffer %])
            [% selectionImplType %](
                original.[% selectionVar %], d_allocator_p);
[% END -%]
[% ELSE -%]
        new ([% selectionBuffer %])
            [% selectionImplType %](original.[% selectionVar %]);
[% END -%]
      } break;
[% END -%]
      default:
        BSLS_ASSERT(SELECTION_ID_UNDEFINED == d_selectionId);
    }
}

// MANIPULATORS

[% Class %]&
[% Class %]::operator=(const [% Class %]& rhs)
{
    if (this != &rhs) {
        switch (rhs.d_selectionId) {
[% FOREACH selection = selections -%]
          case SELECTION_ID_[% SELECTION_NAME %]: {
[% IF selection.allocatedType -%]
            make[% SelectionName %](*rhs.[% selectionField %]);
[% ELSE -%]
            make[% SelectionName %](rhs.[% selectionVar %]);
[% END -%]
          } break;
[% END -%]
          default:
            BSLS_ASSERT(SELECTION_ID_UNDEFINED == rhs.d_selectionId);
            reset();
        }
    }
    return *this;
}

[% IF !choice.noAggregateConversion -%]
int [% Class %]::fromAggregate(const bcem_Aggregate& aggregate)
{
    int rc = 0;

    int selectorId = aggregate.selectorId();
    switch (selectorId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]: {
        rc = bcem_AggregateUtil::fromAggregate(&make[% SelectionName %](),
                                               aggregate,
                                               selectorId);
      } break;
[% END -%]
      default: {
        rc = bcem_Aggregate::BCEM_ERR_BAD_CONVERSION;
      }
    }

    return rc;
}

[% END -%]
void [% Class %]::reset()
{
    switch (d_selectionId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]: {
[% IF selection.requiresDestruction -%]
[% IF selection.allocatedType -%]
        d_allocator_p->deleteObject([% selectionField %]);
[% ELSE -%]
[% IF selectionType.search('::') || selectionType.search('<') -%]
        typedef [% selectionType %] Type;
        [% selectionVar %].~Type();
[% ELSE -%]
        [% selectionVar %].~[% selectionType %]();
[% END -%]
[% END -%]
[% ELSE -%]
        // no destruction required
[% END -%]
      } break;
[% END -%]
      default:
        BSLS_ASSERT(SELECTION_ID_UNDEFINED == d_selectionId);
    }

    d_selectionId = SELECTION_ID_UNDEFINED;
}

[% IF !choice.omitIntrospection -%]
int [% Class %]::makeSelection(int selectionId)
{
    switch (selectionId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]: {
        make[% SelectionName %]();
      } break;
[% END -%]
      case SELECTION_ID_UNDEFINED: {
        reset();
      } break;
      default:
        return -1;
    }
    return 0;
}

int [% Class %]::makeSelection(const char *name, int nameLength)
{
    const bdeat_SelectionInfo *selectionInfo =
           lookupSelectionInfo(name, nameLength);
    if (0 == selectionInfo) {
       return -1;
    }

    return makeSelection(selectionInfo->d_id);
}

[% END -%]
[% FOREACH selection = selections -%]
[% IF selection.allocatedType -%]
[% selectionType %]& [% Class %]::make[% SelectionName %]()
[% ELSE -%]
[% selectionImplType %]& [% Class %]::make[% SelectionName %]()
[% END -%]
{
    if (SELECTION_ID_[% SELECTION_NAME %] == d_selectionId) {
[% IF selection.defaultCppVal.defined -%]
[% IF selection.typeref.baseType.defined -%]
        [% selectionVar %].[% selection.typeref.fromFunction %]([% -%]
        [%- %]DEFAULT_INITIALIZER_[% SELECTION_NAME %]);
[% ELSE -%]
        [% selectionVar %] = DEFAULT_INITIALIZER_[% SELECTION_NAME %];
[% END -%]
[% ELSE -%]
[% IF selection.allocatedType -%]
        bdeat_ValueTypeFunctions::reset([% selectionField %]);
[% ELSE -%]
        bdeat_ValueTypeFunctions::reset(&[% selectionVar %]);
[% END -%]
[% END -%]
    }
    else {
        reset();
[% IF selection.defaultCppVal.defined -%]
[% IF choice.allocatesMemory && selection.allocatesMemory -%]
        new ([% selectionBuffer %])
            [% selectionType %](DEFAULT_INITIALIZER_[% SELECTION_NAME %],[% -%]
                         [%- %] d_allocator_p);
[% ELSE -%]
        new ([% selectionBuffer %])
            [% selectionType %](DEFAULT_INITIALIZER_[% SELECTION_NAME %]);
[% END -%]
[% ELSE -%]
[% IF choice.allocatesMemory && selection.allocatesMemory -%]
[% IF selection.allocatedType -%]
        [% selectionField %] = new (*d_allocator_p)
                [% selectionType %](d_allocator_p);
[% ELSE -%]
        new ([% selectionBuffer %])
                [% selectionImplType %](d_allocator_p);
[% END -%]
[% ELSE -%]
        new ([% selectionBuffer %])
    [% IF selection.typeref.trait == 'enumeration'
        && !selection.isNullable
        && !selection.defaultCppVal.defined
        && 1 == selection.maxOccurs -%]
                [% selectionType %](static_cast<[% selectionType %]>(0));
    [% ELSE -%]
        [% selectionType %]();
    [% END -%]
[% END -%]
[% END %]
        d_selectionId = SELECTION_ID_[% SELECTION_NAME %];
    }

[% IF selection.allocatedType -%]
    return *[% selectionField %];
[% ELSE -%]
    return [% selectionVar %];
[% END -%]
}

[% IF selection.allocatedType -%]
[% selectionType %]& [% Class %]::make[% SelectionName %]([% selectionArgType %] value)
[% ELSE -%]
[% selectionImplType %]& [% Class %]::make[% SelectionName %]([% selectionArgType %] value)
[% END -%]
{
    if (SELECTION_ID_[% SELECTION_NAME %] == d_selectionId) {
[% IF selection.allocatedType -%]
        *[% selectionField %] = value;
[% ELSE -%]
        [% selectionVar %] = value;
[% END -%]
    }
    else {
        reset();
[% IF choice.allocatesMemory && selection.allocatesMemory -%]
[% IF selection.allocatedType -%]
        [% selectionField %] = new (*d_allocator_p)
                [% selectionType %](value, d_allocator_p);
[% ELSE -%]
        new ([% selectionBuffer %])
                [% selectionImplType %](value, d_allocator_p);
[% END -%]
[% ELSE -%]
        new ([% selectionBuffer %])
                [% selectionType %](value);
[% END -%]
        d_selectionId = SELECTION_ID_[% SELECTION_NAME %];
    }

[% IF selection.allocatedType -%]
    return *[% selectionField %];
[% ELSE -%]
    return [% selectionVar %];
[% END -%]
}

[% END -%]
// ACCESSORS

bsl::ostream& [% Class %]::print(
    bsl::ostream& stream,
    int           level,
    int           spacesPerLevel) const
{
    if (level < 0) {
        level = -level;
    }
    else {
        bdeu_Print::indent(stream, level, spacesPerLevel);
    }

    int levelPlus1 = level + 1;

    if (0 <= spacesPerLevel) {
        // multiline

        stream << "[\n";
        bdeu_Print::indent(stream, levelPlus1, spacesPerLevel);

        switch (d_selectionId) {
[% FOREACH selection = selections -%]
          case SELECTION_ID_[% SELECTION_NAME %]: {
            stream << "[% SelectionName %] = ";
[% cast = selection.cpptype == 'char' || selection.cpptype == 'unsigned char' ? '(int)' : '' -%]
[% IF selection.allocatedType -%]
            bdeu_PrintMethods::print(stream, [% cast %]*[% selectionField %],
                                     -levelPlus1, spacesPerLevel);
[% ELSE -%]
            bdeu_PrintMethods::print(stream, [% cast %][% selectionVar %],
                                     -levelPlus1, spacesPerLevel);
[% END -%]
          } break;
[% END -%]
          default:
            stream << "SELECTION UNDEFINED\n";
        }
        bdeu_Print::indent(stream, level, spacesPerLevel);
        stream << "]\n";
    }
    else {
        // single line

        stream << "[ ";

        switch (d_selectionId) {
[% FOREACH selection = selections -%]
          case SELECTION_ID_[% SELECTION_NAME %]: {
            stream << "[% SelectionName %] = ";
[% cast = selection.cpptype == 'char' || selection.cpptype == 'unsigned char' ? '(int)' : '' -%]
[% IF selection.allocatedType -%]
            bdeu_PrintMethods::print(stream, [% cast %]*[% selectionField %],
                                     -levelPlus1, spacesPerLevel);
[% ELSE -%]
            bdeu_PrintMethods::print(stream, [% cast %][% selectionVar %],
                                     -levelPlus1, spacesPerLevel);
[% END -%]
          } break;
[% END -%]
          default:
            stream << "SELECTION UNDEFINED";
        }

        stream << " ]";
    }

    return stream << bsl::flush;
}

[% IF !choice.noAggregateConversion -%]
int [% Class %]::toAggregate(bcem_Aggregate *result) const
{
    bcem_Aggregate selection = result->makeSelectionById(d_selectionId);
    if (selection.isError()) {
        return selection.errorCode();
    }

    int rc = 0;

    switch (d_selectionId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]: {
        const [% selectionType %]& source = [% selectionName %]();
        rc = bcem_AggregateUtil::toAggregate(result,
                                             d_selectionId,
                                             source);
      } break;
[% END -%]
      default:
        BSLS_ASSERT(SELECTION_ID_UNDEFINED == d_selectionId);
    }

    return rc;
}
[% END -%]

const char *[% Class %]::selectionName() const
{
    switch (d_selectionId) {
[% FOREACH selection = selections -%]
      case SELECTION_ID_[% SELECTION_NAME %]:
[% IF !choice.omitIntrospection -%]
        return SELECTION_INFO_ARRAY[[% -%][%- %]SELECTION_INDEX_[% SELECTION_NAME %]].name();
[% ELSE -%]
        return "[% selection.origName | escapeQuotes %]";
[% END -%]
[% END -%]
      default:
        BSLS_ASSERT(SELECTION_ID_UNDEFINED == d_selectionId);
        return "(* UNDEFINED *)";
    }
}
[%- END -%]

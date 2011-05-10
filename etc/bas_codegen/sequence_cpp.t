[% PROCESS sequence_util.t -%]
[% BLOCK ReturnAttributeInfo -%]
return &ATTRIBUTE_INFO_ARRAY[ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]];
[%- END -%]
[% BLOCK sequenceMethodDefinitions -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

// CONSTANTS

[% IF !sequence.omitIntrospection -%]
const char [% Class %]::CLASS_NAME[] = "[% Class %]";

[% END -%]
[% FOREACH appInfoConstant = sequence.appInfoConstants -%]
const char [% Class %]::APPINFO_[% appInfoConstant.name | UPPER_UPPER %][][%-%]
       [%- %] = [%- appInfoConstant.cppValue%];

[% END -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.defaultCppVal.defined -%]
[% IF attribute.typeref.baseType.defined -%]
[% IF "bsl::string" == attribute.typeref.baseType -%]
const char [% Class %]::DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %][] = [% -%]
[% ELSE -%]
const [% attribute.typeref.baseType %] [% -%]
      [%- %][% Class %]::DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %] = [% -%]
[% END -%]
      [%- attribute.defaultCppVal %];
[% ELSE -%]
[% IF "bsl::string" == attributeType -%]
const char [% Class %]::DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %][] = [% -%]
[% ELSE -%]
const [% attributeType %] [% -%]
           [%- %][% Class %]::DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %] = [% -%]
[% END -%]
                                                [%- attribute.defaultCppVal %];
[% END -%]

[% END -%]
[% END -%]
[% IF !sequence.omitIntrospection -%]
[% IF attributes.size > 0 -%]
const bdeat_AttributeInfo [% Class %]::ATTRIBUTE_INFO_ARRAY[] = {
[% FOREACH attribute = attributes -%]
    {
        ATTRIBUTE_ID_[% ATTRIBUTE_NAME %],
        "[% attribute.origName | escapeQuotes %]",
        sizeof("[% attribute.origName | escapeQuotes %]") - 1,
        "",
        bdeat_FormattingMode::[% attribute.formattingMode | UPPER_UPPER -%]
        [%- IF attribute.isAttribute %]
      | bdeat_FormattingMode::IS_ATTRIBUTE
        [%- END %]
        [%- IF attribute.isUntagged %]
      | bdeat_FormattingMode::IS_UNTAGGED
        [%- END %]
        [%- IF attribute.isSimpleContent %]
      | bdeat_FormattingMode::IS_SIMPLE_CONTENT
        [%- END %]
        [%- IF attribute.isNillable %]
      | bdeat_FormattingMode::IS_NILLABLE
        [%- END %]
    }[% loop.last ? '' : ',' %]
[% END -%]
};
[% END -%]

[% END -%]
// CLASS METHODS

[% IF !sequence.omitIntrospection -%]
const bdeat_AttributeInfo *[% Class %]::lookupAttributeInfo(
        const char *name,
        int         nameLength)
{
[% FOREACH attribute = attributes -%]
[% IF attribute.isUntagged && "choice" == attribute.typeref.trait -%]
[% FOREACH choice = attribute.typeref.choice -%]
    if (bdeu_String::areEqualCaseless("[% choice.name %]", name, nameLength)) {
        return &ATTRIBUTE_INFO_ARRAY[ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]];
    }

[% END -%]
[% END -%]
[% END -%]
[% FILTER indent -%]
[% INCLUDE attributeSearchBlock
    tree=attributeSearchTree depth=0
    visit='ReturnAttributeInfo' name='name' nameLength='nameLength' -%]
return 0;
[% END -%]
}

const bdeat_AttributeInfo *[% Class %]::lookupAttributeInfo(int id)
{
    switch (id) {
[% FOREACH attribute = attributes -%]
      case ATTRIBUTE_ID_[% ATTRIBUTE_NAME %]:
        return &ATTRIBUTE_INFO_ARRAY[ATTRIBUTE_INDEX_[% ATTRIBUTE_NAME %]];
[% END -%]
      default:
        return 0;
    }
}

[% END -%]
// CREATORS

[% IF sequence.allocatesMemory -%]
[% Class %]::[% Class %](bslma_Allocator *basicAllocator)
[% IF sequence.holdsAllocator -%]
: d_allocator_p(bslma_Default::allocator(basicAllocator))
[% END -%]
[% FOREACH attribute = sortedAttributes -%]
[% UNLESS attribute.allocatedType -%]
[% SET constructorArgs = [] -%]
[% IF attribute.defaultCppVal.defined -%]
[% SET argument = 'DEFAULT_INITIALIZER_' _ ATTRIBUTE_NAME -%]
      [%- constructorArgs.push(argument) -%]
[% END -%]
[% IF attribute.allocatesMemory -%]
    [%- constructorArgs.push('basicAllocator') -%]
[%- END -%]
[% loop.first && !sequence.holdsAllocator ? ': ' : ', ' -%]
    [%- IF attribute.typeref.trait == 'enumeration'
        && !attribute.isNullable
        && !attribute.defaultCppVal.defined
        && 1 == attribute.maxOccurs -%]
        [%- attributeVar %](static_cast<[% attribute.cppargtype %]>(0))
    [%- ELSE -%]
        [%- attributeVar %]([% constructorArgs.join(', ') %])
    [%- END %]
[% END -%]
[% END -%]
{
[% FOREACH attribute = sortedAttributes -%]
[% IF attribute.allocatedType -%]
[% SET constructorArgs = [] -%]
[% IF attribute.allocatesMemory -%]
    [%- constructorArgs.push('d_allocator_p') -%]
[%- END -%]
    [% attributeVar %] = new (*d_allocator_p)
            [% attributeType -%]([% constructorArgs.join(', ') %]);
[% END -%]
[% END -%]
}

[% IF sequence.parameterizedConstructor && attributes.size > 0 -%]
[% SET maxCppArgLength = 0 -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.cppargtype.length > maxCppArgLength -%]
[% SET maxCppArgLength = attribute.cppargtype.length -%]
[% END -%]
[% END -%]
[% SET paramOffset = 3 + Class.length * 2 -%]
[% SET offset = String.new(' ').repeat(paramOffset) -%]
[% Class %]::[% Class %]([% FOREACH attribute = attributes -%]
[% SET paramOffset = maxCppArgLength - attribute.cppargtype.length -%]
[% SET paramVarOffset = String.new(' ').repeat(paramOffset) -%]
[% IF !loop.first %][% offset %][% END %][% attribute.cppargtype -%]  [% paramVarOffset %][% attributeName %],
[% END -%]
[% SET paramOffset = maxCppArgLength - 15 -%]
[% SET paramVarOffset = String.new(' ').repeat(paramOffset) -%]
[% offset %]bslma_Allocator [% paramVarOffset %]*basicAllocator)
[% IF sequence.holdsAllocator -%]
: d_allocator_p(bslma_Default::allocator(basicAllocator))
[% END -%]
[% FOREACH attribute = sortedAttributes -%]
[% UNLESS attribute.allocatedType -%]
[% SET constructorArgs = [] -%] 
[%- constructorArgs.push(attributeName) -%]
[% IF attribute.allocatesMemory -%]
    [%- constructorArgs.push('basicAllocator') -%]
[%- END -%]
[% loop.first && !sequence.holdsAllocator ? ': ' : ', ' -%]
        [%- attributeVar %]([% constructorArgs.join(', ') %])
[% END -%]
[% END -%]
{
[% FOREACH attribute = sortedAttributes -%]
[% IF attribute.allocatedType -%]
[% SET constructorArgs = [] -%]
[%- constructorArgs.push(attributeName) -%]
[% IF attribute.allocatesMemory -%]
    [%- constructorArgs.push('d_allocator_p') -%]
[%- END -%]
    [% attributeVar %] = new (*d_allocator_p)
            [% attributeType -%]([% constructorArgs.join(', ') %]);
[% END -%]
[% END -%]
}

[% END -%]
[% SET paramOffset = 3 + Class.length * 2 -%]
[% SET offset = String.new(' ').repeat(paramOffset) -%]
[% Class %]::[% Class %](const [% Class %]& original,
[% offset %]bslma_Allocator *basicAllocator)
[% IF sequence.holdsAllocator -%]
: d_allocator_p(bslma_Default::allocator(basicAllocator))
[% END -%]
[% FOREACH attribute = sortedAttributes -%]
[% UNLESS attribute.allocatedType -%]
[% SET constructorArgs = [ String.new('original.d_').append(mixedMixed(attribute.name)) ] -%]
[% IF attribute.allocatesMemory -%]
    [%- constructorArgs.push('basicAllocator') -%]
[%- END -%]
[% loop.first && !sequence.holdsAllocator ? ': ' : ', ' -%]
    [%- attributeVar %]([% constructorArgs.join(', ') %])
[% END -%]
[% END -%]
{
[% FOREACH attribute = sortedAttributes -%]
[% IF attribute.allocatedType -%]
[% IF attribute.allocatedType -%]
[% SET constructorArgs = [ String.new('*original.d_').append(mixedMixed(attribute.name)) ] -%]
[% ELSE -%]
[% SET constructorArgs = [ String.new('original.d_').append(mixedMixed(attribute.name)) ] -%]
[% END -%]
[% IF attribute.allocatesMemory -%]
    [%- constructorArgs.push('d_allocator_p') -%]
[%- END -%]
    [% attributeVar %] = new (*d_allocator_p)
            [% attributeType %]([% constructorArgs.join(', ') %]);
[% END -%]
[% END -%]
}
[% ELSE -%]
[% Class %]::[% Class %]()
[% FOREACH attribute = sortedAttributes -%]
[% loop.first ? ': ' : ', ' -%]
[% IF attribute.defaultCppVal.defined -%]
    [%- attributeVar %](DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %])
[% ELSE -%]
    [%- IF attribute.typeref.trait == 'enumeration'
        && !attribute.isNullable
        && !attribute.defaultCppVal.defined
        && 1 == attribute.maxOccurs -%]
        [%- attributeVar %](static_cast<[% attribute.cppargtype %]>(0))
    [%- ELSE -%]
        [%- attributeVar %]()
    [%- END %]
[% END -%]
[% END -%]
{
}

[% IF sequence.parameterizedConstructor && attributes.size > 0 -%]
[% SET maxCppArgLength = 0 -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.cppargtype.length > maxCppArgLength -%]
[% SET maxCppArgLength = attribute.cppargtype.length -%]
[% END -%]
[% END -%]
[% SET paramOffset = 3 + Class.length * 2 -%]
[% SET offset = String.new(' ').repeat(paramOffset) -%]
[% Class %]::[% Class %]([% FOREACH attribute = attributes -%]
[% SET paramOffset = maxCppArgLength - attribute.cppargtype.length -%]
[% SET paramVarOffset = String.new(' ').repeat(paramOffset) -%]
[% IF !loop.first %][% offset %][% END %][% attribute.cppargtype -%] [% paramVarOffset %][% attributeName %][% IF !loop.last %],[% ELSE %])[% END %]
[% END -%]
[% FOREACH attribute = sortedAttributes -%]
[% loop.first ? ': ' : ', ' -%]
    [%- attributeVar %]([% attributeName %])
[% END -%]
{
}

[% END -%]
[% Class %]::[% Class %](const [% Class %]& original)
[% FOREACH attribute = sortedAttributes -%]
[% loop.first ? ': ' : ', ' -%]
    [%- attributeVar %](original.[% attributeVar %])
[% END -%]
{
}
[% END -%]

[% Class %]::~[% Class %]()
{
[% FOREACH attribute = sortedAttributes -%]
[% IF attribute.allocatedType -%]
    d_allocator_p->deleteObject([% attributeVar %]);
[% END -%]
[% END -%]
}

// MANIPULATORS

[% Class %]&
[% Class %]::operator=(const [% Class %]& rhs)
{
    if (this != &rhs) {
[% FOREACH attribute = attributes -%]
[% star = attribute.allocatedType ? '*' : '' -%]
        [% star %][% attributeVar %] = [% star %]rhs.[% attributeVar %];
[% END -%]
    }
    return *this;
}

[% IF !sequence.noAggregateConversion -%]
int [% Class %]::fromAggregate(const bcem_Aggregate& aggregate)
{
[% IF attributes.size > 0 -%]
    int rc;
[% SET requiredAttributes = [] -%]
[% SET optionalAttributes = [] -%]
[% FOREACH attribute = attributes -%]
[% IF attribute.isNullable
   || (attribute.isVectorFlag && attribute.minOccurs == 0)
   || attribute.defaultCppVal.defined -%]
[% optionalAttributes.push(attribute) -%]
[% ELSE -%]
[% requiredAttributes.push(attribute) -%]
[% END -%]
[% END -%]
[% IF requiredAttributes.size > 0 -%]
[% FOREACH attribute = requiredAttributes -%]
    [% IF loop.first -%]if ([% ELSE %]    [% END %](rc = bcem_AggregateUtil::fromAggregate(
[% IF attribute.allocatedType -%]
                       [% attributeVar %],
[% ELSE -%]
                       &[% attributeVar %],
[% END -%]
                       aggregate,
                       ATTRIBUTE_ID_[% ATTRIBUTE_NAME %]))[% IF !loop.last %] ||[% ELSE %])[% END %]
[% END -%]
    {
        return rc;
    }
[% END -%]
[% IF optionalAttributes.size > 0 -%]
[% FOREACH attribute = optionalAttributes -%]

    rc = bcem_AggregateUtil::fromAggregate(
[% IF attribute.allocatedType -%]
                       [% attributeVar %],
[% ELSE -%]
                       &[% attributeVar %],
[% END -%]
                       aggregate,
                       ATTRIBUTE_ID_[% ATTRIBUTE_NAME %]);
    if (rc != 0 && rc != bcem_Aggregate::BCEM_ERR_BAD_FIELDID) {
        return -1;
    }
[% END -%]
    
[% END -%]
[% END -%]
    return 0;
}

[% END -%]
void [% Class %]::reset()
{
[% FOREACH attribute = attributes -%]
[% IF attribute.defaultCppVal.defined -%]
[% IF attribute.typeref.baseType.defined -%]
    [% attributeVar %].[% attribute.typeref.fromFunction %]([% -%]
    [%- %]DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %]);
[% ELSE -%]
    [% attributeVar %] = DEFAULT_INITIALIZER_[% ATTRIBUTE_NAME %];
[% END -%]
[% ELSE -%]
[% addr = attribute.allocatedType ? '' : '&' -%]
    bdeat_ValueTypeFunctions::reset([% addr %][% attributeVar %]);
[% END -%]
[% END -%]
}

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

[% IF attributes.size -%]
    int levelPlus1 = level + 1;

[% END -%]
    if (0 <= spacesPerLevel) {
        // multiline

        stream << "[\n";

[% FOREACH attribute = attributes -%]
[% star = attribute.allocatedType ? '*' : '' -%]
[% cast = attribute.cpptype == 'char' || attribute.cpptype == 'unsigned char' ? '(int)' : '' -%]
        bdeu_Print::indent(stream, levelPlus1, spacesPerLevel);
        stream << "[% AttributeName %] = ";
        bdeu_PrintMethods::print(stream, [% cast %][% star %][% attributeVar %],
                                 -levelPlus1, spacesPerLevel);

[% END -%]
        bdeu_Print::indent(stream, level, spacesPerLevel);
        stream << "]\n";
    }
    else {
        // single line

        stream << '[';

[% FOREACH attribute = attributes -%]
[% star = attribute.allocatedType ? '*' : '' -%]
[% cast = attribute.cpptype == 'char' || attribute.cpptype == 'unsigned char' ? '(int)' : '' -%]
        stream << ' ';
        stream << "[% AttributeName %] = ";
        bdeu_PrintMethods::print(stream, [% cast %][% star %][% attributeVar %],
                                 -levelPlus1, spacesPerLevel);

[% END -%]
        stream << " ]";
    }

    return stream << bsl::flush;
}

[% IF !sequence.noAggregateConversion -%]
int [% Class %]::toAggregate(bcem_Aggregate *result) const
{
[% IF attributes.size > 0 -%]
    int rc;
[% FOREACH attribute = attributes -%]

    rc = bcem_AggregateUtil::toAggregate(
                       result,
                       ATTRIBUTE_ID_[% ATTRIBUTE_NAME %],
[% IF attribute.allocatedType -%]
                       *[% attributeVar %]);
[% ELSE -%]
                       [% attributeVar %]);
[% END -%]
    if (rc != 0 && rc != bcem_Aggregate::BCEM_ERR_BAD_FIELDID) {
        return rc;
    }
[% END -%]

[% END -%]
    return 0;
}
[% END -%]

[%- END -%]

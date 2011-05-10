[% PROCESS enumeration_util.t -%]
[% BLOCK LoadEnumerator -%]
*result = [% Class %]::[% ENUMERATOR_NAME %];
return 0;
[%- END -%]
[% BLOCK enumerationMethodDefinitions -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]

// CONSTANTS

[% IF !enumeration.omitIntrospection -%]
const char [% Class %]::CLASS_NAME[] = "[% Class %]";

const bdeat_EnumeratorInfo [% Class %]::ENUMERATOR_INFO_ARRAY[] = {
[% FOREACH enumerator = enumerators -%]
    {
        [% Class %]::[% ENUMERATOR_NAME %],
        "[% enumerator.value | escapeQuotes %]",
        sizeof("[% enumerator.value | escapeQuotes %]") - 1,
        ""
    }[% loop.last ? '' : ',' %]
[% END -%]
};

[% END -%]
[% IF enumeration.appInfoConstants.length() -%]
[% FOREACH appInfoConstant = enumeration.appInfoConstants -%]
const char [% Class %]::APPINFO_[% appInfoConstant.name | UPPER_UPPER %][][%-%]
       [%- %] = [%- appInfoConstant.cppValue%];

[% END -%]

[% END -%]
// CLASS METHODS

int [% Class %]::fromInt([% Class %]::Value *result, int number)
{
    switch (number) {
[% FOREACH enumerator = enumerators -%]
      case [% Class %]::[% ENUMERATOR_NAME %]:
[% END -%]
        *result = ([% Class %]::Value)number;
        return 0;
      default:
        return -1;
    }
}

int [% Class %]::fromString([% Class %]::Value *result,
                            const char         *string,
                            int                 stringLength)
{
[% FILTER indent -%]

[% INCLUDE enumeratorSearchBlock
    tree=enumeratorSearchTree depth=0
    visit='LoadEnumerator' name='string' nameLength='stringLength' -%]

return -1;
[% END -%]
}

const char *[% Class %]::toString([% Class %]::Value value)
{
    switch (value) {
[% FOREACH enumerator = enumerators -%]
      case [% ENUMERATOR_NAME %]: {
        return "[% enumerator.value | escapeQuotes %]";
      } break;
[% END -%]
    }

    BSLS_ASSERT(!"invalid enumerator");
    return 0;
}
[% END -%]

[% PROCESS customizedtype_util.t -%]
[% BLOCK customizedtypeMethodDefinitions -%]
[% String.new("// $thinline").center(79) %]
[% String.new("// class $Class").center(79) %]
[% String.new("// $thinline").center(79) %]
[% IF customizedtype.localConstants -%]

// LOCAL CONSTANTS
namespace {

[% FOREACH localConstant = customizedtype.localConstants -%]
[% localConstant %]
[% END -%]

}  // close unnamed namespace
[% END -%]
[% IF 1 < customizedtype.restriction.size() -%]

// PRIVATE CLASS METHODS

int [% Class %]::checkRestrictions([% BaseArgType %] value)
{
[% IF customizedtype.restriction.exists('enumeration') -%]
[% FOREACH enumerator = enumerators -%]
[% IF loop.first -%]
    if ([% enumerator.cppValue %] != value[% -%]
[% ELSE -%]
     && [% enumerator.cppValue %] != value[% -%]
[% END -%]
[%- loop.last ? ") {" : "" %]
[% END -%]
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('maxLength') -%]
[%# if (4 * [ % customizedtype.restriction.maxLength.value % ] < value.size()) { #%]
    if ([% customizedtype.restriction.maxLength.value %] < bdede_Utf8Util::numCharacters(value.c_str(), value.length())) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('minLength') -%]
    if ([% customizedtype.restriction.minLength.value %] > value.size()) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('length') -%]
[%# if ([ % customizedtype.restriction.length.value % ] != value.size()) { #%]
    if ([% customizedtype.restriction.length.value %]     > value.size()
    ||  [% customizedtype.restriction.length.value %] * 4 < value.size()) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('minInclusive') -%]
    if ([% customizedtype.restriction.minInclusive.value %] > value) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('maxInclusive') -%]
    if ([% customizedtype.restriction.maxInclusive.value %] < value) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('minExclusive') -%]
    if ([% customizedtype.restriction.minExclusive.value %] >= value) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('maxExclusive') -%]
    if ([% customizedtype.restriction.maxExclusive.value %] <= value) {
        return -1;
    }

[% END -%]
[% IF customizedtype.restriction.exists('pattern') -%]
    bsl::string errorMessage;
    int         errorOffset;
    const char  PATTERN[] =
[% FOREACH pattern = patterns -%]
[% IF loop.first -%]
        "^(" "([% pattern.value | escapeQuotes %])"[% -%]
[% ELSE -%]
        "|"  "([% pattern.value | escapeQuotes %])"[% -%]
[% END -%]
[%- IF loop.last %] ")\$";[% END %]
[% END -%]

    bdepcre_RegEx regex;
    int rc = regex.prepare(&errorMessage, &errorOffset, PATTERN);
    if (0 == rc) {
[% IF 'bsl::string' == BaseType -%]
        rc = regex.match(value.c_str(), value.length());
[% ELSE -%]
        bsl::ostringstream oss;
        oss << value;
        rc = regex.match(oss.str().c_str(), oss.str().length());
[% END -%]
    }

    if (0 != rc) {
        return -1;
    }

[% END -%]
    return 0;
}

[% END -%]
// CONSTANTS

const char [% Class %]::CLASS_NAME[] = "[% Class %]";

[% FOREACH appInfoConstant = customizedtype.appInfoConstants -%]
const char [% Class %]::APPINFO_[% appInfoConstant.name | UPPER_UPPER %][][%-%]
       [%- %] = [%- appInfoConstant.cppValue%];

[% END -%]
[% IF customizedtype.restriction.enumeration.defined -%]
[% FOREACH enumerator = enumerators -%]
[% IF enumerator.name.defined -%]
const [% BaseType %] [% Class %]::[% ENUMERATOR_NAME %] = [% enumerator.cppValue %];

[% END -%]
[% END -%]
[% END -%]
[% END -%]

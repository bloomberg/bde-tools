[% USE String -%]
[% USE Dumper -%]
[%#
     Some useful vars & macros
-%]
[% SET Class = sequence.cpptype -%]
[% SET thinline = String.new('-').repeat(Class.length).append("------") %]
[% SET fatline = String.new('=').repeat(Class.length).append("======") %]
[% SET attributes = sequence.sequence -%]
[% SET sortedAttributes = sequence.sortedMembers -%]
[% MACRO ATTRIBUTE_NAME    GET   attribute.memberName | UPPER_UPPER -%]
[% MACRO AttributeName     GET   attribute.memberName | MixedMixed -%]
[% MACRO attributeName     GET   attribute.memberName | mixedMixed -%]
[% MACRO attributeType     GET   attribute.allocatedType || attribute.cpptype -%]
[% MACRO attributeImplType GET   attribute.cpptype -%]
[% MACRO attributeIntfType GET   attribute.allocatedType || selection.cpptype -%]
[% MACRO attributeArgType  GET   attribute.cppargtype -%]
[% MACRO attributeVar      GET   'd_' _ mixedMixed(attribute.name) -%]
[%#
     Attribute search
-%]
[% BLOCK attributeSearchBlock -%]
[% IF tree.type == 'val' -%]
[% INCLUDE $visit attribute=tree.val %]
[% ELSIF tree.type == 'matchText' -%]
if ([% -%]
[% maxDepth = depth + tree.text.split('').size() -%]
[% FOREACH char = tree.text.split('') -%]
[% UNLESS loop.first -%]
 && [% -%]
[% END -%]
[% IF opts.ignoreCase -%]
             [%- PERL -%]
                 my $isChar = $stash->{char} =~ /[a-zA-Z]/;
                 $stash->set(isChar => $isChar);
                 $stash->set(char   => lc $stash->{char}) if $isChar;
             [%- END -%]
             [%- %]([% name %][[% depth %]][% isChar ? '|0x20' : '' %])==[% -%]
[% ELSE -%]
             [%- name %][[% depth %]]==[% -%]
[% END -%]
             [%- IF '\\' == char -%]
               [%- %]'\\'[% -%]
             [%- ELSIF '\'' == char -%]
               [%- %]'\''[% -%]
             [%- ELSE -%]
               [%- %]'[% char %]'[% -%]
             [%- END -%]
[% depth = depth + 1 -%]
[% depth == maxDepth ? ")" : "" %]
[% END -%]
{
[% INCLUDE attributeSearchBlock tree=tree.node | indent -%]
}
[% ELSIF tree.type == 'checkLen' -%]
switch([% nameLength %]) {
[% FILTER indent -%]
[% FOREACH branch = tree.branches -%]
case [% branch.len %]: {
[% INCLUDE attributeSearchBlock tree=branch.node | indent -%]
} break;
[% END -%]
[% END -%]
}
[% ELSIF tree.type == 'checkChar' -%]
[% IF opts.ignoreCase -%]
switch(bdeu_CharType::toUpper([% -%]
        [%- name %][[% depth %]])) {
[% ELSE -%]
switch([% name %][[% depth %]]) {
[% END -%]
[% FILTER indent -%]
[% FOREACH branch = tree.branches -%]
case '[% branch.char %]': {
[% INCLUDE attributeSearchBlock tree=branch.node depth=depth+1 | indent -%]
} break;
[% END -%]
[% END -%]
}
[% ELSE -%]
ERROR: unknown search tree type
[% END -%]
[% END -%]
[% -%]
[% -%]
[% SET attributeSearchTree = [] -%]
[% FOREACH attribute = attributes -%]
[% IF opts.ignoreCase -%]
[% CALL attributeSearchTree.push({ type => String.new(sequence.name).text
                                 , key  => String.new(attribute.origName)
                                                 .upper.text
                                 , val  => attribute }) -%]
[% ELSE -%]
[% CALL attributeSearchTree.push({ type => String.new(sequence.name).text
                                 , key  => String.new(attribute.origName).text
                                 , val  => attribute }) -%]
[% END -%]
[% END -%]
[% SET attributeSearchTree = buildSearchTree(attributeSearchTree) -%]

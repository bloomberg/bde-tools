[% USE String -%]
[% USE Dumper -%]
[%#
     Some usefull vars & macros
-%]
[% SET Class = enumeration.cpptype -%]
[% SET thinline = String.new('-').repeat(Class.length).append("------") %]
[% SET fatline = String.new('=').repeat(Class.length).append("======") %]
[% SET enumerators = enumeration.restriction.enumeration -%]
[% MACRO ENUMERATOR_NAME GET enumerator.name  | UPPER_UPPER -%]
[% MACRO EnumeratorName  GET enumerator.name  | MixedMixed -%]
[% MACRO enumeratorName  GET enumerator.name  | mixedMixed -%]
[% MACRO EnumeratorValue GET enumerator.value | escapeQuotes -%]
[%#
     Enumerator search
-%]
[% BLOCK enumeratorSearchBlock -%]
[% IF tree.type == 'val' -%]
[% INCLUDE $visit enumerator=tree.val %]
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
[% INCLUDE enumeratorSearchBlock tree=tree.node | indent -%]
}
[% ELSIF tree.type == 'checkLen' -%]
switch([% nameLength %]) {
[% FILTER indent -%]
[% FOREACH branch = tree.branches -%]
case [% branch.len %]: {
[% INCLUDE enumeratorSearchBlock tree=branch.node | indent -%]
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
[% INCLUDE enumeratorSearchBlock tree=branch.node depth=depth+1 | indent -%]
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
[% SET enumeratorSearchTree = [] -%]
[% FOREACH enumerator = enumerators -%]
[% IF opts.ignoreCase -%]
[% CALL enumeratorSearchTree.push(
        { type => String.new(enumeration.name).text
        , key  => String.new(enumerator.value).upper.text
        , val  => enumerator }) -%]
[% ELSE -%]
[% CALL enumeratorSearchTree.push(
        { type => String.new(enumeration.name).text
        , key  => String.new(enumerator.value).text
        , val  => enumerator }) -%]
[% END -%]
[% END -%]
[% SET enumeratorSearchTree = buildSearchTree(enumeratorSearchTree) -%]

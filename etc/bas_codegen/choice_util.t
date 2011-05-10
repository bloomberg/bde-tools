[% USE String -%]
[% USE Dumper -%]
[%#
     Some usefull vars & macros
-%]
[% SET Class = choice.cpptype -%]
[% SET thinline = String.new('-').repeat(Class.length).append("------") %]
[% SET fatline = String.new('=').repeat(Class.length).append("======") %]
[% SET selections = choice.choice -%]
[% MACRO SELECTION_NAME    GET   selection.memberName | UPPER_UPPER -%]
[% MACRO SelectionName     GET   selection.memberName | MixedMixed -%]
[% MACRO selectionName     GET   selection.memberName | mixedMixed -%]
[% MACRO selectionType     GET   selection.allocatedType || selection.cpptype -%]
[% MACRO selectionImplType GET   selection.cpptype -%]
[% MACRO selectionIntfType GET   selection.allocatedType || selection.cpptype -%]
[% MACRO selectionArgType  GET   selection.cppargtype -%]
[% MACRO selectionField    GET   'd_' _ mixedMixed(selection.name) -%]
[% MACRO selectionVar      GET   'd_' _ mixedMixed(selection.name) _
                                 '.object()' -%]
[% MACRO selectionBuffer   GET   'd_' _ mixedMixed(selection.name) _
                                 '.buffer()' -%]
[%#
     Selection search
-%]
[% BLOCK selectionSearchBlock -%]
[% IF tree.type == 'val' -%]
[% INCLUDE $visit selection=tree.val %]
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
[% INCLUDE selectionSearchBlock tree=tree.node | indent -%]
}
[% ELSIF tree.type == 'checkLen' -%]
switch([% nameLength %]) {
[% FILTER indent -%]
[% FOREACH branch = tree.branches -%]
case [% branch.len %]: {
[% INCLUDE selectionSearchBlock tree=branch.node | indent -%]
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
[% INCLUDE selectionSearchBlock tree=branch.node depth=depth+1 | indent -%]
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
[% SET selectionSearchTree = [] -%]
[% FOREACH selection = selections -%]
[% IF opts.ignoreCase -%]
[% CALL selectionSearchTree.push({ type => String.new(choice.name).text
                                 , key  => String.new(selection.origName)
                                                 .upper.text
                                 , val  => selection }) -%]
[% ELSE -%]
[% CALL selectionSearchTree.push({ type => String.new(choice.name).text
                                 , key  => String.new(selection.origName).text
                                 , val  => selection }) -%]
[% END -%]
[% END -%]
[% SET selectionSearchTree = buildSearchTree(selectionSearchTree) -%]

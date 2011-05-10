[% USE String -%]
[% USE Dumper -%]
[%#
     Some usefull vars & macros
-%]
[% SET Class = customizedtype.cpptype -%]
[% SET thinline = String.new('-').repeat(Class.length).append("------") %]
[% SET fatline = String.new('=').repeat(Class.length).append("======") %]
[% SET BaseType = customizedtype.baseType -%]
[% SET BaseArgType = customizedtype.baseArgType -%]
[% SET patterns = customizedtype.restriction.pattern -%]
[% SET enumerators = customizedtype.restriction.enumeration -%]
[% MACRO ENUMERATOR_NAME    GET   enumerator.name | UPPER_UPPER -%]
[% MACRO EnumeratorName     GET   enumerator.name | MixedMixed -%]
[% MACRO enumeratorName     GET   enumerator.name | mixedMixed -%]
[%#
     Enumerator search
-%]
[% BLOCK enumeratorSearchBlock -%]
[% IF tree.type == 'val' -%]
[% INCLUDE $visit enumerator=tree.val %]
[% ELSIF tree.type == 'matchText' -%]
if ([% -%]
[% FOREACH char = tree.text.split('') -%]
[% loop.first ? '' : ' && ' %]bdeu_CharType::toUpper([% -%]
             [%- name %][[% depth %]])=='[% char %]'[% -%]
[% depth = depth + 1 -%]
[% END -%]) {
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
switch(bdeu_CharType::toUpper([% -%]
        [%- name %][[% depth %]])) {
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
[% CALL enumeratorSearchTree.push(
        { key => String.new(enumerator.value).upper.text,
          val => enumerator }) -%]
[% END -%]
[% SET enumeratorSearchTree = buildSearchTree(enumeratorSearchTree) -%]

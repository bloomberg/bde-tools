package BDE::Rule::Doc;
use strict;

use base 'BDE::Rule::Base';


#==============================================================================

=head1 NAME

BDE::Rule::D1 - Base documentation

=head1 DESCRIPTION

This rule contains introductory information to the rules as well as the 
documentation for rules which are implicitly validated by the tools
infrastructure.

=cut

#==============================================================================

=head1 AUTHOR

Ralph Gibbons

=head1 SEE ALSO

BDE::Rule::Base

=cut

#==============================================================================

1;

__DATA__
<<<INTRO>>>
---------------------------------------
RULES AND GUIDELINES FOR C++ COMPONENTS
---------------------------------------

The following document contains a summary of the rules documented with the
"bde_verify.pl Rules Summary" document (see {BDE<GO> -> BDE Information Page).


Also provided:

    - indications as to whether a rule is validated either explicitly via a
      perl module (see BDE::Rule), or implictly via the tools infrastructure

    - cross references to the "30 Rules" where appropriate

KEY:

A : Architectural Definitions	
N : Nomenclature
P : Physical Design
L : Logical Design
R : Procedural Rules
T : Testing

<<<A1>>>
A package group is is the unit of release. It is grouped into packages (A2).
Package groups may not have cyclic dependencies (P2). The name of a package
group is a registered identifier consisting of three lowercase letters.

* IMPLICIT
* CROSS REFERENCE: Rule 1

<<<A2>>>
A package is a physical unit within a package group (A1). It contains 
components (A3) that are logically and physically related. Packages may not
have cyclic dependencies (P2). The name of a package is the name of the 
package group to which it belongs followed by a 1-3 letter package suffix

* IMPLICIT
* CROSS REFERENCE: Rule 2

<<<A3>>>
A component is an atom of physically and logically encapsulated code within a
package (A2). It is comprised of a .h/.cpp pair and an additional .t.cpp test
driver.  The name of the component is the name of the package followed by an
underscore and a meaningful lowercase identifier.

* IMPLICIT
* CROSS REFERENCE: Rule 3

<<<A4>>>
An application is a collection of non-shared C++ files that implements an
executable and contains a main function. It is prefixed with an m_ followed by 
any suitable name. Applications are not required to be composed of components.

* IMPLICIT

<<<A5>>>
An adapter is a physical unit with the properties of a package except that it
does not reside in a package group. It is prefixed with a_, followed by the
name of the package that provides the protocol that it implements. It is 
composed purely of components.

* IMPLICIT

<<<A6>>>
A wrapper is a physical unit with the properties of a package group
implemented purely in C components. It is prefixed with z_, followed by the 
name of the C++ core library (A1) that it wraps.

* IMPLICIT

<<<INCLUDE L1>>>

<<<END>>>




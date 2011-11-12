// bdeflag_report.h                                                   -*-C++-*-

#ifndef INCLUDED_BDEFLAG_GROUP
#define INCLUDED_BDEFLAG_GROUP

#ifndef INCLUDED_BSLS_IDENT
#include <bsls_ident.h>
#endif
BSLS_IDENT("$Id: $")

//@PURPOSE: Provide a class representing a '()' or '{}' pair.
//
//@CLASSES:
//    Group: a '()' or '{}' pair in the source file, and information about it
//
//@AUTHOR: Bill Chapman
//
//@DESCRIPTION: Top level, describing class bdeflag::Group.  A group describes
// a matching pair of '()'s or '{}'s.  One object of type 'Group' describes
// many things about such a pair -- the string, if any, that precedes it, the
// Places where the open and close of the pair are, the Place where the
// statement that the group is within started, a set of the groups that are
// contained within this group, an enum specifying what syntactic type of pair
// this is.  All groups are within a recursive tree, and most checking is done
// by traversing that tree and analyzing one group at a time.  This class does
// most of the checking for warnings.

#ifndef INCLUDED_BDEFLAG_LINES
#include <bdeflag_lines.h>
#endif

#ifndef INCLUDED_BDEFLAG_PLACE
#include <bdeflag_place.h>
#endif

#ifndef INCLUDED_BDEFLAG_UT
#include <bdeflag_ut.h>
#endif

#ifndef INCLUDED_BSL_SET
#include <bsl_set.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#endif

namespace BloombergLP {

namespace bdeFlag {

class Group {
    // PRIVATE TYPES
    struct Flags {
        unsigned        d_parenBased : 1;
            // initialized before 'recurseInitGroup' starts with the group

        // all of these are initialized by 'recurseInitGroup'

        unsigned        d_closedWrong : 1;
        unsigned        d_earlyEof : 1;
        unsigned        d_noGroupsFound : 1;
    };

    enum GroupType {
        // BRACES TYPES
        BDEFLAG_UNKNOWN_BRACES,
        BDEFLAG_TOP_LEVEL,
        BDEFLAG_NAMESPACE,
        BDEFLAG_CLASS,
        BDEFLAG_ENUM,
        BDEFLAG_INIT_BRACES,
        BDEFLAG_ROUTINE_BODY,
        BDEFLAG_CODE_BODY,

        BDEFLAG_NUM_BRACES_TYPES,

        // PARENS TYPES
        BDEFLAG_UNKNOWN_PARENS = BDEFLAG_NUM_BRACES_TYPES,
        BDEFLAG_ROUTINE_UNKNOWN_CALL_OR_DECL,
        BDEFLAG_ROUTINE_DECL,
        BDEFLAG_CTOR_CLAUSE,
        BDEFLAG_ROUTINE_CALL,
        BDEFLAG_IF_WHILE_FOR,
        BDEFLAG_SWITCH_PARENS,
        BDEFLAG_CATCH_PARENS,
        BDEFLAG_THROW_PARENS,
        BDEFLAG_EXPRESSION_PARENS,
        BDEFLAG_ASM };

    // PUBLIC TYPES
  public:
    struct GroupPtrLess {
        bool operator()(const Group *lhs, const Group *rhs) const;
    };
    typedef bsl::set<Group *, GroupPtrLess> GroupSet_Base;
    struct GroupSet : GroupSet_Base {
        // CREATORS
        ~GroupSet();
            // Delete all of the groups pointed at by the group pointers
            // contained in this set.
    };
    typedef GroupSet::iterator       GroupSetIt;

    typedef void (Group::*GroupMemFunc)();
    typedef void (Group::*GroupMemFuncConst)() const;

  private:
    // CLASS DATA
    static
    Group          *s_topLevel;

    // DATA
    const Group    *d_parent;
    Place           d_open;
    Place           d_close;
    Place           d_statementStart;
    Place           d_prevWordBegin;
    bsl::string     d_prevWord;
    bsl::string     d_className;
    GroupType       d_type;
    union {
        Flags       d_flags;
        int         d_zeroFlags;
    };
    GroupSet        d_subGroups;

    // PRIVATE MANIPULATORS
    Group *recurseFindGroupForPlace(Group *group);
        // Recurse down the group tree, looking for the deepest group in the
        // tree that includes the given place.

    int recurseInitGroup(Place *place, const Group *parent);
        // Recursively parse '()' and '{}' pairs, building a tree.

    void recurseMemTraverse(const GroupMemFunc func);
        // Recurse all the groups in the tree starting at 's_topLevel', calling
        // 'func' on each one.

    void recurseMemTraverse(const GroupMemFuncConst func);
        // Recurse all the groups in the tree starting at 's_topLevel', calling
        // 'func' on each one.

    // PRIVATE ACCESSORS
    void checkArgNames() const;
        // Do all checks related to argument names for the current group.

    void checkBooleanRoutineNames() const;
        // Do all checks related to boolean routine names for the current
        // group.  Groups that don't represent routine definitions in classes
        // are ignored.

    void checkCodeComments() const;
        // Check all comments in code are appropriately indented.

    void checkCodeIndents() const;
        // Check all statements in code are appropriately indented.

    void checkFunctionDoc() const;
        // If this is a function decl, check it is docced if that is
        // approrpriate.

    void checkIfWhileFor() const;
        // Check if/while/for controls a {} block.

    void checkNamespace() const;
        // If this is a namespace, check that the end comment is right

    void checkNotImplemented() const;
        // Check proper formatting of '// NOT IMPLEMENTED' comment.

    void checkReturns() const;
        // Check return statements have '// RETURN' comments when appropriate.

    void checkRoutineCallArgList() const;
        // Check that the args to this routine call are either all on one line
        // or each on a separate line.

    void checkStartingAsserts() const;
        // If this is a routine body, check any asserts starting it out are
        // followed by a blank line.

    void checkStartingBraces() const;
        // If this is a routine body, check that the starting '{' is on its own
        // line and properly indented.

    void registerValidFriendTarget() const;
        // Only called if we're in a .h file.  If this a group, put it on the
        // list of valid friend target groups.  If this is a function decl
        // not in a group, put it in the list of friend target routines.

    void getArgList(bsl::vector<bsl::string> *typeNames,
                    bsl::vector<bsl::string> *names,
                    bsl::vector<int>         *lineNums) const;
        // If this is a routine decl, get the arg list for it.  Care has to be
        // taken to avoid calling this on things that turn out not to be
        // routine decls.

  public:
    // CLASS METHODS
    static
    void checkAllArgNames();
        // Check the arg lists of all routines.

    static
    void checkAllBooleanRoutineNames();
        // Check that routines beginning with 'is', 'are' and 'has', and
        // boolean operators do in fact return bools.

    static
    void checkAllCodeComments();
        // Check all comments in classes, code blocks and routine bodies are
        // indented and spaced appropriately.

    static
    void checkAllCodeIndents();
        // Check indentation of all code in classes, code bodies and routine
        // bodies.

    static
    void checkAllFriends();
        // Nop unless in a .h file.  Make sure that all friendships occurring
        // in this file refer to groups or methods declared in this file.

    static
    void checkAllFunctionDoc();
        // Check all functions are appropriately docced.

    static
    void checkAllIfWhileFor();
        // Check all if/while/for.

    static
    void checkAllNamespaces();
        // Check all namespaces have proper comments on their ends.

    static
    void checkAllNotImplemented();
        // Check all '// NOT IMPLEMENTED' comments are as they should be.

    static
    void checkAllReturns();
        // Check all returns are marked by '// RETURN' where appropriate.

    static
    void checkAllRoutineCallArgLists();
        // Check all routine call arg lists, that either all args are on one
        // line or each arg is on a separate line.

    static
    void checkAllStartingAsserts();
        // Check all asserts at the start of routine bodies are followed by
        // blank lines.

    static
    void checkAllStartingBraces();
        // Check all routines have (with some exceptions) starting braces
        // properly aligned and on their own lines.

    static
    void checkAllStatics();
        // In a .h file, check that all statics are within classes.

    static
    void checkAllTemplateOnOwnLine();
        // Check all 'template' clauses are on their own lines.

    static
    void clearGroups();
        // Free all memory allocated by this component.

    static
    void doEverything();
        // Initialize groups, do all checks, clean up.  Assumes Lines & Place
        // are initialized.

    static
    Group *findGroupForPlace(const Place& place);
        // Give a specified 'place', find the narrowest group that encloses
        // that place.

    static
    void initGroups();
        // Parse file into a recursive group tree structure, then traverse the
        // tree, initializing group types.

    static
    void printAll();
        // Dump the tree of groups.  For debugging.

    static
    Group& topLevel();
        // Return 's_topLevel', the top level group enclosing the whole file.

    static
    const char *typeToStr(GroupType groupType);
        // Return a string representing a group type, for error messages (not
        // to be confused with warning messages).

    // CREATORS
    Group(GroupType groupType, bool parenBased);
        // Great a group with the specified 'groupType' and 'parenBased'
        // status.

    // MANIPULATORS
    void determineGroupType();
        // Determine the group type.  Can assume the parent group (if there is
        // one) type has been determined already, as have those of groups
        // before it in the source file.

    int initTopLevelGroup();
        // Assuming the current group is default constructed, initialize it
        // with the first balanced pair of '()' or '{}' encountered at or
        // after 'place', returning 0 on success and non-zero otherwise,
        // setting 'place' to the position of the closing paren or brace.  If
        // the specified 'parent' is 0, we are at the top level, and we should
        // gather all groups into subgroups of this group;

    // ACCESSORS
    void print() const;
        // Print information about one group on one line.

    const Place& open() const;
        // Return 'd_open'.
};

// ===========================================================================
//                      INLINE FUNCTION DEFINITIONS
// ===========================================================================

                                // -----------
                                // class Group
                                // -----------

// CLASS METHODS
inline
Group& Group::topLevel()
{
    return *s_topLevel;
}

// CREATORS
inline
Group::Group(GroupType groupType, bool parenBased)
: d_parent(0)
, d_prevWordBegin(Place::rEnd())
, d_type(groupType)
, d_zeroFlags(0)
{
    d_flags.d_parenBased = parenBased;
}

// ACCESSORS
inline
const Place& Group::open() const
{
    return d_open;
}

                        // -------------------------
                        // class Group::GroupPtrLess
                        // -------------------------

// FREE OPERATORS
inline
bool Group::GroupPtrLess::operator()(const Group *lhs, const Group *rhs) const
    // Note this function should come after the definition of inline
    // 'Group::open'.
{
    return lhs->open() < rhs->open();
}

}  // close namespace bdeFlag
}  // close namespace BloombergLP

#endif

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2010
//      All Rights Reserved.
//      Property of Bloomberg L.P.  (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------

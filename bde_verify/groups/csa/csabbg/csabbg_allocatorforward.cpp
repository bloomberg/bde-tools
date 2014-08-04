// csabbg_allocatorforward.cpp                                        -*-C++-*-

#include <clang/AST/ASTContext.h>
#include <clang/AST/Decl.h>
#include <clang/AST/DeclBase.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/DeclTemplate.h>
#include <clang/AST/Expr.h>
#include <clang/AST/ExprCXX.h>
#include <clang/AST/Stmt.h>
#include <clang/AST/TemplateBase.h>
#include <clang/AST/TemplateName.h>
#include <clang/AST/Type.h>
#include <clang/ASTMatchers/ASTMatchFinder.h>
#include <clang/ASTMatchers/ASTMatchers.h>
#include <clang/ASTMatchers/ASTMatchersInternal.h>
#include <clang/ASTMatchers/ASTMatchersMacros.h>
#include <clang/Basic/SourceLocation.h>
#include <clang/Basic/Specifiers.h>
#include <csabase_analyser.h>
#include <csabase_debug.h>
#include <csabase_diagnostic_builder.h>
#include <csabase_registercheck.h>
#include <csabase_util.h>
#include <llvm/ADT/APSInt.h>
#include <llvm/ADT/Optional.h>
#include <llvm/ADT/VariadicFunction.h>
#include <llvm/Support/Casting.h>
#include <utils/event.hpp>
#include <utils/function.hpp>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace csabase { class PPObserver; }
namespace csabase { class Visitor; }

using namespace clang;
using namespace clang::ast_matchers;
using namespace clang::ast_matchers::internal;
using namespace csabase;

// -----------------------------------------------------------------------------

static std::string const check_name("allocator-forward");

// -----------------------------------------------------------------------------

namespace clang {
namespace ast_matchers {

AST_MATCHER_P(TemplateArgument, equalsIntegral, unsigned, N) {
  return Node.getKind() == TemplateArgument::Integral &&
         Node.getAsIntegral() == N;
}

AST_MATCHER_P(ClassTemplateSpecializationDecl, templateArgumentCountIs,
              unsigned, N) {
    return Node.getTemplateArgs().size() == N;
}

AST_MATCHER_P(FunctionDecl, hasLastParameter,
               internal::Matcher<ParmVarDecl>, InnerMatcher) {
    return Node.getNumParams() > 0 &&
           InnerMatcher.matches(
               *Node.getParamDecl(Node.getNumParams() - 1), Finder, Builder);
}

}
}

namespace
{

struct data
    // Data stored for this set of checks.
{
    QualType bslma_allocator_;
        // The type of 'BloombergLP::bslma::Allocator'.

    typedef std::vector<const CXXConstructorDecl*> Ctors;
    Ctors ctors_;
        // The set of constructor declarations seen.

    typedef std::set<const NamedDecl*> DeclsWithAllocatorTrait;
    DeclsWithAllocatorTrait decls_with_true_allocator_trait_;
        // The set of declarations having a true allocator trait.

    DeclsWithAllocatorTrait decls_with_false_allocator_trait_;
        // The set of declarations having a false allocator trait.

    DeclsWithAllocatorTrait decls_with_dependent_allocator_trait_;
        // The set of declarations having a dependent allocator trait.

    typedef std::set<const CXXConstructExpr*> Cexprs;
    Cexprs cexprs_;
        // The set of constructor expressions seen.

    typedef std::map<const Type*, bool> TypeTakesAllocator;
    TypeTakesAllocator type_takes_allocator_;
        // A map of whether a type has a constructor with an allocator
        // parameter.

    typedef std::map<const CXXConstructorDecl*, bool> CtorTakesAllocator;
    CtorTakesAllocator ctor_takes_allocator_;
        // A map of whether a constructor has an allocator parameter.

    typedef std::set<const ReturnStmt*> Returns;
    Returns returns_;

    typedef std::set<const VarDecl*> Globals;
    Globals globals_;
};

struct report
    // This class two static analysis checkers, one to detect object
    // constructors with allocator parameters which do not pass an allocator to
    // the constructors of their base classes and members with allocator
    // parameters, and a second which detects constructor expressions with an
    // explicit allocator argument in which that argument does not initialize
    // an allocator parameter.  It also contains a variety of utility methods
    // used in implementing those checks.
{
    report(Analyser& analyser);
        // Create an object of this type, using the specified 'analyser' for
        // access to compiler data structures.

    const CXXRecordDecl *get_record_decl(QualType type);
        // Return the record declaration for the specified 'type' and a null
        // pointer if it does not have one.

    bool is_allocator(QualType type);
        // Return 'true' iff the specified 'type' is pointer to
        // 'bslma::Allocator'.

    bool last_arg_is_explicit(const CXXConstructExpr* call);
        // Return 'false' iff the specified 'call' to a constructor has
        // arguments and the last argument is the default rather than
        // explicitly passed.

    bool takes_allocator(QualType type);
        // Return 'true' iff the 'specified' type has a constructor which has a
        // final allocator paramater.

    bool takes_allocator(CXXConstructorDecl const* constructor);
        // Return 'true' iff the specified 'constructor' has a final allocator
        // pointer paramater.

    void match_allocator_type(const BoundNodes& nodes);
        // Callback for bslma::Allocator.

    void match_nested_allocator_trait(const BoundNodes& nodes);
        // Callback for classes with nested allocator traits.

    void match_class_using_allocator(const BoundNodes& nodes);
        // Callback for classes having constructors with allocator parameters.

    void match_allocator_trait(data::DeclsWithAllocatorTrait* set,
                               const BoundNodes& nodes);
        // Method to insert discovered classes with allocator traits contained
        // within the specifed 'nodes' into the specified 'set'.

    void match_negative_allocator_trait(const BoundNodes& nodes);
        // Callback for discovered classes with negative allocator traits
        // contained within the specifed 'nodes'.

    void match_positive_allocator_trait(const BoundNodes& nodes);
        // Callback for discovered classes with positive allocator traits
        // contained within the specifed 'nodes'.

    void match_dependent_allocator_trait(const BoundNodes& nodes);
        // Callback for discovered classes with dependent allocator traits
        // contained within the specifed 'nodes'.

    void match_should_return_by_value(const BoundNodes& nodes);
        // Callback for functions which could return by value instead of
        // through a pointer.

    void operator()();
        // Invoke the checking procedures.

    void check_globals_use_allocator(data::Globals::const_iterator begin,
                                     data::Globals::const_iterator end);

    void check_not_forwarded(data::Ctors::const_iterator begin,
                             data::Ctors::const_iterator end);
        // Invoke the forwarding check on the items in the range from the
        // specified 'begin' up to but not including the specified 'end'.

    void check_not_forwarded(const CXXConstructorDecl *decl);
        // If the specified constructor 'decl' takes an allocator parameter,
        // check whether it passes the parameter to its subobjects.

    void check_not_forwarded(CXXConstructorDecl::init_const_iterator begin,
                             CXXConstructorDecl::init_const_iterator end,
                             const ParmVarDecl* palloc);
        // Check if the items in the sequence from the specified 'begin' up to
        // but not including the specified 'end' are passed the specified
        // 'palloc' allocator parameter.

    void check_not_forwarded(const CXXCtorInitializer* init,
                             const ParmVarDecl* palloc);
        // Check if the specified 'init' initializer is passed the specified
        // 'palloc' allocator parameter, if the initialized object is capable
        // of being so initialized.

    std::string parm_name(const ParmVarDecl* parm, int position);
        // Construct a descriptive name string for the specified 'parm'
        // parameter, incorporating the specified 'position'.

    template <typename Iter>
    void check_wrong_parm(Iter begin, Iter end);
        // Check if the items in the sequence from the specified 'begin' up to
        // but not including the specified 'end' initialize a non-allocator
        // parameter from an explicit allocator argument.

    void check_wrong_parm(const CXXConstructExpr *expr);
        // Check whether the specified 'expr' constructor expression contains a
        // final explicit allocator pointer argument used to initialize a non-
        // allocator parameter.  The canonical case is
        //..
        //  struct X {
        //      bdef_Function<void(*)()> d_f;
        //      X(const bdef_Function<void(*)()>& f, bslma::Allocator *a = 0);
        //  };
        //  X x(bslma::Default::defaultAllocator());
        //..
        // typically occurring when a bdef_Function member is added to a class
        // which did not have one.

    template <typename Iter>
    void check_alloc_returns(Iter begin, Iter end);
        // Check that the return statements in the specified half-open range
        // '[ begin .. end )' do not return items that take allocators.

    void check_alloc_return(const ReturnStmt* stmt);
        // Check that the specified return 'stmt' does not return an item that 
        // takes allocators.

    Analyser& analyser_;  // afford access to compiler data
    data& data_;          // data held for this set of checks
};

report::report(Analyser& analyser)
: analyser_(analyser)
, data_(analyser.attachment<data>())
{
}

const CXXRecordDecl *report::get_record_decl(QualType type)
{
    const TemplateSpecializationType *tst =
        llvm::dyn_cast<TemplateSpecializationType>(type.getTypePtr());

    if (tst) {
        type = tst->desugar();
    }

    const SubstTemplateTypeParmType *sttpt =
        llvm::dyn_cast<SubstTemplateTypeParmType>(type.getTypePtr());

    if (sttpt) {
        type = sttpt->desugar();
    }

    const CXXRecordDecl *rdecl = type->getAsCXXRecordDecl();

    if (!rdecl) {
        rdecl = type->getPointeeCXXRecordDecl();
    }

    return rdecl;
}

bool report::is_allocator(QualType type)
    // Return 'true' iff the specified 'type' is pointer to
    // 'bslma::Allocator'.
{
    return type->isPointerType()
        && type->getPointeeType()->getCanonicalTypeInternal() ==
           data_.bslma_allocator_;
}

bool report::last_arg_is_explicit(const CXXConstructExpr* call)
    // Return 'false' iff the specified 'call' to a constructor has
    // arguments and the last argument is the default rather than
    // explicitly passed.
{
    unsigned n = call ? call->getNumArgs() : 0;

    return n == 0 || !call->getArg(n - 1)->isDefaultArgument();
}

bool report::takes_allocator(QualType type)
{
    while (type->isArrayType()) {
        type = QualType(type->getArrayElementTypeNoTypeQual(), 0);
    }
    return data_.type_takes_allocator_
        [type.getTypePtr()->getCanonicalTypeInternal().getTypePtr()];
}

bool report::takes_allocator(CXXConstructorDecl const* constructor)
{
    data::CtorTakesAllocator::iterator itr =
        data_.ctor_takes_allocator_.find(constructor);
    if (itr != data_.ctor_takes_allocator_.end()) {
        return itr->second;
    }
    data_.ctor_takes_allocator_[constructor] = false;
    unsigned n = constructor->getNumParams();

    if (n == 0) {
        return false;                                                 // RETURN
    }

    QualType type = constructor->getParamDecl(n - 1)->getType();

    if (is_allocator(type)) {
        return data_.ctor_takes_allocator_[constructor] = true;       // RETURN
    }

    const ReferenceType *ref =
        llvm::dyn_cast<ReferenceType>(type.getTypePtr());

    if (!ref) {
        return false;                                                 // RETURN
    }

    type = ref->getPointeeType();

    if (!type.isConstQualified()) {
        return false;                                                 // RETURN
    }

    return data_.ctor_takes_allocator_[constructor] = takes_allocator(type);
}

static const DynTypedMatcher &
    // Return an AST matcher for BloombergLP::bslma::Allocator.
allocator_type_matcher()
{
    static const DynTypedMatcher matcher = decl(hasDescendant(recordDecl(
        hasName("::BloombergLP::bslma::Allocator")).bind("allocator")));
    return matcher;
}

void report::match_allocator_type(const BoundNodes& nodes)
{
    analyser_.attachment<data>().bslma_allocator_ = QualType(
        nodes.getNodeAs<CXXRecordDecl>("allocator")->getTypeForDecl(), 0);
}

static const DynTypedMatcher &
nested_allocator_trait_matcher()
    // Return an AST matcher which looks for nested traits.  Expanded from
    // macros, allocator traits look like:
    //..
    //  class MyClass { operator bslalg::TypeTraitUsesBslmaAllocator::
    //                           NestedTraitDeclaration<MyClass>() const ... };
    //..
    // or
    //..
    //  class MyClass { operator BloombergLP::bslmf::NestedTraitDeclaration<
    //                                      MyClass,
    //                                      bslma::UsesBslmaAllocator,
    //                                      true>() const ... };
    //..
    // In the second case above, the final boolean parameter may also be false
    // or missing.  The details of the classes involved are too hairy to tease
    // out in the AST matcher; instead the matcher looks for a superset of
    // methods and the callback look sfor further structure.
{
    static const DynTypedMatcher matcher = decl(forEachDescendant(
        methodDecl(
            matchesName("::operator NestedTraitDeclaration($|<)"),
            returns(qualType().bind("type")),
            ofClass(recordDecl().bind("class"))
        ).bind("trait")
    ));
    return matcher;
}

void report::match_nested_allocator_trait(const BoundNodes& nodes)
{
    CXXRecordDecl const* decl = nodes.getNodeAs<CXXRecordDecl>("class");
    std::string type = nodes.getNodeAs<QualType>("type")->getAsString();

    if (!contains_word(type, decl->getNameAsString())) {
        analyser_.report(nodes.getNodeAs<CXXMethodDecl>("trait"),
                         check_name, "BT01",
                         "Trait declaration does not mention its class '%0'")
            << decl->getNameAsString();
    }

    if (type.find("bslalg::struct TypeTraitUsesBslmaAllocator::"
                  "NestedTraitDeclaration<") == 0 ||
        type.find("bslalg_TypeTraitUsesBslmaAllocator::"
                  "NestedTraitDeclaration<") == 0 ||
        (type.find("BloombergLP::bslmf::NestedTraitDeclaration<") == 0 &&
         (type.find(", bslma::UsesBslmaAllocator, true>") != type.npos ||
          type.find(", bslma::UsesBslmaAllocator>") != type.npos))) {
        analyser_.attachment<data>().decls_with_true_allocator_trait_.insert(
            llvm::dyn_cast<NamedDecl>(decl->getCanonicalDecl()));
    } else if (type.find("BloombergLP::bslmf::NestedTraitDeclaration<") == 0 &&
               type.find(", bslma::UsesBslmaAllocator, false>") != type.npos) {
        analyser_.attachment<data>().decls_with_false_allocator_trait_.insert(
            llvm::dyn_cast<NamedDecl>(decl->getCanonicalDecl()));
    }
}

static const DynTypedMatcher &
class_using_allocator_matcher()
    // Matcher for classes that have constructors with a final parameter that
    // is a pointer to an allocator or a reference to a class that has such a
    // constructor.
{
    static const DynTypedMatcher matcher = decl(forEachDescendant(recordDecl(
        has(constructorDecl(
            hasLastParameter(parmVarDecl(anyOf(
                hasType(referenceType(
                    pointee(hasDeclaration(decl(has(constructorDecl(
                        isPublic(),
                        hasLastParameter(parmVarDecl(
                            hasType(pointerType(pointee(hasDeclaration(
                                recordDecl(isSameOrDerivedFrom(
                                    "::BloombergLP::bslma::Allocator"
                                ))
                            ))))
                        ))
                    )))))
                )),
                hasType(pointerType(pointee(hasDeclaration(
                    recordDecl(isSameOrDerivedFrom(
                        "::BloombergLP::bslma::Allocator"
                    ))
                ))))
            )))
        ))
    ).bind("class")));
    return matcher;
}

void report::match_class_using_allocator(const BoundNodes& nodes)
{
    analyser_.attachment<data>()
        .type_takes_allocator_[nodes.getNodeAs<CXXRecordDecl>("class")
                                   ->getTypeForDecl()
                                   ->getCanonicalTypeInternal()
                                   .getTypePtr()] = true;
}

static const DynTypedMatcher
allocator_trait_matcher(int value)
{
    const DynTypedMatcher matcher =
        decl(forEachDescendant(classTemplateSpecializationDecl(
            hasName("::BloombergLP::bslma::UsesBslmaAllocator"),
            templateArgumentCountIs(1),
            isDerivedFrom(classTemplateSpecializationDecl(
                hasName("::bsl::integral_constant"),
                templateArgumentCountIs(2),
                hasTemplateArgument(0, refersToType(asString("_Bool"))),
                hasTemplateArgument(1, equalsIntegral(value))
            ))
        ).bind("class")));
    return matcher;
}

void report::match_allocator_trait(data::DeclsWithAllocatorTrait* set,
                                   const BoundNodes& nodes)
{
    const ClassTemplateSpecializationDecl* td =
        nodes.getNodeAs<ClassTemplateSpecializationDecl>("class");
    QualType arg = td->getTemplateArgs()[0].getAsType();
    const NamedDecl *d = arg->getAsCXXRecordDecl();
    if (!d) {
        const TemplateSpecializationType* tst =
            arg->getAs<TemplateSpecializationType>();
        if (tst) {
            d = tst->getTemplateName().getAsTemplateDecl();
            if (d) {
                d = llvm::dyn_cast<TemplateDecl>(d)->getTemplatedDecl();
            }
        }
    }
    if (d) {
        d = llvm::dyn_cast<NamedDecl>(d->getCanonicalDecl());
        set->insert(d);
    }
}

void report::match_negative_allocator_trait(const BoundNodes& nodes)
{
    match_allocator_trait(
        &analyser_.attachment<data>().decls_with_false_allocator_trait_,
        nodes);
}

void report::match_positive_allocator_trait(const BoundNodes& nodes)
{
    match_allocator_trait(
        &analyser_.attachment<data>().decls_with_true_allocator_trait_, nodes);
}

static const DynTypedMatcher
dependent_allocator_trait_matcher()
{
    const DynTypedMatcher matcher =
        decl(forEachDescendant(classTemplateSpecializationDecl(
            hasName("::BloombergLP::bslma::UsesBslmaAllocator"),
            templateArgumentCountIs(1),
            unless(isDerivedFrom(classTemplateSpecializationDecl(
                hasName("::bsl::integral_constant"),
                templateArgumentCountIs(2),
                hasTemplateArgument(0, refersToType(asString("_Bool"))),
                anyOf(hasTemplateArgument(1, equalsIntegral(0)),
                      hasTemplateArgument(1, equalsIntegral(1)))
            )))
        ).bind("class")));
    return matcher;
}

void report::match_dependent_allocator_trait(const BoundNodes& nodes)
{
    match_allocator_trait(
        &analyser_.attachment<data>().decls_with_dependent_allocator_trait_,
        nodes);
}

static const DynTypedMatcher
should_return_by_value_matcher()
{
    const DynTypedMatcher matcher = decl(forEachDescendant(
        functionDecl(
            returns(asString("void")),
            hasParameter(0, hasType(pointerType(
                unless(pointee(isConstQualified())),
                unless(pointee(asString("void"))),
                unless(pointee(functionType())),
                unless(pointee(memberPointerType()))
            ).bind("type"))),
            anyOf(
                parameterCountIs(1),
                hasParameter(1, unless(anyOf(
                    hasType(isInteger()),
                    hasType(pointerType(
                        unless(pointee(isConstQualified())),
                        unless(pointee(asString("void"))),
                        unless(pointee(functionType())),
                        unless(pointee(memberPointerType()))
                    ))
                )))
            )
        ).bind("func")
    ));
    return matcher;
}

void report::match_should_return_by_value(const BoundNodes& nodes)
{
    const FunctionDecl *func = nodes.getNodeAs<FunctionDecl>("func");
    const PointerType *p1 = nodes.getNodeAs<PointerType>("type");
    if (analyser_.is_component(func) &&
        func->getCanonicalDecl() == func &&
        !func->isTemplateInstantiation() &&
        !func->getLocation().isMacroID() &&
        !func->getParamDecl(0)->hasDefaultArg() &&
        !is_allocator(p1->desugar()) &&
        !takes_allocator(p1->getPointeeType().getCanonicalType())) {
        analyser_.report(func, check_name, "RV01",
                         "Consider returning '%0' by value")
            << p1->getPointeeType().getCanonicalType().getAsString();
        analyser_.report(func->getParamDecl(0), check_name, "RV01",
                         "instead of through pointer parameter",
                         false, DiagnosticsEngine::Note);
    }
}

void report::operator()()
{
    MatchFinder mf;

    OnMatch<report, &report::match_allocator_type> m1(this);
    mf.addDynamicMatcher(allocator_type_matcher(), &m1);

    OnMatch<report, &report::match_nested_allocator_trait> m2(this);
    mf.addDynamicMatcher(nested_allocator_trait_matcher(), &m2);

    OnMatch<report, &report::match_negative_allocator_trait> m4(this);
    mf.addDynamicMatcher(allocator_trait_matcher(0), &m4);

    OnMatch<report, &report::match_positive_allocator_trait> m6(this);
    mf.addDynamicMatcher(allocator_trait_matcher(1), &m6);

    OnMatch<report, &report::match_dependent_allocator_trait> m5(this);
    mf.addDynamicMatcher(dependent_allocator_trait_matcher(), &m5);

    OnMatch<report, &report::match_class_using_allocator> m3(this);
    mf.addDynamicMatcher(class_using_allocator_matcher(), &m3);

    OnMatch<report, &report::match_should_return_by_value> m7(this);
    mf.addDynamicMatcher(should_return_by_value_matcher(), &m7);

    mf.match(*analyser_.context()->getTranslationUnitDecl(),
             *analyser_.context());

    check_not_forwarded(data_.ctors_.begin(), data_.ctors_.end());
    check_wrong_parm(data_.cexprs_.begin(), data_.cexprs_.end());
    check_alloc_returns(data_.returns_.begin(), data_.returns_.end());
    check_globals_use_allocator(data_.globals_.begin(), data_.globals_.end());
}

void report::check_globals_use_allocator(data::Globals::const_iterator begin,
                                         data::Globals::const_iterator end)
{
    for (data::Globals::const_iterator itr = begin; itr != end; ++itr) {
        const VarDecl *decl = *itr;
        const CXXConstructExpr *expr =
            llvm::dyn_cast<CXXConstructExpr>(decl->getInit());
        if (takes_allocator(expr->getType())) {
            unsigned n = expr->getNumArgs();
            bool bad = n == 0;
            if (n > 0) {
                const Expr *last = expr->getArg(n - 1);
                bool result;
                if (last->isDefaultArgument() ||
                    (last->EvaluateAsBooleanCondition(
                         result, *analyser_.context()) &&
                     result == false)) {
                    bad = true;
                }
            }
            if (bad) {
                analyser_.report(decl, check_name, "GA01",
                                 "Variable with global storage must be "
                                 "initialized with non-default allocator");
            }
        }
    }
}

void report::check_not_forwarded(data::Ctors::const_iterator begin,
                                 data::Ctors::const_iterator end)
{
    std::set<std::pair<bool, const CXXRecordDecl *> > records;

    int count = 0;
    for (data::Ctors::const_iterator itr = begin; itr != end; ++itr) {
        const CXXConstructorDecl *decl = *itr;
        const CXXRecordDecl* record = decl->getParent()->getCanonicalDecl();
        bool uses_allocator = takes_allocator(
                   record->getTypeForDecl()->getCanonicalTypeInternal());
        bool has_true_alloc_trait =
            data_.decls_with_true_allocator_trait_.count(record);
        bool has_false_alloc_trait =
            data_.decls_with_false_allocator_trait_.count(record);
        bool has_dependent_alloc_trait =
            !has_true_alloc_trait &&
            !has_false_alloc_trait &&
            data_.decls_with_dependent_allocator_trait_.count(record);
        const CXXRecordDecl *tr = record;
        if (const ClassTemplateSpecializationDecl* ts =
                llvm::dyn_cast<ClassTemplateSpecializationDecl>(tr)) {
            const CXXRecordDecl* tr = ts->getSpecializedTemplate()
                                          ->getTemplatedDecl()
                                          ->getCanonicalDecl();
            if (uses_allocator &&
                !has_true_alloc_trait &&
                !has_false_alloc_trait &&
                !has_dependent_alloc_trait) {
                record = tr;
            }
            if (data_.decls_with_true_allocator_trait_.count(tr)) {
                has_true_alloc_trait = true;
            }
            if (data_.decls_with_false_allocator_trait_.count(tr)) {
                has_false_alloc_trait = true;
            }
            if (data_.decls_with_dependent_allocator_trait_.count(tr)) {
                has_dependent_alloc_trait = true;
            }
        }

        if (has_false_alloc_trait) {
            continue;
        }

        std::pair<bool, const CXXRecordDecl *> rp =
            std::make_pair(uses_allocator, record);

        check_not_forwarded(decl);

        if (records.count(rp) == 0) {
            records.insert(rp);

            if (!uses_allocator && has_true_alloc_trait) {
                analyser_.report(record, check_name, "AT01",
                        "Class %0 does not use allocators but has a "
                        "positive allocator trait")
                    << record;
            } else if (uses_allocator &&
                       !has_true_alloc_trait &&
                       !has_dependent_alloc_trait) {
                analyser_.report(record, check_name, "AT02",
                        "Class %0 uses allocators but does not have an "
                        "allocator trait")
                    << record;
            }
        }

        if (decl == decl->getCanonicalDecl() &&
            uses_allocator &&
            !takes_allocator(decl)) {
            // Warn if the class does not have a constructor that matches this
            // one, but with a final allocator parameter.

            bool found =    // Private copy constructor declarations are OK.
                decl->getAccess() == AS_private &&
                decl->isCopyOrMoveConstructor() &&
                decl->isUserProvided() &&
                !decl->hasBody();

            unsigned num_parms = decl->getNumParams();
            for (data::Ctors::const_iterator ci = begin; !found && ci != end;
                 ++ci) {
                const CXXConstructorDecl *ctor = *ci;
                if (ctor == ctor->getCanonicalDecl() &&
                    ctor != decl &&
                    ctor->getParent() == record &&
                    ctor->getNumParams() == num_parms + 1 &&
                    takes_allocator(ctor)) {
                    found = true;
                    for (unsigned pi = 0; found && pi < num_parms; ++pi) {
                        if (decl->getParamDecl(pi)->getOriginalType() !=
                            ctor->getParamDecl(pi)->getOriginalType()) {
                            found = false;
                        }
                    }
                }
            }

            if (!found) {
                if (decl->isUserProvided()) {
                    analyser_.report(decl, check_name, "AC01",
                                 "This constructor has no version that can be "
                                 "called with an allocator")
                        << decl;
                }
                else {
                    std::string type =
                        decl->isDefaultConstructor()    ? "default " :
                        decl->isCopyOrMoveConstructor() ? "copy "    :
                                                          "";

                    analyser_.report(decl, check_name, "AC02",
                                 "Implicit " + type + "constructor cannot be "
                                 "called with an allocator")
                        << decl;
                }
            }
        }
    }
}

void report::check_not_forwarded(const CXXConstructorDecl *decl)
{
    if (data_.bslma_allocator_.isNull()) {
        // We have not seen the declaration for the allocator yet, so this
        // constructor cannot be using it.
        return;                                                       // RETURN
    }

    if (!decl->hasBody()) {
        return;                                                       // RETURN
    }

    if (!takes_allocator(decl)) {
        return;                                                       // RETURN
    }

    // The allocator parameter is the last one.
    const ParmVarDecl* palloc =
        decl->getParamDecl(decl->getNumParams() - 1);

    // Iterate through the base and member initializers and report those
    // which take an allocator parameter that we do not pass.

    check_not_forwarded(decl->init_begin(), decl->init_end(), palloc);
}

void report::check_not_forwarded(CXXConstructorDecl::init_const_iterator begin,
                                 CXXConstructorDecl::init_const_iterator end,
                                 const ParmVarDecl* palloc)
{
    while (begin != end) {
        check_not_forwarded(*begin++, palloc);
    }
}

void report::check_not_forwarded(const CXXCtorInitializer* init,
                                 const ParmVarDecl* palloc)
{
    // Type of object being initialized.
    const Type* type = init->isBaseInitializer()
        ? init->getBaseClass()
        : init->getAnyMember()->getType().getTypePtr();

    if (!takes_allocator(type->getCanonicalTypeInternal()) ||
        data_.decls_with_false_allocator_trait_.count(
            get_record_decl(type->getCanonicalTypeInternal()))) {
        return;                                                       // RETURN
    }

    const CXXConstructExpr* ctor_expr =
        llvm::dyn_cast<CXXConstructExpr>(init->getInit());

    if (!ctor_expr) {
        return;                                                       // RETURN
    }

    if (takes_allocator(ctor_expr->getConstructor()) &&
        last_arg_is_explicit(ctor_expr)) {
        // The allocator parameter is passed.
        return;                                                       // RETURN
    }

    SourceLocation loc;
    SourceRange range;

    if (init->isWritten()) {
        loc = ctor_expr->getExprLoc();
        range = init->getSourceRange();
    } else {
        loc = palloc->getLocation();
        range = palloc->getSourceRange();
    }

    if (init->isBaseInitializer()) {
        analyser_.report(loc, check_name, "MA01",
                "Allocator not passed to base %0")
            << init->getBaseClass()->getCanonicalTypeInternal().
            getAsString() << range;
    } else {
        analyser_.report(loc, check_name, "MA02",
                "Allocator not passed to member %0")
            << init->getAnyMember()->getNameAsString() << range;
    }
}

std::string report::parm_name(const ParmVarDecl* parm, int position)
{
    std::ostringstream s;

    s << "parameter " << position;

    std::string name = parm->getNameAsString();

    if (name.length() > 0) {
        s << " ('" << name << "')";
    }

    return s.str();
}

template <typename Iter>
void report::check_wrong_parm(Iter begin, Iter end)
{
    while (begin != end) {
        check_wrong_parm(*begin++);
    }
}

void report::check_wrong_parm(const CXXConstructExpr *expr)
{
    const CXXConstructorDecl *decl = expr->getConstructor();
    unsigned n = expr->getNumArgs();
    const ParmVarDecl *lastp;
    const Expr *lastarg;

    // For the problem to possibly occur, we need each of the following:
    //: 1 The constructor has at least two parameters.
    //:
    //: 2 The constructor and the constructor expression have the same
    //:   number of parameters/arguments.  (I believe this will always be
    //:   true.)
    //:
    //: 3 The final constructor parameter has a default argument.
    //:
    //: 4 The final constructor argument expression is the default
    //:   argument.
    //:
    //: 5 The type of the final constructor parameter is pointer to
    //:   allocator.

    if (   n >= 2
        && decl->getNumParams() == n
        && (lastp = decl->getParamDecl(n - 1))->hasDefaultArg()
        && (lastarg = expr->getArg(n - 1))->isDefaultArgument()
        && is_allocator(lastp->getType())) {

        // The error will be that the second-to-last parameter is
        // initialized by the allocator.

        const ParmVarDecl* allocp = decl->getParamDecl(n - 1);
        const ParmVarDecl* wrongp = decl->getParamDecl(n - 2);

        // Descend into the expression, looking for a conversion from an
        // allocator.  The details of this come from an examination of the
        // type structure when a test case exhibiting the problem is
        // encountered.  We use a loop because elements of the descent can
        // repeat.

        const Expr* arg = expr->getArg(n - 2);
        for (;;) {
            arg = arg->IgnoreImpCasts();
            if (const MaterializeTemporaryExpr* mte =
                           llvm::dyn_cast<MaterializeTemporaryExpr>(arg)) {
                arg = mte->GetTemporaryExpr();
                continue;
            }

            if (const CXXBindTemporaryExpr* bte =
                               llvm::dyn_cast<CXXBindTemporaryExpr>(arg)) {
                arg = bte->getSubExpr();
                continue;
            }

            if (const CXXConstructExpr* ce =
                                   llvm::dyn_cast<CXXConstructExpr>(arg)) {
                unsigned i;
                for (i = ce->getNumArgs(); i > 0; --i) {
                    const Expr* carg = ce->getArg(i - 1);
                    if (!carg->isDefaultArgument()) {
                        // Get the rightmost non-defaulted argument
                        // expression.

                        arg = carg->IgnoreImpCasts();
                        break;
                    }
                }

                if (i > 0) {
                    continue;
                }
            }

            // At this point, we should have stripped off all the outer
            // layers of the argument expression which are performing the
            // conversion to the parameter type, and have the inner
            // expression with its actual type.  If that type is
            // pointer-to-allocator, report the problem if it is new.

            if (is_allocator(arg->getType())) {
                analyser_.report(arg->getExprLoc(), check_name, "AM01",
                                "Allocator argument initializes "
                                "non-allocator %0 of type '%1' rather than "
                                "allocator %2")
                    << parm_name(wrongp, n - 1)
                    << wrongp->getType().getAsString()
                    << parm_name(allocp, n)
                    << arg->getSourceRange();
            }

            break;  // Done.
        }
    }
}

template <typename Iter>
void report::check_alloc_returns(Iter begin, Iter end)
{
    for (Iter itr = begin; itr != end; ++itr) {
        check_alloc_return(*itr);
    }
}

void report::check_alloc_return(const ReturnStmt *stmt)
{
    if (   stmt->getRetValue()
        && !stmt->getRetValue()->getType()->isPointerType()
        && data_.decls_with_true_allocator_trait_.count(
            get_record_decl(stmt->getRetValue()->getType()))) {
        const FunctionDecl* func = analyser_.get_parent<FunctionDecl>(stmt);
        if (!func || !func->getResultType()->isReferenceType()) {
            analyser_.report(stmt, check_name, "AR01",
                             "Type using allocator is returned by value");
        }
    }
}

void subscribe(Analyser& analyser, Visitor&, PPObserver&)
    // Create a callback within the specified 'analyser' which will be invoked
    // after a translation unit has been processed.
{
    analyser.onTranslationUnitDone += report(analyser);
}

// -----------------------------------------------------------------------------

static void
gather_var_decls(Analyser& analyser, const VarDecl* decl)
{
    if (analyser.is_component(decl) &&
        decl->hasGlobalStorage() &&
        decl->hasInit() &&
        llvm::dyn_cast<CXXConstructExpr>(decl->getInit())) {
        data& info(analyser.attachment<data>());
        info.globals_.insert(decl);
    }
}

// -----------------------------------------------------------------------------
static void
gather_ctor_exprs(Analyser& analyser, const CXXConstructExpr* expr)
    // Accumulate the specified 'expr' within the specified 'analyser'.
{
    if (analyser.is_component(expr)) {
        data& info(analyser.attachment<data>());
        info.cexprs_.insert(expr);
    }
}

// -----------------------------------------------------------------------------

static void
gather_ctor_decls(Analyser& analyser, CXXConstructorDecl const* decl)
    // Accumulate the specified 'decl' within the specified 'analyser'.
{
    if (analyser.is_component(decl)) {
        analyser.attachment<data>().ctors_.push_back(decl);
    }
}

// -----------------------------------------------------------------------------

static void
gather_return_stmts(Analyser& analyser, ReturnStmt const* stmt)
    // Accumulate the specified 'stmt' within the specified 'analyser'.
{
    if (analyser.is_component(stmt)) {
        analyser.attachment<data>().returns_.insert(stmt);
    }
}

// -----------------------------------------------------------------------------

}  // close anonymous namespace

static RegisterCheck c2(check_name, &gather_ctor_decls);
static RegisterCheck c3(check_name, &gather_ctor_exprs);
static RegisterCheck c4(check_name, &subscribe);
static RegisterCheck c8(check_name, &gather_return_stmts);
static RegisterCheck c1(check_name, &gather_var_decls);

// ----------------------------------------------------------------------------
// Copyright (C) 2014 Bloomberg Finance L.P.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
// ----------------------------- END-OF-FILE ----------------------------------

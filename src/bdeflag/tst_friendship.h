
//@PURPOSE: provide a 'purpose' line.

class topLevelForward;

namespace BloombergLP {
class BBForward;

class FriendShipKlass1 {
    friend class FriendShipKlass2;
    friend class BBForward;
    friend class OutsideClass;
    friend outsideRoutine();
    class ClassForward;

    friend class ClassForward;

    template <class PROTOTYPE>
    struct TemplateStructForward;

    friend template <class PROTOTYPE> struct TemplateStructForward;

    friend class FriendShipabc_Klass3_Helper;

    friend FriendShipabc_Klass3::meow();
};

class FriendShipKlass2 {
    friend bsl::stream& operator<<(bsl::stream, int);
    friend FriendShipKlass2& operator+=(const Klass2&);
};

class FriendShipabc_Klass3 {
};
z
bsl::stream& operator<<(bsl::stream, int);

class friendShipabc_Klass4 {
    // Only problem should be lower case 'f'
};

class txt_friendShipabc_Klass5 {
    // Only problem should be lower case 'f'
};

}  // close enterprise namespace

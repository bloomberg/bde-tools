GDB Pretty printers for Bloomberg components
============================================

GDB, the GNU debugger, is the basic tool for debugging code in linux and is
also a supported tool in other platforms.  During the process of debugging the
debugger has access to all the process memory and, if debugging symbols are
present, to the contents of each objects and its members that can be printed
for user consumption.

The problem is that the data is raw and uninterpreted, providing far more than
what you wished for and at the same time not enough of what you really care.
There are mainly three problems when printing data inside the debugger: too
much detail, not enough information and uninterpreted hard to process data.

The debugger will present all of the members and the structure of the object,
providing too much data as some of which are just implementation details that
provide no useful information about the state of the object. At the same time
many data structures use dynamically allocated memory and printing the object
does not help to see the contents.  Finally, even in cases where the
information is there, it might require interpretation and understanding of the
implementation to provide real value.

Motivating examples
-------------------

Printing the contents of a map:

    (gdb) print mii
    $2 = {
      d_compAndAlloc = {<BloombergLP::bslstl::MapComparator<int, short, std::less<int> >> = {<std::less<int>> = {<std::binary_function<int, int, bool>> = {<No data fields>}, <No data fields>}, <No data fields>}, d_pool = {
          d_pool = {<bsl::allocator<BloombergLP::bsls::AlignmentImp8ByteAlignedType>> = {
              d_mechanism = 0x804ebc8 <BloombergLP::g_newDeleteAllocatorSingleton>}, d_chunkList_p = 0x804f008, d_freeList_p = 0x0, 
            d_blocksPerChunk = 2}}}, d_tree = {d_sentinel = {d_parentWithColor_p = 0xf63d4e2e, d_left_p = 0x804f00c, 
          d_right_p = 0x804f00c}, d_numNodes = 1}}
    
The printed value of the map contains approximatelly 5 lines, too much, of
which only the last few characters provide any insight about the contents of
the map: 'd_numNodes = 1', too little.

Getting to print the contents of the data structure requires knowledge of the
implementation details and being able to navigate the structure jumping through
pointers to nodes. Or we can just use a pretty printer:

    (gdb) print mii
    $3 = map<int,short> [size:1] = {[10] = 321}
    
The dump is now obvious: It contains a single entry that maps the value '10' to
the value '321'.

Printing a bteso_IPv4Address:

    (gdb) print addr2
    $2 = {d_address = 23374016, d_portNumber = 8080}
    
In this case all of the information is present and readily available, the port
is 8080, but the actual address is kept as an integer in network byte order. We
can take advantage of that and print the number in hexadecimal to separate the
4 bytes:

    (gdb) print /x addr2.d_address
    $3 = 0x164a8c0
    
Now we just need to decode each one of the bytes to get the original address.
Or we can use a simple pretty printer to solve that for us:

    (gdb) print addr2
    $4 = 192.168.100.1:8080
    
Goal
====

The goal of the pretty printers is to present the information available to the
debugger in the most useful way.  It should not hide any information from the
user, as it might be important for the debugging session, but it should
abstract the complexity of the implementation to provide the same or more
information in an easy to digest format.

Running the pretty printers
===========================

The pretty printers can be loaded manually inside gdb or they can be loaded
automatically on startup. To load the pretty printers manually run:

    (gdb) python execfile(\
          '/bbshr/bde/bde-oss-tools/contrib/gdb-printers/bde_printer.py')

To load the pretty printers automatically at gdb startup you can copy the file
'gdbinit' into the '.gdbinit' file in your home directory.

Once the pretty printers are loaded, you can list the supported types by
running:

    (gdb) info pretty-printer
    global pretty-printers:
      BDE
        (internal)ContainerBase
        (internal)StringImp
        (internal)StringRefData
        (internal)VectorImp
        atomic
        bdeut_NullableValue
        bdlt::Date
        bdlt::DateTz
        bdlt::Datetime
        bdlt::DatetimeTz
        bdlt::Time
        bdlt::TimeTz
        bslma::ManagedPtr
        bslstl::StringRef
        bteso_IPv4Address
        map
        pair
        set
        shared_ptr
        string
        unordered_map
        unordered_set
        vector
        weak_ptr
    
Each printer can be enabled or disabled individually or by blocks.  This can be
useful to inspect the raw memory when we need to access some detail that is not
shown by the pretty printer:

    (gdb) disable pretty-printer global BDE;IPv4Address
    (gdb) disable pretty-printer global BDE

Some help is provided inside gdb by running the command:

    (gdb) bde-help
    GDB pretty printer support for BDE components
    [...]

    (gdb) bde-help BslString
    Printer for 'bsl::string'.
    [...]

Most of the documentation will be inside the pretty printer scripts as
docstrings.

Finally some of the parameters controlling the output of the pretty printer can
be configured within gdb itself.  At this point this is limited to controlling
whether the bslma::Allocator* will be printed in allocator-aware components.
It can be a useful piece of information if debugging memory issues, but more
often than not it just pollutes the output.  Most printers will play nice with
the 'print pretty' option to break output into multiple lines.

    (gdb) set print bslma-allocator on
    (gdb) set print pretty
    (gdb) print mii
    $3 = map<int,short> [size:3,alloc:0x804ebc8 <BloombergLP::g_newDeleteAllocatorSingleton>] = {
      [0] = 1,
      [1] = 10,
      [2] = 20
    }

Supported Types
===============

The most current list will be available in the documentation inside the
scripts, or as part of the online documentation inside gdb. The pretty printers
at this point support the following types (implementation types shown inside
brackets)

    BDE
      (internal)ContainerBase  [bslalg::ContainerBase (1)]
      (internal)StringImp      [bsl::String_Imp]
      (internal)StringRefData  [bslstl::StringRefData]
      (internal)VectorImp      [bsl::Vector_ImpBase]
      atomic                   bsls::Atomic -- multiple types
      bdeut_NullableValue      bdeut_NullableValue<T>
      bdlt::Date               bdlt::Date
      bdlt::DateTz             bdlt::DateTz
      bdlt::Datetime           bdlt::Datetime
      bdlt::DatetimeTz         bdlt::DatetimeTz
      bdlt::Time               bdlt::Time
      bdlt::TimeTz             bdlt::TimeTz
      bslma::ManagedPtr        bslma::ManagedPtr<T>
      bslstl::StringRef        bslstl::StringRef
      bteso_IPv4Address        bteso_IPv4Address
      map                      bsl::map<K,V>
      pair                     bsl::pair<T,U>
      set                      bsl::set<T>
      shared_ptr               bsl::shared_ptr<T>
      string                   bsl::string
      unordered_map            bsl::unordered_map<K,V>
      unordered_set            bsl::unordered_set<T>
      vector                   bsl::vector<T> (2)
      weak_ptr                 bsl::weak_ptr<T>
  
(1) Only specialization with 'bsl::allocator<T>' (i.e. polymorphic allocator
    adaptor) is supported

(2) The documentation in BSL mentions a specialization 'bsl::vector<bool>' with
    the same properties as 'std::vector<bool>', but experiments indicate that
    there is no specialization for that type.

Contact
=======

You can contact me through:

     MSG: DAVID RODRIGUEZ IBEAS
   email: David Rodriguez Ibeas <dribeas@bloomberg.net>

Any comments or suggestions are welcome, as well as requests to support
specific types, or if you want to  build support for your own type and need help
getting started.

Additionally, Hyman Rosen is maintaining the official version of this for BDE.
You may contact him through:

     MSG: HYMAN ROSEN
   email: Hyman Rosen <hrosen4@bloomberg.net>

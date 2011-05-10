use Cwd;
use File::Basename;
use File::Copy;
use File::Find;
use File::Path;
use Getopt::Long;
use strict;

my $BUILD_DIR_NAME = "msvc";     # relative to $BUILD_ROOT
my $INC_DIR_NAME   = "include";  # relative to $BUILD_DIR_NAME
my $LIB_DIR_NAME   = "lib";      # relative to $BUILD_DIR_NAME
my $BIN_DIR_NAME   = "bin";      # relative to $BUILD_DIR_NAME

my $UPLID        = "windows-Windows_NT-x86-5.1-cl-13.10";
my $XERCESC_LOC  = "thirdparty/xerces-c-2.7.0/${UPLID}";
my $OPENSSL_LOC  = "thirdparty/openssl-0.9.8b/${UPLID}";

# ------------------------------------------------
# 
# ------------------------------------------------
my $BDE_ROOT     = $ENV {"BDE_ROOT"};
my $BUILD_ROOT   = getcwd();
my $CLONE_INC    = 1;
my $OVERRIDE     = 1;
my $COPY_INC     = 0;
my $CORE_BUILD   = 1;
my $TEST_DRIVER  = "";
my $HELP         = 0;

my $inc_dir;  
my $lib_dir;  
my $bin_dir;  

use constant FLG_APPLICATION => 0x01;
use constant FLG_GROUP       => 0x02;
use constant FLG_TEST        => 0x04;


# -------------------------------------------------------
#  hash table :
#  key   - string - project name
#  value - hash table - project information with keys
#  type        - FLG_APPLICATION, FLG_GROUP
#  location    - parent directory
#  clone       - array : list of additional directories to clone
#  foldersCPP  - hash table : CPP folders
#  foldersH    - hash table : H folders
#  dep         - array      : list of dependencies
# -------------------------------------------------------
my %projects =
(
    "bde"       => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "clone"      =>  [ "bde+stlport/stlport"], 
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
              },
    "bce"       => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
               "thirdparty" =>  []
              },
    "bae"       => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
              },
    "bte"       => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
              },
    "bsc"       => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
              },
    "a_xercesc" => 
              {"type"       =>  0,
               "location"   =>  "adapters",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
               "thirdparty"       =>  ["${XERCESC_LOC}"],
               "thirdparty_libs"  =>  ["Xerces-c_static_2D"],
              },
    "xml" => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
              },
    "bas"       => 
              {"type"       =>  0,
               "location"   =>  "groups",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
              },
              
    "a_ossl" => 
              {"type"       =>  0,
               "location"   =>  "adapters",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
               "thirdparty"       =>  ["${OPENSSL_LOC}"],
               "thirdparty_libs"  =>  ["libeay32", "ssleay32" ],
              },
    "m_bass"       => 
              {"type"       =>  (FLG_APPLICATION),
               "location"   =>  "applications",
               "foldersCPP" =>  {},
               "foldersH"   =>  {},
               "macros"           => ["NO_FASTSEND", "BAS_NOBBENV"],
              },
);
    
my %test_proj_info =
              {"type"             =>  (FLG_APPLICATION)|(FLG_TEST),
               "location"         =>  "",
               "foldersCPP"       =>  {},
               "foldersH"         =>  {},
               "dep"              =>  [],
               "thirdparty"       =>  [],
               "thirdparty_libs"  =>  [],
               "macros"           => ["NO_FASTSEND", "BAS_NOBBENV"],
              };

# ************************************************************
#
# ************************************************************
sub print_array  
{
    my $text  = $_[0];
    my $arr   = $_[1];
    
    print "${text}\n";
    foreach  my $x ( @{$arr} )
    {
        print "    $x\n";
    }

}

sub print_hash_table 
{
    my $table = $_[0];
    my $text  = $_[1];
    
    print "====== Hash Table: $text ======\n";
    foreach my $x (keys %{$table} )
    {
        print_array( $x, ${$table}{$x} );
    }
}

# ************************************************************
#
# ************************************************************
sub read_file
{
    my $filename  = $_[0];  # file to read
    my $ref_array = $_[1];  # array where to read

    print "Read  file ${filename} ...\n";

    open (FH, "<" , $filename ) || die "can not open $filename : $!" ;

    @{$ref_array} = <FH>;
    
    chomp ( @{$ref_array} );

    close FH;
}
# ************************************************************
#
# ************************************************************
sub read_tokens_from_file
{
    my $filename  = $_[0];  # file to read
    my $ref_array = $_[1];  # array where to read

    my @lines;
    
    read_file ($filename, \@lines);
    
    foreach my $line (@lines)
    {
        my @words = split (/\s/,$line);
        
        foreach my $word (@words)
        {
            if ( $word =~ m/#|\[/ )
            {
                last;
            }
            
            if ( $word !~ m/\w+/ )
            {
                next;
            }
            
            push (@{$ref_array}, $word);
         }
    }
    return scalar ( @{$ref_array} );
}

# ************************************************************
#
# ************************************************************
sub scan_dir_for_src
{
    my $in_path = $_[0];  # directory to scan
    my $result  = $_[1];  # result array
    
    foreach my $z (glob("${in_path}/*"))   
    {
        if (-f $z)
        {
            my $y = basename ($z);
            if ($y =~ m/\.cpp$/ || 
                $y =~ m/\.c$/ )
            {
                if ( $y =~ m/\.t\.cpp$/ || 
                     $y =~ m/\.t\.c$/ )
                {
                    next;
                }
                push (@{$result}, $y);
            }
        }
    }
}
# ************************************************************
#
# ************************************************************
sub scan_dir_for_inc 
{
    my $in_path = $_[0];  # directory to scan
    my $result  = $_[1];  # result array
    
    foreach my $z ( glob("${in_path}/*") )   
    {
        if (-f $z)
        {
            my $y = basename ($z);
            if ($y =~ m/\.h$/ )
            {
                push (@{$result}, $y);
            }
        }
    }
}

# ************************************************************
#  clone file 
# ************************************************************
sub clone_file
{
    if ($CLONE_INC == 0)
    {
        return;
    }
    
    my $in_path  = $_[0];  # input  parent dir
    my $out_path = $_[1];  # output parent dir
    my $name     = $_[2];  # file   name to clone
    
    if ($OVERRIDE != 0)
    {
        unlink ("${out_path}/${name}" );
    }
    
    #if (-f "${out_path}/${name}" )
    #{
    #    die "can not clone ${out_path}/${name} already exists";
    #} 
    
    if ($COPY_INC != 0)
    {
        copy ( "${in_path}/${name}", "${out_path}/${name}" );
    }
    else
    {
        link ( "${in_path}/${name}", "${out_path}/${name}" );
    }
    #print ( "clone_file: ${out_path}/${name} -> ${in_path}/${name}\n" );
}

sub clone_file_ext
{
    if ($CLONE_INC == 0)
    {
        return;
    }
    my $in_path      = $_[0];  # input  parent dir
    my $out_path     = $_[1];  # output parent dir
    my $name         = $_[2];  # file   name to clone
    
    my $path_name = dirname ($name);
    my $base_name = basename ($name);
    
    $in_path .= "/${path_name}";
    $out_path .= "/${path_name}";
    
    mkpath ($out_path);
    
    if ($OVERRIDE != 0)
    {
        unlink ("${out_path}/${base_name}" );
    }
    
    if ($COPY_INC != 0)
    {
        copy ( "${in_path}/${base_name}", "${out_path}/${base_name}" );
    }
    else
    {
        link ( "${in_path}/${base_name}", "${out_path}/${base_name}" );
    }
    #print ( "clone_file_ext: ${out_path}/${base_name} -> ${in_path}/${base_name}\n" );
}

# ************************************************************
#  clone subtree of directories recursively
# ************************************************************
sub clone_subtree
{
    if ($CLONE_INC == 0)
    {
        return;
    }
    my $in_path      = $_[0];  # input  parent dir
    my $out_path     = $_[1];  # output parent dir
    my $name         = $_[2];  # dir name to copy
    
    my $dname = dirname  ($name);
    my $bname = basename ($name);
        
    $in_path  .= "/${name}" ;
    $out_path .= "/${bname}" ;
   
    print ("clone_subtree: ${in_path} --> ${out_path} \n");
    
    mkpath ("${out_path}");
    
    foreach my $z (glob("${in_path}/*"))   
    {
        my $y = basename ($z);

        if (-d $z)
        {
            if ($y =~ m/\./ || $y =~ m/\.\./ )
            {
               next;
            }
            clone_subtree ("${in_path}", "${out_path}", ${y} );
        }
        else
        {
            clone_file ( ${in_path}, ${out_path}, ${y} );
        }
    }
}

# ************************************************************
#
# ************************************************************
sub write_line
{
    my $filename = $_[0];  # arg 0  - file name
    my $line     = $_[1];  # arg 1  - line to write

    open (FH, ">" , $filename ) || die "can not open $filename : $!" ;

    print FH "${line}\n";
    
    truncate  (FH, tell(FH));
    close FH;
}

# ************************************************************
#
# ************************************************************
sub write_mwc
{
    my $ref_projects = $_[0];  # list of projects
    
    my $mwc_name = "${BUILD_ROOT}/build.mwc";
    
    print ( "Generating mwc : ${mwc_name}\n" );
    
    open (FH, ">" , $mwc_name ) || die "can not open ${mwc_name}: $!" ;
    
    print FH "workspace(build) \{ \n";

    foreach my $key (keys %$ref_projects )
    {
        print FH "     ${key}.mpc\n";
    }

    if (length(${TEST_DRIVER}) != 0)
    {
        print FH "     ${TEST_DRIVER}.t.mpc\n";
    }
            
    
    print FH "\}\n";
    
    truncate  (FH, tell(FH));
    close FH;
}

# ************************************************************
#
# ************************************************************
sub write_mpc
{
    my $proj_name  = $_[0];   # project  name
    my $proj_info  = $_[1];   # project  information
    
    my $flg_grp    = ${$proj_info}{"type"} & (FLG_GROUP);
    my $flg_app    = ${$proj_info}{"type"} & (FLG_APPLICATION);
    my $flg_test   = ${$proj_info}{"type"} & (FLG_TEST);
    
    my $foldersCPP = ${$proj_info}{"foldersCPP"}; 
    my $foldersH   = ${$proj_info}{"foldersH"};   
    my $parent_dir = ${$proj_info}{"location"};
    
    my $proj_dir   = "${BDE_ROOT}/${parent_dir}";
    
    if ($flg_test == 0)  # not a test
    {
        $proj_dir .= "/${proj_name}";
    }
    
    my $mpc_name = "${BUILD_ROOT}/${proj_name}.mpc";

    print ( "Generating mpc: ${mpc_name}\n" );
    
    open (FH, ">" , "${mpc_name}" ) || die "can not open ${mpc_name} : $!" ;

    print FH  <<"EOL1";
project ($proj_name) {

EOL1
#
    if ( $flg_app != 0 )     # application
    {
        print FH  "    exename = ${proj_name}\n";
        print FH  "    exeout = ./${BIN_DIR_NAME}\n";
    }
    else                     # library
    {
        print FH  "    staticname = ${proj_name}\n";
        print FH  "    libout = ./${LIB_DIR_NAME}\n";
    }
    

    foreach my $x ( @{$proj_info->{"dep"}} )
    {
            print FH "    after += ${x}\n";
    }
    print FH "\n";
    
    foreach my $x ( @{$proj_info->{"dep"}} )
    {
            print FH "    libs  += ${x}\n";
    }
    print FH "\n";
    
    foreach my $x ( @{$proj_info->{"thirdparty_libs"}} )
    {
            print FH "    lit_libs  += ${x}\n";
    }
    print FH "\n";
    
    print FH "    libpaths = ./${LIB_DIR_NAME}\n";

    foreach my $x ( @{$proj_info->{"thirdparty"}} )
    {
            print FH "    libpaths += ${BDE_ROOT}/${x}/lib\n";
    }
    print FH "\n";
    
    
    if ($flg_app != 0 && $flg_test == 0 )   # application and not a test
    {
        print FH  "    includes += ${proj_dir}\n";
    }
        
    print FH  <<"EOL2";
    includes += ./${INC_DIR_NAME}
    includes += ./${INC_DIR_NAME}/stlport
EOL2
#
 
    foreach my $x ( @{$proj_info->{"thirdparty"}} )
    {
            print FH "    includes += ${BDE_ROOT}/${x}/include\n";
    }
    
    print FH "\n";
    
    if ( $flg_app != 0 )     # application
    {
        print FH "    macros += _CONSOLE\n";
    }
    
    print FH  <<"EOL22";
        
    macros += WIN32 _WINDOWS _MBCS NOMINMAX
    macros += _STLP_USE_STATIC_LIB 
    macros += _STLP_HAS_NATIVE_FLOAT_ABS 
    macros += _STLP_DONT_FORCE_MSVC_LIB_NAME
    macros += USE_STATIC_XERCES    
    macros += BDE_BUILD_TARGET_DBG 
    macros += BDE_BUILD_TARGET_EXC 
    macros += BDE_BUILD_TARGET_MT
    //macros += BDE_BUILD_TARGET_OPT
    
    macros += BDE_DCL BCE_DCL BAE_DCL BTE_DCL 
    macros += BSC_DCL XML_DCL
EOL22
#
    
    foreach my $x ( @{$proj_info->{"macros"}} )
    {
            print FH "    macros += ${x}\n";
    }
    
    
    print FH  <<"EOL23";
    
    specific(vc8, nmake) {
        macros += _CRT_SECURE_NO_WARNINGS 
        macros += _CRT_SECURE_NO_DEPRECATE 
        macros += _CRT_NONSTDC_NO_DEPRECATE
    }
    
    specific(vc7, vc8, nmake) {
        lib_modifier = .dbg_exc_mt
        compile_flags += /TP
        lit_libs += ws2_32
    }
EOL23
    
    print FH  "    Source_Files {\n";
    
    foreach my $x ( @{$proj_info->{"compile_flags"}} )
    {
        print FH "    compile_flags += ${x}\n";
    }
    
    #-----------------------------------
    #  print cpp names
    #-----------------------------------

    foreach my $x (keys %{$foldersCPP} )
    {
        my $names = $foldersCPP->{$x};
        if (scalar(@{$names}) == 0) 
        {
            next;
        }
        
        my $z = $x;
        $z =~ s/\+/_/;
       
        print FH "\n        ${z} {\n";
        
        foreach my $y ( @{$names} )
        {
            print FH "              ${y}\n";
        }
        print FH "        }\n";
    }


    print FH  <<"EOL3";
    }

    Header_Files {
EOL3
# 
    #-----------------------------------
    #  print h names
    #-----------------------------------
    
    foreach my $x (keys %{$foldersH} )
    {
        my $names = $foldersH->{$x};
        if (scalar(@{$names}) == 0) 
        {
            next;
        }
        
        my $z = $x;
        $z =~ s/\+/_/;
       
        print FH "\n        ${z} {\n";
        
        foreach my $y ( @{$names} )
        {
            print FH "              ${y}\n";
            
        }
        print FH "        }\n";
    }

    print FH  <<"EOL4";
    }
}
EOL4
#
    truncate  (FH, tell(FH));
    close FH;
}

# ************************************************************
#
# ************************************************************
sub build_dep_list
{
    my $proj_name  = $_[0];   # project  name
    my $proj_info  = $_[1];   # project  information
    
    my $flg_grp    = ${$proj_info}{"type"} & (FLG_GROUP);
    my $flg_app    = ${$proj_info}{"type"} & (FLG_APPLICATION);
    
    my $parent_dir = ${$proj_info}{"location"};
    
    my $proj_dir = "${BDE_ROOT}/${parent_dir}/${proj_name}";
    
    my $dep_file_name;
    
    if ($flg_grp != 0)
    {
        $dep_file_name = "${proj_dir}/group/${proj_name}.dep" ;
    }
    else
    {
        $dep_file_name = "${proj_dir}/package/${proj_name}.dep" ;
    }
    
    my @dep_array;
    read_tokens_from_file ($dep_file_name, \@dep_array);
    
    if (!defined ${proj_info}->{"dep"})
    {
        ${proj_info}->{"dep"} = [];
    }
    
    push (@{${proj_info}->{"dep"}}, @dep_array);
}
# ************************************************************
#
# ************************************************************
sub process_package
{
    my $pkg_name   = $_[0];   # package  name
    my $grp_name   = $_[1];   # group    name
    my $proj_info  = $_[2];   # project  information
    
    
    my $flg_grp    = ${$proj_info}{"type"} & (FLG_GROUP);
    my $flg_app    = ${$proj_info}{"type"} & (FLG_APPLICATION);
    
    my $foldersCPP = ${$proj_info}{"foldersCPP"}; # hash with CPP folders
    my $foldersH   = ${$proj_info}{"foldersH"};   # hash with H   folders
    my $parent_dir = ${$proj_info}{"location"};
    
    my $pkg_dir = "${BDE_ROOT}/${parent_dir}/${grp_name}";
    
    if ($flg_grp != 0)
    {
        $pkg_dir          .= "/${pkg_name}";
    }
    
    print ("Processing package '${pkg_name}' in ${pkg_dir}\n");  

    my $word;    
    my @words;
    my @filesCPP;
    my @filesH;
    
    #----------------------------------------
    #  read .mem file
    #----------------------------------------
    if (-f "${pkg_dir}/package/${pkg_name}.mem")
    {    
        read_tokens_from_file ( "${pkg_dir}/package/${pkg_name}.mem", \@words);
    
        foreach $word (@words)
        {
            push (@filesCPP, "${pkg_dir}/${word}.cpp" );
        
            if ($flg_app == 0)  # library
            {
                push (@filesH,   "./${INC_DIR_NAME}/${word}.h" );
                clone_file ( ${pkg_dir}, ${inc_dir}, "${word}.h" );
            }
            else
            {
                push (@filesH, "${pkg_dir}/${word}.h" );
            }
        }
    }

    #----------------------------------------
    #  check .pub file
    #----------------------------------------
    if (-f "${pkg_dir}/package/${pkg_name}.pub")
    {    
        read_tokens_from_file ( "${pkg_dir}/package/${pkg_name}.pub",
                                 \@words);
     
        foreach $word (@words)
        {
            push (@filesH,  "./${INC_DIR_NAME}/${word}" );
            clone_file_ext ( ${pkg_dir}, ${inc_dir}, ${word} );
        }
    }

    #--------------------------------------
    # check if CPP list is empty    
    #--------------------------------------
    @words = ();
    
    if (scalar(@filesCPP) == 0)
    {
        scan_dir_for_src ( ${pkg_dir}, \@words);
        foreach $word (@words)
        {
            push (@filesCPP, "${pkg_dir}/${word}" );
        }
    }
        
    if (scalar(@filesCPP) != 0)
    {        
        ${$foldersCPP}{$pkg_name} = \@filesCPP;
    }
        
    #--------------------------------------
    # check if H list is empty    
    #--------------------------------------
    @words = ();
    
    if (scalar(@filesH) == 0)
    {
        scan_dir_for_inc ( ${pkg_dir}, \@words);
        foreach $word (@words)
        {
            push (@filesH, "${pkg_dir}/${word}" );
            if ($flg_app == 0)  # library
            {
                clone_file_ext ( ${pkg_dir}, ${inc_dir}, ${word} );
            }
        }
    }
    
    if (scalar(@filesH) != 0)
    {
        ${$foldersH}{$pkg_name} = \@filesH;
    }
}

# ************************************************************
#
# ************************************************************
sub process_group
{
    my $grp_name   = $_[0];   # group  name
    my $proj_info  = $_[1];   # project information
    
    my $foldersCPP = ${$proj_info}{"foldersCPP"}; 
    my $foldersH   = ${$proj_info}{"foldersH"};   
    my $parent_dir = ${$proj_info}{"location"};
    
    my $grp_dir = "${BDE_ROOT}/${parent_dir}/${grp_name}";
    
    print ("Processing group ${grp_name} in ${grp_dir}\n");  
   
    my @lines;
    read_file ( "${grp_dir}/group/${grp_name}.mem", \@lines);
    
    foreach my $line (@lines)
    {
        my @pkg_names = split (/\s/,$line);
        
        foreach my $pkg_name (@pkg_names)
        {
            if ( $pkg_name =~ m/#|\[/ )
            {
                last;
            }
            
            if ( $pkg_name !~ m/\w+/ )
            {
                next;
            }
            
            if (-d "${grp_dir}/${pkg_name}/package" )
            {
                # package in group
                process_package ($pkg_name,
                                 $grp_name, 
                                 $proj_info);
            }
            else
            {
                print ("Unable to process package '${pkg_name}' \n");
            }
        }
    }
}         

# ************************************************************
#
# ************************************************************
sub process_project
{
    my $proj_name = $_[0];  # project name
    my $proj_info = $_[1];  # project information
        
    my $proj_parent_dir = ${$proj_info}{"location"};
    my $proj_dir = "${BDE_ROOT}/${proj_parent_dir}/${proj_name}";
    
    # reset group flag
    ${$proj_info}{"type"} &= ~(FLG_GROUP);
    
    if (-d "${proj_dir}/group")
    {
        # group of packages
        
        ${$proj_info}{"type"} |= (FLG_GROUP);
        process_group ($proj_name, $proj_info);
    }
    elsif (-d "${proj_dir}/package")
    {
        # standalone package
        
        process_package ($proj_name, $proj_name, $proj_info);
    }
    else
    {
        print ("Unable to detect project type for '${proj_name}'\n");
        print ("Location: '${proj_dir}'\n");
        process_package ($proj_name, $proj_name, $proj_info);
    }
}


# ************************************************************
#
# ************************************************************
sub generate_full_dep
{
    my $ref_projects    = $_[0];
    my $base_name       = $_[1];  # project name
    my $ref_dep         = $_[2];
    my $ref_3party      = $_[3];
    my $ref_3party_libs = $_[4];
    
    my $base_info    = ${$ref_projects}{$base_name};
    
    foreach my $x ( @{${$base_info}{"thirdparty"}} )
    {
        ${$ref_3party}{$x} = 1;
    }  
    
    foreach my $x ( @{${$base_info}{"thirdparty_libs"}} )
    {
        ${$ref_3party_libs}{$x} = 1;
    }  
    
    foreach my $x ( @{${$base_info}{"dep"}} )
    {
        if ($x =~ m/^xerces-c$/ ||
            $x =~ m/^openssl$/  ||
            $x =~ m/^a_basfs$/  )
        {
            next;
        }
        ${$ref_dep}{$x} = 1;
        generate_full_dep ($ref_projects,
                           $x, 
                           $ref_dep,
                           $ref_3party,
                           $ref_3party_libs);
    }   
     
}

# ************************************************************
#
# ************************************************************
sub process_projects
{
    my $ref_projects = $_[0];
    
    foreach my $key ( keys %$ref_projects )
    {
        my $proj_info = ${$ref_projects}{$key};
        process_project ($key, $proj_info);
        build_dep_list  ($key, $proj_info);
   }    
   
   foreach my $key ( keys %$ref_projects )
   {
      my $proj_info = ${$ref_projects}{$key};
      my %proj_dep;
      my %proj_3party;
      my %proj_3party_libs;
      
      generate_full_dep ($ref_projects,
                         $key, 
                         \%proj_dep,
                         \%proj_3party,
                         \%proj_3party_libs);
      
      @{$proj_info->{"dep"}} = keys%proj_dep;
      @{$proj_info->{"thirdparty"}} = keys%proj_3party;
      @{$proj_info->{"thirdparty_libs"}} = keys%proj_3party_libs;
   }
}
# ************************************************************
#
# ************************************************************
sub generate_test
{
    my $ref_projects = $_[0];
    my $base_name    = $_[1];  # project name
    my $base_info    = ${$ref_projects}{$base_name};
    
    my %test_dep;
    my %test_3party;
    my %test_3party_libs;
    
    $test_proj_info{"location"} = ${$base_info}{"location"};
    $test_proj_info{"type"} = ${$base_info}{"type"} |
                             (FLG_APPLICATION) | (FLG_TEST);
    
    $test_dep{$base_name} = 1;
    generate_full_dep ($ref_projects,
                  $base_name,
                  \%test_dep,
                  \%test_3party,
                  \%test_3party_libs);
                       
    push ( @{$test_proj_info{"dep"}}, keys%test_dep);
    push ( @{$test_proj_info{"thirdparty"}}, keys%test_3party);
    push ( @{$test_proj_info{"thirdparty_libs"}}, keys%test_3party_libs);

    my $foldersCPP =  ${$base_info}{"foldersCPP"};   
    
    OUTER: foreach my $x (keys %{$foldersCPP} )
    {
        my $names = $foldersCPP->{$x};
        
        if (scalar(@{$names}) == 0) 
        {
            next;
        }
        
        INNER: foreach my $y (@{$names} )
        {
            my ($name, $dir, $sfx) = fileparse ($y, qr/\.[^.]*/);
            if ( ${TEST_DRIVER} =~ m/^${name}$/ )
            {
                ${$test_proj_info{"foldersCPP"}}{$x} =
                    ["${dir}${name}.t.cpp"];
                return;
            }                      
        } 
    }       
    
    die "Unable to find corresponed source file for ${TEST_DRIVER}\n";
}

# ************************************************************
#
# ************************************************************
sub build_test_driver
{
    my $ref_projects = $_[0];
    
    foreach my $proj_name ( keys %$ref_projects )
    {
        if ( $TEST_DRIVER =~ m/^${proj_name}/ )
        {
            generate_test ($ref_projects, $proj_name);
            return;
        }
    }
    
    die "Could not find a package for ${TEST_DRIVER}\n";
}
# ************************************************************
#
# ************************************************************
sub write_projects
{
    my $ref_projects = $_[0];
    
    if ($CORE_BUILD != 0) 
    {
        foreach my $key ( keys %$ref_projects )
        {
            my $proj_info = ${$ref_projects}{$key};
            write_mpc ($key, $proj_info);
        }    
        
        if (length(${TEST_DRIVER}) != 0)
        {
            write_mpc ("${TEST_DRIVER}.t", \%test_proj_info); 
        }
        write_mwc ($ref_projects);
    }
    elsif (length(${TEST_DRIVER}) != 0)
    {
        write_mpc ("${TEST_DRIVER}.t", \%test_proj_info);
    } 
}

# ************************************************************
#
# ************************************************************
sub clone_includes 
{
    my $ref_projects = $_[0];
    
    foreach my $proj_name ( keys %$ref_projects )
    {
        my $proj_info = ${$ref_projects}{$proj_name};
        my $proj_parent_dir = ${$proj_info}{"location"};
        my $proj_clone      = ${$proj_info}{"clone"};
    
        my $proj_dir = "${BDE_ROOT}/${proj_parent_dir}/${proj_name}";
    
        foreach my $x (@{$proj_clone})
        {
            clone_subtree (${proj_dir} , 
                           ${inc_dir},
                           ${x});
        }
    }
}
# ************************************************************
#
# ************************************************************
sub  create_dirs
{
    if (!defined($BDE_ROOT) || length($BDE_ROOT) == 0)
    {
        die "BDE_ROOT is not defined";
    }
    
    if (!defined($BUILD_ROOT) || length($BUILD_ROOT) == 0)
    {
        die "BUILD_ROOT is not defined";
    }
    mkpath ("${BUILD_ROOT}", 1);
    
    chdir($BUILD_ROOT);
    
    $BUILD_ROOT  = getcwd();
    $BUILD_ROOT .= "/${BUILD_DIR_NAME}" ;
    $inc_dir   = "${BUILD_ROOT}/${INC_DIR_NAME}" ;
    $lib_dir   = "${BUILD_ROOT}/${LIB_DIR_NAME}" ;
    $bin_dir   = "${BUILD_ROOT}/${BIN_DIR_NAME}" ;
    
    mkpath ("${BUILD_ROOT}", 1);
    mkpath ("${inc_dir}", 1);
    mkpath ("${lib_dir}", 1);
    mkpath ("${bin_dir}", 1);
}

sub print_options
{
    print "BUILD_ROOT=${BUILD_ROOT}\n";
    print "BDE_ROOT=${BDE_ROOT}\n";
    print "CLONE_INC=${CLONE_INC}\n";
    print "OVERRIDE=${OVERRIDE}\n";
    print "CORE_BUILD=${CLONE_INC}\n";
    print "TEST_DRIVER=${TEST_DRIVER}\n";
}

sub usage
{
    print "Usage:  genbdemwc.pl [options]\n";
    print "Options:\n";
    print "  -clone (-noclone)\n";
    print "         clone or not the include directoties. default is clone\n";
    print "  -copy  (-nocopy)\n";
    print "         clone via copying or via hardlinks. default is nocopy\n";
    print "  -override (-nooverride)\n";
    print "         override existing file during clone step. default is override\n";
    print "  -core  (-nocore)\n";
    print "         generate projects or not for core BDE, BAS, adapters libraries and m_bass\n";
    print "         default is to generate core\n";
    print "  -bde-root=value \n";
    print "         BDE_ROOT value. the default is env. variable value\n";
    print "  -dir = value\n";
    print "         directory to create projects and perform build\n";
    print "  -test-driver|td=name\n";
    print "          generate test driver project for given component\n";
}

sub do_main 
{
    my $dir_save =  getcwd ();
    
    GetOptions ( 'dir=s'            => \$BUILD_ROOT,
                 'bde-root=s'       => \$BDE_ROOT,
                 'test-driver|td=s' => \$TEST_DRIVER,
                 'clone!'           => \$CLONE_INC,
                 'copy!'            => \$COPY_INC,
                 'core!'            => \$CORE_BUILD,
                 'override!'        => \$OVERRIDE,
                 'help|usage|?'     => \$HELP
                );

    if ($HELP != 0)
    {
        usage();
        return;
    }                
    
    print_options ();
    create_dirs ();
        
    if ($CLONE_INC != 0) 
    {
        clone_includes (\%projects);
    }
    
    process_projects (\%projects);
    
    if (length($TEST_DRIVER) != 0)
    {
        build_test_driver (\%projects);
    }
    
    write_projects (\%projects);
    
    chdir (${BUILD_ROOT});
    system ("mwc.pl -type VC8 -static build.mwc");
    
    if (length(${TEST_DRIVER}) != 0)
    {
        system ("mpc.pl -type VC8 -static ${TEST_DRIVER}.t.mpc");
    }
    
    chdir ($dir_save);
}
           
do_main () ;

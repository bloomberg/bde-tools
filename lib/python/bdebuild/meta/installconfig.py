import copy
import os

from bdebuild.meta import graphutil
from bdebuild.common import blderror
from bdebuild.common import mixins


class InstallConfig(mixins.BasicEqualityMixin, mixins.BasicReprMixin,
                    mixins.BasicSerializeMixin):
    """This class provides install options for a build configuration.

    The ``setup_install_uors`` method must be called to set up the install_uors
    attribute.

    Attributes:
       is_flat_include (bool): Whether header files should be installed to a
           flat directory for all UORs or a separate directory for each UOR.
       pc_dir (str): The path of the directory relative to the prefix in which
           pkg-config files will be installed.
       lib_dir (str): The path of the directory relative to the prefix in which
           library files will be installed.
       install_uors (set of str): The names of UORs to be installed.
       lib_suffix (str): The suffix to add to the library being built.
       is_install_h (bool): Whether to install header files.
       is_install_lib (bool): Whether to install library files.
       is_install_pc (bool): Whether to install pkgconfig files.
    """

    def __init__(self, ufid,
                 is_dpkg,
                 is_flat_include,
                 lib_dir,
                 lib_suffix):
        """Initialize the object.

        Args:
            ufid (Ufid): The build flags.
            is_dpkg (bool): Whether install to dpkg, this value overrides other
                install options.
            is_flat_include (bool): Whether to install headers to a flat path.
            lib_dir (str): The directory to install libraries.
            lib_suffix (str): A suffix to add to the name of the libraries.
        """
        if is_dpkg:
            self.is_flat_include = True
            lib_dir = 'lib64' if '64' in ufid.flags else 'lib'
            ufid_copy = copy.deepcopy(ufid)
            if '64' in ufid_copy.flags:
                ufid_copy.flags.remove('64')
            self.pc_dir = os.path.join(lib_dir, 'pkgconfig')
            self.lib_dir = os.path.join(lib_dir, str(ufid_copy))
            self.lib_suffix = ''
        else:
            self.is_flat_include = is_flat_include
            self.lib_dir = lib_dir
            self.pc_dir = os.path.join(lib_dir, 'pkgconfig')
            self.lib_suffix = lib_suffix
        self.install_uors = set()
        self.is_install_h = True
        self.is_install_lib = True
        self.is_install_pc = True

    def setup_install_uors(self, targets, is_install_dep, uor_digraph):
        """Determine install targets.

        Determine the name of the Units of Release (package groups, stand-alone
        packages, and third-party directories) to be installed.

        Args:
            targets (list of str): The list of install targets.
            is_install_dep (bool): Whether to also install dependencies of the
                targets.
            uor_digraph (dict): The depency graph of UOR names.

        Raises:
            blderror.InvalidInstallTargetError
        """

        uors = uor_digraph.keys()
        if targets:
            targets = targets.split(',')
            if any(t not in uors for t in targets):
                raise blderror.InvalidInstallTargetError(
                    'Install targets must be UORs (package groups, '
                    'stand-alone packages, and third-party directories).')
            if is_install_dep:
                self.install_uors = set(graphutil.topological_sort(
                    uor_digraph, targets))
            else:
                self.install_uors = targets
        else:
            self.install_uors = uors

    def should_install(self, uor_name):
        """Whether a UOR should be installed.
        """
        return uor_name in self.install_uors

    def get_target_name(self, uor_name):
        """Return the the target library name of a UOR.
        """
        return uor_name + self.lib_suffix

    def get_lib_install_path(self, uor_name):
        """Return library install path of a UOR.
        """
        if not self.is_install_lib or not self.should_install(uor_name):
            return None

        return os.path.join('${PREFIX}', self.lib_dir)

    def get_h_install_path(self, uor_name, is_thirdparty=False,
                           inner_package_name=None):
        """Return the headers install path of a UOR.

        Args:
            uor_name (str): The name of the unit of release.
            inner_package_name (str, optional): The name of the inner package.
        """

        if not self.is_install_h or not self.should_install(uor_name):
            return None

        install_path = os.path.join('${PREFIX}', 'include')

        # Temporary: Don't treat third-party packages specially: Install
        # third-party header files of third-party packages in the same global
        # include path as other types of UORs to preserve backwards
        # compatibilty.  In the future, we want to use relatively include path
        # for third-party packages internally within BDE.
        if not self.is_flat_include:
            install_path = os.path.join(install_path, uor_name)
        if inner_package_name == 'bsl+stdhdrs':
            install_path = os.path.join(install_path, 'stlport')
        return install_path

    def get_pc_install_path(self, uor_name):
        """Return the install path of the pkg-config file of a UOR.
        """
        if not self.is_install_pc or not self.should_install(uor_name):
            return None

        return os.path.join('${PREFIX}', self.pc_dir)

    def get_pc_libdir(self, uor_name):
        """Return the value of $libdir variable in the pkg-config file.
        """
        return '${prefix}/%s' % self.lib_dir.replace('\\', '/')

    def get_pc_includedir(self, uor_name, is_thirdparty=False):
        """Return the value of the $includedir variable in the pkg-config file.
        """
        include_path = '${prefix}/include'

        # Temporary: Don't treat third-party packages specially: Install
        # third-party header files of third-party packages in the same global
        # include path as other types of UORs to preserve backwards
        # compatibilty.  In the future, we want to use relatively include path
        # for third-party packages internally within BDE.
        if not self.is_flat_include:
            # use "/" even on Windows for compatibility with pykg-config.
            include_path += '/%s' % uor_name
        return include_path

    def get_pc_extra_includes(self, uor_name):
        """Return any extra include paths in the pkg-config file.
        """
        if uor_name == 'bsl':
            return ['${includedir}/stlport']
        else:
            return []

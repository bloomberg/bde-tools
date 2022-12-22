.. _bbs_make_vscode-top:

===============
bbs_make_vscode
===============
Create a `VSCode <https://code.visualstudio.com/>`_ project for the current
directory.

This script simplifies the process of using ``VS Code`` on a BDE style
repository by automatically generating a project with toolchains and build
targets populated.

Setting up VS Code from WSL
===========================
  * Install and configure WSL with gcc or clang compiler.

  * Clone and setup ``bde-tools`` from
{{{ internal
    ether internal `bbgithub bde-tools
    <https://bbgithub.dev.bloomberg.com/bde/bde-tools>`_ repository:

    .. code-block:: shell

       git clone bbgithub:bde/bde-tools
       export PATH=${PWD}/bde-tools/bin:${PATH}

    or from
}}}
    public `github bde-tools <https://github.com/bloomberg/bde-tools>`_
    repository:

    .. code-block:: shell

       $ git clone https://github.com/bloomberg/bde-tools.git
       export PATH=${PWD}/bde-tools/bin:${PATH}

  * Clone bde code (or :ref:`setup a workspace<bbs-build-workspace-top>`) from
{{{ internal
    ether internal `bbgithub bde
    <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

    .. code-block:: shell

       $ git clone bbgithub:bde/bde
       $ cd bde

    or from
}}}
    public `github bde <https://github.com/bloomberg/bde>`_ repository:

    .. code-block:: shell

       $ git clone https://github.com/bloomberg/bde.git
       $ cd bde

  * Now we can set up the build environment with ``bbs_build_env``, followed by
    ``bbs_make_vscode`` which will create a ``.vscode`` directory, e.g.:

    .. code-block:: shell

       eval `bbs_build_env -u dbg_64 -p gcc-10`
       bbs_make_vscode

  * With the environment set up, we can now start VS Code:

    .. code-block:: shell

       code .

    VS Code will detect that you've opened a CMake workspace and will suggest
    selecting the kit. Choose the "[Unspecified]" kit. Then choose CMake:
    Configure in the command pallette to configure the workspace.

    To change the UFID, simply repeat ``eval`` and ``bbs_make_vscode`` steps.
    Note that the files will be overwritten and any manual changes will be
    lost.

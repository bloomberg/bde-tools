.. _docs-howto-top:

===========================
Updating this Documentation
===========================

Get Source
----------

Source files for BDE documentation can be found in the `bde/bde-docs
<https://bbgithub.dev.bloomberg.com/bde/bde-docs/>`_ repository.

Clone repository:

  ::

    $ git clone bbgithub:bde/bde-tools
    $ cd bde-tools/docs

Enable Sphinx virtualenv
------------------------

BDE documentation is generated with Sphinx generator.

To load pre-configured virtualenv for Sphinx:

  ::

    $ source /bb/bde/documentation/sphinx_env/bin/activate

Modify the source code
----------------------

**reStructuredText** is the default plantext markup language used by Sphinx.
Extensive documentation on the **reStructuredText** concepts and syntax can be
found `here
<http://www.sphinx-doc.org/en/master/usage/restructuredtext/basics.html>`_.

Use existing BDE documentation for reference.

Render the BDE documentation html
---------------------------------

To render BDE documentation site (internal version):

  ::

    $ make internal

To render BDE documentation site (OSS version):

  ::

    $ make oss

Verify the content
------------------

To verify the visual appearence of the generated site (internal version):

  ::

    $ mkdir -p ~/public_html/bde-tools
    $ cp -R build/internal/html/* ~/public_html/bde-tools/


To verify the visual appearence of the generated site (OSS version):

  ::

    $ mkdir -p ~/public_html/bde-tools
    $ cp -R build/oss/html/* ~/public_html/bde-tools/

In the browser, open the following URL to view the generated site (``<USER>``
is your UNIX login ):

  ::

    http://devhtml.dev.bloomberg.com/~<USER>/bde-tools/


When you are happy with the content and the rendering of the site, create a
Pull Request to the master repository. BDE documentation site will be updated
on the regular basis to reflect changes.

Deactivate Sphinx virtualenv
----------------------------

To deactivate the Sphinx virtualenv:

  ::

    $ deactivate

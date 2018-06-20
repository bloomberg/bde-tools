##bde-c-style

This package provides a cc-mode C/C++ style, 'bde', that mostly conforms to the
[BDE style guide](https://github.com/bloomberg/bde/wiki/Introduction-to-BDE-Coding-Standards).

##Installation

Add bde-c-style.el to the `load-path` and `(require 'bde-c-style)`.

##Usage

Set "bde" as the default c++-mode style:

```elisp
(add-to-list 'c-default-style '(c++-mode . "bde"))
(add-to-list 'c-default-style '(c-mode . "bde"))
```

Alternatively, you can call `c-set-style` in the `c-mode-common-hook`:

```elisp
(add-hook 'c-mode-common-hook
    (lambda () (c-set-style "bde"))
```

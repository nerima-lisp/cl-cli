# Installation

`cl-cli` itself depends only on `uiop`, which ships with every modern ASDF, so
cloning it where ASDF can find it (for example under `~/common-lisp/` or
`~/quicklisp/local-projects/`) is enough to load it:

```bash
git clone https://github.com/nerima-lisp/cl-cli  ~/common-lisp/cl-cli
```

```lisp
(ql:quickload :cl-cli)
```

=== "Nix (recommended for development)"

    The flake wires up [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog)
    and [`cl-weave`](https://github.com/nerima-lisp/cl-weave) for you -- both
    are only needed to run the test suite, not to use `cl-cli` itself:

    ```bash
    nix develop        # drop into a shell with all dependencies available
    nix flake check    # run the test suite across sbcl and ecl
    ```

=== "Running the test suite without Nix"

    Clone `cl-prolog` and `cl-weave` where ASDF can find them, the same way as
    `cl-cli` above, then load `tests/run-tests.lisp`.

The repository includes Nix checks for both `sbcl` and `ecl`, so
`nix flake check` verifies the current test suite across multiple Common Lisp
implementations.

Continue with [Quick Start](quick-start.md) to write and dispatch your first
app spec.

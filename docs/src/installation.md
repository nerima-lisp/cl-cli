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

    The flake wires up [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog),
    [`cl-weave`](https://github.com/nerima-lisp/cl-weave),
    [`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit) (plus its
    own [`cl-boundary-kit`](https://github.com/nerima-lisp/cl-boundary-kit) /
    [`cl-log-kit`](https://github.com/nerima-lisp/cl-log-kit) dependencies), and
    [`cl-json-kit`](https://github.com/nerima-lisp/cl-json-kit) for you -- all
    are only needed to run the test suite, not to use `cl-cli` itself:

    ```bash
    nix develop        # drop into a shell with all dependencies available
    nix flake check    # run the sbcl and ecl suites and build the docs
    ```

    Both commands work on `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`,
    and `aarch64-darwin`.

=== "Running the test suite without Nix"

    Clone `cl-prolog`, `cl-weave`, and `cl-json-kit` where ASDF can find
    them, the same way as `cl-cli` above, then load `tests/run-tests.lisp`:

    ```bash
    sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
    ```

    Adding `cl-process-kit`, `cl-boundary-kit`, and `cl-log-kit` alongside
    them enables the extra suite that runs generated scripts through the real
    shells.

Both the `sbcl` and `ecl` checks must be green. They do not run the same
thing: the shell-verification half of the suite needs `cl-process-kit`, whose
own `cl-log-kit` dependency is SBCL-only
([nerima-lisp/cl-log-kit#1](https://github.com/nerima-lisp/cl-log-kit/issues/1)),
so ECL runs the portable core. The runner prints which half it loaded. See
[Compatibility](compatibility.md) for the full matrix.

Continue with [Quick Start](quick-start.md) to write and dispatch your first
app spec.

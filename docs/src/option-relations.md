# Option Relations and Grouping

For CLIs that need cross-option validation, declare option relationships
directly in the option spec so parsing and help stay aligned — no
hand-written post-parse checks required.

```lisp
(list
 (cl-cli:make-option :name "profile"
                     :kind :value)
 (cl-cli:make-option :name "config"
                     :kind :value
                     :requires '(:profile)
                     :description "Config file.")
 (cl-cli:make-option :name "token"
                     :kind :value)
 (cl-cli:make-option :name "password"
                     :kind :value
                     :conflicts-with '("token")))
```

Relation targets may be written either as option keys such as `:profile` or
as names such as `"profile"` / `"--profile"`. They are evaluated after CLI
values, environment defaults, and literal defaults are resolved — so a
`:default` can satisfy a `:requires` target without the user typing it.

When a relation target points at a hidden option, parsing still honors the
relation, but generated help omits that hidden target from public metadata
and runtime relationship errors avoid printing the hidden option's name.

## Requiring one of several alternatives

`:requires` demands every listed target. When only one of several
alternatives must be present — such as authenticating with a token *or* a
username and password — declare `:requires-any-of` instead:

```lisp
(cl-cli:make-option :name "login"
                    :kind :flag
                    :requires-any-of '(:token :username))
```

Parsing signals `cli-missing-any-of-options` when none of the declared
alternatives are supplied, and help lists them as
`requires one of: --token, --username`.

## Conditional requirements

For requirements that depend on *other* options, use `:required-if` (the
option becomes mandatory when any listed option is present) or
`:required-unless` (it is mandatory unless any listed option is present).
Both signal `cli-missing-option-value` and render in help as
`required if: ...` / `required unless: ...`:

```lisp
(list
 (cl-cli:make-option :name "profile" :kind :value)
 (cl-cli:make-option :name "config" :kind :value :required-if '(:profile))
 (cl-cli:make-option :name "token" :kind :value)
 (cl-cli:make-option :name "user" :kind :value :required-unless '(:token)))
```

## Exclusive and inclusive groups

To make a set of options mutually exclusive (at most one may be supplied),
splice them through `cl-cli:exclusive-group` instead of hand-writing every
pairwise `:conflicts-with`. Each member gains the others as conflicts, so
exclusivity reuses the same validation and hidden-target-safe error messages:

```lisp
:global-options (cl-cli:exclusive-group
                 (cl-cli:make-option :name "json" :kind :flag)
                 (cl-cli:make-option :name "yaml" :kind :flag)
                 (cl-cli:make-option :name "table" :kind :flag))
```

Conflicts an option already declares are preserved, so a group member can
still conflict with options outside the group.

When the choice is mandatory, use `cl-cli:required-exclusive-group` instead:
exclusivity is enforced as above, and parsing additionally fails with
`Exactly one of ...` when none of the members is supplied — expressing an
"exactly one of" obligation that pairwise `:conflicts-with` cannot.

For the opposite relationship — options meant to be used *together*, such as
a paired `--host` and `--port` — splice them through `cl-cli:inclusive-group`.
If any member is supplied, all must be (supplying none is fine); a partial
set signals `cli-missing-dependent-option` and help renders the members as
"all or none of":

```lisp
:global-options (cl-cli:inclusive-group
                 (cl-cli:make-option :name "host" :kind :value)
                 (cl-cli:make-option :name "port" :kind :value))
```

## Grouping in help output

Options accept a `:group` label too, which sections them under their own
heading in help (and appears in JSON), mirroring [command
grouping](commands.md#grouping-large-command-surfaces):

```lisp
(list
 (cl-cli:make-option :name "output" :kind :value :group "Output")
 (cl-cli:make-option :name "format" :kind :value :group "Output")
 (cl-cli:make-option :name "token" :kind :value :group "Auth"))
```

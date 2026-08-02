{
  description = "Composable Common Lisp CLI parsing and dispatch primitives.";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The org flake preset. Everything this file used to spell out by hand --
    # the `:version` extraction out of cl-cli.asd, `forAllSystems`, the treefmt
    # eval wired to both `formatter` and `checks.formatting`, the mkdocs
    # package plus its check, the run-tests.lisp gate, the `apps.test`/
    # `apps.default` pair and the devShell -- is the single `mkPackageFlake`
    # call below. PACKAGE_STANDARD.md distributes that shape as a *template*
    # copied by hand into 21 repositories, and the copies drift: cl-weave and
    # cl-prolog have already converged on the preset, and this file's 357 hand-
    # written lines were the last copy in the set still re-deriving all of it.
    #
    # Pinned to a release TAG like every other input: a bare
    # `github:nerima-lisp/cl-nix-forge` follows that repository's default
    # branch and would change this build without warning.
    #
    # This and paredit-cli below are the two places ADR-0079's `flake = false`
    # rule is deliberately not applied, and it costs -- each drags its own
    # input graph into flake.lock. They earn it by being consumed for their
    # `lib` outputs, which a bare source tree cannot provide.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # paredit-cli is the structural editor this repository's Lisp refactors go
    # through. It is wired in here for `lib.mkLintCheck`, so the balanced-
    # S-expression property those refactors depend on becomes a `nix flake
    # check` gate instead of something only an interactive session would ever
    # notice -- a truncated `defun` still reads as a plausible diff.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling packages are ALWAYS pinned to a release tag. A bare
    # `github:nerima-lisp/cl-weave` follows that repo's default branch, which
    # means an upstream push to main breaks this repo's CI without warning.
    #
    # `flake = false` on every one of them, per ADR-0079. Nothing below reads a
    # sibling's `packages`, `checks` or `lib`; each is used only as a source
    # tree, handed to `cl.lispDerivation` to be BUILT into an ASDF system that
    # cl-nix-forge then resolves onto CL_SOURCE_REGISTRY. A `flake = true`
    # input drags its ENTIRE input graph into flake.lock even when no output is
    # used, and six siblings each carrying their own nixpkgs/treefmt-nix/
    # cl-weave/paredit-cli/rust-overlay is what put this lock at 82 nodes
    # against an org range of 5-19.
    #
    # No `inputs.nixpkgs.follows` on them either: a non-flake input has no
    # inputs of its own, so the override has no target and Nix warns
    # `has an override for a non-existent input 'nixpkgs'` on every evaluation.
    #
    # Every one of these is a TEST dependency, so they are
    # `lispCheckDependencies` and never `lispDependencies` below.
    #
    # cl-host-kit (declared separately below, near cl-json-kit) is the one
    # exception as of the 2026-08-01 uiop->cl-host-kit migration: the main
    # `cl-cli` system's :depends-on now names it too, guarded by `#+sbcl`, so
    # it is wired through `lispDependencies` instead. DEPENDENCY_POLICY.md's
    # L1 tier no longer means "zero org-internal dependencies" for every
    # member -- see its 2026-08-01 revision -- only that depth still
    # decreases strictly along every edge, which `cl-cli -> cl-host-kit`
    # satisfies (depth 0 -> 1).
    # 2026-08-02: cl-weave's main system used to grow a
    # `(:require "sb-cover")` on every tag from v1.1.0 through v1.1.2,
    # SBCL-only, which took the ECL half of the suite below out at load
    # time ("Module error: Don't know how to REQUIRE sb-cover"). Two
    # rounds of upstream fixes, each verified against this repo's own
    # checks.ecl after two premature bump attempts here first found them
    # incomplete: nerima-lisp/cl-weave#36 (the sb-cover :depends-on
    # itself, released v1.1.3) and #37 (five more unguarded SB-EXT
    # references the first fix had been masking -- src/cli-image.lisp
    # and four spots in t/ -- released v1.1.4, this pin). Both extend
    # cl-weave's own existing platform-protocol.lisp/platform-sbcl.lisp
    # capability-dispatch pattern, already used correctly for its
    # :timeout feature, rather than inventing a new shape. If a future
    # cl-weave bump ever reproduces an ECL load failure, re-open the
    # upstream issue with the exact error rather than reverting this pin
    # blind -- see project memory under
    # `project_cl_weave_ecl_portability` for the full history.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.4";
      flake = false;
    };

    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v1.3.0";
      flake = false;
    };

    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v3.1.0";
      flake = false;
    };

    # v1.0.0, not the latest v2.0.1: pinned to match the exact version
    # cl-process-kit v3.1.0's OWN flake.lock verifies against (still
    # `:depends-on (:asdf :cl-log-kit)` there -- v2.0.1 replaced that edge
    # with `:cl-host-kit`, a combination cl-process-kit's own suite has
    # never been run against). Bumping past what upstream itself tested
    # would trade a verified pin for an unverified guess.
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.0.1";
      flake = false;
    };

    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.0.1";
      flake = false;
    };

    # Neither of these is a dependency cl-cli names anywhere. cl-log-kit
    # v2.0.1's own `:depends-on` is `((:version "cl-date-kit" "0.2.0")
    # (:version "cl-concurrent-kit" "0.1.0") (:version "cl-host-kit" "0.2.0"))`,
    # and `siblingSystem` below resolves a system's graph only from the
    # `lispDependencies` it is handed -- never from the .asd -- so a
    # transitive edge is invisible until it is spelled out. It was: the
    # shell-verification half of the suite died with `Component "cl-date-kit"
    # not found, required by #<SYSTEM "cl-log-kit">`.
    #
    # Both are `:depends-on ()` leaves, so neither drags anything further in.
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v0.2.0";
      flake = false;
    };

    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.4.2";
      flake = false;
    };

    # cl-process-kit v3.0.0 migrated its UTF-8/octet handling onto this
    # (previously hand-rolled), so it is now a real transitive dependency of
    # the base "cl-process-kit" ASDF system, not just its PTY extension.
    # Dependency-free (`:depends-on ()`), SBCL-only usage here since its only
    # consumer, cl-process-kit, is.
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.4.0";
      flake = false;
    };

    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.0.2";
      flake = false;
    };

    # Unlike the siblings above, this one is a REAL runtime dependency (see
    # cl-cli.asd's :depends-on), not test-only -- the 2026-08-01 uiop->
    # cl-host-kit org migration. It stays `flake = false` per ADR-0079 like
    # every other sibling here; it is SBCL-only (its own README), which is
    # why cl-cli.asd guards it with a `#+sbcl` reader conditional and why
    # `eclPackage` below explicitly excludes it from the ECL build.
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.2.5";
      flake = false;
    };

    # treefmt-nix stays a real flake: `mkPackageFlake`'s `treefmt.evalModule`
    # argument below IS `treefmt-nix.lib.evalModule`, so ADR-0079 keeps it at
    # `flake = true` -- and because it is a flake, the `follows` does have a
    # target and does its job. It is taken as an argument rather than closed
    # over by cl-nix-forge so this repo picks its own treefmt-nix version.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      paredit-cli,
      cl-weave,
      cl-prolog,
      cl-process-kit,
      cl-boundary-kit,
      cl-log-kit,
      cl-date-kit,
      cl-concurrent-kit,
      cl-codec-kit,
      cl-json-kit,
      cl-host-kit,
      treefmt-nix,
    }:
    let
      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # The suites in t/completion-commands-shell-verification-test.lisp pipe
      # cl-cli's own generated output through the real tools that will consume
      # it. They self-skip when a tool is missing, so the tools have to be on
      # PATH inside the sandbox or the checks silently verify nothing.
      verificationTools = pkgs: [
        pkgs.bash
        pkgs.zsh
        pkgs.fish
        pkgs.mandoc
        pkgs.nushell
        pkgs.elvish
        pkgs.powershell
      ];

      # A `flake = false` sibling source tree, as a BUILT ASDF system fit for
      # `lispCheckDependencies`.
      #
      # The tree cannot simply be put on the registry as-is: `lispDerivation`
      # sets ASDF_OUTPUT_TRANSLATIONS to the identity mapping so fasls land
      # beside their sources and the output stays reusable, and ASDF would then
      # try to write a sibling's fasls into the read-only Nix store. Building
      # each one here is what produces a tree that already has its fasls.
      #
      # `lisp` is an argument rather than defaulted because fasls are
      # implementation-specific: cl-nix-forge asserts a consumer and its
      # dependencies were built by the same implementation, so the SBCL and ECL
      # halves of the suite need two independent derivations per sibling. The
      # version is read from the sibling's own .asd for the same reason cl-cli's
      # is -- a hardcoded copy here is a number nobody would remember to bump.
      siblingSystem =
        ctx:
        {
          pname,
          source,
          lisp,
          asdName ? "${pname}.asd",
          lispSystem ? pname,
          lispDependencies ? [ ],
        }:
        ctx.cl.lispDerivation {
          inherit
            pname
            lispSystem
            lisp
            lispDependencies
            ;
          version = ctx.cl.fromAsdSystem "${source}/${asdName}";
          src = source;
        };

      clWeaveSystem =
        ctx: lisp:
        siblingSystem ctx {
          pname = "cl-weave";
          source = cl-weave;
          inherit lisp;
        };

      clJsonKitSystem =
        ctx: lisp:
        siblingSystem ctx {
          pname = "cl-json-kit";
          source = cl-json-kit;
          inherit lisp;
        };

      # The one REAL (non-test) sibling dependency: cl-cli.asd's
      # :depends-on names "cl-host-kit" under `#+sbcl`. SBCL-only, like
      # cl-log-kit/cl-boundary-kit/cl-process-kit below, and for the same
      # reason -- it wraps sb-posix directly.
      clHostKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-host-kit";
          source = cl-host-kit;
          lisp = ctx.pkgs.sbcl;
        };

      # `cl-prolog/weave` is one of four systems cl-prolog.asd defines, and its
      # `:depends-on` names both `cl-prolog` (resolved out of that same file, so
      # nothing to pass) and `cl-weave` (which is not, so it is passed). The
      # ASDF system name carries a slash; `pname` cannot, since it becomes a
      # store path component.
      clPrologWeaveSystem =
        ctx: lisp:
        siblingSystem ctx {
          pname = "cl-prolog-weave";
          source = cl-prolog;
          asdName = "cl-prolog.asd";
          lispSystem = "cl-prolog/weave";
          inherit lisp;
          lispDependencies = [ (clWeaveSystem ctx lisp) ];
        };

      # cl-process-kit and its two dependencies are SBCL-only, so they take no
      # `lisp` argument at all: cl-log-kit calls SB-THREAD unconditionally
      # (https://github.com/nerima-lisp/cl-log-kit/issues/1), which is the whole
      # reason cl-cli.asd splits the shell-verification half of the suite into
      # its own system. An `ecl` flavour of these would be an evaluation error
      # waiting for somebody to add it to the ECL check.
      # cl-log-kit v2.0.1's three `:depends-on` edges, all spelled out because
      # `siblingSystem` reads the graph from here and not from the .asd. The two
      # kit systems below are `:depends-on ()` leaves; cl-host-kit is the same
      # derivation cl-cli's own runtime dependency uses.
      clDateKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-date-kit";
          source = cl-date-kit;
          lisp = ctx.pkgs.sbcl;
        };

      clConcurrentKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-concurrent-kit";
          source = cl-concurrent-kit;
          lisp = ctx.pkgs.sbcl;
        };

      clLogKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-log-kit";
          source = cl-log-kit;
          lisp = ctx.pkgs.sbcl;
          lispDependencies = [
            (clDateKitSystem ctx)
            (clConcurrentKitSystem ctx)
            (clHostKitSystem ctx)
          ];
        };

      # cl-boundary-kit v1.0.0 (the version pinned here) still
      # `:depends-on (:asdf :cl-log-kit)`; v2.0.1 replaced that edge with
      # `:cl-host-kit` instead, which is why this pin stays at v1.0.0 rather
      # than the latest tag -- see the flake input's own comment. That edge is
      # easy to miss by reading a working checkout instead of the pinned tag,
      # and the previous run-tests.lisp arrangement hid it too, because
      # registering all three .asd files up front let ASDF resolve the graph
      # in whatever order it liked. Here the graph has to be declared, so a
      # wrong edge is a build failure.
      clBoundaryKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-boundary-kit";
          source = cl-boundary-kit;
          lisp = ctx.pkgs.sbcl;
          lispDependencies = [ (clLogKitSystem ctx) ];
        };

      # Dependency-free (`:depends-on ()`), so no `lispDependencies` of its
      # own. cl-process-kit v3.0.0 migrated its hand-rolled UTF-8/octet
      # handling onto this, making it a real transitive dependency of the
      # base "cl-process-kit" system.
      clCodecKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-codec-kit";
          source = cl-codec-kit;
          lisp = ctx.pkgs.sbcl;
        };

      # Only cl-process-kit is ever named in a `lispCheckDependencies` list:
      # `lispDerivation` walks the dependency graph transitively and resolves
      # the whole closure onto CL_SOURCE_REGISTRY, so cl-boundary-kit,
      # cl-log-kit and cl-codec-kit arrive because they are named HERE, once,
      # where the ASDF `:depends-on` that needs them lives.
      clProcessKitSystem =
        ctx:
        siblingSystem ctx {
          pname = "cl-process-kit";
          source = cl-process-kit;
          lisp = ctx.pkgs.sbcl;
          lispDependencies = [
            (clBoundaryKitSystem ctx)
            (clLogKitSystem ctx)
            (clCodecKitSystem ctx)
          ];
        };

      # The portable half of the suite's dependencies -- `cl-cli/test`'s
      # `:depends-on`, minus `cl-cli` itself. Every one of these loads on SBCL
      # and ECL alike, which is what makes the ECL check below possible.
      coreTestSystems = ctx: lisp: [
        (clWeaveSystem ctx lisp)
        (clPrologWeaveSystem ctx lisp)
        (clJsonKitSystem ctx lisp)
      ];

      # `checks.ecl` -- the portability gate. cl-cli promises to load on more
      # than SBCL, and nothing else in the suite would notice an SBCL-only form
      # creeping into src/.
      #
      # Built from `ctx.lispDerivationArgs`, the exact attrset the preset handed
      # `lispDerivation` for the default package, with only the implementation
      # and its matching dependency set replaced. Re-spelling pname/version/src/
      # lispSystem/meta here instead would be a second source of truth for the
      # package's identity inside the one file whose migration was about
      # removing exactly that.
      #
      # `nativeBuildInputs` rides along from `packageArgs` on purpose. ECL runs
      # only `cl-cli/test`, which shells out to nothing today -- but a core test
      # that grows a `bash` invocation tomorrow should fail here rather than
      # self-skip on the one implementation nobody watches.
      eclPackage =
        ctx:
        ctx.cl.lispDerivation (
          ctx.lispDerivationArgs
          // {
            lisp = ctx.pkgs.ecl;
            # `ctx.lispDerivationArgs.lispDependencies` is the SBCL-built
            # cl-host-kit closure (see `lispDependencies` on the
            # `mkPackageFlake` call below) -- wrong implementation for this
            # derivation and unneeded besides, since the ECL build reads
            # cl-cli.asd's `#+sbcl "cl-host-kit"` as absent. Overridden to
            # empty rather than left to leak through the `//` merge.
            lispDependencies = [ ];
            lispCheckDependencies = coreTestSystems ctx ctx.pkgs.ecl;
          }
        );

      # `nix run .#test`, wrapping the preset's own generated app rather than
      # replacing it: the wrapper adds nothing but PATH, so the registry, the
      # timeout and the runner stay the preset's single spelling of them.
      #
      # The PATH is the point. `mkTestApp` has no argument for runtime tools,
      # and without them the shell-verification cases self-skip -- so a bare
      # `nix run .#test` would quietly verify less than `nix flake check` does,
      # while reporting the same "all tests passed".
      # The `cl-cli/demo` system delivered as a binary -- published below as
      # `packages.default`/`apps.default` (so `nix build` yields
      # `./result/bin/cl-cli-demo`) and as `packages.cl-cli-demo`/
      # `apps.cl-cli-demo`. See `overrideOutputs` for why the wiring is done
      # there rather than through `mkPackageFlake`'s `executable` argument.
      #
      # `args` starts from `ctx.lispDerivationArgs`, the exact attrset the
      # preset handed `lispDerivation` for the library, rather than re-spelling
      # src/version/lisp/lispDependencies. cl-nix-forge names this as the
      # supported escape hatch for exactly this case (package-flake.nix's
      # `rejectOwnedExecutable` message), and the reason is that a dependency
      # added to the `mkPackageFlake` call above then reaches the binary by
      # construction -- a hand-written `args` would silently stop shipping
      # cl-host-kit the day somebody added a second runtime dependency.
      #
      # `programPath` is not optional here. It defaults to `lispSystem`, which
      # is right only when the system name, its `:build-pathname` and its
      # directory all coincide; `cl-cli/demo` sets `:pathname "demo"` and
      # `:build-pathname "cl-cli-demo"`, and ASDF's `program-op` resolves the
      # latter against the former, so the program is written to
      # `demo/cl-cli-demo` and nothing else finds it.
      demoExecutable =
        ctx:
        ctx.cl.mkExecutable {
          programPath = "demo/cl-cli-demo";
          args = ctx.lispDerivationArgs // {
            pname = "cl-cli-demo";
            lispSystem = "cl-cli/demo";
            # The one inherited attribute that is dropped rather than kept.
            # `packageArgs` puts the seven shells and mandoc here for the
            # shell-verification suite; `cl-cli/demo` shells out to nothing, so
            # inheriting them would make `nix build .#cl-cli-demo` pull
            # powershell into a build that never runs it.
            nativeBuildInputs = [ ];
            meta = ctx.lispDerivationArgs.meta // {
              description = "Runnable demonstration CLI built from cl-cli's own primitives.";
            };
          };
        };

      testApp =
        ctx:
        let
          generated = ctx.generated.apps.test;
          wrapper = ctx.pkgs.writeShellApplication {
            name = "cl-cli-test";
            runtimeInputs = verificationTools ctx.pkgs;
            text = ''
              exec ${generated.program} "$@"
            '';
          };
        in
        generated // { program = nixpkgs.lib.getExe wrapper; };
    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # this function is taken from contributes nothing but the function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-cli";

      # Single source of truth for the package version: the `:version` form in
      # cl-cli.asd, so the flake can never drift from the ASDF system
      # definition. All three systems in that file declare the same version;
      # `fromAsdSystem` accepts that unanimity and refuses to pick a winner if
      # they ever disagree -- which the hand-rolled `builtins.match` this
      # replaces did not, since it simply took the first matching line.
      asd = ./cl-cli.asd;

      # Spelled out rather than left to the preset's `self` default, which does
      # not evaluate: a flake's `self` is an attrset carrying an `outPath`, and
      # `lib.fileset` refuses string-like values. `./.` is the same directory as
      # a path literal. `self` is still what the preset hands the treefmt gate,
      # which wants the UNFILTERED tree.
      root = ./.;

      # `mkLispSource` is an allowlist -- `*.asd` and `*.lisp` under the root,
      # nothing else unless named here. README.md is named because cl-cli.asd
      # reads it at ASDF-LOAD time, for `:long-description`, so its absence is
      # not a missing docs file but a system that cannot be found at all.
      # Nothing else in src/, t/ or examples/ opens a file it does not create.
      sourceInclude = [ ./README.md ];

      meta = {
        description = "Composable Common Lisp CLI parsing and dispatch primitives.";
        homepage = "https://github.com/nerima-lisp/cl-cli";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      # SBCL is the reference implementation, so the default package and
      # `checks.default` are the ones that get the shell-verification half.
      # These are BUILT derivations, never CL_SOURCE_REGISTRY strings --
      # assembling that registry is `lispDerivation`'s job and it does it
      # transitively, which is why cl-process-kit alone stands in for itself
      # plus cl-boundary-kit plus cl-log-kit.
      lispCheckDependencies = ctx: coreTestSystems ctx ctx.pkgs.sbcl ++ [ (clProcessKitSystem ctx) ];

      # The real (non-test) dependency cl-cli.asd's `#+sbcl "cl-host-kit"`
      # names. SBCL-only; `eclPackage` above explicitly zeroes this back out
      # rather than inheriting it through `ctx.lispDerivationArgs`.
      lispDependencies = ctx: [ (clHostKitSystem ctx) ];

      # Puts the real shells and mandoc on PATH for `checks.default` -- and, via
      # `inputsFrom` on the check-enabled derivation the preset builds the dev
      # shell from, for `nix develop` too, so a shell-verification failure can
      # be reproduced by hand without listing these twice.
      packageArgs = ctx: {
        nativeBuildInputs = verificationTools ctx.pkgs;
      };

      # Rooted at the repository, not at ./docs, so the config path is the same
      # `docs/mkdocs.yml` a contributor types by hand. `mkDocsSite` builds with
      # `--strict`, so a broken link or a page missing from the nav fails the
      # build, and `checks.docs` runs it -- which is what keeps such a break
      # inside a pull request instead of surfacing as a failed post-merge Pages
      # deploy.
      docs = {
        root = ./.;
        fileset = nixpkgs.lib.fileset.unions [
          ./docs/mkdocs.yml
          ./docs/src
        ];
        mkdocsYmlName = "docs/mkdocs.yml";
      };

      # ONE treefmt evaluation drives `nix fmt` and the `checks.formatting`
      # gate, so the formatter and the CI gate can never disagree about what
      # "formatted" means. Scope stays the preset's Nix-only default: nixfmt
      # (RFC style) is a zero-footgun, low-diff formatter, whereas a YAML
      # formatter mangles the GitHub Actions `on:` key and reformatting Markdown
      # would churn the whole docs tree.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # The interactive-only extras, and only those. sbcl, the test
      # dependencies and the verification tools all arrive through `inputsFrom`
      # on the derivation the preset builds this shell from -- the CHECK-ENABLED
      # one -- so `sbcl --script run-tests.lisp` inside `nix develop` resolves
      # cl-weave and finds zsh on PATH without either being named again here.
      # ecl is not that derivation's implementation, so it does need naming.
      devShellPackages = ctx: [
        ctx.pkgs.ecl
        ctx.pkgs.rlwrap
        paredit-cli.packages.${ctx.system}.default
      ];

      # `apps.test`: see `testApp` -- the generated app is kept, wrapped only to
      # give the shell-verification cases the tools they self-skip without.
      #
      # `packages.default`/`apps.default`: the DELIVERED BINARY, so that a bare
      # `nix build` in this checkout produces `./result/bin/cl-cli-demo` and
      # `nix run .` runs it, the same way it does in every other repository in
      # the org that ships a command. `packages.cl-cli` -- which is what all
      # seven in-org consumers actually read on their `lispDependencies` edge,
      # and what `overlays.default`'s attribute is named after -- is untouched
      # and still the library.
      #
      # Done here rather than through `mkPackageFlake`'s own `executable`
      # argument, which would compute the delivery's `args` as
      # `lispDerivationArgs // { pname, lispSystem, meta }` and offers no way to
      # drop anything else. `packageArgs` above puts the seven shells and mandoc
      # in `nativeBuildInputs` for the shell-verification suite; through
      # `executable` they would follow into a binary that shells out to nothing,
      # so `nix build` would build powershell to deliver a demo that never runs
      # it. `demoExecutable` drops them explicitly, which is why it stays.
      overrideOutputs = ctx: {
        apps.test = testApp ctx;
        packages.default = demoExecutable ctx;
        apps.default = ctx.cl.mkApp { drv = demoExecutable ctx; };
      };

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      extraOutputs = ctx: {
        # The one binary this repository ships: `cl-cli/demo`, the executable
        # cl-cli dogfoods itself with (see that system in cl-cli.asd).
        #
        # The NAMED spelling of what `overrideOutputs` above also publishes as
        # `packages.default`/`apps.default`. Both names are kept rather than
        # collapsed into one: `nix build .#cl-cli-demo` is what this repository's
        # README and docs have advertised since the demo existed, and it says
        # which binary it builds, which a bare `nix build` cannot. Same
        # derivation either way, so the duplicate costs nothing.
        packages.cl-cli-demo = demoExecutable ctx;
        apps.cl-cli-demo = ctx.cl.mkApp { drv = demoExecutable ctx; };

        checks = {
          # The same run-tests.lisp entry point as `checks.default`, under ECL.
          # One runner serves both because its own guard is a capability check:
          # it loads the shell-verification half only where SB-THREAD exists and
          # cl-process-kit is on the registry, and says which half it ran.
          ecl = ctx.cl.mkScriptCheck {
            drv = eclPackage ctx;
            entryPoint = "run-tests.lisp";
            name = "cl-cli-ecl-test";
            timeoutSeconds = 600;
          };

          # Structural parse gate over every Lisp source in the filtered tree:
          # fails if any .lisp/.asd file is not a balanced S-expression
          # document. The suite would not catch it -- an unbalanced file makes
          # ASDF fail to load the system, which reads like any other build
          # error and points at the wrong cause.
          paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
            inherit (ctx) src;
            name = "cl-cli-paredit-lint";
          };

          # An sb-cover HTML coverage report for `src/`, as a buildable
          # artifact rather than a pass/fail gate -- `nix build
          # .#checks.<system>.coverage --no-link --print-out-paths` prints a
          # store path whose `cover-index.html` is the report to open.
          #
          # This exists because an interactive `sbcl --script` coverage run
          # against the nix-store sibling dependencies (cl-weave, cl-prolog,
          # ...) hangs indefinitely on this org's shared dev machines for
          # reasons never root-caused -- see the project memory this repo's
          # sessions keep under `reference_cl_cli_interactive_sbcl_hang`. The
          # identical dependency graph builds correctly and quickly inside the
          # Nix sandbox, which is what this check exploits: it never touches
          # an interactive SBCL session at all.
          #
          # `ctx.cl.mkCoverageReport` is cl-nix-forge's own battery for
          # exactly this (`lib/batteries/coverage.nix`) -- built from
          # `ctx.package`, the SAME doCheck-false derivation `checks.default`
          # is built from via `mkScriptCheck`, so this costs no build that
          # check does not already pay for. It handles the
          # `(declaim (optimize sb-cover:store-coverage-data))` /
          # `:force t` / `(declaim (optimize (sb-cover:store-coverage-data
          # 0)))` dance itself (instrumentation is a COMPILE-time property,
          # and `buildPhase` already compiled `cl-cli` once without it, so a
          # forced recompile under the declaim is the only way any line ends
          # up in the report) and fails the build outright if the report
          # comes back empty, so a broken instrumentation path cannot pass as
          # a silent no-op the way it did in the abandoned interactive
          # attempt.
          #
          # `systems = [ "cl-cli" ]` rather than the default (`ctx.package`'s
          # own `lispSystems`, which already resolves to just `[ "cl-cli" ]`
          # here) is spelled out anyway: it is the one knob that decides what
          # the report is ABOUT, and leaving it implicit would make a future
          # multi-system change to this file silently start instrumenting
          # `cl-cli/test` too.
          #
          # No coverage-percentage threshold, and cl-nix-forge deliberately
          # offers none (see coverage.nix's own comment) -- the project's
          # `/goal` tracks "no untested reachable branch inside a function
          # body", which sb-cover's raw expression percentage cannot express
          # (it under-attributes top-level `defvar`/`defstruct`/
          # `define-condition` forms and macro-expansion-time helpers by
          # design), so a numeric gate here would be gating on the wrong
          # thing.
          coverage = ctx.cl.mkCoverageReport {
            drv = ctx.package;
            systems = [ "cl-cli" ];
            name = "cl-cli-coverage";
            timeoutSeconds = 900;
          };
        };
      };
    };
}

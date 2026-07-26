{
  description = "Composable Common Lisp CLI parsing and dispatch primitives.";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Sibling packages are ALWAYS pinned to a release tag. A bare
    # `github:nerima-lisp/cl-weave` follows that repo's default branch, which
    # means an upstream push to main breaks this repo's CI without warning.
    #
    # `flake = false` on every one of them, per ADR-0079. Nothing below reads a
    # sibling's `packages`, `checks` or `lib`; each is used only as a source
    # tree, handed to run-tests.lisp through a CL_*_SOURCE_DIR variable so ASDF
    # can find the .asd. A `flake = true` input drags its ENTIRE input graph
    # into flake.lock even when no output is used, and six siblings each
    # carrying their own nixpkgs/treefmt-nix/cl-weave/paredit-cli/rust-overlay
    # is what put this lock at 82 nodes against an org range of 5-19.
    #
    # No `inputs.nixpkgs.follows` on them either: a non-flake input has no
    # inputs of its own, so the override has no target and Nix warns
    # `has an override for a non-existent input 'nixpkgs'` on every evaluation.
    #
    # Every one of these is a TEST dependency. DEPENDENCY_POLICY.md places
    # cl-cli at L1, and the `cl-cli` system itself depends on uiop alone; that
    # must stay true, so nothing here may migrate into the .asd :depends-on of
    # the main system.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.0";
      flake = false;
    };

    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v1.0.1";
      flake = false;
    };

    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v1.0.1";
      flake = false;
    };

    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v0.6.0";
      flake = false;
    };

    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v1.0.0";
      flake = false;
    };

    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.0.0";
      flake = false;
    };

    # treefmt-nix stays a real flake: `treefmt-nix.lib.evalModule` below reads
    # one of its outputs, so ADR-0079 keeps it at `flake = true` -- and because
    # it is a flake, the `follows` does have a target and does its job.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
      cl-prolog,
      cl-process-kit,
      cl-boundary-kit,
      cl-log-kit,
      cl-json-kit,
      treefmt-nix,
      ...
    }:
    let
      # Only the platforms CI actually verifies are declared. ci.yml runs the
      # `check` job on ubuntu-latest and macos-latest, and `nix flake check`
      # evaluates the outputs of the system it runs on, so each of these two is
      # covered by a real build. aarch64-linux and x86_64-darwin were declared
      # before and never verified anywhere; advertising an unbuilt platform is
      # what PACKAGE_STANDARD.md forbids.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Single source of truth for the package version: the `:version` form in
      # cl-cli.asd. A release only ever edits the .asd file. Nix regexes are
      # whole-string anchored and `.` never spans newlines, so the version is
      # extracted line-by-line rather than with one multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-cli.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # The suites in t/cases-shell-verification.lisp pipe cl-cli's own
      # generated output through the real tools that will consume it. They
      # self-skip when a tool is missing, so the tools have to be on PATH
      # inside the sandbox or the checks silently verify nothing.
      verificationTools = pkgs: [
        pkgs.bash
        pkgs.zsh
        pkgs.fish
        pkgs.mandoc
        pkgs.nushell
        pkgs.elvish
        pkgs.powershell
      ];

      # Sources for the portable half of the suite. Every one of these loads
      # on SBCL and ECL alike.
      coreTestSources = {
        CL_WEAVE_SOURCE_DIR = cl-weave.outPath;
        CL_PROLOG_SOURCE_DIR = cl-prolog.outPath;
        CL_JSON_KIT_SOURCE_DIR = cl-json-kit.outPath;
      };

      # Sources for the shell-verification half. cl-process-kit pulls in
      # cl-log-kit, which hard-codes sb-thread and therefore only compiles on
      # SBCL (https://github.com/nerima-lisp/cl-log-kit/issues/1), so only the
      # SBCL check gets them. run-tests.lisp refuses to load that half
      # anywhere SB-THREAD is missing regardless; leaving these out keeps the
      # check's declared inputs honest about what it actually exercises.
      shellVerificationSources = {
        CL_PROCESS_KIT_SOURCE_DIR = cl-process-kit.outPath;
        CL_BOUNDARY_KIT_SOURCE_DIR = cl-boundary-kit.outPath;
        CL_LOG_KIT_SOURCE_DIR = cl-log-kit.outPath;
      };

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt (RFC-style) is a zero-footgun, low-diff
      # formatter, whereas YAML formatters mangle the GitHub Actions `on:`
      # key and Markdown reformatting would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );

      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-cli-docs";
          inherit version;
          # Rooted at the repository, not at docs/, because
          # docs/src/changelog.md snippet-includes the top-level CHANGELOG.md
          # and pymdownx.snippets resolves base_path against the working
          # directory mkdocs was started from.
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
              ./CHANGELOG.md
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file docs/mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-cli";
            homepage = "https://github.com/nerima-lisp/cl-cli";
            license = pkgs.lib.licenses.mit;
          };
        };

      # `extraSources` carries the implementation-specific dependency set, so
      # the only difference between the two checks below is which half of the
      # suite their environment can reach.
      mkLispCheck =
        pkgs:
        {
          name,
          package,
          command,
          extraSources ? { },
        }:
        pkgs.runCommand "cl-cli-tests-${name}"
          (
            {
              nativeBuildInputs = [ package ] ++ verificationTools pkgs;
              src = self;
            }
            // coreTestSources
            // extraSources
          )
          ''
            cp -R "$src" source
            chmod -R u+w source
            cd source
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME"
            ${command}
            touch "$out"
          '';

      sbclCommand = ''
        sbcl --non-interactive --load run-tests.lisp \
          --eval '(cl-cli/test:run-tests)' --quit
      '';

      # No ASDF preload here any more. It used to be required because
      # cl-log-kit demands ASDF >= 3.3.1 while nixpkgs' ECL 26.5.5 bundles
      # 3.1.8.11 -- but cl-log-kit is no longer on ECL's path at all now
      # that the shell-verification half is a separate system, and the
      # remaining test dependencies load fine against the bundled ASDF.
      # This keeps the documented `ecl --norc --load run-tests.lisp`
      # invocation and the one CI runs identical.
      eclCommand = ''
        ecl --norc --load run-tests.lisp \
          --eval '(cl-cli/test:run-tests)'
      '';
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          cl-cli = pkgs.sbcl.buildASDFSystem {
            pname = "cl-cli";
            inherit version;
            src = self;
            systems = [ "cl-cli" ];
          };
          default = cl-cli;
          docs = mkDocs pkgs;
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lispCheck = mkLispCheck pkgs;
        in
        {
          # SBCL is the reference implementation, so it is the default check
          # and the only one that gets the shell-verification half.
          default = lispCheck {
            name = "sbcl";
            package = pkgs.sbcl;
            extraSources = shellVerificationSources;
            command = sbclCommand;
          };

          # Portability gate. cl-cli promises to load on more than SBCL, and
          # nothing else in the suite would notice an SBCL-only form creeping
          # into src/.
          ecl = lispCheck {
            name = "ecl";
            package = pkgs.ecl;
            command = eclCommand;
          };

          # Fails `nix flake check` when any tracked Nix file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # The docs package builds with `mkdocs --strict`, so a broken link or
          # a page missing from the nav fails the build. Without this the docs
          # are only ever built by the publish workflow, which runs after a
          # merge to main, meaning such a break surfaces as a failed deploy
          # rather than as a failed pull request.
          docs = mkDocs pkgs;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-cli-test";
            runtimeInputs = [ pkgs.sbcl ] ++ verificationTools pkgs;
            text =
              let
                exports = nixpkgs.lib.concatStringsSep "\n" (
                  nixpkgs.lib.mapAttrsToList (n: v: "export ${n}=${nixpkgs.lib.escapeShellArg v}") (
                    coreTestSources // shellVerificationSources
                  )
                );
              in
              ''
                ${exports}
                cd "''${1:-.}"
                ${sbclCommand}
              '';
          };
          # `nix flake check` warns on an app without meta, so it is declared
          # once and shared by both aliases below.
          testApp = {
            type = "app";
            program = "${test}/bin/cl-cli-test";
            meta = {
              description = "Run the cl-cli test suite under SBCL";
              license = pkgs.lib.licenses.mit;
            };
          };
        in
        {
          default = testApp;
          test = testApp;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell (
            {
              packages = [
                pkgs.sbcl
                pkgs.ecl
                pkgs.rlwrap
              ]
              ++ verificationTools pkgs;
            }
            // coreTestSources
            // shellVerificationSources
          );
        }
      );
    };
}

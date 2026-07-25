{
  description = "Dependency-light Common Lisp CLI toolkit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    cl-weave = {
      url = "github:nerima-lisp/cl-weave";
      flake = false;
    };
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit";
      flake = false;
    };
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit";
      flake = false;
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, cl-weave, cl-prolog, cl-process-kit, cl-boundary-kit, cl-log-kit, cl-json-kit }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      clWeaveSourceDir = cl-weave.outPath;
      clPrologSourceDir = cl-prolog.outPath;
      clProcessKitSourceDir = cl-process-kit.outPath;
      clBoundaryKitSourceDir = cl-boundary-kit.outPath;
      clLogKitSourceDir = cl-log-kit.outPath;
      clJsonKitSourceDir = cl-json-kit.outPath;

      # Single source of truth for the docs package version: the `:version`
      # form in cl-cli.asd. Nix regexes are whole-string anchored and `.`
      # never spans newlines, so the version is extracted line-by-line rather
      # than with one multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-cli.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-cli-docs";
          inherit version;
          src = pkgs.lib.fileset.toSource {
            root = ./docs;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-cli";
            homepage = "https://github.com/nerima-lisp/cl-cli";
            license = pkgs.lib.licenses.mit;
          };
        };
      # The suites in tests/cases-shell-verification.lisp pipe cl-cli's own
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
        CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
        CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
        CL_JSON_KIT_SOURCE_DIR = clJsonKitSourceDir;
      };

      # Sources for the shell-verification half. cl-process-kit pulls in
      # cl-log-kit, which hard-codes sb-thread and therefore only compiles on
      # SBCL (https://github.com/nerima-lisp/cl-log-kit/issues/1), so only the
      # SBCL check gets them. tests/run-tests.lisp refuses to load that half
      # anywhere SB-THREAD is missing regardless; leaving these out keeps the
      # check's declared inputs honest about what it actually exercises.
      shellVerificationSources = {
        CL_PROCESS_KIT_SOURCE_DIR = clProcessKitSourceDir;
        CL_BOUNDARY_KIT_SOURCE_DIR = clBoundaryKitSourceDir;
        CL_LOG_KIT_SOURCE_DIR = clLogKitSourceDir;
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          docs = mkDocs pkgs;
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell ({
            packages = [
              pkgs.sbcl
              pkgs.ecl
              pkgs.rlwrap
            ] ++ verificationTools pkgs;
          } // coreTestSources // shellVerificationSources);
        });

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # `extraArgs` carries the implementation-specific dependency set, so
          # the only difference between the two checks below is which half of
          # the suite their environment can reach.
          makeLispCheck = { name, package, command, extraSources ? { } }:
            pkgs.runCommand "cl-cli-tests-${name}"
              ({
                nativeBuildInputs = [ package ] ++ verificationTools pkgs;
                src = self;
              } // coreTestSources // extraSources)
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
          sbcl-check = makeLispCheck {
            name = "sbcl";
            package = pkgs.sbcl;
            extraSources = shellVerificationSources;
            command = ''
              sbcl --non-interactive --load tests/run-tests.lisp \
                --eval '(cl-cli/tests:run-tests)' --quit
            '';
          };
          # nixpkgs' ECL bundles an ASDF older than the 3.3.1 the test systems
          # need (26.5.5 ships 3.1.8.11). ASDF upgrades itself in place, so
          # pkgs.asdf's single-file bundle is loaded first.
          ecl-check = makeLispCheck {
            name = "ecl";
            package = pkgs.ecl;
            command = ''
              ecl --norc \
                --load ${pkgs.asdf}/lib/common-lisp/asdf/build/asdf.lisp \
                --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
            '';
          };
        in
        {
          sbcl = sbcl-check;
          ecl = ecl-check;
          docs = mkDocs pkgs;
        });
    };
}

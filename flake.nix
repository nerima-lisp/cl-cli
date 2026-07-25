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
  };

  outputs = { self, nixpkgs, cl-weave, cl-prolog, cl-process-kit, cl-boundary-kit, cl-log-kit }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      clWeaveSourceDir = cl-weave.outPath;
      clPrologSourceDir = cl-prolog.outPath;
      clProcessKitSourceDir = cl-process-kit.outPath;
      clBoundaryKitSourceDir = cl-boundary-kit.outPath;
      clLogKitSourceDir = cl-log-kit.outPath;

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
          default = pkgs.mkShell {
            packages = [
              pkgs.sbcl
              pkgs.rlwrap
            ];
            CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
            CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
            CL_PROCESS_KIT_SOURCE_DIR = clProcessKitSourceDir;
            CL_BOUNDARY_KIT_SOURCE_DIR = clBoundaryKitSourceDir;
            CL_LOG_KIT_SOURCE_DIR = clLogKitSourceDir;
          };
        });

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          makeLispCheck = implementation: package:
            pkgs.runCommand "cl-cli-tests-${implementation}"
              {
                nativeBuildInputs = [ package ];
                src = self;
                CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
                CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
                CL_PROCESS_KIT_SOURCE_DIR = clProcessKitSourceDir;
                CL_BOUNDARY_KIT_SOURCE_DIR = clBoundaryKitSourceDir;
                CL_LOG_KIT_SOURCE_DIR = clLogKitSourceDir;
              }
              ''
                cp -R "$src" source
                chmod -R u+w source
                cd source
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$TMPDIR/cache"
                mkdir -p "$HOME" "$XDG_CACHE_HOME"
                ${implementation} --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
                touch "$out"
              '';
          sbcl-check = pkgs.runCommand "cl-cli-tests-sbcl"
            {
              nativeBuildInputs = [ pkgs.sbcl ];
              src = self;
              CL_WEAVE_SOURCE_DIR = clWeaveSourceDir;
              CL_PROLOG_SOURCE_DIR = clPrologSourceDir;
              CL_PROCESS_KIT_SOURCE_DIR = clProcessKitSourceDir;
              CL_BOUNDARY_KIT_SOURCE_DIR = clBoundaryKitSourceDir;
              CL_LOG_KIT_SOURCE_DIR = clLogKitSourceDir;
            }
            ''
              cp -R "$src" source
              chmod -R u+w source
              cd source
              export HOME="$TMPDIR/home"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              mkdir -p "$HOME" "$XDG_CACHE_HOME"
              sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
              touch "$out"
            '';
          ecl-check = makeLispCheck "ecl" pkgs.ecl;
        in
        {
          sbcl = sbcl-check;
          ecl = ecl-check;
          default = pkgs.runCommand "cl-cli-checks" {} ''
            mkdir -p "$out"
            ln -s ${sbcl-check} "$out/sbcl"
            ln -s ${ecl-check} "$out/ecl"
          '';
        });
    };
}

{ type ? "develop" }:
let
  nixpkgs =
    let cfg = builtins.fromJSON (builtins.readFile ./nixpkgs.json);
    in fetchTarball {
      url = "https://github.com/${cfg.owner}/${cfg.repo}/tarball/${cfg.rev}";
      sha256 = cfg.sha256;
    };
  pkgs = import nixpkgs {
    config = { allowUnfree = true; };
    overlays = [];
  };
  inherit (pkgs) lib;

  dependencies = let mapping = {
    develop = developDeps ++ testDeps ++ buildDeps ++ runDeps;
    test = testDeps ++ buildDeps ++ runDeps;
    build = buildDeps ++ runDeps;
    run = runDeps;
  }; in mapping.${type} or (throw
    "${type} is not a valid shell type. Valid ones are ${toString (lib.attrNames mapping)}");

  stdenv = if type == "develop" then pkgs.stdenv else pkgs.stdenvNoCC;

  developDeps = with pkgs; [
    heroku
    vim
    micro
    tmux
    curl
  ]

  # The watchdog Python lib has a few extra requirements on Darwin (MacOS)
  # Taken from https://github.com/NixOS/nixpkgs/blob/d72887e0d28a98cc6435bde1962e2b414224e717/pkgs/development/python-modules/watchdog/default.nix#L20
  ++ lib.optionals pkgs.stdenv.isDarwin [
    pkgs.darwin.apple_sdk.frameworks.CoreServices
  ];

  # These are needed to run tests in CI/CD
  testDeps = with pkgs; [
    gnumake
    nodejs
    b2sum
    libffi
    libxslt
    netcat
    openssl
    which
    zlib
    jq
  ]

  # Currently, both firefox and firefox-bin are broken on Darwin (MacOS)
  # so if you are on a MacBook, you have to manually install firefox.
  # If https://github.com/NixOS/nixpkgs/issues/53979 gets fixed,
  # we can remove this if.
  ++ lib.optionals (!pkgs.stdenv.isDarwin) [
    pkgs.firefox
  ];

  # These are needed to build the production artifacts
  buildDeps = with pkgs; [
    gitMinimal
  ];

  # Only these dependencies are needed to run in production
  runDeps = with pkgs; [
    python38
    poetry
    postgresql_12    # For interacting with the database
  ];
in

stdenv.mkDerivation {
  name = "dev-shell";
  buildInputs = dependencies;

  # Needed to be able to install Python packages from GitHub
  GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # Such that nixpkgs doesn't need to be downloaded again when running we make
  # it a dependency of the derivation. Also allows using `nix-shell -p` with the
  # correct nixpkgs version
  NIX_PATH = "nixpkgs=${nixpkgs}";

  # By default, all files from the Nix store (which have a timestamp of the
  # UNIX epoch of January 1, 1970) are included in the .ZIP, but .ZIP archives
  # follow the DOS convention of counting timestamps from 1980. The command
  # `bdist_wheel` reads the SOURCE_DATE_EPOCH environment variable, which
  # nix-shell sets to 1. Giving it a value corresponding to 1980 enables
  # building wheels.
  SOURCE_DATE_EPOCH = 315532800;
}

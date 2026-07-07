{
  config,
  lib,
  ...
}:
let
  cfg = config.boot.loader.external;
  inherit (import ../providers/lib.nix { inherit lib; }) mkBackend;
in
{
  imports = [ (mkBackend "bootloader" "external") ];

  options.boot.loader.external = {
    enable = lib.mkEnableOption "an externally-provided bootloader install hook";

    installHook = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        A program that installs the bootloader. Called with one argument:
        the path to the system toplevel.

        This is the same contract as {option}`providers.bootloader.installHook`.
        Setting this option wires the hook into the `external` `providers.bootloader`
        backend automatically.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.installHook != null;
        message = "boot.loader.external.enable = true but installHook is not set.";
      }
    ];

    providers.bootloader.backend = "external";
    providers.bootloader.installHook = cfg.installHook;
  };
}

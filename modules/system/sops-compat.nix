# Compatibility shims so sops-nix's nixosModules.sops works with finix
#
# sops-nix's modules/sops/secrets-for-users/default.nix unconditionally assigns to `systemd.services.*` (behind a mkIf, but the option reference itself is evaluated before the condition)

{ lib, ... }:
{
  options.systemd = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    description = "Stub systemd option for sops-nix compatibility. Values are ignored on finix.";
  };

  # sops secrets-for-users also checks `options.services ? userborn`
  options.services.userborn.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Stub for sops-nix compatibility.";
  };
}

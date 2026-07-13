{ lib, ... }:
{
  # Declares that this module implements `providers.<provider>` as `name` by extending the `backend` enum
  #
  # Usage:
  #   imports = [ (mkBackend "bootloader" "external") ];
  #   config = lib.mkIf cfg.enable {
  #     providers.bootloader.backend = "external";
  #     ...
  #   };
  mkBackend = provider: name: {
    options.providers.${provider}.backend = lib.mkOption {
      type = lib.types.enum [ name ];
    };
  };
}

# Compatibility shims so home-manager's nixosModules.home-manager works with finix

{
  config,
  pkgs,
  lib,
  ...
}:
{
  options.system.stateVersion = lib.mkOption {
    type = lib.types.str;
    description = "stateVersion for home-manager compatibility.";
  };

  options.system.activationScripts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.coercedTo lib.types.str lib.noDepEntry (
        lib.types.submodule {
          options = {
            deps = lib.mkOption {
              type = with lib.types; listOf str;
              default = [ ];
            };
            text = lib.mkOption { type = lib.types.lines; };
          };
        }
      )
    );
    default = { };
    description = "NixOS-compat activation scripts; forwarded to system.activation.scripts.";
  };

  options.system.userActivationScripts = lib.mkOption {
    type = lib.types.attrsOf lib.types.lines;
    default = { };
    description = "Per-user activation scripts; run as each home-manager user during activation.";
  };

  config = {
    system.activation.scripts =
      (lib.mapAttrs (_: v: {
        inherit (v) deps text;
      }) config.system.activationScripts)
      // lib.optionalAttrs (config.system.userActivationScripts != { }) {
        userActivation = {
          deps = [ "users" ];
          text =
            let
              script = pkgs.writeShellScript "user-activation" ''
                set -euo pipefail
                ${lib.concatStringsSep "\n" (lib.attrValues config.system.userActivationScripts)}
              '';
            in
            ''
              for user in ${
                lib.concatStringsSep " " (
                  lib.mapAttrsToList (n: _: n) (
                    lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users
                  )
                )
              }; do
                su - "$user" -c "${script}" || true
              done
            '';
        };
      };

  # finix's openssh module already defines the full option set including `enable`, but it lives under a different module path and the attribute may not be visible when sops-nix evaluates
    sops.age.sshKeyPaths = lib.mkDefault [ ];
    sops.gnupg.sshKeyPaths = lib.mkDefault [ ];
  };
}
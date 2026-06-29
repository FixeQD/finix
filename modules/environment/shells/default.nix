{
  config,
  pkgs,
  lib,
  ...
}:
let
  utils = import (pkgs.path + "/nixos/lib/utils.nix") { inherit config pkgs lib; };

  sessionVarsScript = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value:
      let
        v = if lib.isList value then lib.concatStringsSep ":" value else value;
      in
      "export ${name}=${lib.escapeShellArg v}"
    ) config.environment.sessionVariables
  );
in
{
  options.environment.shells = lib.mkOption {
    type = with lib.types; listOf (either shellPackage path);
    default = [ ];
  };

  options.environment.sessionVariables = lib.mkOption {
    type = with lib.types; attrsOf (either str (listOf str));
    default = { };
    description = ''
      Environment variables to set for all login shells via /etc/profile.d/.
      Values can be strings or lists of strings (joined with ':').
    '';
    example = {
      EDITOR = "nvim";
      XDG_DATA_DIRS = [ "/usr/share" "/usr/local/share" ];
    };
  };

  config = {
    environment.etc.shells.text = ''
      ${lib.concatStringsSep "\n" (map utils.toShellPath config.environment.shells)}
      /bin/sh
    '';

    environment.etc.profile.text = ''
      # /etc/profile: system-wide initialisation for POSIX login shells

      # Source the drop-in scripts.
      if [ -d /etc/profile.d ]; then
        for i in /etc/profile.d/*.sh; do
          [ -r "$i" ] && . "$i"
        done
        unset i
      fi
    '';

    environment.etc."profile.d/session-vars.sh" = lib.mkIf (config.environment.sessionVariables != { }) {
      text = sessionVarsScript;
    };
  };
}

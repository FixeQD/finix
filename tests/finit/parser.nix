{
  name = "finit.parser";

  nodes.machine =
    { pkgs, ... }:
    {
      services.getty.enable = true;
      services.mdevd.enable = true;

      users.users.parser = {
        isSystemUser = true;
        uid = 1984;
        group = "parser";
      };
      users.groups.parser.gid = 1984;

      finit.tmpfiles.rules = [
        "d /run/finit-parser 0755 root root -"
      ];

      finit.services.parser-quoted = {
        runlevel = "2";
        description = "Parser quote: \" and slash: \\";
        command = pkgs.writeShellScript "finit-parser-quoted" ''
          ${pkgs.coreutils}/bin/printf '%s\n' quoted > /run/finit-parser/quoted
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };

      finit.services.parser-no-log = {
        runlevel = "2";
        log = false;
        command = pkgs.writeShellScript "finit-parser-no-log" ''
          ${pkgs.coreutils}/bin/printf '%s\n' no-log > /run/finit-parser/no-log
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };

      finit.services.parser-log = {
        runlevel = "2";
        log = true;
        command = pkgs.writeShellScript "finit-parser-log" ''
          ${pkgs.coreutils}/bin/printf '%s\n' log > /run/finit-parser/log
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };

      finit.tasks.parser-condition-source = {
        runlevel = "2";
        command = pkgs.writeShellScript "finit-parser-condition-source" ''
          ${pkgs.coreutils}/bin/printf '%s\n' source > /run/finit-parser/condition-source
        '';
      };

      finit.tasks.parser-never-bootstrap = {
        runlevel = "S2";
        conditions = [ "usr/parser-never-bootstrap" ];
        required = false;
        command = pkgs.writeShellScript "finit-parser-never-bootstrap" ''
          ${pkgs.coreutils}/bin/printf '%s\n' unexpected > /run/finit-parser/never-bootstrap
        '';
      };

      finit.services.parser-condition-gated = {
        runlevel = "2";
        conditions = [
          "task/parser-condition-source/success"
          "usr/parser-condition-second"
        ];
        command = pkgs.writeShellScript "finit-parser-condition-gated" ''
          ${pkgs.coreutils}/bin/printf '%s\n' gated > /run/finit-parser/condition-gated
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };

      finit.services.parser-cgroup = {
        runlevel = "2";
        cgroup.init = { };
        command = pkgs.writeShellScript "finit-parser-cgroup" ''
          ${pkgs.coreutils}/bin/printf '%s\n' cgroup > /run/finit-parser/cgroup
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };

      finit.services.parser-directories = {
        runlevel = "2";
        user = "parser";
        group = "parser";
        runtime-dir = "finit-parser-runtime";
        state-dir = "finit-parser-state";
        cache-dir = "finit-parser-cache";
        logs-dir = "finit-parser-logs";
        runtime-dir-mode = "0700";
        state-dir-mode = "0700";
        cache-dir-mode = "0700";
        logs-dir-mode = "0700";
        command = pkgs.writeShellScript "finit-parser-directories" ''
          set -eu
          printf '%s\n' \
            "RUNTIME_DIRECTORY=$RUNTIME_DIRECTORY" \
            "STATE_DIRECTORY=$STATE_DIRECTORY" \
            "CACHE_DIRECTORY=$CACHE_DIRECTORY" \
            "LOGS_DIRECTORY=$LOGS_DIRECTORY" \
            > "$RUNTIME_DIRECTORY/environment.tmp"
          if [ ! -e "$STATE_DIRECTORY/state-marker" ]; then
            printf '%s\n' state > "$STATE_DIRECTORY/state-marker"
          fi
          if [ ! -e "$CACHE_DIRECTORY/cache-marker" ]; then
            printf '%s\n' cache > "$CACHE_DIRECTORY/cache-marker"
          fi
          if [ ! -e "$LOGS_DIRECTORY/logs-marker" ]; then
            printf '%s\n' logs > "$LOGS_DIRECTORY/logs-marker"
          fi
          ${pkgs.coreutils}/bin/mv "$RUNTIME_DIRECTORY/environment.tmp" "$RUNTIME_DIRECTORY/environment"
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };
    };

  testScript = ''
    import json
    from datetime import timedelta

    TIMEOUT = timedelta(seconds=30)

    def json_status(name):
        return json.loads(machine.succeed(f"initctl -j status {name}"))

    def wait_until_condition(condition):
        machine.wait_until_succeeds(
            f"initctl cond get {condition}", timeout=TIMEOUT
        )

    def wait_until_file(path):
        machine.wait_until_succeeds(f"test -f {path}", timeout=TIMEOUT)

    def wait_until_running(name):
        wait_until_condition(f"service/{name}/running")
        status = json_status(name)
        assert status["status"] == "running", (
            f"expected {name} to be running, got {status['status']}"
        )
        return status

    def condition_dump():
        return json.loads(machine.succeed("initctl -j cond dump"))

    def condition_status(name):
        condition = next(
            (item for item in condition_dump() if item["condition"] == name), None
        )
        assert condition is not None, f"condition {name} not found"
        return condition["status"]

    machine.start()

    machine.wait_for_console_text("finix - stage 1")
    machine.wait_for_console_text("finix - stage 2")
    machine.wait_for_console_text("entering runlevel S")
    machine.wait_for_console_text("entering runlevel 2")

    with subtest("required=false bootstrap task does not block boot"):
        machine.succeed("grep -Fq 'required = false' /etc/finit.d/parser-never-bootstrap.conf")
        machine.fail("initctl cond get usr/parser-never-bootstrap")
        machine.succeed("test ! -e /run/finit-parser/never-bootstrap")
        bootstrap_status = json_status("parser-never-bootstrap")
        assert bootstrap_status["status"] == "waiting", bootstrap_status
        assert bootstrap_status["pid"] == 0, bootstrap_status

    with subtest("quoted description and simple command are parsed"):
        wait_until_file("/run/finit-parser/quoted")
        assert machine.succeed("cat /run/finit-parser/quoted").strip() == "quoted"
        quoted_status = wait_until_running("parser-quoted")
        original_description = 'Parser quote: " and slash: \\'
        assert quoted_status["description"] == original_description, (
            f"description round-trip mismatch: {quoted_status['description']!r}"
        )

    with subtest("log false omits stanza and service runs"):
        machine.succeed("test -f /etc/finit.d/parser-no-log.conf")
        machine.fail(
            "grep -Eq '^[[:space:]]*log[[:space:]]*\\{'"
            " /etc/finit.d/parser-no-log.conf"
        )
        wait_until_file("/run/finit-parser/no-log")
        wait_until_running("parser-no-log")

    with subtest("log true renders empty stanza and service runs"):
        machine.succeed("test -f /etc/finit.d/parser-log.conf")
        machine.succeed(
            "grep -Eq '^[[:space:]]*log[[:space:]]*\\{[[:space:]]*\\}[[:space:]]*$'"
            " /etc/finit.d/parser-log.conf"
        )
        wait_until_file("/run/finit-parser/log")
        wait_until_running("parser-log")

    with subtest("condition list is ANDed and second source is explicit"):
        wait_until_file("/run/finit-parser/condition-source")
        wait_until_condition("task/parser-condition-source/success")
        assert condition_status("task/parser-condition-source/success") == "on"

        machine.succeed("test ! -e /run/finit-parser/condition-gated")
        gated_before = json_status("parser-condition-gated")
        assert gated_before["status"] == "waiting", gated_before
        assert gated_before["pid"] == 0, gated_before
        assert gated_before["condition"] == [
            "+task/parser-condition-source/success",
            "-usr/parser-condition-second",
        ], gated_before
        machine.fail("initctl cond get usr/parser-condition-second")

        machine.succeed("initctl cond set parser-condition-second")
        wait_until_file("/run/finit-parser/condition-gated")
        wait_until_running("parser-condition-gated")
        assert condition_status("usr/parser-condition-second") == "on"
        machine.succeed(
            "grep -Fq 'task/parser-condition-source/success'"
            " /etc/finit.d/parser-condition-gated.conf"
        )
        machine.succeed(
            "grep -Fq 'usr/parser-condition-second'"
            " /etc/finit.d/parser-condition-gated.conf"
        )

    with subtest("cgroup block parses and service joins actual cgroup"):
        machine.succeed("test -f /etc/finit.d/parser-cgroup.conf")
        machine.succeed(
            "grep -Eq '^[[:space:]]*cgroup[[:space:]]+init[[:space:]]*\\{[[:space:]]*\\}'"
            " /etc/finit.d/parser-cgroup.conf"
        )
        wait_until_file("/run/finit-parser/cgroup")
        cgroup_status = wait_until_running("parser-cgroup")

        cgroup_v2, _ = machine.execute("grep -Eq '(^|[[:space:]])cgroup2$' /proc/filesystems")
        if cgroup_v2 == 0:
            machine.succeed("test -f /sys/fs/cgroup/cgroup.controllers")
            pid = cgroup_status["pid"]
            assert pid > 1, cgroup_status
            machine.wait_until_succeeds(
                f"grep -Fxq '0::/init/parser-cgroup' /proc/{pid}/cgroup",
                timeout=TIMEOUT,
            )
        else:
            print("Guest kernel has no cgroup2 support; checked stanza and running service only")

    with subtest("nonroot service directories expose env and persist correctly"):
        runtime = "/run/finit-parser-runtime"
        state = "/var/lib/finit-parser-state"
        cache = "/var/cache/finit-parser-cache"
        logs = "/var/log/finit-parser-logs"

        wait_until_file(f"{runtime}/environment")
        wait_until_file(f"{state}/state-marker")
        wait_until_file(f"{cache}/cache-marker")
        wait_until_file(f"{logs}/logs-marker")
        directory_status = wait_until_running("parser-directories")
        process_status = machine.succeed(f"cat /proc/{directory_status['pid']}/status")
        for field in ("Uid:", "Gid:"):
            values = next(line.split()[1:] for line in process_status.splitlines() if line.startswith(field))
            assert values == ["1984"] * 4, f"unexpected process {field} {values}"

        for path in (runtime, state, cache, logs):
            mode = machine.succeed(f"stat -c %a {path}").strip()
            assert mode == "700", f"expected mode 700 for {path}, got {mode}"
            owner = machine.succeed(f"stat -c %U:%G {path}").strip()
            assert owner == "parser:parser", (
                f"expected parser:parser for {path}, got {owner}"
            )

        expected_environment = [
            "RUNTIME_DIRECTORY=/run/finit-parser-runtime",
            "STATE_DIRECTORY=/var/lib/finit-parser-state",
            "CACHE_DIRECTORY=/var/cache/finit-parser-cache",
            "LOGS_DIRECTORY=/var/log/finit-parser-logs",
        ]
        environment = machine.succeed(f"cat {runtime}/environment").splitlines()
        assert environment == expected_environment, (
            f"service directory environment mismatch: {environment}"
        )

        machine.succeed("initctl stop parser-directories")
        wait_until_condition("service/parser-directories/stopped")
        machine.wait_until_succeeds(f"test ! -e {runtime}", timeout=TIMEOUT)
        machine.succeed("test ! -e /run/finit-parser-runtime/environment")

        wait_until_file(f"{state}/state-marker")
        wait_until_file(f"{cache}/cache-marker")
        wait_until_file(f"{logs}/logs-marker")
        assert machine.succeed(f"cat {state}/state-marker").strip() == "state"
        assert machine.succeed(f"cat {cache}/cache-marker").strip() == "cache"
        assert machine.succeed(f"cat {logs}/logs-marker").strip() == "logs"

        for path, marker in ((state, "state"), (cache, "cache"), (logs, "logs")):
            machine.succeed(f"printf '%s\\n' {marker}-preserved > {path}/{marker}-marker")

        machine.succeed("initctl start parser-directories")
        wait_until_file(f"{runtime}/environment")
        wait_until_running("parser-directories")
        wait_until_file(f"{state}/state-marker")
        wait_until_file(f"{cache}/cache-marker")
        wait_until_file(f"{logs}/logs-marker")
        assert machine.succeed(f"cat {state}/state-marker").strip() == "state-preserved"
        assert machine.succeed(f"cat {cache}/cache-marker").strip() == "cache-preserved"
        assert machine.succeed(f"cat {logs}/logs-marker").strip() == "logs-preserved"
        assert machine.succeed(f"cat {runtime}/environment").splitlines() == expected_environment
        assert machine.succeed(f"stat -c %a:%U:%G {runtime}").strip() == "700:parser:parser"

    with subtest("shutdown"):
        machine.shutdown()
  '';
}

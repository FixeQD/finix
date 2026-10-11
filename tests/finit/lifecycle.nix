{
  name = "finit.lifecycle";

  nodes.machine =
    { pkgs, ... }:
    {
      services.getty.enable = true;
      services.mdevd.enable = true;

      finit.tmpfiles.rules = [
        "d /run/finit-lifecycle 0755 root root -"
      ];

      finit.services.lifecycle-never = {
        runlevel = "2";
        restart = "never";
        command = pkgs.writeShellScript "finit-lifecycle-never" ''
          count=0
          if [ -f /run/finit-lifecycle/never.count ]; then
            count=$(${pkgs.coreutils}/bin/cat /run/finit-lifecycle/never.count)
          fi
          count=$((count + 1))
          printf '%s\n' "$count" > /run/finit-lifecycle/never.count
          printf '%s\n' failed > /run/finit-lifecycle/never.marker
          exit 42
        '';
      };

      finit.services.lifecycle-zero = {
        runlevel = "2";
        restart-max = 0;
        command = pkgs.writeShellScript "finit-lifecycle-zero" ''
          printf '%s\n' started >> /run/finit-lifecycle/zero.starts
          exit 42
        '';
      };

      finit.services.lifecycle-limited = {
        runlevel = "2";
        restart-max = 1;
        command = pkgs.writeShellScript "finit-lifecycle-limited" ''
          count=0
          if [ -f /run/finit-lifecycle/limited.count ]; then
            count=$(${pkgs.coreutils}/bin/cat /run/finit-lifecycle/limited.count)
          fi
          count=$((count + 1))
          printf '%s\n' "$count" > /run/finit-lifecycle/limited.count
          printf '%s\n' crashed > /run/finit-lifecycle/limited.marker
          exit 43
        '';
      };

      finit.services.lifecycle-reload = {
        runlevel = "2";
        exec-reload = pkgs.writeShellScript "finit-lifecycle-reload" ''
          printf '%s\n' "$MAINPID" >> /run/finit-lifecycle/reload-exec.pids
          kill -HUP "$MAINPID"
        '';
        command = pkgs.writeShellScript "finit-lifecycle-reload-service" ''
          trap 'printf "%s\n" hup >> /run/finit-lifecycle/reload.hups' HUP
          trap 'exit 0' TERM INT
          printf '%s\n' "$$" > /run/finit-lifecycle/reload.pid
          while :; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
      };

      finit.services.lifecycle-provider = {
        runlevel = "2";
        notify = "pid";
        pidfile = "/run/finit-lifecycle/provider.pid";
        exec-reload = pkgs.writeShellScript "finit-lifecycle-provider-reload" ''
          printf '%s\n' "$MAINPID" >> /run/finit-lifecycle/provider-reload.pids
          kill -HUP "$MAINPID"
        '';
        command = pkgs.writeShellScript "finit-lifecycle-provider" ''
          reload() {
            printf '%s\n' hup >> /run/finit-lifecycle/provider.hups
            ${pkgs.coreutils}/bin/rm -f /run/finit-lifecycle/provider.pid
            ${pkgs.coreutils}/bin/sleep 1
            printf '%s\n' "$$" > /run/finit-lifecycle/provider.pid
          }
          trap '${pkgs.coreutils}/bin/rm -f /run/finit-lifecycle/provider.pid; exit 0' TERM INT
          trap reload HUP
          printf '%s\n' "$$" > /run/finit-lifecycle/provider.pid
          while :; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
      };

      finit.services.lifecycle-dependent = {
        runlevel = "2";
        conditions = [ "service/lifecycle-provider/ready" ];
        exec-reload = pkgs.writeShellScript "finit-lifecycle-dependent-reload" ''
          printf '%s\n' "$MAINPID" >> /run/finit-lifecycle/dependent-reload.pids
          kill -HUP "$MAINPID"
        '';
        command = pkgs.writeShellScript "finit-lifecycle-dependent" ''
          trap 'exit 0' TERM INT
          trap 'printf "%s\n" hup >> /run/finit-lifecycle/dependent.hups' HUP
          printf '%s\n' started > /run/finit-lifecycle/dependent.marker
          while :; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
      };

      finit.services.lifecycle-stale = {
        runlevel = "2";
        notify = "pid";
        pidfile = "/run/finit-lifecycle/stale.pid";
        restart-max = 1;
        command = pkgs.writeShellScript "finit-lifecycle-stale" ''
          if [ -e /run/finit-lifecycle/stale.pid ]; then
            printf '%s\n' refused >> /run/finit-lifecycle/stale.refused
            exit 44
          fi
          trap '${pkgs.coreutils}/bin/rm -f /run/finit-lifecycle/stale.pid; exit 0' TERM INT
          trap ':' HUP
          printf '%s\n' "$$" >> /run/finit-lifecycle/stale.starts
          printf '%s\n' "$$" > /run/finit-lifecycle/stale.pid
          while :; do
            ${pkgs.coreutils}/bin/sleep 0.1
          done
        '';
      };

      finit.services.lifecycle-timeouts = {
        runlevel = "2";
        manual-start = true;
        exec-reload-timeout = 1;
        exec-stop-timeout = 1;
        exec-reload = pkgs.writeShellScript "finit-lifecycle-timeout-reload" ''
          printf '%s\n' "$MAINPID" > /run/finit-lifecycle/timeout-reload.pid
        '';
        exec-stop = pkgs.writeShellScript "finit-lifecycle-timeout-stop" ''
          printf '%s\n' "$MAINPID" > /run/finit-lifecycle/timeout-stop.pid
          kill -TERM "$MAINPID"
        '';
        command = pkgs.writeShellScript "finit-lifecycle-timeouts" ''
          printf '%s\n' "$$" > /run/finit-lifecycle/timeouts.pid
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };
    };

  testScript = ''
    from datetime import timedelta
    import json
    import time

    WAIT = timedelta(seconds=30)
    BOOT = timedelta(seconds=180)

    def json_status(name):
        return json.loads(machine.succeed(f"initctl -j status {name}"))

    def wait_status(name, states, predicate=lambda status: True):
        deadline = time.monotonic() + WAIT.total_seconds()
        while time.monotonic() < deadline:
            status = json_status(name)
            if status["status"] in states and predicate(status):
                return status
            time.sleep(0.1)
        raise AssertionError(f"{name} did not reach {states}: {status}")

    def line_count(path):
        return int(machine.succeed(f"wc -l < /run/finit-lifecycle/{path}"))

    def condition_status(name):
        conditions = json.loads(machine.succeed("initctl -j cond dump"))
        condition = next(
            (item for item in conditions if item["condition"] == name), None
        )
        assert condition is not None, f"condition {name} not found"
        return condition["status"]

    def wait_condition_status(name, expected):
        deadline = time.monotonic() + WAIT.total_seconds()
        while time.monotonic() < deadline:
            status = condition_status(name)
            if status == expected:
                return
            time.sleep(0.1)
        raise AssertionError(
            f"condition {name} did not reach {expected}; got {condition_status(name)}"
        )

    def writable_conf(name):
        path = f"/etc/finit.d/{name}.conf"
        machine.succeed(f"cp -L {path} {path}.fixture && chmod u+w {path}.fixture")
        machine.succeed(f"mv -Tf {path}.fixture {path}")
        machine.succeed(f"test ! -L {path} && test -w {path}")

    machine.start()
    machine.wait_for_console_text("finix - stage 1", timeout=BOOT)
    machine.wait_for_console_text("finix - stage 2", timeout=BOOT)
    machine.wait_for_console_text("entering runlevel S", timeout=BOOT)
    machine.wait_for_console_text("entering runlevel 2", timeout=BOOT)

    with subtest("restart never and restart-max zero independently forbid retries"):
        for name in ("lifecycle-never", "lifecycle-zero"):
            status = wait_status(name, {"crashed", "stopped"})
            assert status["pid"] == 0, status
        assert status["exit"]["code"] == 42, status
        assert int(machine.succeed("cat /run/finit-lifecycle/never.count")) == 1
        assert line_count("zero.starts") == 1
        for name in ("lifecycle-never", "lifecycle-zero"):
            assert json_status(name)["status"] in ("crashed", "stopped")
        machine.succeed("test -f /run/finit-lifecycle/never.marker")

    with subtest("restart-max one permits one retry then reaches crashed"):
        status = wait_status("lifecycle-limited", {"crashed", "stopped"})
        assert status["pid"] == 0, status
        assert status["exit"]["code"] == 43, status
        count = int(machine.succeed("cat /run/finit-lifecycle/limited.count"))
        assert count == 2, f"restart-max=1 allowed unexpected starts: count={count}"
        machine.succeed("test -f /run/finit-lifecycle/limited.marker")

    with subtest("exec-reload receives MAINPID and preserves the service PID"):
        pid_before = wait_status("lifecycle-reload", {"running"})["pid"]
        assert pid_before > 1
        machine.wait_until_succeeds("test -s /run/finit-lifecycle/reload.pid", timeout=WAIT)
        assert int(machine.succeed("cat /run/finit-lifecycle/reload.pid")) == pid_before
        writable_conf("lifecycle-reload")
        machine.succeed("initctl touch lifecycle-reload.conf")
        machine.succeed("initctl reload lifecycle-reload")
        machine.wait_until_succeeds(
            "test \"$(wc -l < /run/finit-lifecycle/reload-exec.pids)\" -eq 1",
            timeout=WAIT,
        )
        machine.wait_until_succeeds(
            "test \"$(wc -l < /run/finit-lifecycle/reload.hups)\" -eq 1",
            timeout=WAIT,
        )
        pid_after = json_status("lifecycle-reload")["pid"]
        assert pid_after == pid_before, (
            f"exec-reload restarted service: before={pid_before}, after={pid_after}"
        )
        reload_pid = int(machine.succeed("cat /run/finit-lifecycle/reload-exec.pids"))
        assert reload_pid == pid_before, (
            f"MAINPID did not identify service process: MAINPID={reload_pid}, service={pid_before}"
        )
        assert json_status("lifecycle-reload")["status"] == "running"

    with subtest("back-to-back reloads coalesce provider reload work"):
        provider_pid = wait_status("lifecycle-provider", {"running"})["pid"]
        wait_status("lifecycle-dependent", {"running"})
        machine.wait_until_succeeds("test -f /run/finit-lifecycle/dependent.marker", timeout=WAIT)
        machine.succeed(
            "rm -f /run/finit-lifecycle/provider.hups "
            "/run/finit-lifecycle/provider-reload.pids "
            "/run/finit-lifecycle/dependent-reload.pids "
            "/run/finit-lifecycle/dependent.hups"
        )
        for name in ("lifecycle-provider", "lifecycle-dependent"):
            writable_conf(name)
            machine.succeed(f"initctl touch {name}.conf")

        machine.succeed("initctl reload && initctl reload")
        wait_status("lifecycle-provider", {"running"})
        wait_status("lifecycle-dependent", {"running"})
        provider_reload_count = line_count("provider-reload.pids")
        assert provider_reload_count == 1, provider_reload_count
        assert line_count("provider.hups") == 1
        provider_status = json_status("lifecycle-provider")
        assert provider_status["status"] == "running", provider_status
        assert provider_status["pid"] == provider_pid, provider_status
        dependent_status = json_status("lifecycle-dependent")
        assert dependent_status["status"] == "running", dependent_status
        assert dependent_status["pid"] > 1, dependent_status

    with subtest("Finit removes a daemon-owned stale pidfile after SIGKILL"):
        wait_condition_status("service/lifecycle-stale/ready", "on")
        old_pid = wait_status("lifecycle-stale", {"running"})["pid"]
        assert old_pid > 1
        assert int(machine.succeed("cat /run/finit-lifecycle/stale.pid")) == old_pid
        assert line_count("stale.starts") == 1
        machine.succeed(f"kill -KILL {old_pid}")
        restarted = wait_status(
            "lifecycle-stale", {"running"},
            lambda status: status["pid"] > 1 and status["pid"] != old_pid,
        )
        new_pid = restarted["pid"]
        machine.wait_until_succeeds(
            f"test \"$(cat /run/finit-lifecycle/stale.pid)\" -eq {new_pid}", timeout=WAIT
        )
        machine.succeed(f"kill -0 {new_pid}")
        wait_condition_status("service/lifecycle-stale/ready", "on")
        assert line_count("stale.starts") == 2
        machine.fail("test -e /run/finit-lifecycle/stale.refused")

    with subtest("numeric stop and reload hook timeouts keep PID1 responsive"):
        machine.succeed("initctl start lifecycle-timeouts")
        pid = wait_status("lifecycle-timeouts", {"running"})["pid"]
        assert pid > 1
        machine.wait_until_succeeds("test -s /run/finit-lifecycle/timeouts.pid", timeout=WAIT)
        writable_conf("lifecycle-timeouts")
        machine.succeed("initctl touch lifecycle-timeouts.conf")
        machine.succeed("initctl reload lifecycle-timeouts")
        machine.wait_until_succeeds("test -s /run/finit-lifecycle/timeout-reload.pid", timeout=WAIT)
        assert int(machine.succeed("cat /run/finit-lifecycle/timeout-reload.pid")) == pid
        assert json_status("lifecycle-timeouts")["pid"] == pid
        machine.succeed("kill -0 1 && initctl status")
        machine.succeed("initctl stop lifecycle-timeouts")
        wait_status("lifecycle-timeouts", {"stopped"})
        assert int(machine.succeed("cat /run/finit-lifecycle/timeout-stop.pid")) == pid
        machine.succeed("kill -0 1 && initctl status")

    with subtest("shutdown"):
        machine.shutdown()
  '';
}

# @claude 2026-10-04: found while running the refusals of the 2026-10-04 releases
# (every `error:` line was followed by exit status 0). Scenarios are bound to
# cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh
# holds the binding both ways.
Feature: up.sh leaves with the status it was exiting with

  die prints its error and runs `exit 1`. The EXIT trap then runs cleanup, which
  ended in a hard-coded `exit 0`, so once the trap was armed every refusal read as
  a success to a script, a CI step or a supervisor driving the launcher.

  Scenario: a refusal with nothing started
    Given cleanup leaves with the status the script was exiting with
    When it exits 0 instead
    Then die-keeps-its-exit-status.sh fails saying exit 0, wanted 3
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: cleanup exits 0 with nothing started"

  Scenario: a refusal with services already started
    Given the services are stopped and the status survives
    When cleanup ends with exit 0 after stopping them
    Then die-keeps-its-exit-status.sh fails
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: cleanup ends with exit 0 after stopping services"

  Scenario: the operator stops the stack on purpose
    Given SIGINT and SIGTERM are a deliberate stop, status 0
    When they report failure
    Then die-keeps-its-exit-status.sh fails
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: a deliberate stop reports failure"

  Scenario: a plane dies under the launcher
    Given the stack that stopped because a plane died did not stop cleanly, status 1
    When the hold loop stops the rest without a status
    Then die-keeps-its-exit-status.sh fails
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: a dead plane exits 0 again"

  Scenario: rewording the comment is not a fault
    Given the gate judges the status, not the prose
    When the comment above cleanup is reworded
    Then die-keeps-its-exit-status.sh still passes
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: the comment above cleanup is reworded"

  Scenario: no up.sh and no cleanup function left to run
    Given the gate runs the launcher's own cleanup
    When the file or the function is gone
    Then die-keeps-its-exit-status.sh says it measured nothing
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: no up.sh left to read"
    # -> gates-have-teeth.sh "die-keeps-its-exit-status: no cleanup function left to run"

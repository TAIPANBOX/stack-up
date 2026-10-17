# @decided 2026-10-17 (paraphrased): the launcher fails closed on its policy decision point, and a stand that cannot reach that point stops instead of running without it.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: the policy decision point fails closed, and the launcher stops without it

  The gateway asks wardryx for every decision. tokenfuse's default, when that
  answer does not come in time, is to allow the call. This launcher wires the
  gateway to wardryx, so the gateway must refuse a call that wardryx cannot
  answer, and the launcher must not carry on as if the policy plane were there.

  Scenario: the gateway refuses a decision it cannot get from wardryx
    Given a gateway that this launcher wires to wardryx
    When up.sh starts the gateway
    Then the start sets TOKENFUSE_WARDRYX_FAILMODE to closed
    # -> gates-have-teeth.sh "wardryx-fails-closed: the gateway's fail mode is not set"
    # -> gates-have-teeth.sh "wardryx-fails-closed: the gateway's fail mode is open"

  Scenario: a wardryx that does not come up stops the stand
    Given wardryx is started after the gateway is already wired to it
    When wardryx does not answer its health check
    Then the launcher exits with an error, and its exit trap stops what it started
    # -> gates-have-teeth.sh "wardryx-fails-closed: a wardryx that does not come up is only a warning"
    # -> gates-have-teeth.sh "wardryx-fails-closed: the wardryx wait is renamed away"

  Scenario: a failed wardryx fetch or build stops the stand too
    Given the gateway is already wired to wardryx when the fetch and build begin
    When wardryx cannot be fetched or built
    Then the launcher stops, and it does not switch the policy plane off and carry on
    # -> gates-have-teeth.sh "wardryx-fails-closed: a failed build continues without wardryx"
    # -> gates-have-teeth.sh "wardryx-fails-closed: a failed fetch continues without wardryx"

  Scenario: the launcher never says the gateway will fail open
    Given the launcher prints what the stand will do
    When a line that is not a comment says the gateway fails open
    Then wardryx-fails-closed.sh fails
    # -> gates-have-teeth.sh "wardryx-fails-closed: the launcher says the gateway will fail open"

  Scenario: a comment about failing open is prose, not a fault
    Given the launcher's comments describe the fail mode
    When a comment says the gateway fails open
    Then wardryx-fails-closed.sh still passes
    # -> gates-have-teeth.sh "wardryx-fails-closed: a comment that says fail open is not a fault"

  Scenario: the gate says when it had nothing to judge
    Given the gate reads up.sh, its gateway starts and its wardryx block
    When up.sh is gone, or the wardryx wait or the wired start is not there to read
    Then wardryx-fails-closed.sh fails and says it measured nothing
    # -> gates-have-teeth.sh "wardryx-fails-closed: no up.sh left to read"
    # -> gates-have-teeth.sh "wardryx-fails-closed: no gateway start wired to wardryx left to judge"

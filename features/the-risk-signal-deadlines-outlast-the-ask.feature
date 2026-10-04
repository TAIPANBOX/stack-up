# @decided 2026-10-04, aligning with stack-single#88: the typed risk signal's
# proxy waits 3000 ms for its backend and the broker waits 7000 ms for the
# decision. Scenarios are bound to cases in scripts/gates-have-teeth.sh by name,
# and scripts/features-are-bound.sh holds the binding both ways.
Feature: the risk signal's deadlines outlast the ask

  The proxy asks typryx's backend before it forwards the decision to wardryx.
  typryx's own default ask deadline is 150 ms, which drops a hosted answer (Jev
  median 229 ms) and a local-model answer (qwen2.5:7b median 2130 ms on 8 vCPU).
  A dropped answer forwards the call with no signal, so a hold_if_signal rule
  never fires and nothing says so.

  Scenario: the proxy ask deadline is left unset
    Given the proxy is given TYPRYX_PROXY_ASK_TIMEOUT_MS from the launcher's constant
    When the assignment goes
    Then typed-mode.sh fails, because the proxy would run on 150 ms
    # -> gates-have-teeth.sh "typed-mode: the proxy ask deadline is left unset"
    # -> gates-have-teeth.sh "typed-mode: the deadline constants are renamed away"

  Scenario: the ask deadline is shorter than the longest answer, or past what typryx accepts
    Given 3000 ms clears the longest measured answer and is inside typryx's range of 1 to 5000
    When it is set to 150 or to 6000
    Then typed-mode.sh fails naming which
    # -> gates-have-teeth.sh "typed-mode: the proxy ask deadline is shorter than the longest answer"
    # -> gates-have-teeth.sh "typed-mode: the proxy ask deadline is past what typryx accepts"

  Scenario: the broker gives up before the signal can arrive
    Given the broker's decide deadline is TOKENFUSE_MCP_WARDRYX_TIMEOUT_MS, 7000 ms, longer than the ask
    When it is shortened to the ask or less, or the broker is no longer given the variable
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the broker decide deadline is shorter than the ask"
    # -> gates-have-teeth.sh "typed-mode: the broker is not given the tool-call decide deadline"

  Scenario: the LLM gateway's own wardryx timeout moves with the risk signal
    Given the gateway never goes through the proxy
    When its TOKENFUSE_WARDRYX_TIMEOUT_MS changes
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the gateway's own wardryx timeout is changed with the risk signal"

  Scenario: rewording a comment about the deadlines is not a fault
    Given the gate judges the values, not the prose
    When a comment is reworded
    Then typed-mode.sh still passes
    # -> gates-have-teeth.sh "typed-mode: the deadline comment is reworded"

# @claude 2026-10-19: written for wave 3, item W-UP.1 of the 2026-10-17 security review, from
# its paraphrased decision: a risk signal can add a hold and never a deny, and a hold that a
# silent classifier never gave is a hold too. Scenarios are bound to cases in
# scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: a brokered call the typed risk signal never reaches is held when the signal is on

  A hold_if_signal rule had nothing to read when the signal never arrived, so the call went
  on as if it were harmless. With --typed-risk-signal the launcher now seeds one rule that
  holds such a call for a person. No other run is given the rule.

  Scenario: a brokered call with no signal is held when the typed risk signal is on
    Given --typed-risk-signal is given and the wardryx that will run reads when_absent
    When the launcher writes the policy file
    Then the rule stack-up-typed-risk-hold holds when the signal is absent
    # -> gates-have-teeth.sh "risk-hold-is-seeded: the when_absent line is dropped"
    # -> gates-have-teeth.sh "risk-hold-is-seeded: when_absent becomes allow"

  Scenario: the rule is written only under the flag
    Given a run without --typed-risk-signal
    When the launcher writes the policy file
    Then no hold on a missing signal is in it
    # -> gates-have-teeth.sh "risk-hold-is-seeded: the rule is written without the flag"

  Scenario: a wardryx that predates when_absent is refused before it starts
    Given --typed-risk-signal is given and the wardryx binary does not read when_absent
    When the launcher is about to start wardryx
    Then the launcher stops and says why
    # -> gates-have-teeth.sh "risk-hold-is-seeded: wardryx is not checked for when_absent"

  Scenario: the rule keeps its threshold and the three values that carry a risk
    Given the rule reads the risk class the proxy adds
    When the rule is written
    Then it holds destructive, external_send and financial at 0.8 or more
    # -> gates-have-teeth.sh "risk-hold-is-seeded: the threshold is dropped"

  Scenario: the rule covers every agent, not one trust domain
    Given a brokered call carries the agent id of the broker's caller
    When the rule is written
    Then its target is every agent
    # -> gates-have-teeth.sh "risk-hold-is-seeded: the rule is narrowed to one trust domain"

  Scenario: a launch cannot switch single-use off under the hold
    Given a hold on a missing signal lifts one call per approval
    When wardryx is started
    Then WARDRYX_APPROVAL_SINGLE_USE is not set to false
    # -> gates-have-teeth.sh "risk-hold-is-seeded: single-use is switched off"

  Scenario: a comment that names when_absent: allow is not a rule
    Given a comment in the launcher describes what a rule without the key does
    When the gate reads the launcher
    Then it passes
    # -> gates-have-teeth.sh "risk-hold-is-seeded: a comment that names when_absent: allow is not a fault"

  Scenario: the gate refuses to pass when the rule is not in the launcher
    Given the seeded rule is renamed in the launcher
    When the gate reads the launcher
    Then it says it measured nothing and does not report success
    # -> gates-have-teeth.sh "risk-hold-is-seeded: the rule is renamed away"

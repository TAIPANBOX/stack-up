# @decided 2026-11-07 (paraphrased): a tool call nothing grants is held for a person, a model
# call passes, and only an explicit grant lifts the hold. @claude 2026-11-07: that here it goes
# with --typed-risk-signal is my reading: that flag is what turns the broker's policy gate on.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and
# scripts/features-are-bound.sh holds the binding both ways.
Feature: the tool hold goes with the broker's policy gate

  stack-single and stack-k8s hold a tool call nothing grants on a default install. This
  launcher's broker asks wardryx only under --typed-risk-signal, so the hold goes with that
  flag, and a default run says plainly that no policy decision point sees a tool call.

  Scenario: a tool call nothing grants is held under the flag
    Given --typed-risk-signal is given and the wardryx that will run reads when_no_grant
    When the launcher writes the policy file
    Then tool-hold holds a tool call of any agent, with or without the agent scheme
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the floor narrows to ids with a scheme"
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the floor is written as a word wardryx refuses"

  Scenario: the block is written only under the flag
    Given a run without --typed-risk-signal
    When the launcher writes the policy file
    Then no floor is in it, because no tool call reaches wardryx on that run
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the floor is written without the flag"
    # -> gates-have-teeth.sh "tool-hold-is-seeded: a broker gets the gate with no flag"

  Scenario: the fire drills keep working
    Given the rule the two stacks seed for the fire-drill identities
    When the block is written
    Then grant-drills grants those identities every tool, and no wider target gets one
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the drills lose their grant"
    # -> gates-have-teeth.sh "tool-hold-is-seeded: a grant on every agent"

  Scenario: the example this run prints keeps working, and only that
    Given the printed example calls ask as the broker's demo agent on the broker's static key
    When the block is written
    Then that id is granted that one tool on that one door
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the demo grant takes every tool"
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the demo grant is open to any door"

  Scenario: a wardryx that predates the rule is refused before it starts
    Given --typed-risk-signal is given and the wardryx binary does not read when_no_grant
    When the launcher is about to write the block
    Then the launcher stops and says why
    # -> gates-have-teeth.sh "tool-hold-is-seeded: wardryx is not checked for when_no_grant"
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the check of when_no_grant does not refuse"

  Scenario: the pins are the releases the rule needs
    Given wardryx reads the rule from v2.6.0 and the broker says why it held from v1.23.0
    When the pin table is read
    Then neither component sits below that release
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the wardryx pin falls below the floor"
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the tokenfuse pin falls below the floor"

  Scenario: a default run says what it does not have
    Given a stranger reading the README
    When they read what runs on a default run
    Then it says a default run has no policy decision point on tool calls
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the README stops saying what a default run has"

  Scenario: a comment that names the rule is not the rule
    Given a comment in the launcher names when_no_grant
    When the gate reads the launcher
    Then it passes
    # -> gates-have-teeth.sh "tool-hold-is-seeded: a comment that names when_no_grant is not a fault"

  Scenario: the gate refuses to pass when the block is not in the launcher
    Given the block's marker is renamed in the launcher
    When the gate reads the launcher
    Then it says it measured nothing and does not report success
    # -> gates-have-teeth.sh "tool-hold-is-seeded: the block is renamed away"

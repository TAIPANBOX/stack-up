# @decided 2026-10-13: the launcher runs tokenfuse's agent firewall in enforce by
# default, shipped as its own change after a test stack, and an operator keeps one
# switch to run it in shadow or off. Scenarios are bound to cases in
# scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the
# binding both ways.
Feature: every gateway start runs the agent firewall in enforce unless the one switch says otherwise

  tokenfuse's agent firewall refuses a dangerous capability on a run that has read
  untrusted input. Unset, it only records what it would refuse, so a launcher that
  lost its setting would still come up, answer health checks and say nothing. The
  switch is --firewall. It takes enforce, shadow or off, and any other word is
  refused before anything is built.

  Scenario: a gateway start loses the setting
    Given every gateway start sets TOKENFUSE_FIREWALL from the switch
    When one start stops setting it
    Then firewall-is-enforce.sh fails and names that start
    # -> gates-have-teeth.sh "firewall-is-enforce: one gateway start drops TOKENFUSE_FIREWALL"

  Scenario: a gateway start writes shadow in place of the switch
    Given the switch is the only value a gateway start may carry
    When one start writes shadow itself
    Then firewall-is-enforce.sh fails, saying the start is not set from the switch
    # -> gates-have-teeth.sh "firewall-is-enforce: one gateway start sets shadow in place of the switch"

  Scenario: the default is moved to shadow
    Given the switch defaults to enforce
    When the default is changed to shadow
    Then firewall-is-enforce.sh fails, saying the default is not enforce
    # -> gates-have-teeth.sh "firewall-is-enforce: the default becomes shadow"

  Scenario: the default is read from the caller's environment
    Given the switch is read from --firewall only
    When the default is taken from an environment variable instead
    Then firewall-is-enforce.sh fails, saying the default is not enforce
    # -> gates-have-teeth.sh "firewall-is-enforce: the default is read from the caller's environment"

  Scenario: the MCP broker is given the switch
    Given the MCP broker is not the gateway and reads no firewall
    When its start sets TOKENFUSE_FIREWALL
    Then firewall-is-enforce.sh fails and names the broker start
    # -> gates-have-teeth.sh "firewall-is-enforce: the MCP broker start is given the switch"

  Scenario: a word tokenfuse would not read is accepted
    Given --firewall takes enforce, shadow or off and refuses every other word
    When a misspelt word gets through
    Then firewall-is-enforce.sh fails, because that word would run in shadow with nothing said
    # -> gates-have-teeth.sh "firewall-is-enforce: a mode tokenfuse would not read is accepted"

  Scenario: the validation is removed
    Given a word other than enforce, shadow or off stops the launch at argument parsing
    When that check is taken out
    Then firewall-is-enforce.sh fails, because the bad word is no longer refused
    # -> gates-have-teeth.sh "firewall-is-enforce: the validation is removed"

  Scenario: the plan stops saying which mode a launch will run
    Given --plan prints the agent firewall's mode before anything starts
    When that line is reworded so it no longer names the mode
    Then firewall-is-enforce.sh fails, saying the plan does not name it
    # -> gates-have-teeth.sh "firewall-is-enforce: the plan stops naming the mode"

  Scenario: up.sh stops taking --plan
    Given --plan is how the switch is judged without starting anything
    When the flag is renamed away
    Then firewall-is-enforce.sh says it measured nothing
    # -> gates-have-teeth.sh "firewall-is-enforce: up.sh stops taking --plan"

  Scenario: no gateway start is left to judge
    Given the gate reads every gateway start in up.sh
    When the starts are renamed so that none matches
    Then firewall-is-enforce.sh says it measured nothing, and fails
    # -> gates-have-teeth.sh "firewall-is-enforce: no gateway start left to judge"

  Scenario: no up.sh is left to read
    Given the launcher is what the gate reads
    When up.sh is moved away
    Then firewall-is-enforce.sh says it measured nothing, and fails
    # -> gates-have-teeth.sh "firewall-is-enforce: no up.sh left to read"

  Scenario: a comment that names the other two words changes nothing
    Given the gate reads commands, not prose
    When a comment above a gateway start names shadow and off
    Then firewall-is-enforce.sh still passes
    # -> gates-have-teeth.sh "firewall-is-enforce: a comment naming shadow and off is not a setting"

  Scenario: an unrelated variable added to a gateway start changes nothing
    Given the gate looks for the one assignment, not for the exact block
    When an unrelated variable is added to a gateway start
    Then firewall-is-enforce.sh still passes
    # -> gates-have-teeth.sh "firewall-is-enforce: an unrelated var added to the gateway block"

  Scenario: a second broker launch is not taken for a gateway start
    Given the broker is the same binary on a subcommand
    When a second broker launch, with a variable of its own, is added
    Then firewall-is-enforce.sh still passes, because it is neither a gateway start nor carries the switch
    # -> gates-have-teeth.sh "firewall-is-enforce: a second mcp-broker start is not mistaken for a gateway start"

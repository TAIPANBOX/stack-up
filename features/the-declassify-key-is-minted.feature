# @decided 2026-10-04, from the estate audit (wave 1): the tokenfuse gateway's
# declassify endpoint lifts a run's taint label and its credential is optional,
# so a launcher that sets none leaves the endpoint open to anything that reaches
# the gateway port. Scenarios are bound to cases in scripts/gates-have-teeth.sh
# by name, and scripts/features-are-bound.sh holds the binding both ways (it was
# by eye until 2026-10-04).
Feature: the gateway's declassify key is minted per run and reaches the gateway through its environment only

  POST /v1/fuse/declassify takes a run's taint label off after a person
  reviewed it. It is not behind the money plane's key. Its own key is optional
  in the gateway, and with none set, anything that can reach the gateway port
  can clear a run, which the event records only as "authenticated: false".
  Nothing in the estate calls the endpoint, so a key that only this operator was
  shown closes it and breaks nothing.

  Scenario: a gateway start loses the key
    Given every gateway start sets TOKENFUSE_DECLASSIFY_KEY from a per-run variable
    When one start stops setting it
    Then declassify-is-keyed.sh fails and names the start
    # -> gates-have-teeth.sh "declassify-is-keyed: one gateway start drops TOKENFUSE_DECLASSIFY_KEY"

  Scenario: the key is committed as a literal
    Given every gateway start sets TOKENFUSE_DECLASSIFY_KEY from a per-run variable
    When one start writes a literal value instead
    Then declassify-is-keyed.sh fails saying it is not set from a variable
    # -> gates-have-teeth.sh "declassify-is-keyed: the key becomes a literal"

  Scenario: the key becomes an argument to env
    Given the key is a prefix assignment ahead of env, so it is in the environment only
    When it moves to an argument of env
    Then declassify-is-keyed.sh fails saying env would hold it on its command line
    # -> gates-have-teeth.sh "declassify-is-keyed: the key becomes an argument to env"

  Scenario: the key is no longer minted fresh
    Given the key is minted with rand_hex above the first gateway start
    When the mint is replaced by a fixed string
    Then declassify-is-keyed.sh fails saying the key is not per run
    # -> gates-have-teeth.sh "declassify-is-keyed: the mint becomes a fixed string"

  Scenario: the mint is moved below the first start
    Given the key is minted above the first gateway start
    When the mint moves below it
    Then declassify-is-keyed.sh fails saying it is minted after the first start
    # -> gates-have-teeth.sh "declassify-is-keyed: the mint moves below the first gateway start"

  Scenario: an empty mint is not refused
    Given a refusal on an empty key follows the mint, because the gateway reads empty as unset
    When the refusal is removed
    Then declassify-is-keyed.sh fails saying a failed mint would leave the endpoint open
    # -> gates-have-teeth.sh "declassify-is-keyed: the refusal on an empty mint is removed"

  Scenario: no up.sh and no gateway start left to judge
    Given gateway starts are found by the binary variable at the command position
    When up.sh is gone, or no start remains
    Then declassify-is-keyed.sh fails saying it measured nothing, never OK
    # -> gates-have-teeth.sh "declassify-is-keyed: no up.sh left to read"
    # -> gates-have-teeth.sh "declassify-is-keyed: no gateway start left to judge"

  Scenario: the broker start and an unrelated variable are not this gate's business
    Given the MCP broker runs the gateway binary on a subcommand and never serves the route
    When a second broker start appears, or an unrelated variable joins a gateway start
    Then declassify-is-keyed.sh still passes
    # -> gates-have-teeth.sh "declassify-is-keyed: a second mcp-broker start is not mistaken for a gateway start"
    # -> gates-have-teeth.sh "declassify-is-keyed: an unrelated var added to the block"

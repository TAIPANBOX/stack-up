# @decided 2026-10-18 (paraphrased): the gateway admits only callers that hold a key minted for this run, its policy calls use an enforcement-point key rather than the built-in devkey, and the MCP broker blocks secrets and poisoned tools and fails closed when the policy plane is silent.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: the gateway and the MCP broker hold the postures they set, from values minted for this run

  The estate's posture check found six postures this launcher did not hold: the
  metered door admitted any caller, the gateway and the broker talked to wardryx
  with its built-in devkey literal, and the broker's DLP and tool scan only
  shadowed or warned. Each one is now a value minted for this run, or a switch
  the launcher names, and a gate reads it on every start.

  Scenario: every gateway start admits only the client keys minted for this run
    Given each gateway start in up.sh
    When a start does not set TOKENFUSE_CLIENT_KEYS, or takes it from a literal
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: a gateway start does not set the client keys"
    # -> gates-have-teeth.sh "postures-are-held: the client keys are a literal"

  Scenario: the client keys are minted for this run and refused when empty
    Given the launcher mints its keys before the first gateway start
    When nothing refuses an empty client-key mint
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: no refusal after the client-key mint"

  Scenario: the gateway is strict about identity, and says so
    Given each gateway start in up.sh
    When a start sets TOKENFUSE_IDENTITY_STRICT to anything but enforce
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: identity strict is not enforce"

  Scenario: the policy calls use a per-run enforcement-point key, never the devkey literal
    Given the gateway, the MCP broker and scopyx present a key to wardryx
    When the gateway hands wardryx the devkey literal, the devkey switch is set, or scopyx is given the literal
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: the gateway hands wardryx the devkey literal"
    # -> gates-have-teeth.sh "postures-are-held: the devkey switch is assigned"
    # -> gates-have-teeth.sh "postures-are-held: the scanner key is the devkey literal"
    # -> gates-have-teeth.sh "postures-are-held: broker wardryx key is a literal"

  Scenario: wardryx answers only the enforcement-point key, as a pep
    Given wardryx starts with a key list
    When the key list names the gateway's key with any role but pep
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: the wardryx key list gives the gateway a viewer role"

  Scenario: the MCP broker blocks secrets and tool poisoning, and fails closed on wardryx
    Given the MCP broker start in up.sh
    When its DLP is shadow, its scan warns, or its wardryx fail mode is open
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: broker DLP is shadow"
    # -> gates-have-teeth.sh "postures-are-held: broker scan warns"
    # -> gates-have-teeth.sh "postures-are-held: broker fail mode is open"

  Scenario: a comment that names the devkey is prose, not a setting
    Given a comment in up.sh names the devkey literal
    When the gate reads the launcher
    Then postures-are-held.sh still passes
    # -> gates-have-teeth.sh "postures-are-held: a comment that names devkey is not a fault"

  Scenario: the client key never reaches a command line, where ps can read it
    Given the demo's calls to the gateway in up.sh
    When a live line puts the client key in a curl argument or an x-fuse-key header value
    Then postures-are-held.sh fails
    # -> gates-have-teeth.sh "postures-are-held: the client key is on a curl command line"
    # -> gates-have-teeth.sh "postures-are-held: a comment that names the client key is not a fault"

  Scenario: the gate says it measured nothing when its subject is gone
    Given the gate reads every gateway start and the launcher itself
    When no gateway start is left to judge, or up.sh is gone
    Then postures-are-held.sh fails and says it measured nothing
    # -> gates-have-teeth.sh "postures-are-held: no gateway start left to judge"
    # -> gates-have-teeth.sh "postures-are-held: no up.sh left to read"

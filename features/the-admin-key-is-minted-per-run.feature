# @decided 2026-10-17 (paraphrased): each run gives the gateway's admin routes a key of its own, kept in a file only the operator's user can read, and the terminal names that file and never the value.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: the gateway's admin routes answer a key minted for this run, and the key stays out of the terminal

  The admin routes include the kill switch. While TOKENFUSE_ADMIN_KEYS is unset,
  they answer any process on the machine. This launcher gives each run its own
  key, writes it to a file that only the operator's user can read, and names the
  file in the summary, not the value.

  Scenario: every gateway start takes the admin key from this run
    Given each gateway start in up.sh
    When a start does not set TOKENFUSE_ADMIN_KEYS, or sets it to a literal
    Then admin-keys-are-per-run.sh fails
    # -> gates-have-teeth.sh "admin-keys-are-per-run: a gateway start does not set the admin keys"
    # -> gates-have-teeth.sh "admin-keys-are-per-run: the admin keys are a literal"

  Scenario: the key reaches the gateway ahead of env, not on env's command line
    Given a gateway started through env
    When the admin key is an argument to env
    Then admin-keys-are-per-run.sh fails
    # -> gates-have-teeth.sh "admin-keys-are-per-run: the admin key is an argument to env"

  Scenario: the key is minted for this run and refused when empty
    Given the launcher mints its keys before the first gateway start
    When the admin key is a fixed value, or nothing refuses an empty mint
    Then admin-keys-are-per-run.sh fails
    # -> gates-have-teeth.sh "admin-keys-are-per-run: the admin key is never minted"
    # -> gates-have-teeth.sh "admin-keys-are-per-run: no refusal after the mint"

  Scenario: the key is written to a 0600 file and never printed
    Given the operator is told where the key is
    When the key is printed, or is never written to a file, or the file is not 0600
    Then admin-keys-are-per-run.sh fails
    # -> gates-have-teeth.sh "admin-keys-are-per-run: the key is printed to the terminal"
    # -> gates-have-teeth.sh "admin-keys-are-per-run: the key is never written to a file"
    # -> gates-have-teeth.sh "admin-keys-are-per-run: the key file is not made 0600"

  Scenario: a comment that names the key is prose
    Given the launcher's comments explain the key
    When a comment names the key variable
    Then admin-keys-are-per-run.sh still passes
    # -> gates-have-teeth.sh "admin-keys-are-per-run: a comment that names the key variable is not a print"

  Scenario: the gate says when it had nothing to judge
    Given the gate reads up.sh and its gateway starts
    When up.sh is gone, or no gateway start is left to read
    Then admin-keys-are-per-run.sh fails and says it measured nothing
    # -> gates-have-teeth.sh "admin-keys-are-per-run: no up.sh left to read"
    # -> gates-have-teeth.sh "admin-keys-are-per-run: no gateway start left to judge"

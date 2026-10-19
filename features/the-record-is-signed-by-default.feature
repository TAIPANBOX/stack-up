# @decided 2026-10-19 (paraphrased): keyryx is part of every install, and the sealed record is signed through it by default.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: the record is signed through keyryx by default, and the opt-out says the record is unsigned

  The record plane seals a root of the events it read. Custody signs that root under a key it
  holds, and the witness reads the record from its own process. Both are on by default. The one
  flag that turns them off is --without-keyryx, and the launcher says, when it is used, that the
  record pack is then unsigned and that this is the weaker setting. Every call to the record plane
  goes through one function, so the signer is set in one place, for the one-shot seal in up.sh
  and for the scheduled seal in routines.sh alike.

  Scenario: keyryx is on by default, and only the flag turns it off
    Given the defaults and flags of up.sh
    When keyryx is switched off by default, the flag no longer switches it off, or the flag is renamed
    Then record-is-signed-by-default.sh fails
    # -> gates-have-teeth.sh "record-is-signed-by-default: keyryx is off by default"
    # -> gates-have-teeth.sh "record-is-signed-by-default: --without-keyryx is not a flag"
    # -> gates-have-teeth.sh "record-is-signed-by-default: --without-keyryx does not switch keyryx off"

  Scenario: custody starts only in the block that keyryx's own switch decides
    Given the keyryx start block in up.sh
    When the block is decided by another switch
    Then record-is-signed-by-default.sh fails
    # -> gates-have-teeth.sh "record-is-signed-by-default: the keyryx block is not under WANT_KEYRYX"

  Scenario: every seal is signed when keyryx is up, and the same call runs unsigned when it is not
    Given every trailryx-node call in up.sh and routines.sh
    When a call names the node binary directly, the signer is dropped when signing, or the signer is not removed when not signing
    Then record-is-signed-by-default.sh fails
    # -> gates-have-teeth.sh "record-is-signed-by-default: a seal call bypasses seal_node"
    # -> gates-have-teeth.sh "record-is-signed-by-default: seal_node drops the signer when signing"
    # -> gates-have-teeth.sh "record-is-signed-by-default: seal_node keeps the signer when not signing"
    # -> gates-have-teeth.sh "record-is-signed-by-default: a routine seal runs the node binary bare"
    # -> gates-have-teeth.sh "record-is-signed-by-default: the scheduled seal does not sign"
    # -> gates-have-teeth.sh "record-is-signed-by-default: seal_node is renamed away (measured nothing)"

  Scenario: the witness reads the same records directory, under the tenant the seal writes
    Given the witness start and the seal calls in up.sh
    When the witness is pointed at no records, a seal call names no tenant, or the tenant is not the one trailryx seals by default
    Then record-is-signed-by-default.sh fails
    # -> gates-have-teeth.sh "record-is-signed-by-default: the witness does not read the seal's records"
    # -> gates-have-teeth.sh "record-is-signed-by-default: the seal names no tenant the witness reads"
    # -> gates-have-teeth.sh "record-is-signed-by-default: RECORDS_TENANT names another tenant than trailryx's default"

  Scenario: the record-seal credential is minted once and may only sign trailryx-root
    Given the policy written by up.sh and the credential file
    When the root keys are wiped every run, the credential is minted every run, trailryx-root is not ES384, or the record-seal consumer is granted more than sign
    Then record-is-signed-by-default.sh fails
    # -> gates-have-teeth.sh "record-is-signed-by-default: the root keys are wiped every run"
    # -> gates-have-teeth.sh "record-is-signed-by-default: the record-seal credential is minted every run"
    # -> gates-have-teeth.sh "record-is-signed-by-default: trailryx-root is not an ES384 key"
    # -> gates-have-teeth.sh "record-is-signed-by-default: record-seal is granted more than sign"

  Scenario: the opt-out and a failed custody both say the record pack is unsigned
    Given the closing output and the launch plan
    When the opt-out no longer says the pack is unsigned and the weaker setting, or the plan does not name the signing mode
    Then record-is-signed-by-default.sh fails
    # -> gates-have-teeth.sh "record-is-signed-by-default: the opt-out does not say the record pack is unsigned"
    # -> gates-have-teeth.sh "record-is-signed-by-default: the launch plan does not name the signing mode"

  Scenario: the state the scheduled seal reads is written every run, and a comment that names a node call is not a fault
    Given the record signing state written by up.sh
    When the state file is written to another name, or only a comment names the node binary
    Then record-is-signed-by-default.sh fails for the first and passes for the second
    # -> gates-have-teeth.sh "record-is-signed-by-default: the signing state is written to another name"
    # -> gates-have-teeth.sh "record-is-signed-by-default: a comment that names the node binary is not a fault"

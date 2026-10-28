# @decided 2026-10-19 (paraphrased): the record seal is pinned to the key custody signs with, and the pin moves only on purpose.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: the record seal is pinned to custody's active key, and the pin is never moved silently

  trailryx v1.5.0 signs a sealed root only under the key its pin names, and it refuses to start
  without one. The launcher takes the pin from custody itself, checks it against custody's active
  key, keeps it across runs, and changes it only when the operator asks. Every refusal says why, and
  the record is then not signed in that run.

  Scenario: the pins are trailryx v1.5.0 and keyryx v0.1.3, at their tags' commits
    Given the pin table in up.sh
    When trailryx or keyryx is pinned to an older release or another commit
    Then record-key-is-pinned.sh fails
    # -> gates-have-teeth.sh "record-key-is-pinned: the trailryx pin is not v1.5.0"
    # -> gates-have-teeth.sh "record-key-is-pinned: the keyryx pin is not v0.1.3"

  Scenario: the pin is read from custody's trailryx-root key set and its active key, and refused with a reason
    Given custody answers its key set and its state
    When the launcher reads another route, takes no active key, skips a check against the active key or the thumbprint
    Then record-key-is-pinned.sh fails
    # -> gates-have-teeth.sh "record-key-is-pinned: record_key_pin does not read custody's trailryx-root key set"
    # -> gates-have-teeth.sh "record-key-is-pinned: record_key_pin does not read custody's state"
    # -> gates-have-teeth.sh "record-key-is-pinned: the install pin is not checked against the active key"
    # -> gates-have-teeth.sh "record-key-is-pinned: a kept pin is not checked against the active key"
    # -> gates-have-teeth.sh "record-key-is-pinned: a repin is not checked against the key set"
    # -> gates-have-teeth.sh "record-key-is-pinned: a kid is not checked against its RFC 7638 thumbprint"

  Scenario: the pin is kept private, and moves only by the flag, which needs keyryx
    Given the pin file and the repin flag
    When the pin file is not private, is written under another umask, the flag is not a flag, or it runs without keyryx
    Then record-key-is-pinned.sh fails
    # -> gates-have-teeth.sh "record-key-is-pinned: the pin file is not kept private"
    # -> gates-have-teeth.sh "record-key-is-pinned: the pin is not written under umask 077"
    # -> gates-have-teeth.sh "record-key-is-pinned: --repin-record-key is not a flag"
    # -> gates-have-teeth.sh "record-key-is-pinned: --repin-record-key is allowed without keyryx"

  Scenario: the seal and the scheduled seal sign under the pin, and drop it when they do not sign
    Given seal_node in up.sh and trailryx_node in routines.sh
    When a call does not pass the pinned kid, keeps it when not signing, or the scheduled seal does not read the pin file
    Then record-key-is-pinned.sh fails
    # -> gates-have-teeth.sh "record-key-is-pinned: seal_node does not pass the pinned kid"
    # -> gates-have-teeth.sh "record-key-is-pinned: seal_node keeps the pin when not signing"
    # -> gates-have-teeth.sh "record-key-is-pinned: trailryx_node does not pass the pinned kid"
    # -> gates-have-teeth.sh "record-key-is-pinned: trailryx_node does not read the pin file"

  Scenario: signing starts only after the pin is taken, and no key set reaches a log
    Given the custody start in up.sh
    When the pin is never taken, or a log line names the key set
    Then record-key-is-pinned.sh fails
    # -> gates-have-teeth.sh "record-key-is-pinned: the pin is never taken before signing"
    # -> gates-have-teeth.sh "record-key-is-pinned: a log line names the key set"

  Scenario: the released TODO is gone, and a comment that names the pin is not a fault
    Given the seal in up.sh
    When the TODO for trailryx#112 is written back, or only a comment names the pin
    Then record-key-is-pinned.sh fails for the first and passes for the second
    # -> gates-have-teeth.sh "record-key-is-pinned: the released TODO is back"
    # -> gates-have-teeth.sh "record-key-is-pinned: a comment that names the pin is not a fault"

# @decided 2026-10-18 (paraphrased): keyryx's key custody and its witness of the record run in this launcher, from separate data and separate root keys, and wardryx signs its approvals through custody.
# @decided 2026-10-19 (paraphrased): the root keys are kept across runs, not minted fresh each run (the record-is-signed-by-default feature holds the rest).
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: keyryx runs in every install, with custody and the witness kept apart, and no key value leaves the launcher

  Custody holds the key wardryx signs approvals with. The witness reads the event
  streams from its own process and holds nothing custody signs with. This launcher
  gives custody and the witness separate data directories and separate root keys,
  kept across runs, writes the key files for the operator's user only, and never
  prints a key value.

  Scenario: custody and the witness are two processes with separate data and separate root keys
    Given the keyryx starts in up.sh
    When the witness takes custody's data directory or root key file, or the two data directories are the same
    Then keyryx-is-per-run.sh fails
    # -> gates-have-teeth.sh "keyryx-is-per-run: custody and witness share a data directory"
    # -> gates-have-teeth.sh "keyryx-is-per-run: custody takes its root key from a literal"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the witness takes custody's root key"

  Scenario: each root key is minted once, before custody starts, and refused when empty
    Given the custody and witness root keys in up.sh
    When a root key is a fixed string, has no refusal on an empty value, or is minted after custody has started
    Then keyryx-is-per-run.sh fails
    # -> gates-have-teeth.sh "keyryx-is-per-run: the custody root key is a fixed string, not minted"
    # -> gates-have-teeth.sh "keyryx-is-per-run: no refusal after the custody root key mint"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the custody root key is minted after custody starts"

  Scenario: no key value reaches the terminal, a log line or a command line
    Given every key value in up.sh
    When a value is logged, printed outside a file write, or passed on the command line of a keyryx or wardryx process
    Then keyryx-is-per-run.sh fails
    But a log line that names only a key file, or a comment that names a key, is not a fault
    # -> gates-have-teeth.sh "keyryx-is-per-run: the custody root key is logged"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the wardryx key is logged"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the custody root key is on the custody command line"
    # -> gates-have-teeth.sh "keyryx-is-per-run: a log line that names the root key file is not a fault"
    # -> gates-have-teeth.sh "keyryx-is-per-run: a comment that names the root key is not a fault"

  Scenario: the key files are readable by the operator's user only
    Given each key file written by up.sh
    When a key file is not made 0600, or the files are written under the default umask
    Then keyryx-is-per-run.sh fails
    # -> gates-have-teeth.sh "keyryx-is-per-run: the custody root key file is not made 0600"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the wardryx key file is not made 0600"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the key files are written under the default umask"

  Scenario: wardryx signs its approvals through custody and holds no approval secret for them
    Given the wardryx start in up.sh
    When it does not name the keyryx signer, still takes an approval secret, or the launcher does not check the binary names the signer
    Then keyryx-is-per-run.sh fails
    # -> gates-have-teeth.sh "keyryx-is-per-run: wardryx is started without the keyryx signer"
    # -> gates-have-teeth.sh "keyryx-is-per-run: wardryx keeps an approval secret"
    # -> gates-have-teeth.sh "keyryx-is-per-run: the wardryx binary is not checked for the signer"

  Scenario: the witness keeps its alerts beside its own data, off the shared bus
    Given the witness start in up.sh
    When its alert file is named inside the events directory
    Then keyryx-is-per-run.sh fails
    # -> gates-have-teeth.sh "keyryx-is-per-run: the witness alerts go onto the shared bus"

  Scenario: keyryx is built from a pinned commit, and a launcher that measured no keyryx start does not report OK
    Given the keyryx pin and the starts in up.sh
    When the pin is a branch name, or no custody start is left to judge
    Then keyryx-is-per-run.sh fails, and says it measured nothing when there is no start
    # -> gates-have-teeth.sh "keyryx-is-per-run: the pin is a branch name, not a commit"
    # -> gates-have-teeth.sh "keyryx-is-per-run: no custody start to judge"

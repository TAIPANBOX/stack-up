# @claude 2026-10-19: written for finding F-028 of the 2026-10-17 security review, from
# its paraphrased decision (close the agent-security findings, starting with the small
# ones). Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and
# scripts/features-are-bound.sh holds the binding both ways.
Feature: the dashboard reads the cloud key from the link's fragment, and the key is printed nowhere

  The dashboard link used to carry the cloud key in its query string, where the
  dashboard server's access log, the browser history and the Referer all keep it,
  and the summary printed the key as well. The link now carries the key after #key=,
  which a browser never sends to a server. The key itself is written to a file whose
  mode is 0600. The terminal shows that file's path and one line that opens it.

  Scenario: no link the launcher builds carries the key in its query string
    Given a dashboard link is read by a server that logs every query string
    When a link in up.sh puts the key after ? or &
    Then cloud-key-is-not-printed.sh fails and names the query string
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the key goes back into the dashboard query string"

  Scenario: the link the terminal prints does not carry the key
    Given the summary prints the dashboard link the operator opens
    When the link printed is the one that carries the key
    Then cloud-key-is-not-printed.sh fails and names the printed variable
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the link with the key becomes the printed link"

  Scenario: the cloud key never reaches a line the launcher prints
    Given the summary says where the cloud key is held
    When a printed line carries the key itself
    Then cloud-key-is-not-printed.sh fails
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the cloud key is printed on the summary line"
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the API hint prints the key itself"

  Scenario: the files that hold the key are made private in the same statement
    Given the key and the key-bearing link are written to the state directory
    When a file is written without umask 077 and chmod 600 in the same statement
    Then cloud-key-is-not-printed.sh fails
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the key file is written without chmod 600"
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the dashboard link is written under the default umask"

  Scenario: the dashboard link file holds the key after the fragment marker
    Given the dashboard reads its key from the fragment and nowhere else
    When the link file is written without the key
    Then cloud-key-is-not-printed.sh fails, because fewer than two files hold the key
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the dashboard link is written without the key"

  Scenario: the gate refuses to report OK when there is no key to judge
    Given the gate reads up.sh for the place the key is minted
    When the cloud key is never minted
    Then the gate says it measured nothing and fails
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: the key is never minted"

  Scenario: a comment that shows the forbidden form, and a printed file path, are not leaks
    Given a comment shows the forbidden query form, and a line prints the key file's path
    When the gate reads the launcher
    Then it passes
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: a comment that shows the forbidden form is not a fault"
    # -> gates-have-teeth.sh "cloud-key-is-not-printed: printing the key file's path is not a fault"

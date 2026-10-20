# @decided 2026-10-20 (paraphrased): the keyryx witness's findings reach the console and the
# notifier by giving those readers read-only access to the witness's own findings file; the
# witness is never given write access to the bus it witnesses. Each scenario is bound by name
# to a case in scripts/gates-have-teeth.sh.
Feature: the keyryx witness's findings reach heraldyx and a console, off the bus

  The witness reads every stream and notices when one was rewritten after it was seen. A
  witness that wrote the bus could add lines to the record it vouches for, so its findings
  are a file of their own, keyryx.ndjson, which heraldyx reads beside the bus and a console
  started by hand can read too.

  Scenario: the findings directory is the bus
    Given the witness's findings are in $STACK_UP_HOME/keyryx/alerts
    When that directory is made the events directory
    Then the gate fails, because the witness would write the bus it witnesses
    # -> gates-have-teeth.sh "keyryx-alerts: the witness's findings directory is the bus"

  Scenario: the findings directory is the witness's data directory
    Given the witness keeps its keys and its log in its data directory
    When the findings directory is made that directory
    Then the gate fails, because a reader would then be pointed at the witness's keys
    # -> gates-have-teeth.sh "keyryx-alerts: the witness's findings directory is its data directory"

  Scenario: the witness writes its findings back into its data directory
    Given the witness start names KEYRYX_WITNESS_ALERTS
    When it names a file in the witness's data directory again
    Then the gate fails, because heraldyx reads a different file
    # -> gates-have-teeth.sh "keyryx-alerts: the witness writes its findings back into its data directory"

  Scenario: the findings directory is never made
    Given agent-stack-go v2 creates a stream only in a directory its own user owns
    When up.sh stops making the findings directory
    Then the gate fails, because the witness would have nowhere to write
    # -> gates-have-teeth.sh "keyryx-alerts: the findings directory is never made"

  Scenario: heraldyx is not told to read the findings
    Given HERALDYX_EVENTS names the bus and the findings file
    When it names the bus alone
    Then the gate fails, because no finding would reach mail.txt
    # -> gates-have-teeth.sh "keyryx-alerts: heraldyx is not told to read the findings"

  Scenario: a console is not told where the findings are
    Given this launcher starts no console
    When the closing summary stops printing GENARYX_EVENTS_EXTRA with the file
    Then the gate fails, because a console started by hand would not show them
    # -> gates-have-teeth.sh "keyryx-alerts: the summary does not tell a console where the findings are"

  Scenario: another part of the launcher writes the findings file
    Given only the witness writes the findings file
    When routines.sh truncates it
    Then the gate fails and names the line
    # -> gates-have-teeth.sh "keyryx-alerts: another process is pointed at the findings file"

  Scenario: the findings file loses the stem heraldyx reads as keyryx
    Given heraldyx v0.8.0 reads source keyryx from a file named keyryx.ndjson
    When the file is named alerts.ndjson
    Then bus-files-match-sources.sh fails, because heraldyx would refuse every finding
    # -> gates-have-teeth.sh "bus-files-match-sources: the witness's findings file loses its keyryx stem"

  Scenario: heraldyx is pinned before the release that reads keyryx
    Given heraldyx v0.8.0 is the first release that reads and renders the keyryx source
    When the pin table names heraldyx v0.7.0
    Then bus-files-match-sources.sh fails and names the pin
    # -> gates-have-teeth.sh "bus-files-match-sources: the heraldyx pin goes back before the keyryx source"

  Scenario: a reworded comment is not a fault
    Given the gate reads up.sh with comments dropped
    When a comment beside the findings directory is reworded
    Then the gate still passes
    # -> gates-have-teeth.sh "keyryx-alerts: a comment beside the findings directory is not a fault"

  Scenario: the witness start is gone
    Given the gate judges the witness by its start in up.sh
    When the start is renamed away
    Then the gate reports that it measured nothing, and does not pass
    # -> gates-have-teeth.sh "keyryx-alerts: no witness start left to judge"

# @decided 2026-10-04, from the estate audit (wave 1): the launchers move to the
# 2026-10-04 releases. The gateway gets an operator ceiling on a run's budget
# (tokenfuse v1.5.0, invariant 73), a typed risk signal can reach wardryx through
# the MCP broker when the operator asks (wardryx v1.2.0, typryx v0.4.0), the event
# bus gets an on-box chain verifier (agent-stack-go v1.1.0), and heraldyx v0.3.0
# and idryx v1.1.0 refuse an event whose source its file may not carry.
# Scenarios are bound to cases in scripts/gates-have-teeth.sh by name, and
# scripts/features-are-bound.sh holds the binding both ways.
Feature: the launcher after the 2026-10-04 releases

  This launcher builds every plane from source and pins no tag, so what it can
  hold is that the settings it hands a plane are always handed, that an opt-in
  stays opt-in, and that the file names it configures are ones the readers
  accept. Each scenario below is a fault somebody could introduce on purpose or
  by accident, and a gate that must catch it.

  Scenario: a gateway start loses the run-budget ceiling
    Given every gateway start sets TOKENFUSE_MAX_RUN_BUDGET_USD from the ceiling
    When one start stops setting it
    Then run-budget-ceiling-is-set.sh fails and names the start
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: one gateway start drops the ceiling"

  Scenario: the ceiling is written as a literal
    Given the ceiling comes from the variable that --run-budget-ceiling fills
    When a start writes a fixed figure instead
    Then run-budget-ceiling-is-set.sh fails, because the flag could no longer change it
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the ceiling becomes a literal"

  Scenario: the default is no longer tokenfuse's own run budget
    Given the default ceiling is 5.00, which equals tokenfuse's DEFAULT_RUN_BUDGET
    When somebody changes it
    Then run-budget-ceiling-is-set.sh fails, because an ordinary run would no longer be unchanged
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the default changes from 5.00"

  Scenario: a ceiling the gateway would refuse is accepted
    Given the gateway exits 2 at start for zero, a word, a seventh decimal and a figure past its range
    When the flag stops refusing one of them
    Then run-budget-ceiling-is-set.sh fails, because the launcher would die after a long build
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the flag takes a zero"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the flag takes a figure past the gateway's range"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the flag takes a seventh decimal"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the validation is gone"

  Scenario: an old gateway would ignore a ceiling the operator asked for
    Given a gateway older than tokenfuse v1.5.0 does not read the setting and says nothing
    When the launcher stops asking whether the gateway names the setting, or stops refusing when told
    Then run-budget-ceiling-is-set.sh fails
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: an old gateway is judged to read the setting"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: the refusal of an old gateway the operator asked for is removed"

  Scenario: an unrelated variable and the broker start are not this gate's business
    Given the MCP broker is the same binary on a subcommand and holds no run budget
    When an unrelated variable is added to a start, or a second broker start appears
    Then run-budget-ceiling-is-set.sh still passes
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: an unrelated var added to the block"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: a second mcp-broker start is not mistaken for a gateway start"

  Scenario: no up.sh, no gateway start or no plan flag left to judge
    Given gateway starts are found by the binary variable at the command position
    When the file, the starts or the plan flag are gone
    Then run-budget-ceiling-is-set.sh says it measured nothing, never OK
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: no up.sh left to read"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: no gateway start left to judge"
    # -> gates-have-teeth.sh "run-budget-ceiling-is-set: up.sh has no --plan"

  Scenario: the typed risk signal is on without being asked
    Given the typed risk signal is off by default
    When the default flips
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the risk signal is on by default"

  Scenario: the risk signal is accepted with the typed mode off
    Given typed mode off starts no typryx, so there is nothing to give wardryx a signal
    When the refusal is removed
    Then typed-mode.sh fails saying the two contradict
    # -> gates-have-teeth.sh "typed-mode: the risk signal is accepted with typed mode off"

  Scenario: the risk signal is accepted with no wardryx to sit in front of
    Given --only money starts no wardryx
    When the refusal is removed
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the risk signal is accepted without wardryx"

  Scenario: the plan stops saying what leaves the machine
    Given under --typed-mode jev the tool name, arguments and target of every brokered call go to a hosted API
    When the plan stops saying so
    Then typed-mode.sh fails, because the operator would find out after the first call
    # -> gates-have-teeth.sh "typed-mode: the risk signal plan stops naming the hosted API"

  Scenario: the gateway is pointed at the proxy
    Given only the MCP broker is pointed at the proxy and the gateway keeps talking to wardryx directly
    When a gateway start takes the proxy's address
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the gateway is pointed at the proxy"

  Scenario: the broker is not pointed at the proxy, or its policy gate is left off
    Given the broker's policy gate needs its mode and its URL, and the URL is the proxy's
    When either is dropped or changed
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the broker is not pointed at the proxy"
    # -> gates-have-teeth.sh "typed-mode: the broker's policy gate is left off"

  Scenario: the proxy becomes a second writer of the service's files
    Given the proxy runs with no journal, no ledger, no key and no training log
    When it inherits the journal, or the service's training log
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the proxy keeps the service's journal"
    # -> gates-have-teeth.sh "typed-mode: the proxy inherits the training log"

  Scenario: the proxy binds beyond loopback, or is never registered
    Given the proxy binds loopback and is registered, so down.sh and the hold loop see it
    When it binds wider or the registration goes
    Then typed-mode.sh fails
    # -> gates-have-teeth.sh "typed-mode: the proxy binds beyond loopback"
    # -> gates-have-teeth.sh "typed-mode: the proxy is never registered"

  Scenario: rewording the proxy's launch line, or an extra variable on it, is not a fault
    Given the gate judges what is wired, not the sentence announcing it
    When the line is reworded or a spare variable is added
    Then typed-mode.sh still passes
    # -> gates-have-teeth.sh "typed-mode: the risk signal's launch line is reworded"
    # -> gates-have-teeth.sh "typed-mode: an unrelated variable is added to the proxy's launch"

  Scenario: no broker start left to judge
    Given the broker start is found at the command position
    When it is gone
    Then typed-mode.sh says its static half measured nothing
    # -> gates-have-teeth.sh "typed-mode: no broker start left to judge"

  Scenario: a standing break reads ok
    Given the verifier announces a break once and exits 0 on every run after the first
    When the routine records exit 0 as ok without reading the FAIL line
    Then chain-verify-routine.sh fails, because the history would be green over a cut chain
    # -> gates-have-teeth.sh "chain-verify-routine: a standing break is reported ok"

  Scenario: a new break or a failed run reads ok
    Given exit 1 is a new break and exit 2 is a run that could not do its job
    When either is recorded as ok
    Then chain-verify-routine.sh fails
    # -> gates-have-teeth.sh "chain-verify-routine: a new break is reported ok"
    # -> gates-have-teeth.sh "chain-verify-routine: a failed run is reported ok"

  Scenario: the verifier is run on an empty bus
    Given a fresh box has no event file yet and that is not an error
    When the routine stops skipping
    Then chain-verify-routine.sh fails
    # -> gates-have-teeth.sh "chain-verify-routine: an empty bus is run anyway"

  Scenario: the verifier is not scheduled by default, or runs at the seal's minute
    Given chain-verify is one of the six default routines, daily at 06:52
    When it leaves the defaults or moves to 06:57
    Then chain-verify-routine.sh fails
    # -> gates-have-teeth.sh "chain-verify-routine: it is dropped from the default timers"
    # -> gates-have-teeth.sh "chain-verify-routine: it moves to 06:57 with the seal"

  Scenario: the verifier's state is written into the bus
    Given the state file is not an event stream and the bus is flat
    When the state path moves into the events directory
    Then chain-verify-routine.sh fails
    # -> gates-have-teeth.sh "chain-verify-routine: the state file is written into the bus"

  Scenario: the routine is scheduled and components.json does not say so
    Given components.json declares every routine this launcher schedules
    When chain-verify is undeclared
    Then manifest-is-true.sh fails
    # -> gates-have-teeth.sh "manifest-is-true: a routine is scheduled and not declared"

  Scenario: no routine left to judge
    Given the routine is found by name in routines.sh
    When it is gone
    Then chain-verify-routine.sh says it measured nothing
    # -> gates-have-teeth.sh "chain-verify-routine: no routine left to judge"

  Scenario: a stream file is renamed to something the readers do not know
    Given heraldyx v0.3.0 and idryx v1.1.0 read <source>.ndjson as carrying <source>
    When the typryx journal, the broker's events or the verifier's stream get another name
    Then bus-files-match-sources.sh fails naming the unknown stream
    # -> gates-have-teeth.sh "bus-files-match-sources: the typryx journal is renamed"
    # -> gates-have-teeth.sh "bus-files-match-sources: the broker's events get a generic name"
    # -> gates-have-teeth.sh "bus-files-match-sources: the verifier's own stream is renamed"

  Scenario: idryx is loaded as a source its file may not carry
    Given --load tokenfuse:<path> reads tokenfuse.ndjson, which carries tokenfuse
    When the source or the file is changed so they disagree
    Then bus-files-match-sources.sh fails, because idryx would refuse every line
    # -> gates-have-teeth.sh "bus-files-match-sources: idryx is loaded with the wrong source"
    # -> gates-have-teeth.sh "bus-files-match-sources: idryx is pointed at another plane's file"

  Scenario: a stream the readers know is added
    Given the cloud's and broker's files carry tokenfuse and a plane's own file carries its own name
    When one of those is configured
    Then bus-files-match-sources.sh still passes
    # -> gates-have-teeth.sh "bus-files-match-sources: a stream the readers know is added"
    # -> gates-have-teeth.sh "bus-files-match-sources: the cloud's and broker's files carry tokenfuse"

  Scenario: no up.sh and no stream left to judge
    Given streams are found as $EVENTS_DIR/<name>.ndjson in the two launchers
    When the files or the streams are gone
    Then bus-files-match-sources.sh says it measured nothing, never OK
    # -> gates-have-teeth.sh "bus-files-match-sources: no up.sh left to read"
    # -> gates-have-teeth.sh "bus-files-match-sources: no stream left to judge"

  Scenario: a binding points at a case that does not exist
    Given every binding names a run_case in the mutation harness
    When a case is renamed or deleted
    Then features-are-bound.sh fails
    # -> gates-have-teeth.sh "features-are-bound: a binding names a case that does not exist"

  Scenario: a scenario is bound to nothing, or there is nothing to bind
    Given every scenario is bound to at least one case
    When a binding is removed, or the features are gone
    Then features-are-bound.sh fails, and says it measured nothing when there is nothing
    # -> gates-have-teeth.sh "features-are-bound: a scenario with no binding"
    # -> gates-have-teeth.sh "features-are-bound: no features left to read"
    # -> gates-have-teeth.sh "features-are-bound: no scenario left to bind"

# @claude 2026-10-19: written for wave 3, item W-UP.2 of the 2026-10-17 security review
# (finding F-016: the launcher built whatever a sibling checkout held). Scenarios are bound
# to cases in scripts/gates-have-teeth.sh by name; scripts/features-are-bound.sh holds the
# binding both ways.
Feature: every component the launcher builds is a release tag, at the commit the tag names

  The launcher used to build whatever a sibling checkout held, or main of a fresh clone. A
  component is now checked out at one release tag and the commit that tag names, from one
  table, and a checkout that is not that commit is refused. --from-main is the developer
  switch, and it says what it did.

  Scenario: a component is never pinned to a branch name
    Given the pin table names every component the launcher builds
    When one entry names a branch and not a release tag and a commit
    Then pins-are-release-tags.sh fails and names the entry
    # -> gates-have-teeth.sh "pins-are-release-tags: a component is pinned to a branch"

  Scenario: a pin is a full commit, not an abbreviation
    Given a pin names a release tag
    When the commit given is shorter than forty characters
    Then pins-are-release-tags.sh fails
    # -> gates-have-teeth.sh "pins-are-release-tags: a pin names a short commit"

  Scenario: a default build never reaches a sibling checkout
    Given a sibling checkout holds whatever commit its owner left there
    When a component is built without --from-main
    Then the build is taken from pinned_repo and not from locate_repo
    # -> gates-have-teeth.sh "pins-are-release-tags: a build reaches the sibling checkout"

  Scenario: a clone is made from the release tag
    Given a component is cloned for its pin
    When the clone does not name the tag
    Then pins-are-release-tags.sh fails
    # -> gates-have-teeth.sh "pins-are-release-tags: the clone drops its --branch tag"

  Scenario: a checkout that is not the pinned commit is refused
    Given the clone's HEAD is not the commit the table names
    When the launcher is about to build it
    Then the launcher refuses and does not build it
    # -> gates-have-teeth.sh "pins-are-release-tags: a checkout that is not the pinned commit is accepted"

  Scenario: no clone happens outside the pinned path
    Given the launcher clones components in one function
    When a clone is added anywhere else
    Then pins-are-release-tags.sh fails and names the line
    # -> gates-have-teeth.sh "pins-are-release-tags: a git clone is added outside the pinned path"

  Scenario: a component without a pin is not built
    Given verdryx publishes no release tag
    When the table loses an entry the launcher builds
    Then pins-are-release-tags.sh fails
    # -> gates-have-teeth.sh "pins-are-release-tags: a component is built with no pin"

  Scenario: the developer switch is a flag and says it is not a release
    Given --from-main builds sibling or main checkouts
    When the flag is removed or its warning stops saying so
    Then pins-are-release-tags.sh fails
    # -> gates-have-teeth.sh "pins-are-release-tags: --from-main is not a flag any more"
    # -> gates-have-teeth.sh "pins-are-release-tags: --from-main no longer says it is not a release"

  Scenario: a comment that names locate_repo is not a fault
    Given a comment explains that only --from-main reaches the sibling lookup
    When the gate reads the launcher
    Then it passes
    # -> gates-have-teeth.sh "pins-are-release-tags: a comment that names locate_repo is not a fault"

  Scenario: a component the launcher builds has an entry in the table
    Given the pin table is the one place a release is written
    When a component loses its entry
    Then pins-are-release-tags.sh fails and names the component
    # -> gates-have-teeth.sh "pins-are-release-tags: a component is built with no pin"

  Scenario: the gate refuses to pass when the pin table is not in the launcher
    Given the table is renamed in the launcher
    When the gate reads the launcher
    Then it says it measured nothing and does not report success
    # -> gates-have-teeth.sh "pins-are-release-tags: the pin table is renamed away"

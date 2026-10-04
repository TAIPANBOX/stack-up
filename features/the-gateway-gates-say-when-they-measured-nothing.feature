# @claude 2026-10-04: found by the estate audit's review of the declassify key
# (stack-up#40) and fixed here. Scenarios are bound to cases in
# scripts/gates-have-teeth.sh by name, and scripts/features-are-bound.sh holds the
# binding both ways.
Feature: the older gateway gates say when they measured nothing

  gateway-cache-is-off.sh and gateway-decides-its-upstream.sh find the gateway
  starts by reading the launch lines of up.sh through a here-document. That
  here-document always delivers one line, empty when nothing matched, so a
  launcher with no gateway start at all counted as one start and the
  "measured nothing" refusal could never fire: both exited 0 with "(1 checked)".
  A gate that cannot tell "found nothing wrong" from "found nothing" is the
  failure this repository's invariant 6 exists for.

  Scenario: the cache gate has no gateway start to judge
    Given gateway starts are found by the binary variable at the command position
    When both gateway launch lines are renamed away
    Then gateway-cache-is-off.sh fails saying it measured nothing, never "(1 checked)"
    # -> gates-have-teeth.sh "gateway-cache-is-off: no gateway start left to judge"

  Scenario: the upstream gate has no gateway start to judge
    Given gateway starts are found by the binary variable at the command position
    When both gateway launch lines are renamed away
    Then gateway-decides-its-upstream.sh fails saying it measured nothing, never "(1 checked)"
    # -> gates-have-teeth.sh "gateway-decides-its-upstream: no gateway start left to judge"

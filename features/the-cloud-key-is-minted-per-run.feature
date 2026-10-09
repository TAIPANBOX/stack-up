# @claude 2026-10-09: written from the request that removed the tokenfuse cloud's
# devkey fallback (tokenfuse#380) and asked the launchers to keep working with a
# random key per run. Scenarios are bound to cases in scripts/gates-have-teeth.sh
# by name, and scripts/features-are-bound.sh holds the binding both ways.
Feature: the tokenfuse cloud gets one random key per run, and nothing uses devkey

  tokenfuse removed the cloud's devkey fallback. A cloud started with
  TOKENFUSE_CLOUD_ALLOW_DEVKEY set now refuses to start, and an empty
  TOKENFUSE_CLOUD_KEYS authenticates nobody. So up.sh mints one key per run,
  starts the cloud with it, and uses the same key wherever it used to send the
  literal devkey: the gateway, the demo seed, the dashboard link and the hints
  it prints. An operator may bring their own key in STACK_UP_CLOUD_KEY.

  Scenario: the launcher no longer sets the removed devkey switch
    Given a cloud that refuses to start when TOKENFUSE_CLOUD_ALLOW_DEVKEY is set
    When the cloud start in up.sh sets that variable again
    Then cloud-key-is-per-run.sh fails and names the variable
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the cloud is started with the removed devkey switch"

  Scenario: the cloud holds a key generated for this run
    Given the cloud is started with TOKENFUSE_CLOUD_KEYS
    When that key set is empty, or a literal, or the key is a fixed value that is never generated
    Then cloud-key-is-per-run.sh fails
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the cloud is started with an empty key set"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the cloud is started with a literal key"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the key is a fixed value, not minted"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: no refusal after the mint"

  Scenario: the gateway reports to the cloud with the same key, from its environment
    Given the gateway ships every settled call to the cloud with TOKENFUSE_CLOUD_KEY
    When a gateway start uses the old literal, or hands the key to env as an argument
    Then cloud-key-is-per-run.sh fails
    # -> gates-have-teeth.sh "cloud-key-is-per-run: a gateway reports to the cloud with the old literal"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the gateway's cloud key is an argument to env"

  Scenario: the demo seed, the dashboard link and the printed hints use the same key
    Given the launcher talks to the cloud from its seed, its dashboard link and its summary
    When any of them presents devkey or another key
    Then cloud-key-is-per-run.sh fails
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the demo seed posts with the old literal"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the dashboard link carries another key"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the summary names bearer devkey again"

  Scenario: wardryx's own dev key is out of scope
    Given wardryx and scopyx keep their own dev-key mode on this launcher
    When a wardryx hint presents wardryx's devkey, or the cloud start grows an unrelated variable
    Then cloud-key-is-per-run.sh still passes
    # -> gates-have-teeth.sh "cloud-key-is-per-run: a wardryx hint with its own devkey is not the cloud's"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: an unrelated var added to the cloud start"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: the key spelled with braces"

  Scenario: the gate says when it had nothing to judge
    Given the gate finds the cloud start by the binary variable at the command position
    When up.sh is gone, or the cloud start is renamed away
    Then cloud-key-is-per-run.sh fails saying it measured nothing
    # -> gates-have-teeth.sh "cloud-key-is-per-run: no up.sh left to read"
    # -> gates-have-teeth.sh "cloud-key-is-per-run: no cloud start left to judge"

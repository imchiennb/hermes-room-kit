# Pointing the seats at your own provider

The shipped profiles default to a SwiCloud-compatible endpoint (`SWICLOUD_API_KEY`). Nothing in the kit is tied to it — each seat reads a normal Hermes profile config. Three files, three keys.

## The shape of the block

Each seat has its own `~/.hermes/profiles/<seat>/config.yaml`. The two parts that matter:

```yaml
providers:
  myprovider:                                  # <- any name you like
    name: My Provider                          # display label
    base_url: "https://api.example.com/v1"     # OpenAI-compatible base URL
    key_env: MY_PROVIDER_API_KEY               # reads this var from the seat's own .env
    api_mode: chat_completions                 # chat_completions | responses (provider dependent)
    default_model: "vendor/model-id"
    discover_models: true                      # set false if /models is not supported

model:
  default: "vendor/model-id"
  provider: custom:myprovider                  # must be custom:<provider key above>
```

Then give each seat the key — **secret scope is per profile**; `~/.hermes/.env` is not inherited:

```bash
printf 'MY_PROVIDER_API_KEY=sk-...\n' >> ~/.hermes/profiles/supervisor/.env
printf 'MY_PROVIDER_API_KEY=sk-...\n' >> ~/.hermes/profiles/lead/.env
printf 'MY_PROVIDER_API_KEY=sk-...\n' >> ~/.hermes/profiles/peer/.env
chmod 600 ~/.hermes/profiles/*/.env
```

Check it: `bash verify.sh` (asserts every seat has a non-empty key for its provider), then open a seat in Paseo.

## Two worked examples

**A hosted OpenAI-compatible gateway**

```yaml
providers:
  gw:
    name: Gateway
    base_url: "https://gateway.internal/v1"
    key_env: GATEWAY_API_KEY
    api_mode: chat_completions
    default_model: "<vendor>/<model>"
    discover_models: true
model:
  default: "<vendor>/<model>"
  provider: custom:gw
```

**Something local (vLLM / Ollama / LM Studio)** — no key needed, but Hermes still expects the env var to exist, so write a dummy value:

```yaml
providers:
  local:
    name: Local
    base_url: "http://127.0.0.1:8000/v1"
    key_env: LOCAL_API_KEY     # put LOCAL_API_KEY=none in the seat's .env
    api_mode: chat_completions
    default_model: "<local-model-id>"
    discover_models: false      # most local servers do not implement /models
model:
  default: "<local-model-id>"
  provider: custom:local
```

## Give the seats different models — on purpose

| Seat | Sizing guidance | Why |
|---|---|---|
| Supervisor | strong reasoning, long context | it frames the work, verifies claims and reports numbers; it writes almost no code |
| Lead | strongest coding model you can afford | it reads the repo, freezes the contract, reviews every artifact, integrates |
| Peer | fast + cheap, high turn budget | narrow bounded scope, heavy test/harness iteration; volume matters more than depth |

Peers are the ones that run many turns (this kit's own runs had peers at 2.9M and 5.7M input tokens on a cheap model). Putting your strongest model on the Peer seat is usually wasted money; putting a weak model on the Lead seat is where quality collapses.

## Changing the provider on an installed machine

```bash
# 1. edit ~/.hermes/profiles/<seat>/config.yaml (base_url, key_env, model…)
# 2. put the key in the seat's .env
# 3. verify
bash verify.sh
```

Notes and traps:

- **A running agent keeps the config it started with.** Change it while the room is idle; the next session of that seat picks it up.
- Re-running `install.sh` on a machine where the profile already exists and whose `config.yaml` differs **does not clobber it** without `--force`; it writes the kit copy to `config.yaml.room-kit-new` and warns. So local provider edits survive, and `--force` is the deliberate "take the kit version" switch.
- The kit's own `profiles/*/config.yaml` are the defaults shipped to a **fresh** machine. If you want your provider to be the default for everyone, edit those files, then `bash scripts/capture.sh`? No — capture pulls *from* the live machine, so edit the kit copies directly and commit them.
- `agent.max_turns` matters more than it looks: the shipped suggestion is 150 for Supervisor/Lead and 80 for Peer. A peer that runs out of turns mid-harness looks like a "blocked" peer.

# sessions.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first, and a spec per plugin manager |
| [quickstart.md](quickstart.md) | The shortest path: save a session, load it back |
| [configuration.md](configuration.md) | Every option and its default |
| [troubleshooting.md](troubleshooting.md) | What `:checkhealth` asks |

## Using it

| Page | Answers |
| --- | --- |
| [commands.md](commands.md) | `:Session <subcommand>`, one command, subcommand by subcommand |
| [BINDINGS.md](BINDINGS.md) | Every keymap, user command and autocommand — keys are off by default, so this is also where you learn what to switch on |
| [picker.md](picker.md) | `:SessionLoad` and its live preview |
| [session-scoping.md](session-scoping.md) | Two lighter alternatives to a full session, for when a whole one is more than you want |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each subcommand does, but how sessions, branches and scoping combine over a working day |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES.md](FEATURES.md) | Everything this plugin does, in one file: branch- and project-aware session management on top of Neovim's own `:mksession` |
| [git-integration.md](git-integration.md) | What `:Session toggle-track` is for — the cross-device sync dilemma, and which side of it you are choosing |
| [portability.md](portability.md) | Why `:mksession` is already half portable, and what has to be done about the other half |
| [metadata.md](metadata.md) | What the hidden `.{name}.json` holds when `metadata = true`, and what it buys |
| [api.md](api.md) | Every Lua function a config or another plugin can call |

# Commands

A line that starts with `/` is a command. Anything else is sent to the
assistant.

| Command         | Action                                          |
|-----------------|-------------------------------------------------|
| `/help`         | show the command list                           |
| `/init`         | analyse the project and write `CLAUDE.md`       |
| `/model [name]` | show the current model, or switch to `<name>`   |
| `/clear`        | reset the conversation                          |
| `/exit`         | quit (alias `/quit`)                            |

## /init

`/init` asks the agent to inspect the repository — its layout, build process
and conventions — and write a `CLAUDE.md` file. That file is then loaded as
project context on every later run.

## /model

`/model` with no argument prints the active model. `/model <name>` switches it;
the new model takes effect on the next message.

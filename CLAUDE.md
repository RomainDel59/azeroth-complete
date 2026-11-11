# Azeroth Complete

World of Warcraft addon for the WoW Forever client (interface 16001): a completionist tracker
for quests, professions, dungeons, raids, Legacy challenges and collections. The addon lives in
`AzerothComplete/`; `tools/` generates its data, `tests/` checks it offline, and `art/` holds
the source artwork.

## Language

Everything in the repository is written in English: code, comments, logs, documentation and
commit messages. The project is published for players of every language, so this rule takes
precedence over any default language set by a tool, command or personal convention, including
for commit messages and pull request titles. Users see the addon in the language of their game client, so every
user-facing string goes through the localization tables.

## Texts come from the game

Text about game content (quests, items, spells, zones, factions, encounters, collectibles) is
asked from the client at runtime, so that it is always the official wording in the player's
language. The generated data therefore carries identifiers and numbers. A text is shipped only
when no client API exposes it, or when the client depends on a server that may leave the
request unanswered; a shipped text exists for every supported language
(`Data/Strings.<locale>.lua`) and is the official wording, taken from the client tables of the
targeted build when they hold it, otherwise from an outside source that publishes that wording
for the Forever client, the generator stating which. The English names of the data serve
solely as the last fallback, for a text no source provides in the player's language. Interface labels
that the client defines as global strings are read from those globals before the addon's own
translations (`ns:GameLabel`).

## Localization

English (`Locales/enUS.lua`) is the reference and the fallback; every other locale file holds
the same keys, which the tests verify. A key added for one language is added for all of them in
the same change. French follows the official French terms of the game, checked against the
client's global strings rather than translated from English.

## Generated data

Files in `AzerothComplete/Data/` are produced by `python -I tools/build_data.py` and are never
edited by hand: a correction belongs in the generator, or upstream in QuestieDB. The generator
reads QuestieDB through `tools/questie_dump.lua`, which needs PUC Lua 5.1 (LuaJIT rejects the
size of QuestieDB's tables), and the client tables of the build given by `--build`. The quest
row layout and flags are shared between `tools/build_data.py` and `Core/Constants.lua`, which
change together.

## The Forever client

The Forever client runs the modern engine but does not expose every retail API, and some
functions keep their legacy names. Code never calls an uncertain API directly: `Core/Compat.lua`
wraps each one with its alternatives, and `Core/Diagnostics.lua` logs at login which of them
exist. A new client API is added to both. Masks that may exceed 32 bits (race masks include bits
32 and 33) are tested arithmetically with `ns.HasBit` and `ns.MasksIntersect`, never with the
client's 32-bit `bit` library.

## Robustness and logs

Event handlers, message handlers, list rows and view refreshes run through `ns:SafeCall`, so
one failure is logged with its traceback instead of breaking the window. The log is persisted
in `AzerothCompleteDB.log` (account saved variables), which the game writes on `/reload` and on
logout: `WTF/Account/<account>/SavedVariables/AzerothComplete.lua` under the game directory,
which is the `WOW_GAME_DIR` of the local `.env`. Reading that file is the way to investigate a
problem reported in the game; new behaviour that can fail logs enough context to be diagnosed
from the log alone.

## Architecture

`Core/` holds the services (lifecycle and events in `Init.lua`, saved variables, player, client
texts in `Names.lua`), `Modules/` the progress logic of each domain, independent of the
interface, and `UI/` the window: `Widgets.lua` provides every visual building block and the
views in `UI/Views/` only assemble them, so a visual change is made once in the widgets. Views
share the three-column layout of `Views/Layout.lua`. Modules notify the interface through
messages (`AC_PROGRESS_CHANGED`, `AC_NAMES_UPDATED`, `AC_COLLECTIONS_CHANGED`) rather than by
calling it.

## Tests

`lua5.1 tests/run.lua` (and `AC_TEST_LOCALE=frFR lua5.1 tests/run.lua`) loads the addon in TOC
order over `tests/wow_stub.lua`, logs in, opens the window and goes through every tab. The stub
accepts only real widget methods, so it catches calls the game would reject; a widget method or
client API newly used by the addon is added to the stub. Any logged error or missing translation
fails the run. On Windows, QuestieDB's bundled `tools/lua-binary/lua.exe` is a suitable Lua 5.1.
The game itself cannot be launched from here: in-game checks are done by the user, then read
back from the log. `tools/install.sh` (IntelliJ run configuration "Install on Forever") copies
the addon into the game as a release would, stamping the TOC with the commit; the game directory
is machine-specific and private, so it comes from `WOW_GAME_DIR` in the untracked `.env`, whose
template is `.env.example`.

## Releases

Work happens on `develop`; merging a pull request into `master` publishes a release whose
version is read from the pull request title (`.github/workflows/publication.yml`), and the
version replaces `@project-version@` in the packaged TOC.

## Licensing

The addon is GPL-3.0-or-later, as required by the QuestieDB data it embeds; generated files
state their sources in their header.

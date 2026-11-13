# Recipe format

A recipe is a JSON object:

```json
{
  "id": "videasy",
  "name": "Videasy",
  "description": "...",
  "rank": 70,
  "defaultEnabled": false,
  "credits": [{ "author": "...", "project": "...", "url": "...", "source": "...", "license": "..." }],
  "vars": { "api": "https://...", "servers": ["a", "b"] },
  "steps": [ ... ]
}
```

`id` is lower case and names the file. `requires` (optional) is the runtime level the recipe needs; a runtime with a lower `recipeRuntimeLevel` refuses the recipe. Level 2 added the `entries` filter, `bodyEncoding` and the `base64url` response. Level 3 added `headersAs`. `credits` is required: say where the steps come from. `liveSamples` (optional) replaces the sample movie and episode that `dart run bin/pack.dart live` runs, for a site that only has some titles. `vars` are visible to every step. The app adds its inputs (`type`, `id`, `tmdb`, `title`, `year`, ...) on top.

## Metadata

An app lists its sources from the recipes, so it needs no code per source. Four fields describe a recipe to the user:

- `name`: what the list shows.
- `description` (optional): one plain sentence under the name.
- `rank` (optional, a whole number): the default order. Lower comes first. A recipe without one comes after every ranked one, ordered by id.
- `defaultEnabled` (optional, true or false): whether the source starts on. Default `true`. The user can switch it either way; a choice the user made is never overwritten by the pack.

`Pack.infos` returns these as `RecipeInfo` objects, already sorted by `rank`, then id.

Ranks share one scale with the sources an app builds in. Built-in sources take 10 (Torrentio with Real-Debrid), 20 (VixSrc) and 90 (NoTorrent). Recipes start at 30 and go up in steps of 10, so a new recipe fits between two others without renumbering. A recipe that should come after NoTorrent uses 100 or more.

These fields are plain top-level keys, so they need no new runtime level. A runtime that does not know them ignores them: it reads only `id`, `requires`, `vars` and `steps`, and `validateRecipe` does not reject unknown keys. A wrong type is reported by `validateRecipe` and is read as absent by `RecipeInfo`.

## Values

Any string may contain `{{ expression }}`.

- A string that is only one expression keeps the type of the result (a number, a list, a map).
- A string with text around expressions is interpolated. A missing value becomes an empty string.
- An expression is a path (`server.name`, `servers.0`) or a quoted literal (`'x'`), followed by filters: `{{ id | split:':' | at:1 }}`. Quote an argument that contains `:` or `|`.
- `{ "$join": [...], "sep": " - ", "default": "..." }` joins the non-empty parts.
- `{ "$first": [...] }` is the first non-empty part.
- Maps and lists are evaluated entry by entry.

## Filters

| Filter | Result |
|---|---|
| `urlenc` | percent-encodes |
| `lower`, `trim`, `capitalize` | text |
| `split:sep` | list of strings |
| `at:n` | item `n` of a list, or nothing |
| `prefix:p` | the value if it starts with `p`, else empty |
| `digits` | the first run of digits, else empty |
| `default:x` | `x` when the value is empty |
| `map:a=b,c=d` | replaces listed values, passes the others |
| `height` | `720p` or `720` -> 720, `4K` -> 2160, anything else nothing |
| `entries` | a map as a list of `{key, value}`, to loop over keyed results |
| `json` | parses a JSON string, passes a structure through |
| `errorJson` | true for a short JSON object with an `error` key |

## Steps

Steps run in order. Any step may have `"when": { "value": ..., "equals": ..., "not": true }`: it runs only if the value is non-empty (or equals `equals`). `not` flips the test.

| `op` | Fields | Does |
|---|---|---|
| `set` | `as`, `value` | stores a value |
| `require` | `value`, optional `equals` and `not`, `msg` | stops the current scope when the test fails |
| `extract` | `from`, `regex` (one or a list, tried in order), `group` (default 1), `as` | stores the first match, or an empty string |
| `get`, `post` | `url`, `query`, `headers`, `body`, `bodyEncoding` (`base64url`), `response` (`text`, `json` or `base64url`), `as`, `headersAs` | sends a request and stores the reply |
| `foreach` | `in`, `as`, `steps`, `parallel`, `retryOnTimeout` | runs the steps for each item; a failed item is skipped |
| `tryEach` | `in`, `as`, `steps` | like `foreach`, in order, and stops at the first item that emits a stream |
| `emit` | `stream` or `subtitle` | adds a result; skipped when `url` is empty |
| `log` | `message` | writes a line to the log |

`query` values that are empty are left out, and the rest are percent-encoded. A map `body` is sent as JSON. With `bodyEncoding: base64url` the body is decoded and sent as raw bytes, and `response: base64url` stores the raw reply as base64url without padding, for APIs that are not text. A reply that is not 2xx stops the scope. `headersAs` stores the reply headers as a map with lower-case names, for example `{{h.x-user}}`. Each request has a timeout set by the app.

A stream has `title`, `url`, `height` (a number or nothing), `format` (optional: `hls`, `mp4` or `dash`, so a player does not have to guess from a URL without an extension) and `headers`, the headers a player must send. Streams with the same `title` are one server at several qualities. A subtitle has `url`, `lang` and `headers`; a url already emitted is dropped.

### What a recipe must emit for quality

An app that honours a quality cap needs to tell two kinds of stream apart, so every stream should carry `format` and, when it is known, `height`.

- **Ladder**: one link per quality, such as a progressive MP4 file or an HLS media playlist for a single quality. Emit one stream per quality with its `height` and the same `title` per server. The app plays the highest one at or below the cap, or the lowest one when all are above it. Do not sort the streams yourself; the app orders them.
- **Adaptive**: one manifest that holds several renditions, such as an HLS master playlist or a DASH manifest. Emit it with `format` and no `height`. The app applies the cap inside the player and never rewrites the manifest, so audio and subtitle renditions keep working.

A stream with no `height` and no `format` is treated as a ladder stream of unknown quality and stays where it is.

## Failure

A failure stops the current scope. At the top that gives an empty result with the reason in `error`. Inside `foreach` or `tryEach` it skips that item, and what the item emitted is discarded.

Anything a recipe cannot express, for example a site that needs a local hash or AES step, needs a change in the app instead.

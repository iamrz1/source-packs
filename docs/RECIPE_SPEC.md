# Recipe format

A recipe is a JSON object:

```json
{
  "id": "videasy",
  "name": "Videasy",
  "description": "...",
  "credits": [{ "author": "...", "project": "...", "url": "...", "source": "...", "license": "..." }],
  "vars": { "api": "https://...", "servers": ["a", "b"] },
  "steps": [ ... ]
}
```

`id` is lower case and names the file. `credits` is required: say where the steps come from. `vars` are visible to every step. The app adds its inputs (`type`, `id`, `tmdb`, `title`, `year`, ...) on top.

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
| `height` | `720p` -> 720, `4K` -> 2160, anything else nothing |
| `json` | parses a JSON string, passes a structure through |
| `errorJson` | true for a short JSON object with an `error` key |

## Steps

Steps run in order. Any step may have `"when": { "value": ..., "equals": ..., "not": true }`: it runs only if the value is non-empty (or equals `equals`). `not` flips the test.

| `op` | Fields | Does |
|---|---|---|
| `set` | `as`, `value` | stores a value |
| `require` | `value`, optional `equals` and `not`, `msg` | stops the current scope when the test fails |
| `extract` | `from`, `regex` (one or a list, tried in order), `group` (default 1), `as` | stores the first match, or an empty string |
| `get`, `post` | `url`, `query`, `headers`, `body`, `response` (`text` or `json`), `as` | sends a request and stores the reply |
| `foreach` | `in`, `as`, `steps`, `parallel`, `retryOnTimeout` | runs the steps for each item; a failed item is skipped |
| `tryEach` | `in`, `as`, `steps` | like `foreach`, in order, and stops at the first item that emits a stream |
| `emit` | `stream` or `subtitle` | adds a result; skipped when `url` is empty |
| `log` | `message` | writes a line to the log |

`query` values that are empty are left out, and the rest are percent-encoded. A map `body` is sent as JSON. A reply that is not 2xx stops the scope. Each request has a timeout set by the app.

A stream has `title`, `url`, `height` (a number or nothing) and `headers`, the headers a player must send. A subtitle has `url`, `lang` and `headers`; a url already emitted is dropped.

## Failure

A failure stops the current scope. At the top that gives an empty result with the reason in `error`. Inside `foreach` or `tryEach` it skips that item, and what the item emitted is discarded.

Anything a recipe cannot express, for example a site that needs a local hash or AES step, needs a change in the app instead.

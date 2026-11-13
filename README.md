# source-packs

Recipes that tell an app how to resolve streams from a few sites, and the Dart code that runs them. A fix to a site change is published as a new release of the pack. The app does not need a new version.

This is a public resource for learning how these request chains work. It is based on the work of others, credited below.

## What is in a pack

`pack.json` holds one recipe per provider (`cinejoy`, `moviebox`, `vidcore`, `vidfast`, `videasy`, `vidlink`), the pack `version` and the credits. It is attached to every [release](../../releases), with `pack.json.sha256`.

A recipe is plain JSON: variables and a list of steps (`get`, `post`, `extract`, `foreach`, `emit`, ...). See [docs/RECIPE_SPEC.md](docs/RECIPE_SPEC.md). A recipe only describes requests. Ranking, timeouts and which provider is enabled stay in the app.

## Download a pack

Take `pack.json` from the [latest release](../../releases/latest). To check the download, put `pack.json.sha256` next to it and run:

```shell
shasum -a 256 -c pack.json.sha256
```

You should see `pack.json: OK`.

## Use it in an app

1. Ask `https://api.github.com/repos/<owner>/source-packs/releases/latest` for the newest tag.
2. If `compareVersions(tag, installedVersion) > 0`, download `pack.json` from the release assets.
3. Read it with `Pack.parse(bytes)`. Ignore a pack with a `schema` you do not know, and run `validateRecipe` on each recipe before you save it.
4. Run a provider with `RecipeInterpreter(http).run(pack.providers['videasy']!, inputs)`.

`inputs` are strings: `type` (`movie` or `series`), `id` (`tt...` or `tt...:season:episode`), `tmdb`, `title`, `year`. A run never throws. It returns the streams, the subtitles, and an `error` when it found nothing. Keep the previous good pack on disk and fall back to code in the app when there is none.

Stream URLs from these sites expire (VidLink's last about an hour) and some are bound to the IP that resolved them. Never cache them. A stream's `headers` are exactly what the player must send: VidLink's file host rejects any Referer and any browser User-Agent, so its streams carry none, and the player must not add them.

A recipe may set `requires` to the runtime level it needs (`recipeRuntimeLevel`). A runtime that is too old refuses that recipe and runs the others, so check each recipe with `validateRecipe` and keep the valid ones.

## Change a recipe

1. Edit the file in `recipes/`. Every recipe must credit where its steps come from.
2. Run `dart test` and `dart run bin/pack.dart check`.
3. Run `dart run bin/pack.dart live` to try it against the real sites. It exits 1 when a provider returns no streams.
4. Open a PR with a conventional commit title (`fix: ...`, `feat: ...`).

A scheduled workflow runs the live check every day and opens an issue when a provider stops working.

## Releases

Merging to `main` updates a release PR (version and `CHANGELOG.md`, from the commit messages). Merging that PR tags a release. The release workflow then runs the tests, builds `pack.json` and attaches it with `pack.json.sha256`. To rebuild the assets of an existing tag, run the workflow by hand with that tag.

## Credits

The request chains follow the public samples in [smy778/EncDecEndpoints](https://github.com/smy778/EncDecEndpoints) (MIT): `samples/vidcore.py`, `samples/vidfast.py` and `samples/videasy.py`. The decryption those chains need is done by the `enc-dec.app` API that repository documents. The `moviebox` chain follows [faisaljs/Moviebox-API](https://github.com/faisaljs/Moviebox-API) (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE). The recipes follow work that is freely available from others and is shared here for educational purposes. Nothing here claims ownership of it.

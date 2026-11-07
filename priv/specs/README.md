# API specs

- `mastodon-openapi-abraham.json`: the Mastodon client API as OpenAPI 3.1, generated from the Mastodon documentation by [abraham/mastodon-openapi](https://github.com/abraham/mastodon-openapi). Commit `4bbdc3068bf3c0b71547f333f578241629845c1c` (2026-11-01), Mastodon 4.7.0. Licence GFDL-1.3 (derived from the Mastodon docs). `Bonfire.API.MastoCompat.Test.MastoSchema` validates Mastodon API responses against its `components.schemas`.
- `mastodon-openapi.yaml`: an older, incomplete spec from [samwightt/mastodon-openapi](https://github.com/samwightt/mastodon-openapi). Some schema moduledocs cite its line numbers.
- `gotosocial-swagger.json` and `gotosocial-swagger.yaml`: GoToSocial's Swagger 2.0 spec, which describes GoToSocial's own API. The coverage test uses it to list endpoints.
- `akkoma-openapi.json`: Akkoma's OpenAPI spec.

To refresh the Mastodon spec, replace the commit and run from this folder:

```sh
COMMIT=4bbdc3068bf3c0b71547f333f578241629845c1c
curl -sSfL -o mastodon-openapi-abraham.json "https://raw.githubusercontent.com/abraham/mastodon-openapi/$COMMIT/dist/schema.json"
```

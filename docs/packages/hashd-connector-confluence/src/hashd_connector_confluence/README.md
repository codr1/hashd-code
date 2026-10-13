# Confluence Cloud artifacts

Use `@confluence:123456` in an existing reference-enabled input.
Current shared input parsing accepts only slug arguments: a typed full URL is
cut at `https` and fails resolution. The resolver itself supports canonical
same-site page URLs, but that is not a working typed-input path until shared
intake supports full URL consumption. Page titles are not resource identity.
This provider reads one page; it does not search, follow short links, fetch
attachment bytes, render live macros, or write to Confluence.

Configure these keys through the existing project configuration editors or YAML:

```yaml
confluence:
  url: https://team.atlassian.net/wiki
  email: reader@example.com
  api_token: YOUR_API_TOKEN
  # Set explicitly for a scoped token; omit for a site-based unscoped token.
  cloud_id: YOUR_CLOUD_ID
```

`CONFLUENCE_URL`, `CONFLUENCE_EMAIL`, `CONFLUENCE_API_TOKEN`, and
`CONFLUENCE_CLOUD_ID` provide nonempty environment overrides on the server.
YAML credentials remain supported in solo mode. In team mode each person reads
with their own account instead -- `hashd connector login confluence --destination
https://team.atlassian.net`, their Atlassian email and an API token -- and the
connector is handed exactly that, ignoring the YAML and environment credentials.
A variable that displaces a value the YAML
did set is logged by name at load and named in a 401/403 read failure, so a
shadowed account does not report as a rejected token; values are never logged. The URL must use HTTPS, with no credentials,
query, fragment, nonstandard port, or path beyond `/wiki`; a bare site URL is
normalized to `/wiki`.

Both routes use email/API-token Basic authentication. Without `cloud_id`, the
request goes to the configured site's `/wiki/api/v2/pages/{id}`. With it, the
fixed endpoint is `https://api.atlassian.com/ex/confluence/{cloud_id}/wiki/api/v2/pages/{id}`.
There is no token detection, fallback, or alternate gateway. Scoped tokens need
`read:page:confluence`; the account must be able to view the page and its space.
Passwords, Data Center/PAT access and OAuth are outside this provider's scope.
This is user-configured access, not a hosted token-collection integration.

A scoped response must provide `_links.base` matching the configured site before
it can be attributed to that site. Atlassian describes this field as the site's
base URL but does not guarantee its presence. Missing binding evidence produces
an explicit unsupported/verification error. Redirects are refused.

Artifacts retain the complete JSON response and current storage XHTML, with a
plain-text projection that identifies conversion limitations. Unknown macros and
linked media remain visible as references, not claimed rendered content. Failed
conversion produces a new limitation notice, never an older readable page paired
with newer source. Failed fetches remain errors rather than silently using cache.
Explicit cache-only reads use the existing context-aware connector cache.

Identity and per-file digests feed the shared server-owned planning capture
contract. Cached files are inputs to that capture; this provider does not promise
immutable workflow snapshots or remote freshness from a digest.

Official references: [page API](https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-page/),
[Basic authentication](https://developer.atlassian.com/cloud/confluence/basic-auth-for-rest-apis/),
[scoped token routing](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/),
[Cloud page URLs/storage](https://support.atlassian.com/confluence/kb/find-the-page-storage-format-in-confluence-cloud-as-a-non-admin/).
Validated against documentation and offline fixtures; no real-instance validation
is claimed. The original #1608's CLI/admin/search/DC scope is not included.

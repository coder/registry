# Secret storage regression probe

This test-only extension calls the real `ExtensionContext.secrets` API with a synthetic value. It shows `Secret probe: persisted` or `Secret probe: missing` in the status bar. It can run in an untrusted test folder because it does not read or execute workspace files.

Package it with Python's standard library:

```sh
python3 package.py /tmp/registry-secret-storage-probe.vsix
```

Install the VSIX in the test workspace using VS Code's **Extensions: Install from VSIX** command. Test a Linux Docker workspace through Coder's app proxy, using a dedicated browser profile and an app subdomain. Keep the same VS Code commit for both launch modes.

1. With `use_cli = false`, run **Registry Probe: Store Secret**. Confirm the status is `persisted`; reload and confirm it changes to `missing`.
2. With `use_cli = true`, repeat the same operations. The status must remain `persisted` after reload, closing/reopening the tab, switching folders, and restarting the workspace while preserving its home directory.
3. Run **Registry Probe: Delete Secret**, then reload. The status must remain `missing`.
4. Check opening and editing a file, the terminal, extension installation, machine settings, app health, and startup script completion. Try starting another server on the same port; startup must fail visibly.

Use distinct hostnames for a direct-launch comparison: cookies are shared across ports on a host and can contaminate the baseline. A localhost test validates the underlying storage and server behavior, but does not replace an HTTPS Coder app test.

For the separate real-account test, run **Registry Probe: Sign in to GitHub** or **Registry Probe: Sign in to Microsoft**. These optional commands call the built-in authentication providers with `read:user` or Microsoft Graph `User.Read`, respectively. They display only the account label, never the access token, and do not enable Settings Sync. Sign-in and provider consent are interactive; use dedicated test accounts when available.

Reload and restart the workspace. Verify each account label remains visible, then sign out through VS Code's Accounts menu and confirm it stays signed out after reload. Passing the synthetic probe alone does **not** establish that either provider's complete OAuth flow works.

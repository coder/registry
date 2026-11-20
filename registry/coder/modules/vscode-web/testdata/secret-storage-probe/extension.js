const vscode = require("vscode");

exports.activate = async (context) => {
  const key = "persistence-probe";
  const value = "registry-test-secret-not-a-credential";
  const status = vscode.window.createStatusBarItem();
  status.command = "registryProbe.read";
  status.show();
  context.subscriptions.push(status);

  const read = async () => {
    const stored = await context.secrets.get(key);
    status.text = `Secret probe: ${stored === value ? "persisted" : "missing"}`;
  };
  for (const [name, operation] of Object.entries({
    store: () => context.secrets.store(key, value),
    read: async () => {},
    delete: () => context.secrets.delete(key),
  })) {
    context.subscriptions.push(
      vscode.commands.registerCommand(`registryProbe.${name}`, async () => {
        await operation();
        await read();
      }),
    );
  }
  await read();

  // Optional real-account checks. No token is displayed, logged or copied.
  for (const [provider, scopes] of Object.entries({
    github: ["read:user"],
    microsoft: ["https://graph.microsoft.com/User.Read"],
  })) {
    const accountStatus = vscode.window.createStatusBarItem();
    const readAccount = async () => {
      const session = await vscode.authentication.getSession(provider, scopes, {
        silent: true,
      });
      accountStatus.text = `${provider}: ${session ? session.account.label : "signed out"}`;
    };
    accountStatus.show();
    context.subscriptions.push(
      accountStatus,
      vscode.commands.registerCommand(`registryProbe.${provider}`, async () => {
        await vscode.authentication.getSession(provider, scopes, {
          createIfNone: {
            detail:
              "Verify that this account survives a browser reload. No settings synchronization is enabled.",
          },
        });
        await readAccount();
      }),
      vscode.authentication.onDidChangeSessions(async (event) => {
        if (event.provider.id === provider) await readAccount();
      }),
    );
    await readAccount();
  }
};

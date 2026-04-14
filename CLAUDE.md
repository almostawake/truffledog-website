# truffledog-website

## Shell config lives here (`z*` files)
`zshrc`, `zshrc-remote`, `zshenv`, `zshenv-remote` are the user's shell config. They are hosted on the website and fetched by the user's `~/.zshrc` / `~/.zshenv` on other machines at shell startup.

- If the user asks to change shell settings, aliases, PATH, prompt, etc. — edit the relevant `z*` file **in this repo**, don't touch `~/.zshrc` on the local machine.
- `-remote` files are the ones loaded remotely. The non-`-remote` variants are the local bootstrap that fetches them.
- Bump `ZSHRC_VERSION` at the top of `zshrc-remote` on any change (the prompt shows it, so the user can confirm the new version loaded).
- Commit and push on user direction, not automatically — remote machines pull on next shell start.

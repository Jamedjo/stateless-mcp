# Releasing

Both gems are released together, at the version in `stateless-mcp/lib/stateless_mcp/version.rb`, from a local checkout with `bundle exec rake release`. Review happens on GitLab; GitHub only mirrors `main` and the tags.

## One-off setup

1. On RubyGems.org, turn on multi-factor authentication at the **UI and API** level, so that `gem push` needs a one-time code. See [Setting up multi-factor authentication](https://guides.rubygems.org/setting-up-multifactor-authentication/).
2. Store the account's OTP secret on the YubiKey, under the name the release task looks up:

   ```sh
   ykman oath accounts add rubygems.org
   ```

   It prompts for the secret, which RubyGems.org shows as a key while MFA is being set up.

Both gemspecs set `rubygems_mfa_required`, so RubyGems.org refuses any push of these gems without a one-time code.

## Each release

1. Bump `VERSION` in `stateless-mcp/lib/stateless_mcp/version.rb`, and the version in `stateless-mcp/spec/stateless_mcp_spec.rb`.
2. In each gem's `CHANGELOG.md`, move the Unreleased entries under the new version with today's date, and update the compare links at the bottom. A gem with no changes gets an entry saying it was released to keep the versions in step.
3. Merge on GitLab.
4. Sync `main` to GitHub: `git fetch gitlab && git push github gitlab/main:main`.
5. Release from the merged commit: `git checkout --detach gitlab/main && bundle exec rake release`.

`rake release` refuses to start unless the working tree is clean, HEAD is `gitlab/main`, and the version's tag doesn't exist yet. It then:

1. Builds `stateless-mcp`, then `stateless-mcp-rails`, into `pkg/`.
2. Tags `v<version>` and pushes the tag to `gitlab` and `github`.
3. Pushes `stateless-mcp`, then `stateless-mcp-rails`, to RubyGems.org, reading a fresh code from the YubiKey with `ykman oath accounts code -s rubygems.org` before each push. Without `ykman`, `gem push` asks for the code.

If a gem push fails after the tag is pushed, the task prints the `gem push` commands still to run.

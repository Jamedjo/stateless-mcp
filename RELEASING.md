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
5. Check out the merged commit, for example `git switch main && git pull`, and run `bundle exec rake release`.

`rake release` releases the commit checked out, from any branch. A fix for an older version, or an embargoed security fix, can be released from its own branch without going through `main`. It warns when the commit isn't on any GitLab branch, and refuses a version whose tag is already on another commit. It then:

1. Exports the commit with `git archive`, so uncommitted and ignored files never reach a gem.
2. Builds `stateless-mcp`, then `stateless-mcp-rails`, from the export into `pkg/`, dated by the commit so the same commit always builds the same gems.
3. Tags the commit `v<version>`, and pushes the tag to `gitlab` and `github`.
4. Pushes `stateless-mcp`, then `stateless-mcp-rails`, to RubyGems.org. Before each push it reads a fresh code from the YubiKey with `ykman oath accounts code -s rubygems.org`, and the key needs a touch. Without `ykman`, `gem push` asks for the code.

If it stops part way, for instance when the YubiKey isn't touched in time, run it again. It keeps the tag already on the commit and pushes only the gems RubyGems.org doesn't have yet.

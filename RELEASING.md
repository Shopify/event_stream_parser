# Releasing `event_stream_parser`

Publishing a GitHub release runs [`.github/workflows/release.yml`](.github/workflows/release.yml),
which publishes the gem through [RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/).

## Release a version

1. Update `VERSION` in [`lib/event_stream_parser/version.rb`](lib/event_stream_parser/version.rb)
   and keep `# Unreleased` in [`CHANGELOG.md`](CHANGELOG.md).
   Add the version heading below it, move the released entries under that heading, and leave Unreleased empty.
2. Open a PR for those changes, let CI pass, and merge it to `main`.
3. Publish a GitHub release with tag `v<version>` at the merged commit. The tag must match `VERSION`.
4. Check that the release workflow passes and the version appears on [RubyGems.org](https://rubygems.org/gems/event_stream_parser).

# Contributing to event_stream_parser

We love bug reports and PRs to make this library as spec-compliant and robust as possible.

This library aims to stay as simple and solely focused on parsing the EventStream format as possible. If you have a feature request that would make this library more complex, please consider forking it instead.

## Standards

- PR should explain what the feature does, and why the change exists.
- Code _must_ pass tests and linting.
- New tests should be added to cover new functionality or to demonstrate bugs.
- Be consistent. Write clean code that follows [Ruby community standards](https://github.com/bbatsov/ruby-style-guide).
- Code should be generic and reusable.

If you're stuck, ask questions!

## How to contribute

1. Fork it ( https://github.com/Shopify/event_stream_parser/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Testing

```sh
rake test
```

### Linting

```sh
bundle exec rubocop
```

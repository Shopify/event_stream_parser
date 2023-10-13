# EventStreamParser

A lightweight, fully spec-compliant parser for the
[EventStream](https://www.w3.org/TR/eventsource/) format.

It only deals with the parsing of events and not any of the client/transport
aspects. This is not an Server-Sent Events (SSE) client.

Under the hood, it's a stateful parser that receives chunks (that are emitted
from an HTTP client, for example) and emits events as it parses them. But it
remembers the last event id and reconnection time and keeps emitting them as
long as they are not overwritten by new ones.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'event_stream_parser'
```

And then execute:

```sh
bundle
```

Or install it yourself as:

```sh
gem install event_stream_parser
```

## Usage

Create a new Parser and give it a block to receive events:

```rb
parser = EventStreamParser::Parser.new

parser.feed do |type, data, id, reconnection_time|
  puts "Event type: #{type}"
  puts "Event data: #{data}"
  puts "Event id: #{data}"
  puts "Reconnection time: #{reconnection_time}"
end
```

Then, feed it chunks as they come in:

```rb
do_something_that_yields_chunks do { |chunk| parser.feed(chunk) }
```

Or use the `stream` method to generate a proc that you can pass to a chunk
producer:

```rb
parser_stream = parser.stream do |type, data, id, reconnection_time|
  puts "Event type: #{type}"
  puts "Event data: #{data}"
  puts "Event id: #{data}"
  puts "Reconnection time: #{reconnection_time}"
end

do_something_that_yields_chunks(&parser_stream)
```

## Development

After checking out the repo:

1. Run `bundle` to install dependencies.
2. Run `rake test` to run the tests.
3. Run `rubocop` to run Rubocop.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/Shopify/event_stream_parser. This project is intended to be a
safe, welcoming space for collaboration, and contributors are expected to adhere
to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in this repository is expected to follow the
[code of conduct](https://github.com/Shopify/event_stream_parser/blob/master/CODE_OF_CONDUCT.md).

# frozen_string_literal: true

require "test_helper"

describe EventStreamParser::Parser do
  before do
    @event_stream_parser = EventStreamParser::Parser.new
    @events = []
  end

  describe "feed" do
    it "doesn't yield until empty line" do
      feed <<~CHUNK
        data: hello
      CHUNK

      expect []
    end

    it "doesn't yield with just an event field" do
      feed <<~CHUNK
        event: greeting

        #
      CHUNK

      expect []
    end

    it "doesn't yield with just an id field" do
      feed <<~CHUNK
        id: event-1

        #
      CHUNK

      expect []
    end

    it "doesn't yield with just a retry field" do
      feed <<~CHUNK
        retry: 300

        #
      CHUNK

      expect []
    end

    it "yields with a data field" do
      feed <<~CHUNK
        data: hello

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
      ]
    end

    it "yields with data and event fields" do
      feed <<~CHUNK
        event: greeting
        data: hello

        #
      CHUNK

      expect [
        ["greeting", "hello", "", nil],
      ]
    end

    it "yields with data and id fields" do
      feed <<~CHUNK
        id: event-1
        data: hello

        #
      CHUNK

      expect [
        ["", "hello", "event-1", nil],
      ]
    end

    it "yields with data and retry fields" do
      feed <<~CHUNK
        retry: 300
        data: hello

        #
      CHUNK

      expect [
        ["", "hello", "", 300],
      ]
    end

    it "yields with all fields" do
      feed <<~CHUNK
        retry: 300
        id: event-1
        event: greeting
        data: hello

        #
      CHUNK

      expect [
        ["greeting", "hello", "event-1", 300],
      ]
    end

    it "ignores unknown fields" do
      feed <<~CHUNK
        foo: 1
        data: hello

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
      ]
    end

    it "ignores empty lines" do
      feed <<~CHUNK

        #
      CHUNK

      expect []
    end

    it "ignores lines starting with a colon" do
      feed <<~CHUNK
        :comment

        #
      CHUNK

      expect []
    end

    it "joins adjacent data fields with a new line" do
      feed <<~CHUNK
        data: hello
        data: world

        #
      CHUNK

      expect [
        ["", "hello\nworld", "", nil],
      ]
    end

    it "treats CR as line delimiter" do
      feed <<~CHUNK.split("\n").join("\r")
        event: greeting
        data: hello
        data: world

        #
      CHUNK

      expect [
        ["greeting", "hello\nworld", "", nil],
      ]
    end

    it "treats CRLF as line delimiter" do
      feed <<~CHUNK.split("\n").join("\r\n")
        event: greeting
        data: hello
        data: world

        #
      CHUNK

      expect [
        ["greeting", "hello\nworld", "", nil],
      ]
    end

    it "yields multiple events" do
      feed <<~CHUNK
        data: hello

        data: world

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
        ["", "world", "", nil],
      ]
    end

    it "resets event type" do
      feed <<~CHUNK
        event: greeting
        data: hello

        data: world

        #
      CHUNK

      expect [
        ["greeting", "hello", "", nil],
        ["", "world", "", nil],
      ]
    end

    it "preserves last event id" do
      feed <<~CHUNK
        id: event-1
        data: hello

        data: world

        id: event-2
        data: bye

        #
      CHUNK

      expect [
        ["", "hello", "event-1", nil],
        ["", "world", "event-1", nil],
        ["", "bye", "event-2", nil],
      ]
    end

    it "preserves reconnection time" do
      feed <<~CHUNK
        data: hello

        retry: 300
        data: world

        data: bye

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
        ["", "world", "", 300],
        ["", "bye", "", 300],
      ]
    end

    it "ignores non-decimal retry field value" do
      feed <<~CHUNK
        retry: a1
        data: hello

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
      ]
    end

    it "ignores id field value with a null" do
      feed <<~CHUNK
        id: event-\u0000
        data: hello

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
      ]
    end

    it "treats line without a colon as empty field" do
      feed <<~CHUNK
        data

        id: event-1
        data: hello

        id
        data: world

        #
      CHUNK

      expect [
        ["", "", "", nil],
        ["", "hello", "event-1", nil],
        ["", "world", "", nil],
      ]
    end

    it "treats a single space after colon as optional" do
      feed <<~CHUNK.gsub("|", "")
        data:hello

        data: world

        data:  bye

        data:

        data: |

        data:  |

        #
      CHUNK

      expect [
        ["", "hello", "", nil],
        ["", "world", "", nil],
        ["", " bye", "", nil],
        ["", "", "", nil],
        ["", "", "", nil],
        ["", " ", "", nil],
      ]
    end

    it "yields events on subsequent calls" do
      chunks = <<~CHUNK.split("\n").map { |line| line + "\n" }
        event: greeting
        data: hello
        data: world

        event: farewell
        data: bye

        #
      CHUNK

      chunks.each { |chunk| feed(chunk) }

      expect [
        ["greeting", "hello\nworld", "", nil],
        ["farewell", "bye", "", nil],
      ]
    end

    describe "stream" do
      it "yields events" do
        chunks = <<~CHUNK.split("\n").map { |line| line + "\n" }
          event: greeting
          data: hello
          data: world

          event: farewell
          data: bye

          #
        CHUNK

        stream chunks

        expect [
          ["greeting", "hello\nworld", "", nil],
          ["farewell", "bye", "", nil],
        ]
      end

      it "yields events with non-new-line chunk boundaries" do
        chunks = <<~CHUNK.split("e").map { |line| line + "e" }
          event: greeting
          data: hello
          data: world

          event: farewell
          data: bye
          data: world

          #
        CHUNK

        stream chunks

        expect [
          ["greeting", "hello\nworld", "", nil],
          ["farewell", "bye\nworld", "", nil],
        ]
      end

      it "strips BOM from first chunk" do
        chunks = <<~CHUNK.split("\n").map { |line| line + "\n" }
          data: hello
          data: world

          #
        CHUNK

        chunks[0] = chunks[0].prepend(EventStreamParser::Parser::UTF_8_BOM)

        stream chunks

        expect [
          ["", "hello\nworld", "", nil],
        ]
      end
    end
  end

  private

  def feed(chunk)
    @event_stream_parser.feed(chunk) { |*event| @events << event }
  end

  def stream(chunks)
    stream = @event_stream_parser.stream { |*event| @events << event }
    chunks.each { |chunk| stream.call(chunk) }
  end

  def expect(events)
    assert_equal(events, @events)
  end
end

# class EventStreamParserTest < Minitest::Test



# end

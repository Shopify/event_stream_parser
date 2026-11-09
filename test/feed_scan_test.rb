# frozen_string_literal: true

require 'test_helper'

class DelimiterScanBuffer < String
  attr_reader :scanned_bytes

  def initialize
    super
    @scanned_bytes = 0
  end

  def slice!(*args)
    @scanned_bytes += bytesize
    super
  end
end

describe EventStreamParser::Parser do
  it 'keeps delimiter scan work linear across incomplete chunks' do
    work = [32, 128].map do |count|
      parser = EventStreamParser::Parser.new
      buffer = DelimiterScanBuffer.new
      parser.instance_variable_set(:@buffer, buffer)
      count.times { parser.feed('x' * 1024) }
      scanned_bytes = buffer.scanned_bytes
      assert_nil buffer.slice!(/[\r\n]/)
      assert_operator buffer.scanned_bytes, :>, scanned_bytes
      scanned_bytes
    end

    assert_operator work.last, :<=, work.first * 4
  end

  it 'parses the same events with whole, fixed and random chunks' do
    input = "retry: 250\r\nid: first\r\nevent: update\r\ndata: coffee\r\ndata: tea\r\n\r\n" \
            "data: second\n\nid: next\rdata: third\r\rdata: final\n\n"
    expected = [
      ['update', "coffee\ntea", 'first', 250],
      ['', 'second', 'first', 250],
      ['', 'third', 'next', 250],
      ['', 'final', 'next', 250]
    ]

    assert_equal expected, parse_chunks([input])
    (1..16).each do |size|
      chunks = input.bytes.each_slice(size).map { |bytes| bytes.pack('C*') }
      assert_equal expected, parse_chunks(chunks)
    end

    random = Random.new(1234)
    20.times do
      offset = 0
      chunks = []
      while offset < input.bytesize
        chunk = input.byteslice(offset, random.rand(1..19))
        chunks << chunk
        offset += chunk.bytesize
      end
      assert_equal expected, parse_chunks(chunks)
    end
  end

  it 'handles split CRLF with empty chunks between its bytes' do
    chunks = ["data: hello\r", '', '', "\n", '', "event: greeting\r", '', "\n\r", '', "\n"]

    assert_equal [['greeting', 'hello', '', nil]], parse_chunks(chunks)
  end

  it 'processes a lone CR at the end of a chunk immediately' do
    parser = EventStreamParser::Parser.new
    events = []
    callback = proc { |*event| events << event }

    parser.feed("data: first\r", &callback)
    assert_empty events
    parser.feed("\r", &callback)
    assert_equal [['', 'first', '', nil]], events
    parser.feed('', &callback)
    parser.feed("data: second\r\r", &callback)
    assert_equal [['', 'first', '', nil], ['', 'second', '', nil]], events
  end

  it 'preserves UTF-8 data and leaves frozen chunks unchanged' do
    chunks = ['data: café', ' and 茶', "\n\n"]
    original = chunks.map(&:dup)

    events = parse_chunks(chunks)

    assert_equal [['', 'café and 茶', '', nil]], events
    assert_equal Encoding::UTF_8, events.first[1].encoding
    assert_equal original, chunks
  end

  it 'handles binary chunks split inside multibyte characters' do
    input = "data: café and 茶\r\n\r\n".b
    chunks = input.bytes.map { |byte| byte.chr.freeze }
    events = parse_chunks(chunks)

    assert_equal [['', 'café and 茶'.b, '', nil]], events
    assert_equal Encoding::ASCII_8BIT, events.first[1].encoding
  end

  it 'finishes a long line and retains the next incomplete line' do
    chunks = ['data: ', 'a' * 4096, 'b' * 4096, "\n\ndata: ", 'c' * 4096, "\r\n\r\n"]

    assert_equal [['', "#{'a' * 4096}#{'b' * 4096}", '', nil], ['', 'c' * 4096, '', nil]], parse_chunks(chunks)
  end

  it 'resumes buffered events after a callback breaks' do
    ['', 'tail'].each do |chunk|
      parser = EventStreamParser::Parser.new
      events = []
      result = parser.feed("data: first\n\ndata: second\n\n") do |*event|
        events << event
        break :paused
      end

      assert_equal :paused, result
      parser.feed(chunk) { |*event| events << event }
      assert_equal [['', 'first', '', nil], ['', 'second', '', nil]], events
    end
  end

  it 'resumes buffered events after a callback raises' do
    ['', 'tail'].each do |chunk|
      parser = EventStreamParser::Parser.new
      events = []
      assert_raises(RuntimeError) do
        parser.feed("data: first\n\ndata: second\n\n") do |*event|
          events << event
          raise 'stop'
        end
      end

      parser.feed(chunk) { |*event| events << event }
      assert_equal [['', 'first', '', nil], ['', 'second', '', nil]], events
    end
  end

  it 'preserves incomplete UTF-8 errors and resumes after the character is completed' do
    parser = EventStreamParser::Parser.new
    events = []
    incomplete = [0xc3].pack('C*').force_encoding(Encoding::UTF_8)
    completion = [0xa9, 10, 10].pack('C*').force_encoding(Encoding::UTF_8)
    parser.feed('data: caf')

    assert_raises(ArgumentError) { parser.feed(incomplete) }
    assert_raises(ArgumentError) { parser.feed('') }
    parser.feed(completion) { |*event| events << event }

    assert_equal [['', 'café', '', nil]], events
    assert_equal Encoding::UTF_8, events.first[1].encoding
  end

  it 'uses the buffer encoding when an empty chunk has a different encoding' do
    chunks = ['data: hello', ''.encode(Encoding::UTF_16LE), "\n\n"]

    assert_equal [['', 'hello', '', nil]], parse_chunks(chunks)
  end

  it 'returns nil after normally completed feeds' do
    parser = EventStreamParser::Parser.new

    assert_nil parser.feed('data: hello')
    assert_nil(parser.feed("\n\n") { |_type, _data, _id, _time| nil })
    assert_nil parser.feed('')
  end

  def parse_chunks(chunks)
    parser = EventStreamParser::Parser.new
    events = []
    chunks.each { |chunk| parser.feed(chunk) { |*event| events << event } }
    events
  end
end

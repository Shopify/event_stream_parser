# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require 'strscan'

describe EventStreamParser::Parser do
  it 'keeps delimiter scan work linear across incomplete chunks' do
    work = [32, 128].map do |count|
      parser = EventStreamParser::Parser.new
      scanned_bytes { count.times { parser.feed('x' * 1024) } }
    end

    assert_operator(scanned_bytes { StringScanner.new('x').scan_until(/[\r\n]/) }, :>, 0)
    assert_operator work.last, :<=, work.first * 4
  end

  it 'keeps buffer work linear in the lines of one chunk' do
    work = [1_000, 4_000].map do |count|
      parser = EventStreamParser::Parser.new
      events = 0
      bytes = buffer_work(parser) { parser.feed("data: x\n\n" * count) { events += 1 } }
      assert_equal count, events
      bytes
    end

    assert_operator work.first, :>, 0
    assert_operator work.last, :<=, work.first * 4
  end

  it 'continues after the last processed line when the block feeds more data' do
    parser = EventStreamParser::Parser.new
    events = []
    more = ["ur\r\r"]
    # After a CR, the nested call looks for the LF of a split CRLF at the front
    # of the buffer, so the processed blank line must not be there to match.
    # The nested call stops at its first event; the outer call takes the rest.
    parser.feed("\ndata: one\r\rdata: two\r\rdata: three\r\rdata: fo") do |*event|
      events << event
      assert_operator events.size, :<=, 4, 'an event was processed again'
      parser.feed(more.shift.to_s) do |*nested|
        events << nested
        break
      end
    end

    assert_equal(%w[one two three four].map { |data| ['', data, '', nil] }, events)
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

    mutable_chunks = ['data: hello'.b, ''.encode(Encoding::UTF_16LE), "\n\n".b]
    encodings = mutable_chunks.map(&:encoding)
    parse_chunks(mutable_chunks)
    assert_equal encodings, mutable_chunks.map(&:encoding)
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

  # Counts the bytes that each line search offers its scanner, only while the block runs.
  def scanned_bytes(&block)
    scanned = 0
    new_scanner = StringScanner.method(:new)
    counting_scanner = lambda do |string|
      scanner = new_scanner.call(string)
      scanner.define_singleton_method(:scan_until) do |pattern|
        scanned += rest_size
        super(pattern)
      end
      scanner
    end
    StringScanner.stub(:new, counting_scanner, &block)
    scanned
  end

  # Sums the size of the parser's buffer at each method call on it, only while the block runs.
  def buffer_work(parser, &block)
    buffer = parser.instance_variable_get(:@buffer)
    work = Hash.new(0)
    trace = TracePoint.new(:c_call) { |call| work[call.self.equal?(buffer)] += buffer.bytesize }
    trace.enable(&block)
    work[true]
  end
end

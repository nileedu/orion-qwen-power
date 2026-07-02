import test from 'node:test';
import assert from 'node:assert';
import { QwenStreamParser } from '../utils/qwen-stream-parser.js';

// Regression tests for docs/QWEN_CODER_ROOT_CAUSE.md.
//
// Neither bug fixed here was proven to be THE cause of the historical
// "content is only a closing marker" symptom observed against the live
// qwenproxy backend (extensive empirical testing — 16+ real API calls across
// 4 request paths, short and long prompts, streaming and non-streaming,
// single and 3x-repeated — could not reproduce that exact symptom under
// current conditions). Both are real, independently-verifiable bugs found by
// static code audit and are fixed as defensive correctness improvements.

function sseLine(content: string): string {
  return JSON.stringify({
    response_id: 'resp-1',
    choices: [{ delta: { phase: 'answer', content } }],
  });
}

test('Achado #1: tool-call lead-in text is not duplicated or left with a residual <tool_call> tag', () => {
  const tools = [{ type: 'function' as const, function: { name: 'foo', description: '', parameters: { type: 'object', properties: {} } } }];
  const parser = new QwenStreamParser('ui-session-1', { tools });

  // One chunk containing lead-in text AND a complete, well-formed tool call.
  const chunk = 'Hello <tool_call>{"name":"foo","arguments":{}}</tool_call>';
  parser.parseLine(sseLine(chunk));

  // Before the fix: lastFullContent ended up as
  // "Hello Hello <tool_call>{\"name\":\"foo\",\"arguments\":{}}</tool_call>"
  // (lead-in duplicated AND the raw tag never stripped).
  assert.strictEqual(parser.answerContent, 'Hello ', 'lastFullContent must contain only the clean lead-in text, once, with no tool-call tag residue');
  assert.ok(!parser.answerContent.includes('<tool_call'), 'no raw <tool_call> tag should ever reach lastFullContent when a tool call was parsed successfully');
});

test('Achado #1: multiple sequential tool calls do not accumulate tag residue', () => {
  const tools = [{ type: 'function' as const, function: { name: 'bar', description: '', parameters: { type: 'object', properties: {} } } }];
  const parser = new QwenStreamParser('ui-session-2', { tools });

  parser.parseLine(sseLine('Step one. <tool_call>{"name":"bar","arguments":{"x":1}}</tool_call> Step two. '));
  parser.parseLine(sseLine('<tool_call>{"name":"bar","arguments":{"x":2}}</tool_call> Step three.'));

  assert.strictEqual(parser.answerContent, 'Step one.  Step two.  Step three.');
  assert.ok(!parser.answerContent.includes('<tool_call'));
  assert.ok(!parser.answerContent.includes('arguments'));
});

test('Achado #2: long non-streaming content threads contentLength/contentSuffix (matches streaming fast path)', () => {
  const parser = new QwenStreamParser('ui-session-3', {});

  // Simulate the real Qwen wire format for this backend: each SSE event's
  // delta.content carries the FULL accumulated answer so far, not a true
  // incremental delta. Push it past the 2000-char scan window used by the
  // sse-parser.ts fallback.
  const paragraph = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '.repeat(40); // ~3480 chars
  assert.ok(paragraph.length > 2000, 'test fixture must exceed the 2000-char scan window to exercise the bug');

  parser.parseLine(sseLine(paragraph.slice(0, 1000)));
  parser.parseLine(sseLine(paragraph.slice(0, 2500)));
  parser.parseLine(sseLine(paragraph));

  assert.strictEqual(parser.answerContent, paragraph, 'final content must equal the source text exactly, with no duplication from a mis-scanned common prefix');
  assert.strictEqual(parser.answerContent.length, paragraph.length);
});

test('Achado #2: state threading keeps content stable across many small growing chunks', () => {
  const parser = new QwenStreamParser('ui-session-4', {});
  const full = 'The quick brown fox jumps over the lazy dog. '.repeat(80); // ~3680 chars

  let sent = '';
  const step = 137; // deliberately not aligned to any natural boundary
  for (let i = step; i <= full.length; i += step) {
    sent = full.slice(0, i);
    parser.parseLine(sseLine(sent));
  }
  if (sent.length < full.length) {
    parser.parseLine(sseLine(full));
  }

  assert.strictEqual(parser.answerContent, full);
});

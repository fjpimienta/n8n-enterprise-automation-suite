import { describe, expect, it } from 'vitest';
import {
  CHAT_INTERRUPTED_MESSAGE,
  CHAT_UNEXPECTED_MESSAGE,
  chatErrorMessage,
  classifyChatHttpError,
} from './chat-error-message.util';

describe('chat-error-message.util', () => {
  it.each([0, 500, 502, 503, 504, 520, 524])('treats status %i as interrupted', (status) => {
    expect(classifyChatHttpError({ status })).toBe('interrupted');
    expect(chatErrorMessage({ status })).toBe(CHAT_INTERRUPTED_MESSAGE);
  });

  it.each([400, 401, 403, 404, 413, 429])('treats status %i as unexpected', (status) => {
    expect(classifyChatHttpError({ status })).toBe('unexpected');
    expect(chatErrorMessage({ status })).toBe(CHAT_UNEXPECTED_MESSAGE);
  });

  it('falls back to unexpected when the error has no numeric status', () => {
    expect(classifyChatHttpError(null)).toBe('unexpected');
    expect(classifyChatHttpError(undefined)).toBe('unexpected');
    expect(classifyChatHttpError(new Error('boom'))).toBe('unexpected');
    expect(classifyChatHttpError({ status: '502' })).toBe('unexpected');
  });
});

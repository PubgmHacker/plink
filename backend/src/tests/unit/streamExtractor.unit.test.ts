import { describe, expect, it } from 'vitest';
import { extractYouTubeId } from '../../services/streamExtractor.js';

describe('extractYouTubeId', () => {
  it('accepts supported HTTPS YouTube URL forms', () => {
    expect(extractYouTubeId('https://youtu.be/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(extractYouTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(extractYouTubeId('https://www.youtube.com/embed/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(extractYouTubeId('dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
  });

  it('rejects lookalike hosts, insecure URLs, and foreign query parameters', () => {
    expect(extractYouTubeId('https://evil.example/watch?v=dQw4w9WgXcQ')).toBeNull();
    expect(extractYouTubeId('https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ')).toBeNull();
    expect(extractYouTubeId('http://www.youtube.com/watch?v=dQw4w9WgXcQ')).toBeNull();
    expect(extractYouTubeId('https://example.com/?ref=youtube.com&v=dQw4w9WgXcQ')).toBeNull();
  });
});

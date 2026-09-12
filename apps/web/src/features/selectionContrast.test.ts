// Purpose: Keep selected source passages readable using the actual shipped palette roles.
// Inputs: The browser token stylesheet and sRGB luminance arithmetic.
// Outputs: A regression assertion that selected text meets normal-text contrast requirements.
// Side effects: Reads the local stylesheet only; no browser state or network access.

import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';

// MARK: - Resolve shipped selection roles before measuring foreground/background contrast
const stylesheet = readFileSync(new URL('../styles/tokens.css', import.meta.url), 'utf8');
const roles = new Map(
  [...stylesheet.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map((match) => [match[1], match[2].trim()]),
);
function resolveColor(value: string): string {
  const role = /^var\((--[\w-]+)\)$/.exec(value);
  return role ? resolveColor(roles.get(role[1])!) : value;
}
function luminance(value: string): number {
  const hex = resolveColor(value).replace('#', '');
  expect(hex).toMatch(/^[0-9a-f]{6}$/i);
  const channels = [0, 2, 4].map((start) => {
    const channel = parseInt(hex.slice(start, start + 2), 16) / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}
it('keeps selection foreground and background at least 4.5:1 apart', () => {
  const selection = /::selection\s*\{([^}]+)\}/.exec(stylesheet)![1];
  const properties = new Map(
    [...selection.matchAll(/([\w-]+):\s*([^;]+);/g)].map((match) => [match[1], match[2].trim()]),
  );
  const foreground = luminance(properties.get('color')!);
  const background = luminance(properties.get('background')!);
  const contrast = (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05);
  expect(contrast).toBeGreaterThanOrEqual(4.5);
});

import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = [
  'public_page_hydration.js',
  'current_year.js',
  'public_calculator_date_hydration.js'
].map(file => fs.readFileSync(
  path.join(__dirname, '../../src/app/assets/javascripts', file),
  'utf8'
)).join('\n');

class FixedDate extends Date {
  constructor() {
    super('2026-06-15T12:00:00Z');
  }
}

function runCurrentDate(publicCalculator: boolean) {
  const year = { textContent: '2025' };
  const date = { textContent: 'server date', closest: () => ({ classList: { remove: jest.fn() } }) };
  const link = { href: 'https://example.com/en/days?year=2025' };
  const listeners: Record<string, Array<() => void>> = {};
  const querySelectorAll = jest.fn((selector: string) => {
    if (selector === '.current-year') return [year];
    if (selector === '.calendar-current-date') return [date];
    if (selector === '.calendar-jump-today') return [link];
    return [];
  });

  vm.runInNewContext(script, {
    Date: FixedDate,
    URL,
    Intl,
    window: { location: { origin: 'https://example.com' } },
    document: {
      addEventListener: (event: string, callback: () => void) => {
        (listeners[event] ||= []).push(callback);
      },
      querySelectorAll,
      body: { getAttribute: () => publicCalculator ? 'true' : null },
      documentElement: { getAttribute: () => 'en' }
    }
  });
  listeners.DOMContentLoaded.forEach(callback => callback());

  return { year, date, link, querySelectorAll };
}

test('private pages retain their server-rendered calendar date and link', () => {
  const result = runCurrentDate(false);

  expect(result.year.textContent).not.toBe('2025');
  expect(result.date.textContent).toBe('server date');
  expect(result.link.href).toBe('https://example.com/en/days?year=2025');
  expect(result.querySelectorAll).not.toHaveBeenCalledWith('.calendar-current-date');
});

test('public calculator pages refresh cached date-dependent controls', () => {
  const result = runCurrentDate(true);

  expect(result.date.textContent).not.toBe('server date');
  expect(result.link.href).toContain('month=');
  expect(result.link.href).toContain('day=');
});

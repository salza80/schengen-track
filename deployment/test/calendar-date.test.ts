import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = ['public_page_hydration.js', 'calendar.js'].map(file => fs.readFileSync(
  path.join(__dirname, '../../src/app/assets/javascripts', file),
  'utf8'
)).join('\n');

class FakeDate {
  getFullYear() { return 2026; }
  getMonth() { return 0; }
  getDate() { return 2; }
  toISOString() { return '2026-01-01T23:00:00.000Z'; }
}

function runCalendar(publicCalculator: boolean) {
  const listeners: Record<string, () => void> = {};
  const queriedDates: string[] = [];
  const remove = jest.fn();
  const add = jest.fn();
  const currentDayCell = {
    classList: { add, remove },
    getBoundingClientRect: () => ({ top: 0, bottom: 10 })
  };
  const calendarRoot = { getAttribute: () => '2026' };
  const querySelector = jest.fn((selector: string) => {
    if (selector === '.calendar-view-container') return calendarRoot;
    if (selector === '#calendar-scroll-target') return null;
    if (selector.startsWith('[data-date="')) {
      queriedDates.push(selector);
      return currentDayCell;
    }
    return null;
  });
  const querySelectorAll = jest.fn((selector: string) => {
    if (selector === '.day-cell.current-day') return [{ classList: { remove } }];
    return [];
  });

  vm.runInNewContext(script, {
    Date: FakeDate,
    URL,
    window: {
      location: { href: 'https://example.com/en/days' },
      pageYOffset: 0,
      innerHeight: 800,
      scrollTo: jest.fn()
    },
    document: {
      addEventListener: (event: string, callback: () => void) => { listeners[event] = callback; },
      querySelector,
      querySelectorAll,
      body: { getAttribute: () => publicCalculator ? 'true' : null }
    },
    sessionStorage: { getItem: () => null, removeItem: jest.fn() },
    requestAnimationFrame: jest.fn(),
    setTimeout: jest.fn()
  });
  listeners.DOMContentLoaded();

  return { queriedDates, querySelectorAll, remove };
}

test('private calendars preserve the server-aligned UTC current day', () => {
  const result = runCalendar(false);

  expect(result.queriedDates).toContain('[data-date="2026-01-01"]');
  expect(result.querySelectorAll).not.toHaveBeenCalledWith('.day-cell.current-day');
});

test('public cached calendars replace stale highlights with the browser-local day', () => {
  const result = runCalendar(true);

  expect(result.queriedDates).toContain('[data-date="2026-01-02"]');
  expect(result.querySelectorAll).toHaveBeenCalledWith('.day-cell.current-day');
  expect(result.remove).toHaveBeenCalled();
});

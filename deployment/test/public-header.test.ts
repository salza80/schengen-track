import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = fs.readFileSync(path.join(__dirname, '../../src/app/assets/javascripts/public_header.js'), 'utf8');

async function runHeader(cookie: string, status: number, probed = false, fail = false,
                         payload = { html: 'Personal menu', csrf_token: 'session-token', notice_html: '' }) {
  const menu = { innerHTML: 'Log in', dataset: { sessionHeaderUrl: '/fr/session_header' } };
  const notices = { innerHTML: '' };
  const meta: Record<string, any> = {};
  const storage: Record<string, string> = probed ? { 'session-header-probed': '1' } : {};
  const fetch = jest.fn(async () => {
    if (fail) throw new Error('offline');
    return { status, ok: status === 200, json: async () => payload };
  });
  vm.runInNewContext(script, {
    document: {
      cookie, readyState: 'complete',
      getElementById: (id: string) => id === 'public-user-menu' ? menu : id === 'public-notices' ? notices : null,
      querySelector: (selector: string) => meta[selector],
      createElement: () => ({}),
      head: { appendChild: (el: any) => { meta[`meta[name="${el.name}"]`] = el; } }
    },
    sessionStorage: {
      getItem: (key: string) => storage[key],
      setItem: (key: string, value: string) => { storage[key] = value; }
    },
    fetch
  });
  await new Promise(resolve => setImmediate(resolve));
  return { menu, notices, meta, storage, fetch };
}

test('existing sessions replace only the menu and install the session CSRF token', async () => {
  const result = await runHeader('has_calculator_session=1', 200, true);
  expect(result.fetch).toHaveBeenCalledWith('/fr/session_header', { credentials: 'same-origin', cache: 'no-store' });
  expect(result.menu.innerHTML).toBe('Personal menu');
  expect(result.meta['meta[name="csrf-token"]'].content).toBe('session-token');
});

test('legacy sessions can load without the new hint', async () => {
  expect((await runHeader('', 200)).menu.innerHTML).toBe('Personal menu');
});

test('anonymous visitors keep the public menu and are only probed once per tab', async () => {
  const result = await runHeader('', 204);
  expect(result.menu.innerHTML).toBe('Log in');
  expect(result.storage['session-header-probed']).toBe('1');
  expect((await runHeader('', 204, true)).fetch).not.toHaveBeenCalled();
});

test('network failures leave usable public navigation', async () => {
  expect((await runHeader('has_calculator_session=1', 200, false, true)).menu.innerHTML).toBe('Log in');
});

test('flash-only responses display messages even after an anonymous probe', async () => {
  const result = await runHeader('has_flash_message=1', 200, true, false,
    { html: '', csrf_token: '', notice_html: 'Account deleted' });
  expect(result.fetch).toHaveBeenCalledTimes(1);
  expect(result.notices.innerHTML).toBe('Account deleted');
  expect(result.menu.innerHTML).toBe('Log in');
  expect(result.meta).toEqual({});
});

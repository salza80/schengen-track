import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = ['public_page_hydration.js', 'public_header.js'].map(file => fs.readFileSync(
  path.join(__dirname, '../../src/app/assets/javascripts', file),
  'utf8'
)).join('\n');

async function runHeader(cookie: string, status: number, fail = false,
                         payload = { html: 'Personal menu', csrf_token: 'session-token', notice_html: '' }) {
  const menu = { innerHTML: 'Log in', dataset: { sessionHeaderUrl: '/fr/session_header' } };
  const notices = { innerHTML: '' };
  const meta: Record<string, any> = {};
  const fetch = jest.fn(async () => {
    if (fail) throw new Error('offline');
    return { status, ok: status === 200, json: async () => payload };
  });
  const installToken = jest.fn((data: any) => {
    meta['meta[name="csrf-token"]'] = { content: data.token };
  });
  vm.runInNewContext(script, {
    window: { CsrfBootstrap: { installToken } },
    document: {
      cookie, readyState: 'complete',
      getElementById: (id: string) => id === 'public-user-menu' ? menu : id === 'public-notices' ? notices : null,
      querySelector: (selector: string) => meta[selector],
      createElement: () => ({}),
      head: { appendChild: (el: any) => { meta[`meta[name="${el.name}"]`] = el; } }
    },
    fetch
  });
  await new Promise(resolve => setImmediate(resolve));
  return { menu, notices, meta, fetch, installToken };
}

test('existing sessions replace only the menu and install the session CSRF token', async () => {
  const result = await runHeader('has_calculator_session=1', 200);
  expect(result.fetch).toHaveBeenCalledWith('/fr/session_header', { credentials: 'same-origin', cache: 'no-store' });
  expect(result.menu.innerHTML).toBe('Personal menu');
  expect(result.meta['meta[name="csrf-token"]'].content).toBe('session-token');
  expect(result.installToken).toHaveBeenCalledWith({ param: 'authenticity_token', token: 'session-token' });
});

test('anonymous visitors keep the public menu without requesting session state', async () => {
  const result = await runHeader('', 204);
  expect(result.menu.innerHTML).toBe('Log in');
  expect(result.fetch).not.toHaveBeenCalled();
  expect(result.installToken).not.toHaveBeenCalled();
});

test('network failures leave usable public navigation', async () => {
  expect((await runHeader('has_calculator_session=1', 200, true)).menu.innerHTML).toBe('Log in');
});

test('flash-only responses fetch and display messages without a calculator session', async () => {
  const result = await runHeader('has_flash_message=1', 200, false,
    { html: '', csrf_token: '', notice_html: 'Account deleted' });
  expect(result.fetch).toHaveBeenCalledTimes(1);
  expect(result.notices.innerHTML).toBe('Account deleted');
  expect(result.menu.innerHTML).toBe('Log in');
  expect(result.meta).toEqual({});
});

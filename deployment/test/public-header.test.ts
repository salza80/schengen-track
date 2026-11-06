import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = ['public_page_hydration.js', 'public_header.js'].map(file => fs.readFileSync(
  path.join(__dirname, '../../src/app/assets/javascripts', file),
  'utf8'
)).join('\n');

class ElementStub {
  children: ElementStub[] = [];
  attributes: Record<string, string> = {};
  className = '';
  id = '';
  type = '';
  dataset: Record<string, string> = {};
  private text = '';

  constructor(public tagName: string) {}
  set innerHTML(_html: string) { throw new Error('Raw HTML must not be inserted'); }
  set textContent(text: string) { this.text = text; this.children = []; }
  get textContent(): string { return this.text + this.children.map(child => child.textContent).join(''); }
  setAttribute(name: string, value: string) { this.attributes[name] = value; }
  appendChild(child: ElementStub) { this.children.push(child); }
  replaceChildren(fragment: ElementStub) { this.text = ''; this.children = fragment.children; }
  querySelectorAll() { return []; }
}

async function runHeader(cookie: string, status: number, fail = false,
                         payload: Record<string, unknown> = { html: 'Personal menu', csrf_token: 'session-token', messages: [] },
                         sanitizer: boolean | 'unsupported' = true) {
  const menu = new ElementStub('UL');
  menu.textContent = 'Log in';
  menu.dataset.sessionHeaderUrl = '/fr/session_header';
  const notices = new ElementStub('DIV');
  const meta: Record<string, any> = {};
  const fetch = jest.fn(async () => {
    if (fail) throw new Error('offline');
    return { status, ok: status === 200, json: async () => payload };
  });
  const installToken = jest.fn((data: any) => {
    meta['meta[name="csrf-token"]'] = { content: data.token };
  });
  const sanitize = jest.fn((html: string) => {
    const fragment = new ElementStub('#fragment');
    const item = new ElementStub('LI');
    item.textContent = html;
    fragment.appendChild(item);
    return fragment;
  });
  vm.runInNewContext(script, {
    window: {
      location: { href: 'https://schengen.test/fr/about', origin: 'https://schengen.test' },
      DOMPurify: sanitizer ? { sanitize, isSupported: sanitizer !== 'unsupported' } : undefined,
      CsrfBootstrap: { installToken }
    },
    document: {
      cookie, readyState: 'complete',
      getElementById: (id: string) => id === 'public-user-menu' ? menu : id === 'public-notices' ? notices : null,
      createElement: (tag: string) => new ElementStub(tag.toUpperCase()),
      createDocumentFragment: () => new ElementStub('#fragment')
    },
    URL,
    fetch
  });
  await new Promise(resolve => setImmediate(resolve));
  return { menu, notices, meta, fetch, installToken, sanitize };
}

test('existing sessions install the sanitized menu and session CSRF token', async () => {
  const result = await runHeader('has_calculator_session=1', 200);
  expect(result.fetch).toHaveBeenCalledWith('/fr/session_header', { credentials: 'same-origin', cache: 'no-store' });
  expect(result.sanitize).toHaveBeenCalledWith('Personal menu', expect.objectContaining({ RETURN_DOM_FRAGMENT: true }));
  expect(result.menu.textContent).toBe('Personal menu');
  expect(result.meta['meta[name="csrf-token"]'].content).toBe('session-token');
  expect(result.installToken).toHaveBeenCalledWith({ param: 'authenticity_token', token: 'session-token' });

  const stale = await runHeader('has_calculator_session=1', 204);
  expect(stale.fetch).toHaveBeenCalledTimes(1);
  expect(stale.menu.textContent).toBe('Log in');
  expect(stale.sanitize).not.toHaveBeenCalled();
  expect(stale.installToken).not.toHaveBeenCalled();
});

test('anonymous visitors keep the public menu without requesting session state', async () => {
  for (const cookie of ['', '_schengen_track_session=legacy', 'has_calculator_session=0; has_flash_message=0']) {
    const result = await runHeader(cookie, 204);
    expect(result.menu.textContent).toBe('Log in');
    expect(result.fetch).not.toHaveBeenCalled();
    expect(result.installToken).not.toHaveBeenCalled();
  }
});

test('network failures leave usable public navigation', async () => {
  expect((await runHeader('has_calculator_session=1', 200, true)).menu.textContent).toBe('Log in');
});

test('flash-only responses render dismissible notice and alert text', async () => {
  const payload = '<img src=x onerror="alert(1)"> & <script>alert(2)</script>';
  const result = await runHeader('has_flash_message=1', 200, false, { messages: [
    { type: 'notice', text: payload }, { type: 'alert', text: 'Account deleted' },
    { type: 'unknown', text: 'Ignored' }, { type: 'notice', text: {} }
  ] });
  expect(result.fetch).toHaveBeenCalledTimes(1);
  expect(result.notices.children).toHaveLength(2);
  const [notice, alert] = result.notices.children;
  expect(notice.textContent).toBe(payload);
  expect(notice.className).toContain('alert-success');
  expect(alert.textContent).toBe('Account deleted');
  expect(alert.className).toContain('alert-warning');
  expect(notice.children).toHaveLength(1);
  expect(notice.children[0].attributes['data-bs-dismiss']).toBe('alert');
  expect(result.menu.textContent).toBe('Log in');
  expect(result.sanitize).not.toHaveBeenCalled();
  expect(result.meta).toEqual({});
});

test.each([false, 'unsupported'] as const)('unavailable sanitizer (%s) keeps the generic menu and renders text notices', async sanitizer => {
  const result = await runHeader('has_calculator_session=1', 200, false, {
    html: '<li onclick="alert(1)">Untrusted menu</li>',
    messages: [{ type: 'notice', text: 'Still displayed safely' }]
  }, sanitizer);
  expect(result.menu.textContent).toBe('Log in');
  expect(result.sanitize).not.toHaveBeenCalled();
  expect(result.notices.textContent).toBe('Still displayed safely');
});

test('legacy HTML notices are never inserted', async () => {
  const result = await runHeader('has_flash_message=1', 200, false, { notice_html: '<img src=x onerror="alert(1)">' });
  expect(result.notices.textContent).toBe('');
  expect(result.menu.textContent).toBe('Log in');
});

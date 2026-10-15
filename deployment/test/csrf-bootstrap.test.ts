import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = fs.readFileSync(path.join(__dirname, '../../src/app/assets/javascripts/csrf_bootstrap.js'), 'utf8');

function setup(cookie = '') {
  const listeners: Record<string, Function> = {};
  const metas: Record<string, any> = {};
  const hidden: Record<string, any> = {};
  const requestSubmit = jest.fn();
  const reload = jest.fn();
  const alert = jest.fn();
  const fetch = jest.fn(async () => ({
    ok: true,
    json: async () => ({ param: 'authenticity_token', token: 'fresh-token' })
  }));
  const form: any = {
    dataset: { csrfBootstrapUrl: '/en/csrf_token' },
    querySelector: (selector: string) => hidden[selector],
    appendChild: (element: any) => { hidden[`input[name="${element.name}"]`] = element; },
    requestSubmit
  };
  const document: any = {
    cookie,
    body: { dataset: { publicCalculatorPage: 'true' } },
    head: { appendChild: (element: any) => { metas[`meta[name="${element.name}"]`] = element; } },
    addEventListener: (name: string, listener: Function) => { listeners[name] = listener; },
    querySelector: (selector: string) => metas[selector],
    querySelectorAll: () => [],
    createElement: () => ({})
  };
  const window: any = {
    addEventListener: (name: string, listener: Function) => { listeners[name] = listener; },
    location: { reload },
    alert,
    console
  };

  vm.runInNewContext(script, {
    window,
    document,
    fetch,
    console,
    Promise,
    HTMLFormElement: function() {}
  });

  return { listeners, metas, hidden, requestSubmit, reload, alert, fetch, form, window };
}

test('public form fetches and installs a CSRF token before resubmitting', async () => {
  const state = setup();
  const event = {
    target: state.form,
    preventDefault: jest.fn(),
    stopImmediatePropagation: jest.fn()
  };

  state.listeners.submit(event);
  await new Promise(resolve => setImmediate(resolve));

  expect(event.preventDefault).toHaveBeenCalled();
  expect(event.stopImmediatePropagation).toHaveBeenCalled();
  expect(state.fetch).toHaveBeenCalledWith('/en/csrf_token', expect.objectContaining({
    method: 'GET', credentials: 'same-origin', cache: 'no-store'
  }));
  expect(state.metas['meta[name="csrf-token"]'].content).toBe('fresh-token');
  expect(state.hidden['input[name="authenticity_token"]'].value).toBe('fresh-token');
  expect(state.form.dataset.csrfReady).toBe('true');
  expect(state.requestSubmit).toHaveBeenCalledTimes(1);
});

test('concurrent submit attempts start only one bootstrap request', async () => {
  const state = setup();
  const event = () => ({ target: state.form, preventDefault: jest.fn(), stopImmediatePropagation: jest.fn() });

  state.listeners.submit(event());
  state.listeners.submit(event());
  await new Promise(resolve => setImmediate(resolve));

  expect(state.fetch).toHaveBeenCalledTimes(1);
  expect(state.requestSubmit).toHaveBeenCalledTimes(1);
});

test('back-forward restoration reloads public calculator HTML after state exists', () => {
  const state = setup('has_calculator_session=1');
  state.listeners.pageshow({ persisted: true });
  expect(state.reload).toHaveBeenCalledTimes(1);
});

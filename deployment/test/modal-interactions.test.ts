import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

const script = fs.readFileSync(
  path.join(__dirname, '../../src/app/assets/javascripts/modal_interactions.js'),
  'utf8'
);

test('modal submission dispatches a native submit event for CSRF bootstrap', () => {
  const requestSubmit = jest.fn();
  const trigger = jest.fn();
  const form = { checkValidity: () => true, requestSubmit };
  let disabled = false;

  const jquery = jest.fn((selector: string) => {
    if (selector === '#form') {
      return { length: 1, get: () => form, trigger };
    }

    return {
      prop: (name: string, value?: boolean) => {
        if (value === undefined) return disabled;
        disabled = value;
        return undefined;
      }
    };
  });
  const window: any = { jQuery: jquery };

  vm.runInNewContext(script, { window });
  window.ModalInteractions.submitForm('#form', '#submit');

  expect(disabled).toBe(true);
  expect(requestSubmit).toHaveBeenCalledTimes(1);
  expect(trigger).not.toHaveBeenCalled();
});

test('invalid modal form remains enabled so it can be corrected and resubmitted', () => {
  const requestSubmit = jest.fn();
  const reportValidity = jest.fn();
  const form = {
    checkValidity: () => false,
    reportValidity,
    requestSubmit
  };
  let disabled = false;

  const jquery = jest.fn((selector: string) => {
    if (selector === '#form') return { length: 1, get: () => form };

    return {
      prop: (name: string, value?: boolean) => {
        if (value === undefined) return disabled;
        disabled = value;
        return undefined;
      }
    };
  });
  const window: any = { jQuery: jquery };

  vm.runInNewContext(script, { window });
  window.ModalInteractions.submitForm('#form', '#submit');

  expect(reportValidity).toHaveBeenCalledTimes(1);
  expect(requestSubmit).not.toHaveBeenCalled();
  expect(disabled).toBe(false);
});

test('modal allocation errors display the server message and restore the submit button', () => {
  const callbacks: Record<string, Function> = {};
  const prop = jest.fn();
  const document = {};
  const chain: any = {
    off: () => chain,
    on: (event: string, selector: string, callback: Function) => { callbacks[event] = callback; return chain; }
  };
  const jquery = (target: unknown) => target === document ? chain : { prop };
  const window: any = { jQuery: jquery, alert: jest.fn() };
  vm.runInNewContext(script, { window, document });
  window.ModalInteractions.bindSubmissionReset('#form', '#submit');
  callbacks['ajax:error.calculatorLimits'].call({ dataset: {} }, {}, { status: 429, responseText: JSON.stringify({ error: { code: 'calculator_capacity_reached', message: 'Remove unused trips.' } }) });
  expect(window.alert).toHaveBeenCalledWith('Remove unused trips.');
  callbacks['ajax:complete.modalSubmission']();
  expect(prop).toHaveBeenCalledWith('disabled', false);
  callbacks['ajax:error.calculatorLimits'].call({ dataset: {} }, {}, { status: 503, responseText: '<html>unavailable</html>' });
  // Calendar forms render their own inline errors instead of a blocking alert.
  callbacks['ajax:error.calculatorLimits'].call({ dataset: { calendarVisitForm: 'true' } }, {}, { status: 429, responseText: JSON.stringify({ error: { code: 'rate_limited', message: 'Try later.' } }) });
  expect(window.alert).toHaveBeenCalledTimes(1);
});

test('modal form transport delegates rendering and errors without calendar dependencies', () => {
  let active = true;
  const toggle = jest.fn();
  const request = { abort: jest.fn() };
  const ajax = jest.fn(() => request);
  const jquery: any = () => ({ toggle });
  jquery.ajax = ajax;
  const window: any = { jQuery: jquery };
  vm.runInNewContext(script, { window });
  const onSuccess = jest.fn();
  const onError = jest.fn();
  const result = window.ModalInteractions.loadForm({
    url: '/form.json', dataType: 'json', isCurrent: () => active,
    onSuccess, onError, deleteButtonSelector: '#delete', showDeleteButton: true
  });
  expect(result).toBe(request);
  const handlers = (ajax.mock.calls[0] as any)[0];
  const data = { html: '<form></form>' };
  handlers.success(data);
  expect(onSuccess).toHaveBeenCalledWith(data);
  expect(toggle).toHaveBeenCalledWith(true);
  const error = { status: 503 };
  handlers.error(error, 'error');
  expect(onError).toHaveBeenCalledWith(error);
  handlers.error(error, 'abort');
  expect(onError).toHaveBeenCalledTimes(1);
  active = false;
  handlers.success(data);
  handlers.error(error, 'error');
  expect(onSuccess).toHaveBeenCalledTimes(1);
  expect(onError).toHaveBeenCalledTimes(1);
});

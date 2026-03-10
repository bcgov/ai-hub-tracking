import { useRef } from 'react';
import type { ReactNode } from 'react';

import type { FormSchema } from '../types';
import { getInputClassName } from '../utils/formatters';

type FieldInfo = FormSchema['field_info'][keyof FormSchema['field_info']];

/**
 * Renders a bordered section panel with a muted title.
 * @param title - Heading text displayed inside the panel.
 * @returns A `<section>` element styled as a panel.
 */
export function Panel({ title }: { title: string }) {
  return (
    <section className="panel">
      <p className="muted">{title}</p>
    </section>
  );
}

/**
 * Renders a full-page hero card with a title and description.
 * Used for prominent status messages that occupy the main content area.
 * @param title - Heading text for the hero card.
 * @param description - Body text providing detail below the heading.
 * @returns A hero grid layout with a single primary card.
 */
export function FullPageMessage({ title, description }: { title: string; description: string }) {
  return (
    <div className="hero-grid">
      <section className="hero-card hero-card--primary">
        <h2>{title}</h2>
        <p>{description}</p>
      </section>
    </div>
  );
}

/**
 * Renders an empty state section with a title, description, and optional action element.
 * @param title - Heading text for the empty state.
 * @param description - Explanatory text shown below the heading.
 * @param action - Optional React node (e.g. a button) displayed below the description.
 * @returns A panel element styled as an empty state placeholder.
 */
export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <section className="panel empty-state">
      <h3>{title}</h3>
      <p>{description}</p>
      {action}
    </section>
  );
}

/**
 * Renders a coloured inline notification banner with a single message string.
 * @param tone - Visual tone: `'error'` for errors, `'info'` for informational notices.
 * @param message - Text content to display inside the banner.
 * @returns A `<div>` styled as an inline message with the appropriate tone class.
 */
export function InlineMessage({ tone, message }: { tone: 'error' | 'info'; message: string }) {
  return <div className={`inline-message inline-message--${tone}`}>{message}</div>;
}

/**
 * Renders a labelled form field wrapping a child input element, with optional error and help text.
 * @param info - Field metadata from the form schema providing label, placeholder, and description.
 * @param children - The input or control element to embed inside the label.
 * @param error - Optional validation error message displayed below the child element.
 * @returns A `<label>` element containing the field header, child, error, and help text.
 */
export function Field({
  info,
  children,
  error,
}: {
  info: FieldInfo;
  children: ReactNode;
  error?: string;
}) {
  return (
    <label className="field">
      <FieldHeader info={info} />
      {children}
      {error ? <span className="field__error">{error}</span> : null}
      <span className="field__help">{info.description}</span>
    </label>
  );
}

/**
 * Renders a field header row containing the field label and an info tooltip icon.
 * @param info - Field metadata from the form schema providing label and details text.
 * @returns A `<span>` containing the label text and the tooltip icon.
 */
export function FieldHeader({ info }: { info: FieldInfo }) {
  return (
    <span className="field__header">
      <span className="field__label">{info.label}</span>
      <FieldInfoIcon info={info} />
    </span>
  );
}

/**
 * Renders a keyboard-focusable info icon with a tooltip showing the field details text.
 * @param info - Field metadata providing the `details` text shown in the tooltip.
 * @returns A `<span>` containing the icon and a tooltip element.
 */
function FieldInfoIcon({ info }: { info: FieldInfo }) {
  return (
    <span className="field-info" tabIndex={0}>
      <i aria-hidden="true" className="bi bi-info-circle"></i>
      <span className="field-info__tooltip" role="tooltip">
        {info.details}
      </span>
    </span>
  );
}

/**
 * Renders a card-style toggle (checkbox) with a field header and description.
 * @param info - Field metadata providing label and description text.
 * @param checked - Whether the toggle is currently in the checked state.
 * @param onChange - Callback invoked with the new boolean value when the toggle changes.
 * @returns A `<label>` element styled as a toggle card.
 */
export function Toggle({
  info,
  checked,
  onChange,
}: {
  info: FieldInfo;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="toggle-card">
      <input
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        type="checkbox"
      />
      <div className="toggle-card__body">
        <FieldHeader info={info} />
        <span className="field__help">{info.description}</span>
      </div>
    </label>
  );
}

let emailKeyCounter = 0;

/**
 * Renders a dynamic list of email input fields with add and remove controls.
 * Maintains stable React keys across additions and removals using an internal counter ref.
 * @param info - Field metadata providing label, description, and placeholder text.
 * @param values - Current array of email strings.
 * @param addLabel - Label text for the add-another button.
 * @param error - Optional validation error message displayed above the inputs.
 * @param inputPattern - Optional HTML `pattern` attribute applied to each input.
 * @param inputTitle - Optional HTML `title` attribute for input validation tooltip text.
 * @param inputType - Input type, either `'email'` or `'text'`.
 * @param onAdd - Callback invoked when the user clicks the add button.
 * @param onBlur - Optional callback invoked when an input loses focus.
 * @param onChange - Callback invoked with the index and new value when an input changes.
 * @param onRemove - Callback invoked with the index of the entry to remove.
 * @returns A `<section>` containing the dynamic email input list.
 */
export function EmailListField({
  info,
  values,
  addLabel,
  error,
  inputPattern,
  inputTitle,
  inputType,
  onAdd,
  onBlur,
  onChange,
  onRemove,
}: {
  info: FieldInfo;
  values: string[];
  addLabel: string;
  error?: string;
  inputPattern?: string;
  inputTitle?: string;
  inputType?: 'email' | 'text';
  onAdd: () => void;
  onBlur?: () => void;
  onChange: (index: number, value: string) => void;
  onRemove: (index: number) => void;
}) {
  const keysRef = useRef<string[]>([]);
  while (keysRef.current.length < values.length) {
    keysRef.current.push(`email-${emailKeyCounter++}`);
  }

  const handleRemove = (index: number) => {
    keysRef.current.splice(index, 1);
    onRemove(index);
  };

  return (
    <section className={`role-card stack-sm ${error ? 'role-card--error' : ''}`}>
      <FieldHeader info={info} />
      {error ? <span className="field__error">{error}</span> : null}
      <p className="field__help">{info.description}</p>
      <div className="stack-sm">
        {values.map((email, index) => (
          <div className="inline-input-row" key={keysRef.current[index]}>
            <input
              aria-invalid={Boolean(error)}
              className={getInputClassName(error)}
              onBlur={onBlur}
              onChange={(event) => onChange(index, event.target.value)}
              pattern={inputPattern}
              placeholder={info.placeholder ?? 'name@gov.bc.ca'}
              title={inputTitle}
              type={inputType}
              value={email}
            />
            <button
              className="button button--ghost"
              onClick={() => handleRemove(index)}
              type="button"
            >
              Remove
            </button>
          </div>
        ))}
      </div>
      <button className="button button--ghost" onClick={onAdd} type="button">
        {addLabel}
      </button>
    </section>
  );
}

/**
 * Renders a label-value row for use in summary and review layouts.
 * @param label - Descriptive label for the data field.
 * @param value - The data value to display; may be any React node.
 * @returns A `<div>` containing a label span and a value span.
 */
export function SummaryRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="summary-row">
      <span className="summary-row__label">{label}</span>
      <span className="summary-row__value">{value}</span>
    </div>
  );
}

/**
 * Renders a list of tag badges, or a muted fallback message when the list is empty.
 * @param items - Array of string items to display as tags.
 * @returns A tag list `<div>` when items are present, or a muted `<p>` when empty.
 */
export function TagList({ items }: { items: string[] }) {
  if (items.length === 0) {
    return <p className="muted">No services selected.</p>;
  }

  return (
    <div className="tag-list">
      {items.map((item) => (
        <span className="tag" key={item}>
          {item}
        </span>
      ))}
    </div>
  );
}

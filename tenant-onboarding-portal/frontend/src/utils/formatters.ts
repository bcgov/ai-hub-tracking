import { ApiError } from '../api';

/**
 * Returns the CSS class name for a text input, applying the error variant when an error message is provided.
 * @param error - Optional error message string.
 * @returns CSS class string for the text input element.
 */
export function getInputClassName(error?: string) {
  return error ? 'text-input text-input--error' : 'text-input';
}

/**
 * Extracts a user-facing error message string from an unknown thrown value.
 * Returns the message from an `ApiError` or `Error` instance, or a generic fallback.
 * @param error - The caught error value of unknown type.
 * @returns A descriptive error message string suitable for display.
 */
export function getErrorMessage(error: unknown) {
  if (error instanceof ApiError) {
    return error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return 'An unexpected error occurred.';
}

/**
 * Formats an ISO 8601 date string for display using the user's locale.
 * Returns the raw input value if the string cannot be parsed as a valid date.
 * @param value - ISO 8601 date string to format.
 * @returns Locale-formatted date string, or the original value if invalid.
 */
export function formatDate(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value;
  }
  return parsed.toLocaleString();
}

/**
 * Returns the value as a display string, or `'Not provided'` when the value is not a non-empty string.
 * @param value - Value of unknown type to check.
 * @returns The value if it is a non-empty string, otherwise `'Not provided'`.
 */
export function stringValue(value: unknown) {
  return typeof value === 'string' && value ? value : 'Not provided';
}

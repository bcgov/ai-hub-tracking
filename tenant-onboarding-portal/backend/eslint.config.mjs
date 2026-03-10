import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import eslintConfigPrettier from 'eslint-config-prettier';
import jsdoc from 'eslint-plugin-jsdoc';
import { defineConfig, globalIgnores } from 'eslint/config';

export default defineConfig([
  globalIgnores(['dist', 'node_modules', 'frontend-dist']),
  {
    files: ['**/*.ts'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      jsdoc.configs['flat/recommended-typescript'],
    ],
    languageOptions: {
      ecmaVersion: 2022,
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      // JSDoc: require on all public functions and methods; TS handles types so disable type tags
      'jsdoc/require-jsdoc': [
        'error',
        {
          require: {
            FunctionDeclaration: true,
            MethodDefinition: true,
            ClassDeclaration: false,
            ArrowFunctionExpression: false,
            FunctionExpression: false,
          },
          publicOnly: false,
        },
      ],
      'jsdoc/require-description': 'error',
      'jsdoc/require-param': ['error', { checkDestructured: false }],
      'jsdoc/check-param-names': 'off',
      'jsdoc/require-returns': 'error',
      // TypeScript provides types — disable JSDoc type annotations to avoid duplication
      'jsdoc/require-param-type': 'off',
      'jsdoc/require-returns-type': 'off',
      'jsdoc/no-undefined-types': 'off',
      'jsdoc/check-tag-names': ['error', { definedTags: ['throws'] }],
      // Allow blank lines between description and tags (common documentation style)
      'jsdoc/tag-lines': 'off',
      // TypeScript owns throws types — no need to repeat in JSDoc
      'jsdoc/require-throws-type': 'off',
    },
  },
  {
    // Test files do not require JSDoc and may use any for mocking
    files: ['tests/**/*.ts', 'src/**/*.spec.ts'],
    rules: {
      'jsdoc/require-jsdoc': 'off',
      'jsdoc/require-description': 'off',
      'jsdoc/require-param': 'off',
      'jsdoc/require-returns': 'off',
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
  eslintConfigPrettier,
]);

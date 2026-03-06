module.exports = {
  root: true,
  env: {
    node: true,
    es2022: true,
  },
  parser: '@typescript-eslint/parser',
  parserOptions: {
    project: ['tsconfig.json'],
    sourceType: 'module',
  },
  plugins: ['@typescript-eslint'],
  extends: ['eslint:recommended', 'google', 'plugin:@typescript-eslint/recommended'],
  ignorePatterns: ['lib/**'],
  rules: {
    'max-len': ['error', {code: 120}],
    quotes: ['error', 'single'],
    'require-jsdoc': 'off',
  },
};


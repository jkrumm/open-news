// Conventional commits validation config for commitlint
// https://www.conventionalcommits.org/
// Standalone config without external extends (works with bunx commitlint)

export default {
  rules: {
    // Body
    'body-leading-blank': [2, 'always'],
    'body-max-line-length': [0, 'always', Infinity],
    // Footer
    'footer-leading-blank': [2, 'always'],
    'footer-max-line-length': [0, 'always', Infinity],
    // Header
    'header-max-length': [2, 'always', 100],
    // Scope
    'scope-case': [2, 'always', 'lower-case'],
    // Subject
    'subject-case': [2, 'never', ['upper-case', 'pascal-case', 'start-case']],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],
    // Type
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'type-enum': [
      2,
      'always',
      [
        'feat', // New feature
        'fix', // Bug fix
        'refactor', // Code refactoring (no feature change)
        'chore', // Maintenance tasks
        'docs', // Documentation changes
        'perf', // Performance improvements
        'test', // Test additions or updates
        'style', // Code style changes (formatting, etc.)
        'build', // Build system or dependency changes
        'ci', // CI/CD configuration changes
        'revert', // Revert previous commit
      ],
    ],
  },
};

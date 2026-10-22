# Repository conventions

- Always spell the product name `microplanner` in lowercase in UI text,
  documentation, pull requests, and conversation. Use ordinary language naming
  conventions for identifiers that do not contain the product name.
- Write repository content in English, including documentation, comments,
  user-facing text, commit messages, and pull request titles and bodies.
- Use descriptive branch names such as `feature/google-auth-mongodb` or
  `fix/session-restore`. Branch names and pull request text, including hidden
  release metadata, must not mention the development methodology or its tools.
- Before version `1.0.0`, new features increment the minor version and bug fixes
  increment the patch version. Do not introduce a major version before the user
  explicitly decides the application is ready for `1.0.0`.
- Keep credentials in ignored local configuration. Never commit, print, or
  package database credentials, OAuth secrets, or session tokens.
- Preserve user data when rebuilding or updating the application.

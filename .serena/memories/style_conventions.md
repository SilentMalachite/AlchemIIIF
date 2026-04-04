# Style & Conventions

- Comments and documentation in Japanese
- Conventional Commits: feat(scope):, fix(scope):, docs:, etc.
- mix format enforced; Credo strict mode (max line 120, nesting 4, complexity 12)
- @current_scope (not @current_user) — access user via @current_scope.user
- Fields set programmatically (e.g. user_id) must NOT be in cast calls
- Always use to_form/2 for forms, <.input> for inputs, <.icon> for icons
- LiveView streams for collections (not regular list assigns)
- No Phoenix.View, no live_redirect/live_patch (use <.link navigate=…>)
- JS hooks in assets/js/, never inline script tags
- Accessibility: buttons min 60×60px, WCAG AA contrast, aria-label

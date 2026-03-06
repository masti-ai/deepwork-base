# Contributing

## Branch Workflow

- `dev` is the working branch. All work targets `dev`.
- `main` is production-only. Updates via PR from `dev`.
- Feature branches: `gt/<instance-id>/<issue-number>-<description>`

## Creating a PR

1. Branch from `dev`
2. Make changes, write tests
3. Create PR targeting `dev`
4. Add label `needs-review`
5. Wait for review and approval
6. Reviewer merges (do NOT self-merge)

## Commit Format

```
<type>(<scope>): <description>

Types: feat, fix, refactor, chore, test, docs
Scope: issue number or component name
```

Examples:
```
feat(issue-15): add product search endpoint
fix(issue-8): correct auth token expiration
docs(issue-3): update API documentation
```

## Code Style

- **Python**: PEP 8, type hints, Black + isort formatting
- **TypeScript**: ESLint rules, Prettier formatting
- **Commits**: Conventional commits format

## Testing

Run tests before submitting:
```bash
# Python
pytest -q

# Frontend
npm run lint && npm run build
```

## Security

- Never commit `.env` files or secrets
- Never hardcode API keys or credentials
- Use environment variables for all configuration

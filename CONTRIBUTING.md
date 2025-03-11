# Contributing Guidelines

Thank you for considering contributing to this project! Your contributions help us improve and expand our project.

## Workflow

### Creating Issues

Please check existing issues before opening a new one. Clearly describe your issue or feature request, including expected behavior and, if applicable, actual behavior.

### Creating Pull Requests:

Create a branch for your feature or bug fix:
```
git checkout -b feature/your-feature-name
```
Commit your changes with descriptive commit messages.

Push your branch:
```
git push origin feature/your-feature-name
```
Open a pull request against the main branch. Clearly explain the purpose of your changes.

## Coding Style:

Follow established patterns and practices in the repository.

Ensure code passes all linting and tests before submitting a PR.
```
yarn format
```

For Solidity, adhere to security best practices and clearly comment any non-obvious logic.

## Testing:

Write unit tests for all new code.

Ensure existing tests pass. Run tests with:
```
yarn test
```
## Code Reviews:

All PRs will be reviewed by maintainers.

Be prepared to address feedback and make requested changes.

### Merge Process:

Pull requests require approval from maintainers.

Ensure your branch is up to date with main before merging.

### Security:

Report security issues privately by contacting maintainers directly.

## Code of Conduct
See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for more details.

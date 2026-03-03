# Versioning Strategy

This document outlines the versioning strategy for C++ projects, focusing on clear communication of changes, automated release management, and consistent development practices.

## 1. Semantic Versioning (SemVer)

The project will adhere to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). Version numbers will follow the format `MAJOR.MINOR.PATCH`:

*   **`MAJOR` version:** Incremented when incompatible API changes are made. This indicates that existing integrations or applications built against a previous major version might break and require modification.
*   **`MINOR` version:** Incremented when new functionality is added in a backward-compatible manner. This signifies new features without breaking existing code.
*   **`PATCH` version:** Incremented when backward-compatible bug fixes are made. This addresses issues without introducing new features or breaking changes.

**Pre-release and Build Metadata:**
*   Pre-release versions (e.g., `1.0.0-alpha.1`, `1.0.0-beta.2`) can be used for unstable releases.
*   Build metadata (e.g., `1.0.0+20241125`) can be used to provide additional information about the build.

## 2. Conventional Commits

All commit messages will follow the [Conventional Commits specification](https://www.conventionalcommits.org/en/v1.0.0/). This standard provides a set of rules for creating explicit commit history, which:
*   Enables automated changelog generation.
*   Allows automated determination of semantic version bumps (major, minor, patch).
*   Improves collaboration by making the commit history easier to understand.

**Commit Message Structure:**

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Common `<type>` values:**

*   `feat`: A new feature (correlates with `MINOR` version bump).
*   `fix`: A bug fix (correlates with `PATCH` version bump).
*   `build`: Changes that affect the build system or external dependencies (e.g., `vcpkg`, `CMake`).
*   `chore`: Other changes that don't modify src or test files.
*   `ci`: Changes to CI configuration files and scripts.
*   `docs`: Documentation only changes.
*   `style`: Changes that do not affect the meaning of the code (white-space, formatting, missing semicolons, etc.).
*   `refactor`: A code change that neither fixes a bug nor adds a feature.
*   `perf`: A code change that improves performance.
*   `test`: Adding missing tests or correcting existing tests.

**Breaking Changes:**
A `BREAKING CHANGE` must be indicated in the footer or by appending `!` after the type/scope of the header. This signifies an incompatible API change and will result in a `MAJOR` version bump.

```
feat!: implement new API

BREAKING CHANGE: The old API has been removed.
```
OR
```
feat: refactor configuration system

BREAKING CHANGE: The configuration file format has changed, requiring updates.
```

## 3. Git Branching Strategy

A simplified [GitHub Flow](https://docs.github.com/en/get-started/quickstart/github-flow) will be used:

*   **`main` branch:** This branch represents the latest stable, production-ready version of the engine. All releases will be tagged directly from this branch.
*   **Feature Branches:** For every new feature, bug fix, or example (as per EDD), a new branch will be created from `main`. Branch names should be descriptive (e.g., `feat/vulkan-implementation`, `fix/window-resizing`, `docs/update-build-system`).
*   **Pull Requests (PRs):** All changes will be merged into the `main` branch via Pull Requests. PRs will undergo code review and must pass all Continuous Integration (CI) checks before merging.
*   **Direct Commits:** Direct commits to `main` are strictly prohibited.

## 4. Automation with Semantic Release

To ensure consistency and automate the release process, [Semantic Release](https://semantic-release.git.io/) will be integrated into our Continuous Integration (CI) pipeline (e.g., GitHub Actions, Azure DevOps).

**Semantic Release will perform the following automated tasks upon successful merges to the `main` branch:**

1.  **Analyze Commits:** Parse all new Conventional Commits since the last release.
2.  **Determine Version:** Based on the commit types and presence of `BREAKING CHANGE` notes, determine the next appropriate SemVer increment (major, minor, or patch).
3.  **Generate Changelog:** Automatically generate a detailed `CHANGELOG.md` file that summarizes all changes for the new release.
4.  **Create Git Tag:** Tag the `main` branch with the new semantic version (e.g., `v1.2.3`).
5.  **Publish Release:** Create a new release entry on the Git hosting platform (e.g., GitHub Releases), attaching the changelog and potentially build artifacts.
6.  **Update Version File (if applicable):** If a version file exists within the project (e.g., a C++ header defining a project version macro), it can be updated automatically.

**Enforcing Conventional Commits:**
To ensure developers adhere to the Conventional Commits specification, tools like `commitlint` (often used with `husky` for Git hooks) can be integrated into the development workflow to lint commit messages before they are created. This prevents invalid commit messages from entering the repository history.

By adopting this strategy, projects aim for a transparent, predictable, and efficient release management process.
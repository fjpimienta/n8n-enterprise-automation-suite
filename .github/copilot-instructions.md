# Working rules

- Branch from `origin/develop`. Before editing, `git log --oneline origin/develop..HEAD` must be empty.
- Never create, overwrite, or delete files under `hosting3m-workspace/projects/*/src/environments/` in the working tree; these git-ignored files hold real local values. For build checks, use a temporary copy of the project or generate placeholders only inside CI.
- Tests must not depend on git refs, remotes, or network access because CI uses a shallow checkout. Keep expected values inside the test.
- Open pull requests against `develop` with `gh pr create --body-file` using a temporary file, then delete the file. Never merge pull requests. Always report `git diff --stat` and test results without waiting to be asked.
- Never write security-weakness details in commits, pull request text, code comments, or documentation.
- Commit messages must follow Conventional Commits in English and include the affected scope.

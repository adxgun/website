---
title: "Setting up GitAction private repository access for Golang applications"
date: 2021-02-10 00:00:00 +0000
draft: false
---

Recently, i've been working on a Go project that has dependencies on internal/private packages built in-house by the team, mostly to cut boilerplate or automate recurring processes. We're using `go.mod` to manage this project's dependencies. One problem i & other member of the team often encounter is the GitAction error whenever we tried to access private repository/package from inside the project, most especially in `Dockerfile(s)` or some simple `ci` checks.
The solution to this problem is quite simple, even though it skipped my memory almost anytime i had to do it. This write-up is a small documentation for myself(easy future reference when i forget again :) )  and anyone out there facing similar issue.

### An Example GitAction
Below is an example of one of the many steps we have in the project's GitAction:
```yaml
# ci.yml
name: Build
on:
  push:
    branches:
      - *
  pull_request:
    branches: [*]

jobs:

  lint:
    name: Build to prevent compiler error

    # The type of runner that the job will run on
    runs-on: ubuntu-latest

    steps:
      # Setup Go
      - name: Set up Go
        uses: actions/setup-go@v2
        with:
          go-version: ^1.15

      - name: Check out code
        uses: actions/checkout@v2

      - name: Run build
        run: go build .
```

The above `GitAction` manifest is very simple, it builds a Go application to check for general compilation issues e.g unused variables or missed syntax error. Assuming the project or repository this workflow is meant for requires access to a particular private repository, you would get an error from `go.mod` when it tries to fetch & resolve all dependencies.

### Solution & Requirement
* **Access to the target private repository** - You will need a `PAT - Personal Access Token` to configure the authentication mechanism, as a result, you need to have at least `read` access to the target private repository. You can also generate the `PAT` in organization level settings on Github. To generate `PAT`, follow these steps:
   * Login to your Github account
   * Navigate to `Settings -> Developers Settings -> Personal access tokens` and generate a new one with necessary/minimal access.
   * Copy the newly generated `PAT`
* **Add `PAT` as a Github Secret** - For the value of the created `PAT` to be accessed from GitAction context, it needs to be added securely to Github secret. You can access Github secret by navigating to the target repository, click `Settings -> Secrets` on Github.


Once you're able to generate `PAT`, add the lines below to the existing `GitAction` manifest, just before the authentication is required.
```yaml
    - name: Setup credentials to access private repo
      run: git config --global url."https://${{ secrets.PAT }}:x-oauth-basic@github.com/".insteadOf "https://github.com/"
```

The updated `ci.yml` should look like this:

```yaml
# ci.yaml
name: Build
on:
  push:
    branches:
      - *
  pull_request:
    branches: [*]

jobs:

  lint:
    name: Build to prevent compiler error

    # The type of runner that the job will run on
    runs-on: ubuntu-latest

    steps:
      # Setup Go
      - name: Set up Go
        uses: actions/setup-go@v2
        with:
          go-version: ^1.15

      - name: Check out code
        uses: actions/checkout@v2

      - name: Setup credentials to access private repo
        run: git config --global url."https://${{ secrets.PAT }}:x-oauth-basic@github.com/".insteadOf "https://github.com/"

      - name: Run build
        run: go build .
```

And that's it! You should be able to authenticate with Github from GitAction context from now on. Enjoy :)

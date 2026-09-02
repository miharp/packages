# harpworks packages

The yum and apt repository at <https://packages.harpworks.org>: packages for
tools for OpenVox, currently [codavox](https://github.com/miharp/codavox).

It is static files on GitHub Pages, rebuilt in full from each listed project's
GitHub Releases by the [Repository workflow](.github/workflows/repository.yml)
every hour and on demand. There is no branch to maintain and nothing to get out
of step with a releases page, which stays the source of truth.

**What is signed is the repository metadata, not the packages**: `repomd.xml`
for dnf and `Release` for apt, each of which names every package's SHA-256.
That is how apt has always worked, and dnf verifies it with `repo_gpgcheck`,
which the shipped `.repo` file turns on. The packages are byte-for-byte the
release assets, so each project's `checksums.txt` still describes them.

## Use it

```console
# RPM: Rocky, RHEL, AlmaLinux, CentOS Stream
curl -fsSL https://packages.harpworks.org/rpm/harpworks.repo -o /etc/yum.repos.d/harpworks.repo
dnf install codavox
```

```console
# DEB: Debian, Ubuntu
curl -fsSL https://packages.harpworks.org/harpworks.asc -o /etc/apt/keyrings/harpworks.asc
echo "deb [signed-by=/etc/apt/keyrings/harpworks.asc] https://packages.harpworks.org/deb stable main" > /etc/apt/sources.list.d/harpworks.list
apt-get update && apt-get install codavox
```

## Add a project

Add its `owner/name` to [`projects.txt`](projects.txt). Its releases must carry
`.rpm` and `.deb` assets named `<package>_<version>_linux_<arch>`, as
GoReleaser's nfpm produces. The next run picks up every release it has ever
made.

## Publish a release now

The workflow runs hourly. To publish a release immediately:

```console
gh workflow run repository.yml -R miharp/packages
```

#!/bin/bash
# Build the harpworks package repository as a directory of static files.
#
#   build.sh <packages-dir> <site-dir> <gpg-key-id>
#
# The repository is derived, not maintained: every run rebuilds it in full
# from whatever rpm and deb files are in <packages-dir>, which the workflow
# fills from each project's GitHub Releases. There is no state to migrate and
# nothing to get out of step with the releases pages, which stay the source
# of truth. One repository holds every project: yum and apt do not care where
# a package came from, and a user who adopts a second tool adds nothing.
#
# What is signed is the repository metadata — repomd.xml for dnf, Release for
# apt — and not the packages themselves. The metadata carries every package's
# SHA-256, so a signed index vouches for every file below it; this is how apt
# has always worked, and dnf verifies it with repo_gpgcheck. It also means the
# packages here are byte-for-byte the release assets, so checksums.txt on the
# releases page still describes them.
#
# Needs createrepo_c, apt-ftparchive (apt-utils), and gpg with the key's
# secret half. GPG_PASSPHRASE, if set, unlocks it non-interactively.
set -euo pipefail

pkgs="${1:?packages directory}"
site="${2:?site directory}"
key="${3:?gpg key id}"
base_url="${BASE_URL:-https://packages.harpworks.org}"

sign() { # sign <args...> — gpg with the key, unattended when a passphrase is given
  if [ -n "${GPG_PASSPHRASE:-}" ]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 -u "$key" "$@" 3<<<"$GPG_PASSPHRASE"
  else
    gpg --batch --yes -u "$key" "$@"
  fi
}

rm -rf "$site"
install -d "$site/rpm" "$site/deb/pool/main"

# The custom domain, for GitHub Pages.
printf '%s\n' "${base_url#https://}" > "$site/CNAME"

# Pages runs Jekyll over the tree unless told not to, and Jekyll drops files it
# considers internal; nothing here is for Jekyll.
: > "$site/.nojekyll"

# --- the public key, in both encodings a package manager may ask for -------
gpg --export --armor "$key" > "$site/harpworks.asc"
gpg --export "$key" > "$site/harpworks.gpg"

# --- rpm ------------------------------------------------------------------
# One repository for both architectures: dnf filters by the running system's
# arch, and a single baseurl is one less thing to get wrong in a .repo file.
cp "$pkgs"/*.rpm "$site/rpm/"
createrepo_c --quiet "$site/rpm"
sign --detach-sign --armor --output "$site/rpm/repodata/repomd.xml.asc" "$site/rpm/repodata/repomd.xml"

cat > "$site/rpm/harpworks.repo" <<REPO
[harpworks]
name=harpworks - tools for OpenVox
baseurl=${base_url}/rpm
enabled=1
# The packages are unsigned; the metadata that names their checksums is signed.
gpgcheck=0
repo_gpgcheck=1
gpgkey=${base_url}/harpworks.asc
REPO

# --- deb ------------------------------------------------------------------
# pool/main/<initial>/<package>/, the Debian layout, per package name.
for f in "$pkgs"/*.deb; do
  name=$(basename "$f" | cut -d_ -f1)
  install -d "$site/deb/pool/main/${name:0:1}/$name"
  cp "$f" "$site/deb/pool/main/${name:0:1}/$name/"
done
# Filename: fields are relative to where apt-ftparchive runs, so run it at the
# repository root; one index per architecture, from the shared pool.
( cd "$site/deb"
  for arch in amd64 arm64; do
    install -d "dists/stable/main/binary-$arch"
    apt-ftparchive --arch "$arch" packages pool > "dists/stable/main/binary-$arch/Packages"
    gzip -9 -k -f "dists/stable/main/binary-$arch/Packages"
  done
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=harpworks \
    -o APT::FTPArchive::Release::Label=harpworks \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o "APT::FTPArchive::Release::Architectures=amd64 arm64" \
    -o APT::FTPArchive::Release::Components=main \
    release dists/stable > dists/stable/Release
)
sign --clearsign --output "$site/deb/dists/stable/InRelease" "$site/deb/dists/stable/Release"
sign --detach-sign --armor --output "$site/deb/dists/stable/Release.gpg" "$site/deb/dists/stable/Release"

# --- the front page -------------------------------------------------------
packages=$(for f in "$site"/rpm/*_linux_amd64.rpm; do basename "$f" | sed 's/^\(.*\)_\(.*\)_linux_amd64\.rpm$/\1 \2/'; done \
  | sort -k1,1 -k2,2V | awk '{last[$1]=$2} END {for (p in last) print "<li><code>" p "</code> " last[p] "</li>"}' | sort)
cat > "$site/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>harpworks package repository</title>
<style>body{font:15px/1.5 system-ui,sans-serif;max-width:46em;margin:3em auto;padding:0 1em}pre{background:#f4f4f4;padding:.8em;overflow-x:auto}</style>
<h1>harpworks package repository</h1>
<p>Packages for tools for OpenVox, rebuilt from each project's GitHub Releases.
The repository metadata is signed with <a href="harpworks.asc">this key</a>; the
packages are the release assets, unchanged.</p>
<ul>
${packages}
</ul>
<h2>RPM (Rocky, RHEL, AlmaLinux, CentOS Stream)</h2>
<pre>curl -fsSL ${base_url}/rpm/harpworks.repo -o /etc/yum.repos.d/harpworks.repo
dnf install codavox</pre>
<h2>DEB (Debian, Ubuntu)</h2>
<pre>curl -fsSL ${base_url}/harpworks.asc -o /etc/apt/keyrings/harpworks.asc
echo "deb [signed-by=/etc/apt/keyrings/harpworks.asc] ${base_url}/deb stable main" &gt; /etc/apt/sources.list.d/harpworks.list
apt-get update &amp;&amp; apt-get install codavox</pre>
<p>Source: <a href="https://github.com/miharp/packages">miharp/packages</a>.</p>
HTML

rpms=("$site"/rpm/*.rpm); debs=("$site"/deb/pool/main/*/*/*.deb)
echo "built $site: ${#rpms[@]} rpm, ${#debs[@]} deb"

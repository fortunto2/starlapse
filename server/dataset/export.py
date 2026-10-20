# /// script
# requires-python = ">=3.13"
# dependencies = ["huggingface_hub>=0.25", "requests>=2.32"]
# ///
"""Build a release of the Starlapse sky dataset and publish it.

    uv run server/dataset/export.py build            # → server/dataset/out/<version>/
    uv run server/dataset/export.py publish --to github,hf     # zenodo via the GitHub release

Same shape as the genealogy datasets: one GitHub repo per dataset (fortunto2/starlapse-sky-data),
a DOI from Zenodo for each release, CC BY 4.0. `--to zenodo` uploads directly through the
Zenodo API instead (photos included), for when a release must carry them.

What goes in: every row of D1 `observations` and its photo from R2, with one change: the
contributor id is replaced by a salted one-way code. The real id is the bearer secret for
"Delete everything I contributed", so it never leaves our server. The salt lives in
~/.config/starlapse/dataset-salt and is the same for every release, so one phone's readings
stay groupable across versions without being linkable to the phone.

Rows deleted by their contributors are simply absent: each release is a full snapshot.
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SERVER = HERE.parent
OUT = HERE / "out"
ACCOUNT = "33dec9645c443eef5859b1e10ce71e01"
DATABASE = "starlapse-sky"
BUCKET = "starlapse-sky"
HF_REPO = "superduperai/starlapse-sky"
DATA_REPO = "fortunto2/starlapse-sky-data"
SALT_FILE = pathlib.Path.home() / ".config" / "starlapse" / "dataset-salt"

COLUMNS = [
    "id", "contributor", "taken_at", "kind", "latitude", "longitude", "sky_brightness",
    "uncertainty", "naked_eye_limit", "bortle", "stack_limit", "matched_stars", "altitude",
    "azimuth", "meter_version", "camera", "photo", "app_version",
]


def wrangler(*args: str) -> str:
    env = {k: v for k, v in os.environ.items() if k != "CF_API_TOKEN"}
    env["CLOUDFLARE_ACCOUNT_ID"] = ACCOUNT
    return subprocess.run(
        ["npx", "wrangler", *args], cwd=SERVER, env=env, check=True, capture_output=True, text=True
    ).stdout


def salt() -> bytes:
    if not SALT_FILE.exists():
        SALT_FILE.parent.mkdir(parents=True, exist_ok=True)
        SALT_FILE.write_text(secrets.token_hex(32))
        SALT_FILE.chmod(0o600)
    return bytes.fromhex(SALT_FILE.read_text().strip())


def pseudonym(contributor: str, key: bytes) -> str:
    return hashlib.blake2b(contributor.encode(), key=key, digest_size=8).hexdigest()


def rows() -> list[dict]:
    raw = wrangler("d1", "execute", DATABASE, "--remote", "--json", "--command", "SELECT * FROM observations ORDER BY taken_at")
    return json.loads(raw)[0]["results"]


def build() -> pathlib.Path:
    version = dt.date.today().strftime("%Y.%m.%d")
    target = OUT / version
    shutil.rmtree(target, ignore_errors=True)
    (target / "photos").mkdir(parents=True)
    key = salt()
    data = rows()

    with open(target / "observations.csv", "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS)
        writer.writeheader()
        stars, meteors = [], []
        for row in data:
            code = pseudonym(row["contributor"], key)
            photo = None
            if row.get("photo_key"):
                photo = f"photos/{row['id']}.jpg"
                wrangler("r2", "object", "get", f"{BUCKET}/{row['photo_key']}", "--remote", "--file", str(target / photo))
            writer.writerow({
                **{c: row.get(c) for c in COLUMNS if c in row},
                "contributor": code, "photo": photo,
            })
            for star in json.loads(row.get("stars") or "[]"):
                stars.append({"observation": row["id"], **star})
            for meteor in json.loads(row.get("meteors") or "[]"):
                meteors.append({"observation": row["id"], **meteor})
    for name, items in (("stars.csv", stars), ("meteors.csv", meteors)):
        fields = sorted({k for item in items for k in item}) or ["observation"]
        with open(target / name, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(items)

    card = (HERE / "README.template.md").read_text()
    card = card.replace("{{version}}", version).replace("{{count}}", str(len(data)))
    card = card.replace("{{photos}}", str(sum(1 for r in data if r.get("photo_key"))))
    card = card.replace("{{meteors}}", str(len(meteors)))
    (target / "README.md").write_text(card)
    shutil.copy(HERE / "LICENSE", target / "LICENSE")
    print(f"{target}: {len(data)} observations, {len(stars)} star samples, {len(meteors)} meteors")
    return target


def latest() -> pathlib.Path:
    releases = sorted(p for p in OUT.iterdir() if p.is_dir()) if OUT.exists() else []
    if not releases:
        sys.exit("No build yet: run `build` first.")
    return releases[-1]


def publish_hf(target: pathlib.Path) -> None:
    from huggingface_hub import HfApi
    api = HfApi()
    api.create_repo(HF_REPO, repo_type="dataset", exist_ok=True)
    api.upload_folder(folder_path=str(target), repo_id=HF_REPO, repo_type="dataset",
                      commit_message=f"Release {target.name}")
    print(f"Hugging Face: https://huggingface.co/datasets/{HF_REPO}")


def publish_zenodo(target: pathlib.Path) -> None:
    import requests
    token = os.environ.get("ZENODO_TOKEN") or sys.exit("ZENODO_TOKEN is not set (zenodo.org › Applications › Personal access tokens, scopes deposit:write and deposit:actions).")
    api = "https://zenodo.org/api/deposit/depositions"
    headers = {"Authorization": f"Bearer {token}"}
    archive = shutil.make_archive(str(OUT / f"starlapse-sky-{target.name}"), "zip", target)
    deposition = requests.post(api, headers=headers, json={}).json()
    with open(archive, "rb") as handle:
        requests.put(f"{deposition['links']['bucket']}/{pathlib.Path(archive).name}", data=handle, headers=headers).raise_for_status()
    metadata = {"metadata": {
        "title": f"Starlapse sky dataset ({target.name})",
        "upload_type": "dataset",
        "description": "Sky brightness readings (mag/arcsec², Bortle, naked-eye limit) measured from catalogue stars in iPhone stacks, the star samples behind each reading, meteor observations placed on the sky, and sky photos. Locations rounded to 0.1°. Contributed by Starlapse users who opted in.",
        "creators": [{"name": "Starlapse contributors"}, {"name": "Salavatov, Rustam", "affiliation": "SuperDuperAI"}],
        "license": "cc-by-4.0",
        "keywords": ["light pollution", "sky quality", "SQM", "meteors", "citizen science", "astronomy"],
        "related_identifiers": [{"identifier": "https://github.com/fortunto2/starlapse", "relation": "isSupplementTo", "scheme": "url"}],
        "version": target.name,
    }}
    requests.put(deposition["links"]["self"], headers=headers, json=metadata).raise_for_status()
    published = requests.post(deposition["links"]["publish"], headers=headers)
    published.raise_for_status()
    print(f"Zenodo: https://doi.org/{published.json()['doi']}")


def publish_github(target: pathlib.Path) -> None:
    """Tables into fortunto2/starlapse-sky-data, then a release. Zenodo's GitHub integration
    archives every release of that repo with a DOI (switched on once per repo at
    zenodo.org/account/settings/github), the same way the genealogy datasets are published.
    Zenodo archives the repository, not release assets, so the photos stay on Hugging Face.
    """
    work = OUT / "starlapse-sky-data"
    shutil.rmtree(work, ignore_errors=True)
    subprocess.run(["gh", "repo", "clone", DATA_REPO, str(work)], check=True)
    for name in ("observations.csv", "stars.csv", "meteors.csv", "README.md"):
        shutil.copy(target / name, work / name)
    git = ["git", "-C", str(work)]
    subprocess.run([*git, "add", "-A"], check=True)
    subprocess.run([*git, "commit", "-m", f"Release {target.name}"], check=True)
    subprocess.run([*git, "push"], check=True)
    subprocess.run(["gh", "release", "create", f"v{target.name}", "--repo", DATA_REPO,
                    "--title", f"Sky dataset {target.name}", "--notes-file", str(target / "README.md")], check=True)
    print(f"GitHub: https://github.com/{DATA_REPO}/releases/tag/v{target.name} (Zenodo mints the DOI)")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build")
    publish = sub.add_parser("publish")
    publish.add_argument("--to", default="github,hf")
    args = parser.parse_args()
    if args.command == "build":
        build()
        return
    target = latest()
    for place in args.to.split(","):
        {"hf": publish_hf, "zenodo": publish_zenodo, "github": publish_github}[place.strip()](target)


if __name__ == "__main__":
    main()

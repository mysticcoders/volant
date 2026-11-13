# /// script
# requires-python = ">=3.11"
# dependencies = ["click", "pyjwt[crypto]", "requests"]
# ///
"""App Store Connect listing for Volant for iPhone: text, categories, age rating and screenshots
from metadata.json and a screenshot folder, through the App Store Connect API.

  uv run ios/AppStore/asc.py show
  uv run ios/AppStore/asc.py push [--screenshots DIR]

The key is ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 and the issuer comes from
ASC_ISSUER_ID or ~/.appstoreconnect/issuer_id, as for testflight.sh."""
import hashlib
import json
import os
import time
from pathlib import Path

import click
import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.mysticcoders.volant.mobile"
HERE = Path(__file__).parent
ASC_DIR = Path(os.environ.get("VOLANT_ASC_DIR", Path.home() / ".appstoreconnect"))


def token() -> str:
    """A 15-minute ES256 token for the team key."""
    key_id = os.environ.get("ASC_KEY_ID") or "4B57CGG6US"
    issuer = os.environ.get("ASC_ISSUER_ID") or (ASC_DIR / "issuer_id").read_text().strip()
    key = (ASC_DIR / "private_keys" / f"AuthKey_{key_id}.p8").read_text()
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": key_id})


class Client:
    """Thin JSON:API wrapper that raises with Apple's error detail on failure."""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {token()}"

    def call(self, method: str, path: str, **kwargs) -> dict:
        url = path if path.startswith("http") else API + path
        response = self.session.request(method, url, **kwargs)
        if response.status_code >= 400:
            raise click.ClickException(f"{method} {path} -> {response.status_code}: {response.text}")
        return response.json() if response.content else {}

    def get(self, path, **params):
        return self.call("GET", path, params=params)

    def patch(self, kind: str, ident: str, attributes: dict, relationships: dict | None = None):
        data = {"type": kind, "id": ident, "attributes": attributes}
        if relationships:
            data["relationships"] = relationships
        return self.call("PATCH", f"/{kind}/{ident}", json={"data": data})

    def post(self, kind: str, attributes: dict, relationships: dict):
        return self.call("POST", f"/{kind}", json={"data": {"type": kind, "attributes": attributes, "relationships": relationships}})


def app(client: Client) -> dict:
    found = client.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not found:
        raise click.ClickException(f"No App Store Connect app for {BUNDLE_ID}")
    return found[0]


def editable_version(client: Client, app_id: str) -> dict:
    """The iOS version still being prepared, which is the one whose page can be edited."""
    versions = client.get(f"/apps/{app_id}/appStoreVersions", **{"filter[platform]": "IOS"})["data"]
    for version in versions:
        if version["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            return version
    raise click.ClickException("No editable iOS version; create one in App Store Connect first.")


def editable_info(client: Client, app_id: str) -> dict:
    infos = client.get(f"/apps/{app_id}/appInfos")["data"]
    for info in infos:
        if info["attributes"].get("appStoreState") != "READY_FOR_SALE" and info["attributes"].get("state") != "READY_FOR_DISTRIBUTION":
            return info
    return infos[0]


@click.group()
def cli():
    """Manage Volant Mobile's App Store Connect listing."""


@cli.command()
def show():
    """Print the app, its editable version and what the listing holds now."""
    client = Client()
    record = app(client)
    print("app:", record["id"], record["attributes"]["name"], record["attributes"]["primaryLocale"])
    version = editable_version(client, record["id"])
    print("version:", version["id"], version["attributes"]["versionString"], version["attributes"]["appStoreState"])
    for loc in client.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
        a = loc["attributes"]
        print("  locale:", a["locale"], "| description:", bool(a.get("description")), "| keywords:", a.get("keywords"))
        for group in client.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]:
            shots = client.get(f"/appScreenshotSets/{group['id']}/appScreenshots")["data"]
            print("    screenshots:", group["attributes"]["screenshotDisplayType"], len(shots))
    info = editable_info(client, record["id"])
    for loc in client.get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]:
        print("  info:", loc["attributes"])
    builds = client.get("/builds", **{"filter[app]": record["id"], "sort": "-uploadedDate", "limit": 3})["data"]
    for build in builds:
        print("build:", build["attributes"]["version"], build["attributes"]["processingState"])


def push_text(client: Client, app_id: str, meta: dict):
    """App-level info (subtitle, privacy URL, categories) and version-level text."""
    info = editable_info(client, app_id)
    client.patch("appInfos", info["id"], {}, {
        "primaryCategory": {"data": {"type": "appCategories", "id": meta["primaryCategory"]}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": meta["secondaryCategory"]}},
    })
    for loc in client.get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]:
        if loc["attributes"]["locale"] == meta["locale"]:
            client.patch("appInfoLocalizations", loc["id"], {"subtitle": meta["subtitle"], "privacyPolicyUrl": meta["privacyPolicyUrl"]})
    version = editable_version(client, app_id)
    client.patch("appStoreVersions", version["id"], {"copyright": meta["copyright"]})
    for loc in client.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
        if loc["attributes"]["locale"] == meta["locale"]:
            client.patch("appStoreVersionLocalizations", loc["id"], {
                "description": "\n".join(meta["description"]), "keywords": meta["keywords"],
                "promotionalText": meta["promotionalText"], "marketingUrl": meta["marketingUrl"], "supportUrl": meta["supportUrl"],
            })
    print("text, categories and URLs set")


def push_age_rating(client: Client, app_id: str):
    """Answers every content question with its lowest value in one request, as Apple requires:
    "NONE" for frequency questions and false for yes/no ones. The questionnaire changes over time,
    so the types come from Apple's own errors: any question it says expects a boolean is resent as false."""
    import re
    info = editable_info(client, app_id)
    declaration = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    skip = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "gracRatingClassificationNumber", "developerAgeRatingInfoUrl"}
    answers = {name: "NONE" for name in declaration["attributes"] if name not in skip}
    for _ in range(12):
        try:
            client.patch("ageRatingDeclarations", declaration["id"], answers)
            print("age rating answered:", ", ".join(f"{k}={v}" for k, v in sorted(answers.items()) if v is False) or "all NONE")
            return
        except click.ClickException as error:
            booleans = re.findall(r"attribute '(\w+)'\. Expected a BOOLEAN", str(error))
            if not booleans:
                raise
            answers.update({name: False for name in booleans})
    raise click.ClickException("Age rating was not accepted after adjusting answer types.")


SCREENSHOT_SETS = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129", "duo": "APP_IPHONE_DUO"}


def push_screenshots(client: Client, app_id: str, folder: Path, locale: str):
    """Replaces each device's screenshot set with the framed PNGs in folder/<device>, in name order.
    The iPhone Duo set takes the unfolded duo-inner captures when they exist, else the folded duo ones."""
    version = editable_version(client, app_id)
    loc = next(l for l in client.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"] if l["attributes"]["locale"] == locale)
    existing = {g["attributes"]["screenshotDisplayType"]: g for g in client.get(f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]}
    for device, display in SCREENSHOT_SETS.items():
        source = folder / device
        if device == "duo" and (folder / "duo-inner").is_dir():
            source = folder / "duo-inner"
        files = sorted(source.glob("[0-9][0-9]-*.png"))
        if not files:
            continue
        group = existing.get(display) or client.post("appScreenshotSets", {"screenshotDisplayType": display},
                                                      {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}})["data"]
        for old in client.get(f"/appScreenshotSets/{group['id']}/appScreenshots")["data"]:
            client.call("DELETE", f"/appScreenshots/{old['id']}")
        for path in files:
            upload(client, group["id"], path)
        print(f"{device}: {len(files)} screenshots as {display}")


def upload(client: Client, set_id: str, path: Path):
    """Reserves a screenshot, sends its bytes in the parts Apple asks for, then commits it with its MD5."""
    data = path.read_bytes()
    reserved = client.post("appScreenshots", {"fileName": path.name, "fileSize": len(data)},
                           {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}})["data"]
    for op in reserved["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        part = data[op["offset"]: op["offset"] + op["length"]]
        response = requests.request(op["method"], op["url"], headers=headers, data=part)
        if response.status_code >= 300:
            raise click.ClickException(f"upload of {path.name} failed: {response.status_code}")
    client.patch("appScreenshots", reserved["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})


@cli.command()
@click.option("--screenshots", type=click.Path(exists=True, file_okay=False, path_type=Path), help="Folder with iphone/ and ipad/ framed PNGs.")
@click.option("--skip-text", is_flag=True, help="Only upload screenshots.")
def push(screenshots: Path | None, skip_text: bool):
    """Push metadata.json, the age rating and, when given, screenshots to the version being prepared."""
    meta = json.loads((HERE / "metadata.json").read_text())
    client = Client()
    app_id = app(client)["id"]
    if not skip_text:
        push_text(client, app_id, meta)
        push_age_rating(client, app_id)
    if screenshots:
        push_screenshots(client, app_id, screenshots, meta["locale"])


@cli.command("attach-build")
@click.argument("build_number", required=False)
def attach_build(build_number: str | None):
    """Attach a processed build to the version being prepared (the newest one by default). This sets
    the build that would be submitted and is what gives App Store Connect the app's icon; it submits nothing."""
    client = Client()
    app_id = app(client)["id"]
    version = editable_version(client, app_id)
    builds = client.get("/builds", **{"filter[app]": app_id, "sort": "-uploadedDate", "limit": 20})["data"]
    ready = [b for b in builds if b["attributes"]["processingState"] == "VALID" and (build_number is None or b["attributes"]["version"] == build_number)]
    if not ready:
        states = ", ".join(f"{b['attributes']['version']} {b['attributes']['processingState']}" for b in builds[:5])
        raise click.ClickException(f"No processed build to attach yet ({states}).")
    build = ready[0]
    client.call("PATCH", f"/appStoreVersions/{version['id']}/relationships/build", json={"data": {"type": "builds", "id": build["id"]}})
    print(f"attached build {build['attributes']['version']} to {version['attributes']['versionString']}")


def beta_group(client: Client, app_id: str, name: str, internal: bool, **attributes) -> dict:
    """The app's beta group with this name, created when missing."""
    for group in client.get(f"/apps/{app_id}/betaGroups")["data"]:
        if group["attributes"]["name"] == name:
            return group
    return client.post("betaGroups", {"name": name, "isInternalGroup": internal, **attributes},
                       {"app": {"data": {"type": "apps", "id": app_id}}})["data"]


@cli.command("beta-internal")
@click.option("--email", required=True, help="An App Store Connect user on the team; internal testers must be one.")
@click.option("--first-name", default="")
@click.option("--last-name", default="")
def beta_internal(email: str, first_name: str, last_name: str):
    """Create the "Volant Team" internal TestFlight group, which receives every build without
    review, and add a team member to it."""
    client = Client()
    app_id = app(client)["id"]
    group = beta_group(client, app_id, "Volant Team", True, hasAccessToAllBuilds=True)
    existing = client.get("/betaTesters", **{"filter[email]": email, "filter[apps]": app_id})["data"]
    if existing:
        client.call("POST", f"/betaGroups/{group['id']}/relationships/betaTesters", json={"data": [{"type": "betaTesters", "id": existing[0]["id"]}]})
    else:
        client.post("betaTesters", {"email": email, "firstName": first_name, "lastName": last_name},
                    {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}})
    print(f"{email} is in Volant Team; TestFlight sends the invite by email")


BETA_DESCRIPTION = ("Volant for iPhone and iPad: plain Markdown notes in iCloud, snippets and quicklinks shared with "
                    "Volant on the Mac, a calculator for units, time zones and dates, widgets, a share extension and "
                    "Shortcuts actions. No account and no telemetry.")
WHAT_TO_TEST = ("Write and preview notes, pin and search them. Try the widgets, the New Volant Note control, Save to "
                "Volant from Safari's share sheet, and the Volant actions in Shortcuts. If you use Volant on a Mac with "
                "Sync settings and notes with iCloud on, check that snippets and quicklinks match and that edits sync.")
REVIEW_NOTES = ("No sign-in or account is needed. Notes are stored in the tester's own iCloud Drive; with iCloud off they "
                "stay on the device. Snippets and quicklinks start empty unless the tester uses Volant on a Mac; tap + "
                "in Snippets or Quicklinks to add one.")


@cli.command("beta-external")
@click.option("--feedback-email", required=True)
@click.option("--contact-first-name", required=True)
@click.option("--contact-last-name", required=True)
@click.option("--contact-email", required=True)
@click.option("--contact-phone", default=None, help="Apple requires one before a build can be submitted for Beta App Review.")
@click.option("--build", "build_number", default=None, help="Build to add and submit; the newest processed build by default.")
@click.option("--public-link-limit", default=1000, show_default=True)
def beta_external(feedback_email, contact_first_name, contact_last_name, contact_email, contact_phone, build_number, public_link_limit):
    """Prepare external TestFlight: test information, review contact, What to Test, and a "Public Beta"
    group with a public link. With a contact phone it also submits the build for Beta App Review."""
    client = Client()
    app_id = app(client)["id"]
    meta = json.loads((HERE / "metadata.json").read_text())
    localization = {"description": BETA_DESCRIPTION, "feedbackEmail": feedback_email,
                    "marketingUrl": meta["marketingUrl"], "privacyPolicyUrl": meta["privacyPolicyUrl"]}
    existing = client.get(f"/apps/{app_id}/betaAppLocalizations")["data"]
    current = next((l for l in existing if l["attributes"]["locale"] == meta["locale"]), None)
    if current:
        client.patch("betaAppLocalizations", current["id"], localization)
    else:
        client.post("betaAppLocalizations", {"locale": meta["locale"], **localization}, {"app": {"data": {"type": "apps", "id": app_id}}})
    review = client.get(f"/apps/{app_id}/betaAppReviewDetail")["data"]
    details = {"contactFirstName": contact_first_name, "contactLastName": contact_last_name, "contactEmail": contact_email,
               "demoAccountRequired": False, "notes": REVIEW_NOTES}
    if contact_phone:
        details["contactPhone"] = contact_phone
    client.patch("betaAppReviewDetails", review["id"], details)
    builds = client.get("/builds", **{"filter[app]": app_id, "sort": "-uploadedDate", "limit": 20})["data"]
    build = next(b for b in builds if b["attributes"]["processingState"] == "VALID" and (build_number is None or b["attributes"]["version"] == build_number))
    notes = client.get(f"/builds/{build['id']}/betaBuildLocalizations")["data"]
    note = next((n for n in notes if n["attributes"]["locale"] == meta["locale"]), None)
    if note:
        client.patch("betaBuildLocalizations", note["id"], {"whatsNew": WHAT_TO_TEST})
    else:
        client.post("betaBuildLocalizations", {"locale": meta["locale"], "whatsNew": WHAT_TO_TEST}, {"build": {"data": {"type": "builds", "id": build["id"]}}})
    group = beta_group(client, app_id, "Public Beta", False, publicLinkEnabled=True, publicLinkLimitEnabled=True,
                       publicLinkLimit=public_link_limit, feedbackEnabled=True)
    client.call("POST", f"/betaGroups/{group['id']}/relationships/builds", json={"data": [{"type": "builds", "id": build["id"]}]})
    print(f"test information, review details and What to Test set; build {build['attributes']['version']} added to Public Beta")
    if not contact_phone:
        print("not submitted: a contact phone is required for Beta App Review")
        return
    client.post("betaAppReviewSubmissions", {}, {"build": {"data": {"type": "builds", "id": build["id"]}}})
    link = client.get(f"/betaGroups/{group['id']}")["data"]["attributes"].get("publicLink")
    print(f"submitted build {build['attributes']['version']} for Beta App Review; public link once approved: {link}")


@cli.command("age-rating")
def age_rating():
    """Print the age rating declaration's current attributes, to see which questions exist."""
    client = Client()
    info = editable_info(client, app(client)["id"])
    print(json.dumps(client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"], indent=1))


@cli.command("set-version")
@click.argument("version")
def set_version(version: str):
    """Rename the version being prepared, e.g. 0.1.0, to match the build's CFBundleShortVersionString."""
    client = Client()
    current = editable_version(client, app(client)["id"])
    client.patch("appStoreVersions", current["id"], {"versionString": version})
    print(f"{current['attributes']['versionString']} -> {version}")


if __name__ == "__main__":
    cli()

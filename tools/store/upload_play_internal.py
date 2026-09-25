"""Publish a signed AAB to the Google Play internal testing track.

Usage: GOOGLE_APPLICATION_CREDENTIALS=service-account.json \
       python tools/store/upload_play_internal.py com.jape.game build/android/jape.aab
"""

import os
from pathlib import Path
import re
import sys

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account


SCOPE = "https://www.googleapis.com/auth/androidpublisher"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD_API = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"


def send(method: str, url: str, token: str, **kwargs) -> dict:
    headers = {"Authorization": f"Bearer {token}"}
    headers.update(kwargs.pop("headers", {}))
    response = requests.request(method, url, headers=headers, timeout=300, **kwargs)
    if not response.ok:
        raise RuntimeError(f"Google Play API {method} failed: HTTP {response.status_code}: {response.text[:1200]}")
    return response.json()


def publish(package: str, bundle: Path, credentials_path: Path) -> None:
    if not re.fullmatch(r"[A-Za-z][\w]*(?:\.[A-Za-z][\w]*)+", package):
        raise ValueError("Invalid Android package name")
    if not bundle.is_file() or bundle.stat().st_size == 0:
        raise FileNotFoundError(bundle)
    credentials = service_account.Credentials.from_service_account_file(
        str(credentials_path), scopes=[SCOPE]
    )
    credentials.refresh(Request())
    token = credentials.token

    edit = send("POST", f"{API}/{package}/edits", token, json={})["id"]
    with bundle.open("rb") as binary:
        uploaded = send(
            "POST",
            f"{UPLOAD_API}/{package}/edits/{edit}/bundles?uploadType=media",
            token,
            headers={"Content-Type": "application/octet-stream"},
            data=binary,
        )
    version = str(uploaded["versionCode"])
    send(
        "PUT",
        f"{API}/{package}/edits/{edit}/tracks/internal",
        token,
        json={
            "track": "internal",
            "releases": [
                {
                    "name": f"JAPE internal {version}",
                    "versionCodes": [version],
                    "status": "completed",
                    "releaseNotes": [{"language": "ja-JP", "text": "内部テスト用ビルド"}],
                }
            ],
        },
    )
    send("POST", f"{API}/{package}/edits/{edit}:commit", token, json={})
    print(f"Google Play internal testing submitted: {package} versionCode={version}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: upload_play_internal.py PACKAGE AAB")
    publish(
        sys.argv[1],
        Path(sys.argv[2]),
        Path(os.environ["GOOGLE_APPLICATION_CREDENTIALS"]),
    )

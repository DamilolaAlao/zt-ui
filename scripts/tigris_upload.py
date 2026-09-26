#!/usr/bin/env python3
"""Upload a release object to Tigris.

`aws s3 cp --endpoint-url https://t3.storage.dev` uses path-style URLs.
Tigris only accepts virtual-hosted requests
(https://bucket.t3.storage.dev/key) and answers AccessDenied otherwise.
See https://www.tigrisdata.com/docs/sdks/s3/.
"""

import os
import subprocess
import sys


os.environ["AWS_REQUEST_CHECKSUM_CALCULATION"] = "when_required"
os.environ["AWS_RESPONSE_CHECKSUM_VALIDATION"] = "when_required"
os.environ.setdefault("AWS_REGION", "auto")

ENDPOINT = "https://t3.storage.dev"


def ensure_venv():
    venv = os.environ.get("TIGRIS_VENV") or os.path.join(
        os.environ.get("RUNNER_TEMP", "/tmp"), "tigris-venv"
    )
    python = os.path.join(venv, "bin", "python")
    if os.path.abspath(sys.executable) == os.path.abspath(python):
        return
    if not os.path.exists(python):
        subprocess.check_call([sys.executable, "-m", "venv", venv])
        subprocess.check_call(
            [python, "-m", "pip", "install", "--disable-pip-version-check", "boto3>=1.38"]
        )
    os.execv(python, [python, *sys.argv])


def client():
    import boto3
    from botocore.config import Config

    missing = [
        name
        for name in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "TIGRIS_BUCKET")
        if not os.environ.get(name)
    ]
    if missing:
        print(
            "::error::Set the TIGRIS_BUCKET variable and the "
            "TIGRIS_ACCESS_KEY_ID / TIGRIS_SECRET_ACCESS_KEY secrets. "
            "See https://www.tigrisdata.com/docs/sdks/s3/",
            file=sys.stderr,
        )
        raise SystemExit(1)

    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT,
        region_name=os.environ.get("AWS_REGION", "auto"),
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        config=Config(
            signature_version="s3v4",
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
            retries={"max_attempts": 5, "mode": "standard"},
            s3={"addressing_style": "virtual"},
        ),
    )


def require_tag():
    tag = os.environ.get("ZT_UI_TAG", "")
    if not tag:
        print("::error::ZT_UI_TAG is required.", file=sys.stderr)
        raise SystemExit(1)
    return tag


def explain(s3, bucket, key, error):
    code = error.response.get("Error", {}).get("Code", "Error")
    message = error.response.get("Error", {}).get("Message", "")
    visible = "(list failed)"
    try:
        names = [item["Name"] for item in s3.list_buckets().get("Buckets", [])]
        visible = ", ".join(names) if names else "(none)"
    except Exception as list_error:
        visible = f"(list failed: {list_error.__class__.__name__})"
    print(
        f"::error::Tigris {code} for s3://{bucket}/{key}: {message} "
        f"Buckets visible to this key: {visible}",
        file=sys.stderr,
    )


def _call(label, fn):
    from botocore.exceptions import ClientError

    try:
        fn()
    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "Error")
        message = error.response.get("Error", {}).get("Message", "")
        print(f"fail {label}: {code} {message}", flush=True)
        return False
    print(f"ok {label}", flush=True)
    return True


def probe(s3):
    from botocore.exceptions import ClientError

    bucket = os.environ["TIGRIS_BUCKET"]
    key = f"zt-ui/{require_tag()}/.ci-probe"
    body = b"zt-ui tigris probe\n"

    put_ok = _call(
        f"put s3://{bucket}/{key}",
        lambda: s3.put_object(
            Bucket=bucket, Key=key, Body=body, ContentType="text/plain"
        ),
    )
    if put_ok:
        s3.delete_object(Bucket=bucket, Key=key)

    upload_id = {}

    def start_multipart():
        created = s3.create_multipart_upload(
            Bucket=bucket, Key=key, ContentType="application/octet-stream"
        )
        upload_id["id"] = created["UploadId"]

    multipart_ok = _call(f"multipart s3://{bucket}/{key}", start_multipart)
    if upload_id.get("id"):
        try:
            s3.abort_multipart_upload(
                Bucket=bucket, Key=key, UploadId=upload_id["id"]
            )
        except ClientError:
            pass

    if put_ok and multipart_ok:
        print(f"Tigris multipart upload ok for s3://{bucket}/{key}")
        return

    root_ok = _call(
        f"put s3://{bucket}/.ci-probe",
        lambda: s3.put_object(
            Bucket=bucket, Key=".ci-probe", Body=body, ContentType="text/plain"
        ),
    )
    if root_ok:
        s3.delete_object(Bucket=bucket, Key=".ci-probe")

    writable = []
    if not put_ok and not root_ok:
        try:
            names = [item["Name"] for item in s3.list_buckets().get("Buckets", [])]
        except ClientError:
            names = []
        for name in names:
            if name == bucket:
                continue
            if _call(
                f"put s3://{name}/.ci-probe",
                lambda name=name: s3.put_object(
                    Bucket=name, Key=".ci-probe", Body=body, ContentType="text/plain"
                ),
            ):
                writable.append(name)
                s3.delete_object(Bucket=name, Key=".ci-probe")

    explain_denied(s3, bucket, key, put_ok, multipart_ok, root_ok, writable)
    raise SystemExit(1)


def explain_denied(s3, bucket, key, put_ok, multipart_ok, root_ok, writable):
    visible = "(list failed)"
    try:
        names = [item["Name"] for item in s3.list_buckets().get("Buckets", [])]
        visible = ", ".join(names) if names else "(none)"
    except Exception as list_error:
        visible = f"(list failed: {list_error.__class__.__name__})"
    print(
        "::error::Tigris refused to write "
        f"s3://{bucket}/{key} "
        f"(put={'ok' if put_ok else 'denied'}, "
        f"multipart={'ok' if multipart_ok else 'denied'}, "
        f"bucket-root put={'ok' if root_ok else 'denied'}). "
        f"Buckets visible to this key: {visible}. "
        f"Buckets that accepted a write: {', '.join(writable) if writable else '(none)'}. "
        "The access key needs s3:PutObject on "
        f"arn:aws:s3:::{bucket}/zt-ui/*.",
        file=sys.stderr,
    )


def upload(s3):
    from botocore.exceptions import ClientError

    bucket = os.environ["TIGRIS_BUCKET"]
    path = os.environ.get("ZT_UI_MACOS_ZIP", "")
    if not path or not os.path.isfile(path):
        print(f"::error::Missing zip: {path or '(unset)'}", file=sys.stderr)
        raise SystemExit(1)
    name = os.path.basename(path)
    key = f"zt-ui/{require_tag()}/{name}"
    total = os.path.getsize(path)
    sent = 0
    next_report = 0

    def report(amount):
        nonlocal sent, next_report
        sent += amount
        if sent >= next_report or sent >= total:
            print(f"uploaded {sent}/{total} bytes", flush=True)
            next_report = sent + 256 * 1024 * 1024

    try:
        s3.upload_file(
            path,
            bucket,
            key,
            ExtraArgs={"ContentType": "application/zip"},
            Callback=report,
        )
    except ClientError as error:
        explain(s3, bucket, key, error)
        raise SystemExit(1)

    url = f"https://{bucket}.t3.tigrisfiles.io/{key}"
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"url={url}\n")
    print(f"Uploaded {url}")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"probe", "upload"}:
        print("usage: tigris_upload.py probe|upload", file=sys.stderr)
        raise SystemExit(2)
    ensure_venv()
    s3 = client()
    if sys.argv[1] == "probe":
        probe(s3)
    else:
        upload(s3)


if __name__ == "__main__":
    main()

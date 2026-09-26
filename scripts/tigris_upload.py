#!/usr/bin/env python3
"""Upload a release object to Tigris.

Object writes use virtual-hosted requests, as in
https://www.tigrisdata.com/docs/sdks/s3/. A key with no bucket role can still
list buckets and create a bucket it owns
(https://www.tigrisdata.com/docs/concepts/authnz/). A new bucket is created
public with CreateBucket --acl public-read
(https://www.tigrisdata.com/docs/buckets/public-bucket/).
"""

import os
import subprocess
import sys


os.environ["AWS_REQUEST_CHECKSUM_CALCULATION"] = "when_required"
os.environ["AWS_RESPONSE_CHECKSUM_VALIDATION"] = "when_required"
os.environ.setdefault("AWS_REGION", "auto")

ENDPOINT = "https://t3.storage.dev"
OWNED_BUCKET = "zt-ui-releases"


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


def client(addressing):
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
            s3={"addressing_style": addressing},
        ),
    )


def require_tag():
    tag = os.environ.get("ZT_UI_TAG", "")
    if not tag:
        print("::error::ZT_UI_TAG is required.", file=sys.stderr)
        raise SystemExit(1)
    return tag


def bucket_file():
    return os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "tigris-bucket")


def remember_bucket(name):
    path = bucket_file()
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(name)


def remembered_bucket():
    path = bucket_file()
    if not os.path.isfile(path):
        return ""
    with open(path, encoding="utf-8") as handle:
        return handle.read().strip()


def can_write(s3, bucket):
    from botocore.exceptions import ClientError

    key = ".ci-probe"
    try:
        s3.put_object(Bucket=bucket, Key=key, Body=b"probe\n", ContentType="text/plain")
        s3.delete_object(Bucket=bucket, Key=key)
    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "Error")
        print(f"fail put s3://{bucket}/{key}: {code}", flush=True)
        return False
    print(f"ok put s3://{bucket}/{key}", flush=True)
    return True


def create_public_bucket(name):
    from botocore.exceptions import ClientError

    # CreateBucket is path-style. See the public bucket example in
    # https://www.tigrisdata.com/docs/buckets/public-bucket/
    try:
        client("path").create_bucket(Bucket=name, ACL="public-read")
    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "Error")
        message = error.response.get("Error", {}).get("Message", "")
        print(f"create s3://{name}: {code} {message}", flush=True)
        if code == "BucketAlreadyOwnedByYou":
            return True
        return False
    print(f"created public bucket s3://{name}", flush=True)
    return True


def ensure_bucket(s3):
    saved = remembered_bucket()
    if saved and can_write(s3, saved):
        return saved

    requested = os.environ["TIGRIS_BUCKET"]
    if can_write(s3, requested):
        remember_bucket(requested)
        return requested

    for name in (requested, OWNED_BUCKET):
        if not create_public_bucket(name):
            continue
        if can_write(s3, name):
            remember_bucket(name)
            print(f"using bucket {name}", flush=True)
            return name

    print(
        "::error::This access key can list buckets but cannot write to "
        f"s3://{requested}, and it could not create s3://{OWNED_BUCKET}. "
        "Assign the key the ReadWrite role on the bucket: "
        f"tigris access-keys assign <tid> --bucket {requested} --role ReadWrite. "
        "See https://www.tigrisdata.com/docs/concepts/authnz/",
        file=sys.stderr,
    )
    raise SystemExit(1)


def probe(s3):
    from botocore.exceptions import ClientError

    bucket = ensure_bucket(s3)
    key = f"zt-ui/{require_tag()}/.ci-probe"
    upload_id = None
    try:
        created = s3.create_multipart_upload(
            Bucket=bucket, Key=key, ContentType="application/octet-stream"
        )
        upload_id = created["UploadId"]
        part = s3.upload_part(
            Bucket=bucket,
            Key=key,
            UploadId=upload_id,
            PartNumber=1,
            Body=b"zt-ui tigris probe\n",
        )
        s3.complete_multipart_upload(
            Bucket=bucket,
            Key=key,
            UploadId=upload_id,
            MultipartUpload={"Parts": [{"ETag": part["ETag"], "PartNumber": 1}]},
        )
        upload_id = None
        s3.delete_object(Bucket=bucket, Key=key)
    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "Error")
        message = error.response.get("Error", {}).get("Message", "")
        print(
            f"::error::Tigris {code} for multipart s3://{bucket}/{key}: {message}",
            file=sys.stderr,
        )
        raise SystemExit(1)
    finally:
        if upload_id:
            try:
                s3.abort_multipart_upload(Bucket=bucket, Key=key, UploadId=upload_id)
            except ClientError:
                pass
    print(f"Tigris multipart upload ok for s3://{bucket}/{key}")


def upload(s3):
    from botocore.exceptions import ClientError

    bucket = ensure_bucket(s3)
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
        code = error.response.get("Error", {}).get("Code", "Error")
        message = error.response.get("Error", {}).get("Message", "")
        print(
            f"::error::Tigris {code} for s3://{bucket}/{key}: {message}",
            file=sys.stderr,
        )
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
    s3 = client("virtual")
    if sys.argv[1] == "probe":
        probe(s3)
    else:
        upload(s3)


if __name__ == "__main__":
    main()
